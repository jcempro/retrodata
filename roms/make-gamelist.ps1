#!/usr/bin/env pwsh
# -*- coding: utf-8 -*-

[CmdletBinding()]
param(
  [switch]$WhatIf,
  [switch]$VerboseLog
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# =========================
# UTIL
# =========================

function Write-Log {
  param($Msg, [ValidateSet("INFO", "WARN", "ERROR")]$Level = "INFO")

  switch ($Level) {
    "ERROR" { Write-Host "[E] $Msg" -ForegroundColor Red }
    "WARN" { Write-Host "[W] $Msg" -ForegroundColor Yellow }
    default { if ($VerboseLog) { Write-Host "[I] $Msg" -ForegroundColor Gray } }
  }
}

function Escape-Xml {
  param([string]$s)
  if ($null -eq $s) { return "" }
  return [System.Security.SecurityElement]::Escape($s)
}

function Test-WritePermission {
  param($Path)
  try {
    $f = Join-Path $Path (".__test_" + [guid]::NewGuid())
    New-Item $f -ItemType File | Out-Null
    Remove-Item $f -Force
    return $true
  }
  catch { return $false }
}

function Load-XmlSafe {
  param($Path)

  if (-not (Test-Path $Path)) { return $null }

  try {
    [xml](Get-Content $Path -Raw)
  }
  catch {
    Write-Log "XML inválido → ignorando ($Path)" "WARN"
    return $null
  }
}

# =========================
# CRIA NODE GAME (SEM ID)
# =========================
function Create-GameNode {
  param(
    [xml]$Doc,
    [string]$Path,
    [string]$Name
  )

  $game = $Doc.CreateElement("game")

  $p = $Doc.CreateElement("path")
  $p.InnerText = $Path

  $n = $Doc.CreateElement("name")
  $n.InnerText = $Name

  $game.AppendChild($p) | Out-Null
  $game.AppendChild($n) | Out-Null

  foreach ($field in @("lang", "genre", "style", "players", "coop", "versus", "campaign", "goodstory")) {
    $el = $Doc.CreateElement($field)
    $el.InnerText = ""
    $game.AppendChild($el) | Out-Null
  }

  return $game
}

# =========================
# EXEC
# =========================

try {
  $root = Split-Path -Parent $MyInvocation.MyCommand.Path
  Write-Host "Base: $root" -ForegroundColor Cyan

  $dirs = Get-ChildItem $root -Directory

  foreach ($dir in $dirs) {

    Write-Host "`nProcessando: $($dir.Name)" -ForegroundColor Cyan

    if (-not (Test-WritePermission $dir.FullName)) {
      Write-Log "Sem permissão" "ERROR"
      continue
    }

    $xmlPath = Join-Path $dir.FullName "gamelist.xml"
    $existing = Load-XmlSafe $xmlPath

    $existingMap = @{}

    if ($existing) {
      foreach ($g in $existing.gameList.game) {
        if ($g.path) {
          $existingMap[$g.path] = $g
        }
      }
    }

    # =========================
    # DESCOBERTA
    # =========================

    $currentPaths = @()
    $newNodes = @()

    if ($dir.Name -ieq "windows") {
      $items = Get-ChildItem $dir.FullName -Directory
      foreach ($i in $items) {
        $path = "./$($i.Name)/"
        $currentPaths += $path

        if (-not $existingMap.ContainsKey($path)) {
          $newNodes += @{
            path = $path
            name = $i.Name
          }
        }
      }
    }
    else {
      $items = Get-ChildItem $dir.FullName -File | Where-Object {
        $_.Extension -notin @(".xml", ".ps1", ".json", ".txt", ".sha256", ".bat", ".sh")
      }

      foreach ($i in $items) {
        $path = "./$($i.Name)"
        $name = [IO.Path]::GetFileNameWithoutExtension($i.Name)

        $currentPaths += $path

        if (-not $existingMap.ContainsKey($path)) {
          $newNodes += @{
            path = $path
            name = $name
          }
        }
      }
    }

    # =========================
    # FILTRO
    # =========================

    $final = @()

    if ($existing) {
      foreach ($g in $existing.gameList.game) {
        if ($currentPaths -contains $g.path) {
          $final += $g
        }
        else {
          Write-Log "Removendo órfão: $($g.path)" "WARN"
        }
      }
    }

    # =========================
    # BUILD XML
    # =========================

    $doc = New-Object System.Xml.XmlDocument

    $decl = $doc.CreateXmlDeclaration("1.0", "UTF-8", $null)
    $doc.AppendChild($decl) | Out-Null

    $rootNode = $doc.CreateElement("gameList")
    $doc.AppendChild($rootNode) | Out-Null

    # existentes preservados
    foreach ($g in $final) {
      $import = $doc.ImportNode($g, $true)
      $rootNode.AppendChild($import) | Out-Null
    }

    # novos
    foreach ($n in $newNodes) {
      $node = Create-GameNode -Doc $doc -Path $n.path -Name $n.name
      $rootNode.AppendChild($node) | Out-Null
    }

    if ($WhatIf) {
      Write-Host "[WHATIF] $xmlPath atualizado" -ForegroundColor Yellow
      continue
    }

    # escrita atômica
    $tmp = "$xmlPath.tmp"
    $doc.Save($tmp)
    Move-Item $tmp $xmlPath -Force

    Write-Host "OK: atualizado" -ForegroundColor Green
  }

  Write-Host "`nConcluído." -ForegroundColor Gray
}
catch {
  Write-Log "Erro fatal: $($_.Exception.Message)" "ERROR"
  exit 1
}