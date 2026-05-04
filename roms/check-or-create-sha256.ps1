param(
  [switch]$DryRun,
  [switch]$VerifyOnly,
  [string]$LogPath = ".\sha256_log.jsonl"
)

# ================================
# CONFIG
# ================================
$validExt = @('.zip', '.7z', '.iso', '.gen', '.chd', '.z64', '.nes', '.sfc', '.smc', '.bin', '.cue')

# ================================
# LOG
# ================================
function Write-Log {
  param(
    [string]$Level,
    [string]$Message,
    [string]$File,
    [hashtable]$Extra = @{}
  )

  $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

  switch ($Level) {
    "OK" { Write-Host "[OK]    $File" -ForegroundColor DarkGreen }
    "FIX" { Write-Host "[FIX]   $File" -ForegroundColor Green }
    "INFO" { Write-Host "[INFO]  $File" -ForegroundColor Cyan }
    "WARN" { Write-Host "[WARN]  $File" -ForegroundColor Yellow }
    "ERROR" {
      Write-Host "[ERROR] $File" -ForegroundColor White -BackgroundColor DarkRed
      if ($Message) { Write-Host "        -> $Message" -ForegroundColor Red }
    }
    default { Write-Host "[$Level] $File" }
  }

  try {
    $obj = @{
      time  = $timestamp
      level = $Level
      file  = $File
      msg   = $Message
    } + $Extra

    $json = $obj | ConvertTo-Json -Compress -Depth 5
    Add-Content -LiteralPath $LogPath -Value $json -Encoding UTF8
  }
  catch {
    # PROTECAO: falha de log não interrompe execução
  }
}

# ================================
# HELPERS
# ================================
function Get-HashSafe {
  param([string]$Path)

  try {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash
  }
  catch {
    throw "Falha ao calcular hash: $($_.Exception.Message)"
  }
}

function Build-TreeHash {
  param([string]$Base)

  $result = @{}

  Get-ChildItem -LiteralPath $Base -Force -ErrorAction SilentlyContinue | ForEach-Object {

    # PROTECAO: ignorar qualquer .sha256.json (novo padrão fora da pasta não entra aqui, mas mantém compatibilidade)
    if ($_.Name -like "*.sha256.json") { return }

    if ($_.PSIsContainer) {
      $result[$_.Name] = Build-TreeHash $_.FullName
    }
    else {
      $result[$_.Name] = Get-HashSafe $_.FullName
    }
  }

  return $result
}

function Validate-Tree {
  param(
    [string]$BasePath,
    [object]$Node
  )

  Get-ChildItem -LiteralPath $BasePath -Force -ErrorAction SilentlyContinue | ForEach-Object {

    # PROTECAO: ignorar qualquer .sha256.json
    if ($_.Name -like "*.sha256.json") { return }

    if (-not $Node.PSObject.Properties[$_.Name]) {
      Write-Log "ERROR" "item não presente no json" (Get-RelativePathSafe $_.FullName)
      $script:hasError = $true
      continue
    }

    $entry = $Node.$($_.Name)

    if ($_.PSIsContainer) {
      if ($entry -isnot [psobject]) {
        Write-Log "ERROR" "esperado diretório, mas json contém hash" (Get-RelativePathSafe $_.FullName)
        $script:hasError = $true
        continue
      }

      Validate-Tree $_.FullName $entry
    }
    else {
      try {
        $realHash = Get-HashSafe $_.FullName

        if ($entry -ne $realHash) {
          Write-Log "ERROR" "hash divergente → arquivo alterado" (Get-RelativePathSafe $_.FullName)
          $script:hasError = $true
        }
      }
      catch {
        Write-Log "ERROR" "falha ao calcular hash → $($_.Exception.Message)" (Get-RelativePathSafe $_.FullName)
        $script:hasError = $true
      }
    }
  }
}

function Parse-Sha256 {
  param([string]$ShaPath)

  try {
    $line = Get-Content -LiteralPath $ShaPath -TotalCount 1 -ErrorAction Stop

    if (-not $line) { return $null }

    $line = $line.Trim()

    if ($line -match '^[A-Fa-f0-9]{64}') {
      return $Matches[0].ToUpperInvariant()
    }

    return $null
  }
  catch {
    return $null
  }
}

function Write-Sha256 {
  param(
    [string]$ShaPath,
    [string]$Hash,
    [string]$FileName
  )

  try {
    $tmp = "$ShaPath.tmp"
    $content = "$Hash  $FileName"

    [System.IO.File]::WriteAllText($tmp, $content, [System.Text.Encoding]::ASCII)
    Move-Item -LiteralPath $tmp -Destination $ShaPath -Force
  }
  catch {
    throw "Falha ao escrever sha256: $($_.Exception.Message)"
  }
}

function Get-RelativePathSafe {
  param([string]$FullPath)

  try {
    return (Resolve-Path -LiteralPath $FullPath -Relative -ErrorAction Stop)
  }
  catch {
    try {
      $base = (Get-Location).Path.TrimEnd('\')
      if ($FullPath.StartsWith($base, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $FullPath.Substring($base.Length).TrimStart('\')
      }
    }
    catch {}

    return $FullPath
  }
}

# ================================
# LIMPEZA SHA256
# ================================
Get-ChildItem -Recurse -File -Filter "*.sha256" -ErrorAction SilentlyContinue | ForEach-Object {

  $shaPath = $_.FullName
  $relPath = Get-RelativePathSafe $shaPath

  try {
    $line = Get-Content -LiteralPath $shaPath -TotalCount 1 -ErrorAction Stop
    if (-not $line) { throw "arquivo vazio" }

    $line = $line.Trim()

    if ($line -notmatch '^([A-Fa-f0-9]{64})\s+(.+)$') {
      throw "formato inválido"
    }

    $expectedHash = $Matches[1].ToUpperInvariant()
    $expectedName = $Matches[2]

    $dir = Split-Path $shaPath -Parent
    $expectedPath = Join-Path $dir $expectedName

    $found = $false

    if (Test-Path -LiteralPath $expectedPath) {
      try {
        if ((Get-HashSafe $expectedPath) -eq $expectedHash) {
          $found = $true
        }
      }
      catch {}
    }

    if (-not $found) {
      Get-ChildItem -LiteralPath $dir -File | ForEach-Object {
        if ($_.FullName -eq $shaPath) { return }

        try {
          if ((Get-HashSafe $_.FullName) -eq $expectedHash) {
            $found = $true
            return
          }
        }
        catch {}
      }
    }

    if (-not $found) {
      if ($DryRun) {
        Write-Log "WARN" "sha256 órfão → seria removido" $relPath
      }
      else {
        Remove-Item -LiteralPath $shaPath -Force -ErrorAction Stop
        Write-Log "FIX" "sha256 órfão removido" $relPath
      }
    }
  }
  catch {
    if (-not $DryRun) {
      Remove-Item -LiteralPath $shaPath -Force -ErrorAction Stop
      Write-Log "FIX" "sha256 inválido removido" $relPath
    }
  }
}

# ================================
# WINDOWS JSON VALIDATION (FIX ESTRUTURAL)
# ================================
$windowsRoot = Join-Path (Get-Location) "windows"

if (Test-Path $windowsRoot) {

  Get-ChildItem -LiteralPath $windowsRoot -Directory | ForEach-Object {

    $rootDir = $_
    # FIX-BUG: mover json para nível ./windows/<foldername>.sha256.json
    $jsonPath = Join-Path $windowsRoot ($rootDir.Name + ".sha256.json")
    $relPath = Get-RelativePathSafe $jsonPath

    $script:hasError = $false  # FIX-BUG: reset por diretório

    if (-not (Test-Path $jsonPath)) {

      Write-Log "INFO" "json ausente → será criado" $relPath

      if (-not $DryRun) {
        try {
          $tree = Build-TreeHash $rootDir.FullName
          $json = ($tree | ConvertTo-Json -Depth 100 -Compress)

          $tmp = "$jsonPath.tmp"
          [System.IO.File]::WriteAllText($tmp, $json, [System.Text.Encoding]::UTF8)
          Move-Item -LiteralPath $tmp -Destination $jsonPath -Force

          Write-Log "FIX" "json criado" $relPath
        }
        catch {
          Write-Log "ERROR" "falha ao escrever json → $($_.Exception.Message)" $relPath
        }
      }

      return
    }

    try {
      $storedTree = Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json
    }
    catch {
      Write-Log "ERROR" "json inválido" $relPath
      return
    }

    Validate-Tree $rootDir.FullName $storedTree

    if ($hasError) {
      Write-Log "ERROR" "json divergente → não corrigido" $relPath
    }
    else {
      Write-Log "OK" "json consistente" $relPath
    }
  }
}

# ================================
# EXECUÇÃO NORMAL
# ================================
Get-ChildItem -Recurse -File | Where-Object {
  $_.FullName -notmatch '\\windows\\' -and
  $validExt -contains $_.Extension.ToLowerInvariant()
} | ForEach-Object {

  $filePath = $_.FullName
  $relPath = Get-RelativePathSafe $filePath
  $shaPath = "$filePath.sha256"

  try {
    $currentHash = Get-HashSafe $filePath
  }
  catch {
    Write-Log "ERROR" "falha hash" $relPath
    return
  }

  $exists = Test-Path $shaPath
  $storedHash = if ($exists) { Parse-Sha256 $shaPath } else { $null }

  if ($VerifyOnly) {
    if (-not $storedHash) {
      Write-Log "ERROR" "sha256 inválido" $relPath
    }
    elseif ($storedHash -eq $currentHash) {
      Write-Log "OK" "hash válido" $relPath
    }
    else {
      Write-Log "ERROR" "hash divergente" $relPath
    }
    return
  }

  $regenerate = $false

  if (-not $exists -or -not $storedHash) {
    $regenerate = $true
  }
  elseif ($storedHash -ne $currentHash) {
    Write-Log "ERROR" "hash divergente → não corrigido" $relPath
  }
  else {
    Write-Log "OK" "hash consistente" $relPath
  }

  if ($regenerate -and -not $DryRun) {
    Write-Sha256 $shaPath $currentHash $_.Name
    Write-Log "FIX" "sha256 regenerado" $relPath
  }
}