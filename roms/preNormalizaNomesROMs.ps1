[CmdletBinding(SupportsShouldProcess = $true)]
param()

# ================= CONFIG =================

$ValidExtensions = @(
  'sha256', 'chd', 'pbp', '7z', 'zip', 'nes', 'smc', 'sfc', 'fig', 'n64', 'z64', 'v64',
  'gb', 'gbc', 'gba', 'nds', '3ds', 'cia', 'iso', 'wbfs', 'rvz', 'sms', 'md', 'smd',
  'gen', 'bin', 'gg', 'gdi', 'cdi', 'cue', 'img', 'cso', 'neo', 'a26', 'pce'
)

$ValidExtSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$ValidExtensions | ForEach-Object { [void]$ValidExtSet.Add($_) }

$ValidIdiomas = @(
  'BR', 'USA', 'US', 'EUR', 'EU', 'JP', 'JPN', 'JAPAN', 'EN', 'PT', 'ES', 'FR', 'DE', 'IT', 'BR-BR'
)

$IdiomaPriority = @('BR', 'PT', 'USA')

# ================= CORE HELPERS =================

function Split-IdiomaTokens {
  param([string]$text)

  $tokens = @()

  foreach ($m in [regex]::Matches($text, '\(([^)]+)\)')) {
    $content = $m.Groups[1].Value

    foreach ($part in ($content -split '[/,;\-]')) {
      $val = $part.Trim().ToUpperInvariant()
      if ($val -and ($ValidIdiomas -contains $val)) {
        $tokens += $val
      }
    }
  }

  return $tokens
}

function Select-Idioma {
  param([string[]]$tokens)

  if (-not $tokens -or $tokens.Count -eq 0) { return $null }

  foreach ($p in $IdiomaPriority) {
    if ($tokens -contains $p) {
      return "($p)"
    }
  }

  return "($($tokens[0]))"
}

function Get-IdiomaSeguro {
  param([string]$text)

  $tokens = Split-IdiomaTokens $text
  return Select-Idioma $tokens
}

function Get-IdSeguro {
  param([string]$text)

  if (-not $text) { return $null }

  $validIds = @()

  foreach ($m in [regex]::Matches($text, '\[([^\]]+)\]')) {
    $raw = $m.Groups[1].Value.Trim()

    # aceita apenas números puros
    if ($raw -match '^\d+$') {
      $validIds += $raw
    }
  }

  if ($validIds.Count -eq 0) { return $null }

  # 🔒 último ID válido vence (regra definida)
  return "[" + $validIds[-1] + "]"
}

function Remove-NoiseMarkers {
  param([string]$text)

  if (-not $text) { return $null }

  # Remove TODOS () e []
  $t = $text -replace '\s*\([^)]*\)', ''
  $t = $t -replace '\s*\[[^\]]*\]', ''

  # Remove múltiplos espaços
  $t = $t -replace '\s{2,}', ' '

  return $t.Trim()
}

function Normalize-Nome {
  param([string]$nome)

  if (-not $nome) { return $null }

  $n = Remove-NoiseMarkers $nome

  if (-not $n) { return $null }

  # Remoções controladas (conservador)
  $n = $n -replace '\s-\sThe Videogame$', ''

  # Artigo invertido seguro
  if ($n -match '^(?<base>.+),\s(?<artigo>The|A|An)$') {
    if ($matches['base'] -notmatch '-') {
      $n = "$($matches['artigo']) $($matches['base'])"
    }
  }

  # Normalização de espaços
  $n = $n -replace '\s{2,}', ' '

  # TitleCase (controlado)
  $n = $n.Trim().ToLowerInvariant()
  return ([cultureinfo]::InvariantCulture.TextInfo).ToTitleCase($n)
}

function Extract-Extensions {
  param([string]$fileName)

  if (-not $fileName) { return $null }

  $parts = $fileName -split '\.'
  if ($parts.Count -lt 2) { return $null }

  $exts = @()

  for ($i = $parts.Count - 1; $i -gt 0; $i--) {

    $candidate = $parts[$i]

    # remove lixo tipo "(1)"
    $candidate = $candidate -replace '\s*\(.*?\)', ''
    $candidate = $candidate.Trim()

    if ($ValidExtSet.Contains($candidate)) {
      $exts = , $candidate + $exts
    }
    else {
      break
    }
  }

  if ($exts.Count -eq 0) { return $null }

  $baseIndex = $parts.Count - $exts.Count - 1
  if ($baseIndex -lt 0) { return $null }

  $baseName = ($parts[0..$baseIndex] -join '.')

  return [pscustomobject]@{
    Base       = $baseName
    Extensions = $exts
  }
}

function Remove-InvalidFileNameChars {
  param([string]$name)

  if (-not $name) { return $null }

  $invalid = [IO.Path]::GetInvalidFileNameChars()
  foreach ($c in $invalid) {
    $name = $name -replace [regex]::Escape($c), ''
  }

  return $name.TrimEnd(' ', '.')
}

function Get-UniqueFileName {
  param($dir, $name)

  $base = [IO.Path]::GetFileNameWithoutExtension($name)
  $ext = [IO.Path]::GetExtension($name)

  $i = 1
  $candidate = $name

  while (Test-Path -LiteralPath (Join-Path $dir $candidate)) {
    $candidate = "$base ($i)$ext"
    $i++
    if ($i -gt 9999) { throw "Colisão infinita" }
  }

  return $candidate
}

# ================= MAIN =================

[int]$total = 0; [int]$renamed = 0; [int]$skipped = 0; [int]$errors = 0

Get-ChildItem -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {

  $total++

  try {
    $file = $_

    $parsed = Extract-Extensions $file.Name
    if (-not $parsed) { $skipped++; return }

    $rawBase = $parsed.Base
    $exts = $parsed.Extensions

    # EXTRAÇÃO ANTES DE QUALQUER MODIFICAÇÃO
    $idioma = Get-IdiomaSeguro $rawBase
    $id = Get-IdSeguro $rawBase

    # NORMALIZAÇÃO
    $nome = Normalize-Nome $rawBase
    if (-not $nome) { $skipped++; return }

    # RECONSTRUÇÃO CANÔNICA
    $newBase = $nome
    if ($idioma) { $newBase += " $idioma" }
    if ($id) { $newBase += " $id" }

    $newName = "$newBase.$($exts -join '.')"
    $newName = Remove-InvalidFileNameChars $newName

    if (-not $newName) { $skipped++; return }

    # IDEMPOTÊNCIA REAL
    if ($file.Name.Equals($newName, [StringComparison]::Ordinal)) {
      $skipped++; return
    }

    # COLISÃO
    if (Test-Path -LiteralPath (Join-Path $file.DirectoryName $newName)) {
      $newName = Get-UniqueFileName $file.DirectoryName $newName
    }

    if ($PSCmdlet.ShouldProcess($file.Name, "Rename to $newName")) {
      Rename-Item -LiteralPath $file.FullName -NewName $newName -ErrorAction Stop
      Write-Host "[OK] $($file.Name) -> $newName" -ForegroundColor Green
      $renamed++
    }

  }
  catch {
    $errors++
    Write-Host "[ERRO] $($_.Name) :: $($_.Exception.Message)" -ForegroundColor Red
  }
}

Write-Host ""
Write-Host "==== RESUMO ====" -ForegroundColor Cyan
Write-Host "Total: $total | Renomeados: $renamed | Ignorados: $skipped | Erros: $errors"