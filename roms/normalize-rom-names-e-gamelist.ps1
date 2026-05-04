#!/usr/bin/env pwsh
# encoding: utf-8

<#
RFC-002 — REFATORAÇÃO RECURSIVA DE ATIVOS E METADADOS (BATOCERA)
Runtime: PowerShell 5.1 | 7.4+

STATUS
  Especificação normativa (estilo CRF). Determinística, idempotente, auditável.

OBJETIVO
  Processar recursivamente árvores com 'gamelist.xml', impondo nomes
  canônicos, coerência de metadados e tradução segura para pt-BR, com
  invariantes estritos e zero efeitos colaterais não intencionais.

TERMOS (RFC)
  MUST (DEVE), MUST NOT (NÃO DEVE), SHOULD (DEVERIA), MAY (PODE).

ESCOPO
  - Varredura recursiva de diretórios contendo 'gamelist.xml'.
  - Operação sobre ROMs referenciadas por <path> e seus metadados.
  - compatibilidade do gamelista.xml total com batocera.

REQUISITOS PRINCIPAIS
  R1. SINCRONIA:
      Nome físico DEVE corresponder a <path>. Renomeações DEVEM atualizar XML.
  R2. BASENAME:
      Capitalizar basename; preservar extensão; impor consistência de case.
  R3. PARÊNTESES:
      - MANTER localidades: (BR), (XX), (BR-XX), formas compostas.
      - REMOVER tags técnicas (ex.: Beta, Rev, Build) e espaço precedente.
      - NORMALIZAR conteúdo restante para MAIÚSCULO.
  R4. IDENTIFICADOR:
      Sufixar " [id]" (sanitizado) antes da extensão usando <game id>.
      Unicidade do nome DEVE ser garantida via [id].
  R5. HASH:
      Se existir *.sha256, DEVE ser renomeado para casar com a ROM (case).
  R6. CASE (WINDOWS):
      Impor unicidade efetiva sensível a maiúsc./minúsc. (evitar colisões).
  R7. TAG <LANG>:
      Se nome contiver "(BR)" ou "(BR-*)", definir <lang>='pt-br'.
  R8. ESTRUTURA:
      Preservar diretórios e paths relativos.

TRADUÇÃO (<desc> → pt-BR)
  T1. FONTE:
      Traduzir via API REST pública com controle de rate limit.
  T2. SKIP:
      Detectar pt-BR pré-existente e pular quando aplicável.
  T3. QUALIDADE:
      - Se saída == entrada após tentativas, MANTER original.
      - Se saída for sem sentido (nomes técnicos), MANTER original.
  T4. LOTE:
      Enviar pequenos lotes (ex.: 5) com delimitadores rastreáveis,
      mesmo quando mal traduzidos, para evitar perda do contexto original,
      e separação clara entre entradas individuais. 
  T5. BACKOFF:
      Backoff exponencial com limite de tentativas.
  T6. CACHE:
      Cachear resultados para evitar requisições duplicadas.

ERROS E SEGURANÇA
  E1. SEM FALHA SILENCIOSA:
      'catch' vazio é PROIBIDO. Toda falha DEVE ser tratada/reportada.
  E2. VALIDAÇÃO:
      Pré-checagem DEVE verificar integridade (entry 'main', delimitadores).
  E3. SANITIZAÇÃO:
      Proteger contra caracteres inválidos, nomes reservados, ROM ausente.
  E4. INTEGRIDADE:
      Preservar encoding e estrutura do XML (zero mutações indevidas).
  E5. PROTEÇÃO:
      Blocos anti-bug DEVEM conter "// PROTECAO: <descrição>".

DIRETRIZES DE IMPLEMENTAÇÃO
  D1. HIERARQUIA:
      Este RFC prevalece sobre instruções conflitantes.
  D2. CIRURGIA:
      Minimizar diffs; sem refatoração estética; preservar comentários/indent.
  D3. DETERMINISMO:
      Linguagem declarativa; regras testáveis.
  D4. IDEMPOTÊNCIA:
      Reexecução NÃO DEVE produzir deriva.

CONTRATO DE I/O
  Entrada: Árvore com 'gamelist.xml' e ROMs.
  Saída:   Arquivos renomeados, XML sincronizado, <desc> em pt-BR,
           hashes consistentes e nomes sem colisão.

CHECKLIST DE CONFORMIDADE (MUST)
  - Todos os <path> correspondem aos arquivos reais.
  - Nomes contêm " [id]" e são únicos.
  - Regras de parênteses aplicadas; localidades preservadas.
  - <lang>='pt-br' quando (BR)/(BR-*) presente.
  - .sha256 (se houver) alinhado à ROM (case sensitive).
  - Sem falhas silenciosas; erros logados em tela/reportados.
  - Encoding/estrutura do XML inalterados fora do escopo.
  - Script deve ser indepotente, fail-safe e auditável.
  - Tradução controlada: detecta pt-BR, backoff, cache, mantém original se falha.
  - Código em microfunções reutilizáveis
  - evitar reimplementar funcionalidade

  [ESTILO, DESIGN & RASTREABILIDADE]
  - Design: Imutabilidade, Baixo Acoplamento e suporte a camelCase/snake_case.
  - Rastreabilidade Diff-Friendly: Alterações de código minimalistas otimizados
                                    para desempenho aliado a análise visual
                                    de mudanças.

  [CAPACIDADES TÉCNICAS (REAPROVEITÁVEIS)]
  - COMPATIBILIDADE: Identificação de versão/subversão para comandos adequados.
  - RESILIÊNCIA: Retry com backoff progressivo e múltiplas formas de tentativa.
  - DETERMINISMO: Validação de estado real pós-operação (não apenas ExitCode).

  [EVENTOS & TELEMETRIA (CALLBACK)]
  - DESACOPLAMENTO: Script não gerencia arquivos de log, apenas em tela
  - AUDITÁVEL: Logs claros, estruturados e informativos para cada etapa crítica,
                 incluindo falhas, decisões de lógica e resultados de validação.

  [REGRAS DE ARQUITETURA]
  - ISOLAMENTO: Mutex Global obrigatório para prevenir paralelismo.
  - MODULARIDADE: Baseado em micro-funções especialistas e reutilizáveis. 
  - SINCRO: Execução 100% síncrona, bloqueante e sequencial:        
  - ESTADO: Barreira de consistência (DISM/CBS) para operações de sistema.
  - NATIVO: Uso estrito de comandos nativos do OS, salvo exceção declarada.

  [DIRETRIZES DE IMPLEMENTAÇÃO]
  - IDEMPOTÊNCIA: Seguro para múltiplas execuções no mesmo ambiente.
  - HEADLESS: Operação plena sem interface gráfica ou interação de usuário.  

  [RESTRIÇÕES / VEDAÇÕES]
  - Não prosseguir com sistema em estado inconsistente ou pendente.
  - Não assumir conectividade de rede (Offline-First por padrão)
    configurável para Online-FIRST.
  - Não depender de módulos externos ou bibliotecas não nativas.
  - Não executar etapas sem validação de sucesso posterior.

  [ESTRUTURA DE EXECUÇÃO]
  1. Inicialização segura (ExecutionPolicy, TLS, Context Check).
  2. Garantia de instância única (Global Mutex).
  3. Validação de pré-requisitos e pilha de manutenção do SO.
  4. Orquestração modular com validação individual de cada micro-função.
  5. Finalização auditável com log rastreável e saída determinística.

  [INVOCAÇÃO]
  O script sempre auto identifica se foi importado ou executado:
  1. Se executado diretamente executa função main repassando parâmetros 
      recebidos por linha de comando ou variáveis de ambiente.
  2. Se importado expõe as funções públicas para serem chamadas por outros
      scripts sem executar nada.  
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# =========================
# CONFIG
# =========================

$VALID_LANG_PATTERNS = @(
  'BR', 'USA', 'US', 'EUR', 'EU', 'JP', 'JPN', 'JAPAN',
  'EN', 'PT', 'ES', 'FR', 'DE', 'IT'
)

$INVALID_FILENAME_CHARS = [System.IO.Path]::GetInvalidFileNameChars()

$WINDOWS_RESERVED_NAMES = @(
  'CON', 'PRN', 'AUX', 'NUL',
  'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
  'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9'
)

$GLOBAL:TRANSLATE_CACHE = @{}

# =========================
# UTIL
# =========================

function Format-FileName {
  param([string]$name)

  $pattern = '\s*\(([^)]*)\)'

  $result = [regex]::Replace($name, $pattern, {
      param($m)

      $content = $m.Groups[1].Value.ToUpper()
      $parts = $content -split '-'

      foreach ($p in $parts) {
        if ($VALID_LANG_PATTERNS -notcontains $p) {
          return '' # remove metadado técnico
        }
      }

      return " ($($parts -join '-'))"
    })

  $clean = ($result.Trim() -replace '\s{2,}', ' ') # PROTECAO

  $ext = [System.IO.Path]::GetExtension($clean)
  $base = [System.IO.Path]::GetFileNameWithoutExtension($clean)

  if ($base) {
    $base = ($base.Substring(0, 1).ToUpper() + $base.Substring(1))
  }

  return "$base$ext"
}

function Get-LangTag {
  param([string]$name)

  if ($name -match '\((BR([-\w]+)?)\)') {
    return 'pt-br'
  }

  return $null
}

function Remove-InvalidFileNameChars {
  param([string]$name)

  foreach ($char in $INVALID_FILENAME_CHARS) {
    $name = $name -replace [regex]::Escape($char), ''
  }

  $name = $name.TrimEnd('.', ' ')

  $base = [System.IO.Path]::GetFileNameWithoutExtension($name)
  $ext = [System.IO.Path]::GetExtension($name)

  if ($WINDOWS_RESERVED_NAMES -contains $base.ToUpper()) {
    $base = "_$base" # PROTECAO
  }

  if (-not $base) {
    $base = "file" # PROTECAO
  }

  return "$base$ext"
}

function Set-IdOnName {
  param(
    [string]$name,
    [string]$id
  )

  if (-not $id) { return $name }

  $id = ($id -replace '[^\w\-]', '') # PROTECAO

  $ext = [System.IO.Path]::GetExtension($name)
  $base = [System.IO.Path]::GetFileNameWithoutExtension($name)

  if ($base -match '\s\[[^\]]+\]$') {
    return $name
  }

  return "$base [$id]$ext"
}

function Test-Portuguese {
  param([string]$text)

  if (-not $text) { return $false }

  $score = 0
  if ($text -match '\b(de|da|do|para|com|uma|não|que|em)\b') { $score++ }
  if ($text -match '[ãõçáéíóú]') { $score++ }

  return ($score -ge 2) # PROTECAO
}

function Invoke-TextTranslation {
  param(
    [string[]]$texts
  )

  if (-not $texts -or $texts.Count -eq 0) { return @() }

  $results = @()
  $batchSize = 5
  $delimiter = "|||SEP|||"

  for ($i = 0; $i -lt $texts.Count; $i += $batchSize) {

    $batch = $texts[$i..([math]::Min($i + $batchSize - 1, $texts.Count - 1))]

    $toTranslate = @()
    foreach ($t in $batch) {
      if (-not $t) {
        $toTranslate += ""
        continue
      }

      $key = $t.ToLowerInvariant()

      if ($GLOBAL:TRANSLATE_CACHE.ContainsKey($key)) {
        $toTranslate += $null
      }
      else {
        $toTranslate += $t
      }
    }

    $joined = ($toTranslate | ForEach-Object { if ($_ -ne $null) { $_ } else { "" } }) -join " $delimiter "

    for ($retry = 0; $retry -lt 3; $retry++) {
      try {
        $uri = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=pt&dt=t&q=$([uri]::EscapeDataString($joined))"
        $res = Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec 10

        $translatedRaw = ($res[0] | ForEach-Object { $_[0] }) -join ''
        $split = $translatedRaw -split [regex]::Escape($delimiter)

        for ($j = 0; $j -lt $batch.Count; $j++) {
          $original = $batch[$j]

          if (-not $original) {
            $results += ""
            continue
          }

          $cacheKey = $original.ToLowerInvariant() # FIX-BUG: consistência de chave

          if ($GLOBAL:TRANSLATE_CACHE.ContainsKey($cacheKey)) {
            $results += $GLOBAL:TRANSLATE_CACHE[$cacheKey]
            continue
          }

          $translated = if ($j -lt $split.Count) { $split[$j].Trim() } else { "" } # PROTECAO

          if (-not $translated -or $translated -eq $original) {
            $translated = $original # PROTECAO
          }

          $GLOBAL:TRANSLATE_CACHE[$original.ToLowerInvariant()] = $translated # FIX-BUG: chave normalizada
          $results += $translated
        }

        Start-Sleep -Milliseconds 200
        break
      }
      catch {
        Write-Host "[ERRO][Invoke-TextTranslation] tentativa=$retry msg=$($_.Exception.Message)" # PROTECAO
        Start-Sleep -Seconds (2 * ($retry + 1))
      }
    }
  }

  return $results
}

function Get-UniquePath {
  param([string]$path)

  $dir = [System.IO.Path]::GetDirectoryName($path)
  $name = [System.IO.Path]::GetFileNameWithoutExtension($path)
  $ext = [System.IO.Path]::GetExtension($path)

  $existing = Get-ChildItem -Path $dir -File | ForEach-Object { $_.Name.ToLowerInvariant() } # PROTECAO

  $target = ([System.IO.Path]::GetFileName($path)).ToLowerInvariant()

  if ($existing -notcontains $target) {
    return $path
  }

  $i = 1
  do {
    $candidate = Join-Path $dir "$name ($i)$ext"
    $candidateName = ([System.IO.Path]::GetFileName($candidate)).ToLowerInvariant()
    $i++
  } while ($existing -contains $candidateName)

  return $candidate
}

# =========================
# CORE
# =========================

function Invoke-GamelistProcessing {
  param([string]$xmlPath)

  try {
    [xml]$xml = Get-Content $xmlPath -Raw
  }
  catch {
    throw "XML inválido: $xmlPath :: $($_.Exception.Message)" # PROTECAO
  }

  $baseDir = Split-Path $xmlPath

  $toTranslate = @()
  $map = @()

  foreach ($game in $xml.gameList.game) {

    if (-not $game.path) { continue }

    # PROTECAO: suporta XmlNode e string simples
    if ($game.path -is [string]) {
      $relativePath = $game.path
    }
    elseif ($game.path.'#text') {
      $relativePath = $game.path.'#text'
    }
    else {
      continue # PROTECAO: estrutura inesperada
    }

    $fullPath = Join-Path $baseDir $relativePath

    if (-not (Test-Path $fullPath)) {
      continue # PROTECAO: ROM ausente
    }

    $fileName = [System.IO.Path]::GetFileName($fullPath)

    # pipeline correto
    $newName = Format-FileName $fileName
    $newName = Remove-InvalidFileNameChars $newName

    # FIX-BUG: acesso seguro ao <id> (pode não existir)
    $gameIdNode = $game.SelectSingleNode("id")
    $gameId = if ($null -ne $gameIdNode) { $gameIdNode.InnerText } else { $null }

    $newName = Set-IdOnName -name $newName -id $gameId
    $newName = Remove-InvalidFileNameChars $newName

    $originalDir = [System.IO.Path]::GetDirectoryName($fullPath)
    $newFullPath = Join-Path $originalDir $newName
    $newFullPath = Get-UniquePath $newFullPath

    if ($fullPath -ne $newFullPath -and -not (Test-Path $newFullPath)) {
      Rename-Item -Path $fullPath -NewName (Split-Path $newFullPath -Leaf)

      # PROTECAO: sincroniza sha256
      # PROTECAO: sincroniza sha256
      $oldHash = Get-ChildItem -Path $originalDir -Filter "$fileName*.sha256" -ErrorAction SilentlyContinue | Select-Object -First 1

      $newHashBase = [System.IO.Path]::GetFileNameWithoutExtension($newFullPath) # FIX-BUG: remove extensão antes de gerar .sha256
      $newHash = Join-Path $originalDir "$newHashBase.sha256"

      if ($oldHash) {
        Rename-Item -Path $oldHash.FullName -NewName (Split-Path $newHash -Leaf)
      }
    }

    # path relativo preservando subpastas
    try {
      if ([System.IO.Path].GetMethod("GetRelativePath")) {
        $relative = "./" + [System.IO.Path]::GetRelativePath($baseDir, $newFullPath).Replace('\', '/')
      }
      else {
        # FIX-BUG: compatibilidade PowerShell 5.1
        $uriBase = New-Object System.Uri(($baseDir.TrimEnd('\') + '\'))
        $uriFull = New-Object System.Uri($newFullPath)
        $relative = "./" + $uriBase.MakeRelativeUri($uriFull).ToString().Replace('/', '/')
      }
    }
    catch {
      Write-Host "[ERRO][GetRelativePath] fallback aplicado :: $($_.Exception.Message)" # FIX-BUG: evita falha silenciosa
      $relative = "./" + (Split-Path $newFullPath -Leaf) # PROTECAO
    }
    # PROTECAO: mantém formato original do XML
    if ($game.path -is [string]) {
      $game.path = $relative
    }
    elseif ($null -ne $game.path.'#text') {
      $game.path.'#text' = $relative
    }
    else {
      $game.path = $relative # fallback seguro
    }

    # coleta para tradução (fora do loop principal)    

    # FIX-BUG: acesso seguro ao <desc> (pode não existir)
    $descNode = $game.SelectSingleNode("desc")
    $descValue = if ($null -ne $descNode) { $descNode.InnerText } else { $null }

    if ($descValue -and -not (Test-Portuguese $descValue)) {
      $map += $descNode # FIX-BUG: armazena nó diretamente
      $toTranslate += $descValue
    }

    # força lang
    $detectedLang = Get-LangTag $newName # FIX-BUG: remoção de duplicação redundante
    if ($detectedLang -eq 'pt-br') {

      $langNode = $game.SelectSingleNode("lang") # FIX-BUG: acesso seguro compatível com StrictMode

      if ($null -ne $langNode) {
        $langNode.InnerText = 'pt-br'
      }
      else {
        # PROTECAO: cria nó <lang> quando ausente
        $newLang = $xml.CreateElement("lang")
        $newLang.InnerText = "pt-br"
        [void]$game.AppendChild($newLang)
      }
    }
  }

  # tradução em lote (executa uma única vez)
  if ($toTranslate.Count -gt 0) {
    $translated = Invoke-TextTranslation $toTranslate

    for ($i = 0; $i -lt $map.Count; $i++) {
      $node = $map[$i]

      if ($i -lt $translated.Count -and $null -ne $node) {
        $node.InnerText = $translated[$i] # FIX-BUG: escrita segura no nó <desc>
      }
      else {
        # PROTECAO: mantém valor original quando tradução falha
        if ($null -ne $node) {
          $node.InnerText = $node.InnerText
        }
      }
    }
  }

  # salvar com mínimo impacto
  $content = $xml.OuterXml
  [System.IO.File]::WriteAllText($xmlPath, $content, [System.Text.UTF8Encoding]::new($true)) # PROTECAO
}

# =========================
# ENTRY (COM MAIN)
# =========================

function main {
  param(
    [string]$RootPath = (Get-Location).Path
  )

  if (-not (Test-Path $RootPath)) {
    throw "Caminho inválido: $RootPath" # PROTECAO
  }

  $mutex = New-Object System.Threading.Mutex($false, "Global\BatoceraGamelistMutex")

  if (-not $mutex.WaitOne(0)) {
    throw "Outra instância já está em execução" # PROTECAO
  }

  try {
    Get-ChildItem -Path $RootPath -Recurse -Filter "gamelist.xml" -ErrorAction SilentlyContinue | ForEach-Object {
      Invoke-GamelistProcessing $_.FullName
    }
  }
  finally {
    $mutex.ReleaseMutex()
    $mutex.Dispose()
  }
}

# auto-detecção de execução vs importação
if ($MyInvocation.InvocationName -ne '.') {
  main @args
}