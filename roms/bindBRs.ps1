#!/usr/bin/env pwsh
# shellcheck shell=powershell

<#
.SYNOPSIS
  Varre recursivamente o diretório atual em busca de ROMs contendo "(br)"
  no basename (case-insensitive) e gera/atualiza o arquivo "brs.json".

.DESCRIPTION
  - Compatível com:
      * Windows PowerShell 5.1
      * PowerShell 7.4+

  - Não requer parâmetros.
  - O script SEMPRE opera a partir do diretório onde o próprio script está localizado.
  - O script IGNORA:
      * o próprio brs.json
      * arquivos .ps1
      * diretórios inacessíveis
      * links simbólicos problemáticos/reentrantes

  - Estrutura do JSON:
      {
        "subdir": {
          "folder": {
            "arquivos": [
              "Nome do Jogo"
            ]
          }
        }
      }

  - Regras:
      * diretórios => objetos JSON
      * arquivos => lista "arquivos"
      * cada item da lista contém:
          - nome limpo
          - sem extensão
          - truncado antes do primeiro:
              "[" ou "(" ou "."
      * "(br)" é detectado no basename original
      * detecção é case-insensitive

  - O script é resiliente:
      * trata exceções individualmente
      * mantém logs visíveis
      * evita corrupção do JSON
      * evita duplicações
      * ordena resultados
      * preserva Unicode

.NOTES
  O script NÃO aceita ser usado como biblioteca/importado.
#>

Set-StrictMode -Version 2

$ErrorActionPreference = 'Stop'

# ============================================================================
# HARDENING / COMPATIBILIDADE
# ============================================================================

try {
  chcp 65001 > $null
}
catch {}

try {
  [Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
  [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
}
catch {}

try {
  $OutputEncoding = [System.Text.UTF8Encoding]::new($false)
}
catch {}

# ============================================================================
# LOCALIZAÇÃO DO SCRIPT
# ============================================================================

function Get-ScriptRoot {
  try {

    if ($PSScriptRoot) {
      return $PSScriptRoot
    }

    if ($MyInvocation.MyCommand.Path) {
      return (Split-Path -LiteralPath $MyInvocation.MyCommand.Path -Parent)
    }

    return (Get-Location).Path

  }
  catch {
    Write-Host "[FATAL] Falha ao resolver diretório do script: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
  }
}

$ScriptRoot = Get-ScriptRoot

# ============================================================================
# CONFIGURAÇÃO
# ============================================================================

$JsonPath = Join-Path $ScriptRoot 'brs.json'

# Extensões típicas de ROM/imagem compactada
# (normalizadas para lower-case)
$AllowedExtensions = @(
  '.7z',
  '.zip',
  '.rar',
  '.chd',
  '.cue',
  '.iso',
  '.bin',
  '.img',
  '.mdf',
  '.nrg',
  '.ccd',
  '.sub',
  '.toc',
  '.pbp',
  '.cso',
  '.gdi',
  '.rvz',
  '.wbfs',
  '.wia',
  '.elf',
  '.smc',
  '.sfc',
  '.nes',
  '.fds',
  '.gba',
  '.gb',
  '.gbc',
  '.nds',
  '.3ds',
  '.n64',
  '.z64',
  '.v64',
  '.a26',
  '.sms',
  '.gg',
  '.gen',
  '.md',
  '.32x',
  '.pce',
  '.sgx',
  '.ws',
  '.wsc',
  '.ngp',
  '.ngc',
  '.m3u'
)

# ============================================================================
# LOG
# ============================================================================

function Write-Log {
  param(
    [ValidateSet('INFO', 'WARN', 'ERROR', 'OK')]
    [string] $Level,

    [string] $Message
  )

  $color = switch ($Level) {
    'INFO' { 'Cyan' }
    'WARN' { 'Yellow' }
    'ERROR' { 'Red' }
    'OK' { 'Green' }
    default { 'White' }
  }

  Write-Host "[$Level] $Message" -ForegroundColor $color
}

# ============================================================================
# NORMALIZAÇÃO DE NOME
# ============================================================================

function Get-CleanGameName {
  param(
    [Parameter(Mandatory)]
    [string] $BaseName
  )

  try {

    $name = $BaseName

    # Remove a partir do primeiro:
    # [
    # (
    # .
    #
    # Ex:
    #   Zelda (BR) [Hack]
    #   Mario.USA
    #
    # Resultado:
    #   Zelda
    #   Mario

    $match = [regex]::Match($name, '^[^\[\(\.]+')

    if ($match.Success) {
      $name = $match.Value
    }

    # Sanitização final
    $name = $name.Trim()

    # Colapsa espaços múltiplos
    $name = ($name -replace '\s+', ' ').Trim()

    if ([string]::IsNullOrWhiteSpace($name)) {
      return $null
    }

    return $name

  }
  catch {
    Write-Log ERROR "Falha ao limpar nome '$BaseName': $($_.Exception.Message)"
    return $null
  }
}

# ============================================================================
# CRIA NÓ DE DIRETÓRIO
# ============================================================================

function Ensure-DirectoryNode {
  param(
    [hashtable] $Root,
    [string[]]  $Segments
  )

  $current = $Root

  foreach ($segment in $Segments) {

    if (-not $current.ContainsKey($segment)) {
      $current[$segment] = @{}
    }

    if (-not ($current[$segment] -is [hashtable])) {
      $current[$segment] = @{}
    }

    $current = $current[$segment]
  }

  return $current
}

# ============================================================================
# ENUMERAÇÃO SEGURA
# ============================================================================

function Get-SafeFiles {
  param(
    [Parameter(Mandatory)]
    [string] $Root
  )

  $results = New-Object System.Collections.ArrayList

  try {

    $items = Get-ChildItem `
      -LiteralPath $Root `
      -Recurse `
      -File `
      -Force `
      -Attributes !ReparsePoint `
      -ErrorAction SilentlyContinue

    foreach ($item in $items) {

      # Ignora arquivos temporários/sistema
      if (
        $item.Attributes -band [System.IO.FileAttributes]::Temporary
      ) {
        continue
      }

      if (
        $item.Name -match '^(?i)(thumbs\.db|desktop\.ini)$'
      ) {
        continue
      }      

      try {

        if (-not $item) {
          continue
        }

        [void] $results.Add($item)

      }
      catch {
        Write-Log WARN "Falha ao processar item intermediário: $($_.Exception.Message)"
      }
    }

  }
  catch {
    Write-Log ERROR "Falha durante varredura recursiva: $($_.Exception.Message)"
  }

  return $results
}

# ============================================================================
# ESTRUTURA BASE
# ============================================================================

$Index = @{}

# ============================================================================
# PROCESSAMENTO
# ============================================================================

Write-Log INFO "Diretório raiz: $ScriptRoot"
Write-Log INFO "Iniciando varredura..."

[int] $MatchedFiles = 0

foreach ($file in (Get-SafeFiles -Root $ScriptRoot)) {

  # Ignora diretórios temporários/problemáticos
  if (
    $file.FullName -match '(?i)[\\\/](recyclebin~|\.ffs_tmp|temp|tmp)[\\\/]'
  ) {
    continue
  }      


  try {

    # --------------------------------------------------------------------
    # IGNORA .PS1
    # --------------------------------------------------------------------

    if ($file.Extension -match '^(?i)\.ps1$') {
      continue
    }

    # --------------------------------------------------------------------
    # IGNORA O JSON
    # --------------------------------------------------------------------

    if ($file.FullName -eq $JsonPath) {
      continue
    }

    # --------------------------------------------------------------------
    # FILTRO DE EXTENSÃO
    # --------------------------------------------------------------------

    $ext = $file.Extension.ToLowerInvariant()

    if ($AllowedExtensions -notcontains $ext) {
      continue
    }

    # --------------------------------------------------------------------
    # DETECÇÃO REGIONAL BRASIL
    # --------------------------------------------------------------------

    $normalizedBaseName = $file.BaseName

    $IsBrazil = (
      $normalizedBaseName -match '(?i)(?:^|[\s\[\(._-])(br|pt-br|brazil|brasil|portuguese)(?:[\s\]\)._ -]|$)'
    )

    if (-not $IsBrazil) {
      continue
    }

    # --------------------------------------------------------------------
    # NOME LIMPO
    # --------------------------------------------------------------------

    $cleanName = Get-CleanGameName -BaseName $file.BaseName

    if ([string]::IsNullOrWhiteSpace($cleanName)) {
      Write-Log WARN "Nome inválido ignorado: $($file.FullName)"
      continue
    }

    # --------------------------------------------------------------------
    # PATH RELATIVO (BLINDADO)
    # --------------------------------------------------------------------

    $relativeDir = ''

    try {

      $parentDir = [System.IO.Path]::GetDirectoryName($file.FullName)

      if ([string]::IsNullOrWhiteSpace($parentDir)) {
        Write-Log WARN "Diretório pai inválido: $($file.FullName)"
        continue
      }

      $rootNormalized = [System.IO.Path]::GetFullPath($ScriptRoot)
      $dirNormalized = [System.IO.Path]::GetFullPath($parentDir)

      # Normaliza separador final
      if (
        -not $rootNormalized.EndsWith(
          [System.IO.Path]::DirectorySeparatorChar.ToString()
        )
      ) {
        $rootNormalized += [System.IO.Path]::DirectorySeparatorChar
      }

      # Comparação case-insensitive compatível PS5.1
      $belongsToRoot = (
        $dirNormalized.ToLowerInvariant().StartsWith(
          $rootNormalized.ToLowerInvariant()
        )
      )

      if (-not $belongsToRoot) {
        Write-Log WARN "Arquivo fora da raiz ignorado: $($file.FullName)"
        continue
      }

      $relativeDir = $dirNormalized.Substring($rootNormalized.Length)

    }
    catch {

      Write-Log WARN (
        "Falha ao calcular path relativo: " +
        $file.FullName +
        " :: " +
        $_.Exception.Message
      )

      continue
    }

    # Normalização final
    $relativeDir = $relativeDir `
      -replace '^[\\\/]+', '' `
      -replace '[\\\/]+$', ''

    $relativeDir = $relativeDir.Trim()

    # --------------------------------------------------------------------
    # SEGMENTOS
    # --------------------------------------------------------------------

    $segments = @()

    if (-not [string]::IsNullOrWhiteSpace($relativeDir)) {

      $segments = $relativeDir `
        -split '[\\/]+' `
      | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_)
      }
    }

    # --------------------------------------------------------------------
    # NAVEGA/CRIA HIERARQUIA
    # --------------------------------------------------------------------

    $node = Ensure-DirectoryNode `
      -Root $Index `
      -Segments $segments

    # --------------------------------------------------------------------
    # CRIA LISTA
    # --------------------------------------------------------------------

    if (-not $node.ContainsKey('arquivos')) {
      $node['arquivos'] = New-Object System.Collections.ArrayList
    }

    # --------------------------------------------------------------------
    # EVITA DUPLICAÇÃO
    # --------------------------------------------------------------------

    if ($node['arquivos'] -notcontains $cleanName) {
      [void] $node['arquivos'].Add($cleanName)
      $MatchedFiles++
    }

    Write-Log OK "Indexado: $cleanName"

  }
  catch {
    Write-Log ERROR "Erro ao processar '$($file.FullName)': $($_.Exception.Message)"
  }
}

# ============================================================================
# ORDENAÇÃO RECURSIVA
# ============================================================================

function Convert-ToOrderedStructure {
  param(
    [Parameter(Mandatory)]
    $Node
  )

  if ($Node -is [System.Collections.IList]) {

    return @(
      $Node |
      Sort-Object -Unique
    )
  }

  if ($Node -is [hashtable]) {

    $ordered = [ordered]@{}

    foreach ($key in ($Node.Keys | Sort-Object)) {
      $ordered[$key] = Convert-ToOrderedStructure $Node[$key]
    }

    return $ordered
  }

  return $Node
}

$OrderedIndex = Convert-ToOrderedStructure $Index

# ============================================================================
# SERIALIZAÇÃO JSON
# ============================================================================

try {

  $json = $OrderedIndex | ConvertTo-Json -Depth 100

  # Escrita atômica
  $tempFile = "$JsonPath.tmp"

  [System.IO.File]::WriteAllText(
    $tempFile,
    $json,
    [System.Text.UTF8Encoding]::new($false)
  )

  Move-Item `
    -LiteralPath $tempFile `
    -Destination $JsonPath `
    -Force

  Write-Log OK "JSON salvo: $JsonPath"
  Write-Log OK "Total indexado: $MatchedFiles"

}
catch {

  Write-Log ERROR "Falha ao salvar JSON: $($_.Exception.Message)"

  try {

    if (Test-Path -LiteralPath $tempFile) {
      Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
    }

  }
  catch {}

  exit 1
}

Write-Log INFO "Processo concluído."