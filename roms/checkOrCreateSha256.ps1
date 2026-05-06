#!/usr/bin/env pwsh
# encoding: utf-8

<#
DOCUMENTO NORMATIVO - RFC-003
TÍTULO: Sistema de Verificação e Manutenção de Integridade SHA256
VERSÃO: 1.0
STATUS: Implementado
COMPATIBILIDADE: PowerShell 5.1 | 7.4+

RESUMO EXECUTIVO:
Este documento especifica o comportamento do sistema de gerenciamento
de arquivos de integridade (.sha256) para ROMs, garantindo:
- Nome do .sha256 deve ser sensitive casase ao arquivo original (com extensão .sha256)
- Verificação e regeneração de hashes SHA256
- Limpeza de arquivos .sha256 órfãos ou inválidos
- Validação estrutural de diretórios via JSON tree
  * JSON tree se ajusta à realidade do filesystem, como se fosse
    um espelho virtual, removendo e incluindo, mas a alteração de hash, somente
    se houver parametro -Fix, caso contrário, apenas log de divergência
- Suporte a dry-run e modo verificação

PARÂMETROS DE ENTRADA:
[-Fix]        : Força a correção de inconsistências (sem prompt) (recria criar os hash inconsistentes)
[-VerifyOnly] : Apenas valida, não corrige inconsistências nem cria hash inexistentes
[]            : cria hash inexistentes e não corrige hash divergentes (apenas log)

* Não deve existir algo equivalente ao conceito `DryRun`

DIRETRIZES OBRIGATÓRIAS:

1. ESCOPO DE ARQUIVOS
   - Extensões válidas: .zip, .7z, .iso, .gen, .chd, .z64, .nes, .sfc, .smc, .bin, .cue
   - Diretório 'steam' tratado como caso especial (JSON tree validation usado como emulador de pastas virtual)
                * comportamento lógico de .sha256 convencional, mas com estrutura hierárquica definida por JSON
   - Arquivos .sha256.json são ignorados em todas as operações
   - .sha256 convencionais operam por arquivo (.ROM.sha256)

2. COMPORTAMENTO POR MODO

   Modo Normal (sem flags):
   - Para cada ROM válida:
     * Se .sha256 ausente ou inválido → regenera
     * Se hash divergente → log ERROR (sem correção automática)
     * Se hash consistente → log OK
   - Limpeza automática de .sha256 órfãos ou mal formatados

   Modo VerifyOnly:
   - Apenas validação, sem escrita
   - Log OK/ERROR para cada arquivo e .sha256

   Modo Fix:
   - Habilita a atualização do hash com base no arquivo real de ROM
   - Corrige automaticamente hash divergente (regrava .sha256) ou valor de
   - JSON divergente   

3. TRATAMENTO ESPECIAL: DIRETÓRIOS CONTIDOS EM $specialJsonDirs

   Requisito estrutural OBRIGATÓRIO:
   - json emula uma pasta virtual (drive virtual)
   - Cada subdiretório DEVE ter um JSON em ./windows/<nome>.sha256.json
     e ./steam/<nome>.sha256.json
   - JSON contém árvore de hashes de todo o subdiretório

   Comportamento:
   - Se JSON ausente → cria automaticamente
   - Se JSON inválido (mal formatado) → log ERROR, sem correção
   - Valida recursivamente todos os arquivos vs JSON
   - Divergência estrutural (arquivo faltante/sobrando) → log ERROR
   - Hash divergente → log ERROR
   - cada item string do json representa um arquivo .sha256 convencional,
     possuindo a mesma lógica aplicada a ele incluindo, mas não se limidando a:
     * hash divergente → log ERROR, correção automática apenas com -Fix
     * hash ausente → regenera hash, log FIX
     * entrada presente no JSON mas ausente no FS → removido
     * entrada presente no FS mas ausente no JSON → log ERROR, sem correção automática
     * outros...

   Estrutura do JSON:
   {
     "subdir1": { "file.bin": "HASH64", "subdir2": { ... } },
     "file.iso": "HASH64"
   }
  
4. REGRAS DE LOG ESTRUTURADO
   
   Cores no console (humanos), sem incuir os dizeres entre []:
   - OK, com alteraçÃo    : Verde escuro ()
   - OK, já estava certo  : Verde escuro (sem alteração)
   - FIX                  : Verde claro
   - INFO                 : Ciano
   - WARN                 : Amarelo
   - ERROR                : Branco sobre fundo vermelho (com msg em vermelho)

    Diretrizes de conteúdo:

    * Log deve indicar ação tomada 
    * log deve indicar o caminho do arquivo afetado (preferencialmente
      relativo) e a operação ocorrendo 
    * log deve preferir reecrista inline (com clear da linha prévio), e logar
      nova line quando conveniente para histórico legível, evitando
      poluição visual e mantendo rastreabilidade de ações em tempo real   
    * Uso de cores e destaques visuais para facilitar identificação de status
      e erros críticos
    * arquivo de log deve ser estruturado e legível por máquina para análises futuras
    * utilize caractere unicode (emoji) único para identificar OK, FIX, INFO, WARN, ERROR:
      - OK    : ✔ (em cor verde)
      - INFO  : ℹ️
      - WARN  : ⚠️
      - ERROR : ❌
    * utilize caracter unicode (emoji) único para identificar ações de HASHING, JSON-VALIDATE, PROCESS, etc:
      - JSON-VALIDATE : 📄
      - PROCESS       : ⚙️
      - VERIFY        : 🔍      
      - CRIANDO-SHA256: ✍️
      - CHANGE-NAME   : 🔤
      - HASHING       : 🧮
      - FIX:          : 🛠️
      - REMOVE-FILE   : 🗑️ (em cor vermelho, se possível)

   PROTEÇÃO: Falha no log NUNCA interrompe a execução             

5. TRATAMENTO DE SHA256 CONVENCIONAL

   Formato esperado (ASCII) (exceto para JSON tree, que guarda apenas o hash puro ASCII):
   "HASH64  filename.ext"
   * filename.ext é o nome do arquivo original, sem caminho, e deve ser case-sensitive

   Regras de validação:
   - Primeira linha define o formato
   - Hash DEVE ter 64 caracteres hexadecimais (case-insensitive)
   - Espaço duplo ou simples? Ambos aceitos (regex: '\s+')

   Resolução de arquivos órfãos:
   - Verifica se filename original existe com hash correspondente
   - Se não, busca QUALQUER arquivo no mesmo dir com hash correspondente
   - Se nenhum encontrado → .sha256 é ORFÃO (remove)

   PROTEÇÃO: Correção automática de hash divergente padrão é apenas log ERROR
             (sem correção automática), mas pode ser forçada com -Fix   
             Nome do .sha256 DEVE ser sensível a case do arquivo original 
             (ex: game.iso.sha256, não game.ISO.sha256)
             Conteúdo possui nome do arquivo e deve ser case-sensitive,
             e isso deve ser conferido

6. FUNÇÕES CORE (ESPECIFICAÇÃO)

   Get-HashSafe:
   - Entrada: Path (string)
   - Saída: SHA256 em uppercase
   - Exceção: throw com mensagem descritiva (nunca silencioso)

   Build-TreeHash:
   - Entrada: Base (string)
   - Saída: Hashtable aninhada (nome → hash ou sub-hashtable)
   - Ignora: qualquer .sha256.json
   - Tratamento: diretórios viram sub-hashtables, arquivos viram hash

   Validate-Tree:
   - Entrada: BasePath (string), Node (objeto do JSON)
   - Saída: Nenhuma (side-effect: logs e $script:hasError)
   - Verifica correspondência 1:1 entre filesystem e JSON
   - Divergência estrutural → log ERROR

   ConvertFrom-Sha256:
   - Entrada: ShaPath (string)
   - Saída: Hash (string) ou $null se inválido
   - Lê apenas primeira linha
   - Aceita hash com/sem espaços à direita

   Write-Sha256:
   - Entrada: ShaPath, Hash, FileName
   - Saída: Nenhuma (side-effect: escrita atômica via arquivo .tmp)
   - Encoding: OBRIGATORIAMENTE ASCII (compatível com padrão)
   - Formato: "HASH  filename"

   Get-RelativePathSafe:
   - Entrada: FullPath (string)
   - Saída: Caminho relativo (se possível) ou absoluto (fallback)
   - Fallback: extração manual se Resolve-Path falhar

7. VARIÁVEIS GLOBAIS DE ESTADO

   $script:hasError:
   - Escopo: por diretórios contidos em $specialJsonDirs validation
   - Reset: a cada novo diretório
   - Uso: detectar divergência para log final consolidado

8. RESILIÊNCIA E PROTEÇÕES

   PROIBIÇÕES:
   - NENHUM 'catch' vazio (todo catch DEVE ter ação ou log)
   - NENHUMA supressão silenciosa de erro (-ErrorAction SilentlyContinue
     só é permitido com tratamento posterior explícito)

   PROTEÇÕES IMPLEMENTADAS:
   - Escrita atômica via .tmp + Move-Item (evita arquivo corrompido)
   - Validação de formato antes de remoção de .sha256
   - Fallback manual em Get-RelativePathSafe
   - Isolamento do diretório contidos em $specialJsonDirs da varredura normal (regex exclusion)

9. COMPORTAMENTO EM CASOS ESPECÍFICOS

   Arquivo .sha256 vazio:
   - Detectado por -not $line após leitura
   - Tratado como inválido → removido

   Hash em lowercase no arquivo:
   - Normalizado para uppercase antes da comparação
   - Escrita SEMPRE em uppercase

   Arquivo original renomeado/movido:
   - Busca por conteúdo (hash scanning) no mesmo diretório
   - Se encontrado → .sha256 preservado e renomeado (sensitive case)   

   Colisão de hash em diretório:
   - Primeiro arquivo encontrado com hash correspondente determina
     o vínculo;
   - Se encontrar mais de um → log WARN de cada, remove os demais, incluindo
     seus .sha256 e entradas no json equivalentes, mas
     mantém o primeiro encontrado intactamente (sem remoção, 
     sem correção automática (exceto se -Fix)

10. LIMITAÇÕES CONHECIDAS (deciões de escopo e trade-offs)

    - Não suporta .sha256 com múltiplas linhas
    - Não renomeia .sha256 automaticamente quando ROM renomeada (exceto se 
      identificar hash correspondente no mesmo diretório)

    - Suporte a symlinks/junctions (apenas se o sistema de arquivos e PowerShell
      permitirem, sem tratamento especial)

11. EXEMPLOS DE USO

    # Verificação completa com regeneração
    .\script.ps1

    # Apenas validar (modo somente leitura)
    .\script.ps1 -VerifyOnly    

    # Log customizado
    .\script.ps1 -LogPath "C:\logs\audit.jsonl"

    # Correção automática de divergências
    .\script.ps1 -Fix

12. CÓDIGOS DE SAÍDA (NÃO EXPLÍCITOS NO SCRIPT ATUAL)

    - 0 : Execução bem sucedida (sem erros críticos)
    - 1 : Erros detectados (hashes divergentes, JSON inválidos)
    - Nota: Script atual não define $LASTEXITCODE explicitamente

13. REGRAS DE CONTEXTO GLOBAL

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
<#
[... CABEÇALHO ORIGINAL PRESERVADO INTEGRALMENTE ...]
#>

param(
  [switch]$Fix,
  [switch]$VerifyOnly,
  [string]$LogPath = ".\sha256_log.jsonl"
)

# ================================
# CONFIG
# ================================
$validExt = @('.zip', '.7z', '.iso', '.gen', '.chd', '.z64', '.nes', '.sfc', '.smc', '.bin', '.cue', 'cp2', '.mvs')
$specialJsonDirs = @('windows', 'steam')

# ================================
# LOG
# ================================
$script:lastInline = ""

function Write-LogInline {
  param(
    [string]$Status,
    [string]$File
  )

  $line = "$Status :: $File"

  # PROTECAO: limpa completamente a linha anterior evitando resíduos visuais
  $prevLen = if ($script:lastInline) { $script:lastInline.Length } else { 0 }
  $currLen = $line.Length

  if ($currLen -lt $prevLen) {
    $pad = ' ' * ($prevLen - $currLen)
    $line = $line + $pad
  }

  if ($script:lastInline -ne $line) {
    $clear = ' ' * [Math]::Max($script:lastInline.Length, $line.Length)
    Write-Host ("`r" + $clear + "`r" + $line) -NoNewline # FIX-BUG: limpeza completa garantida
    $script:lastInline = $line
  }
}

function Write-Log {
  param(
    [string]$Level,
    [string]$Message,
    [string]$File,
    [hashtable]$Extra = @{}
  )

  $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

  # flush linha inline antes de log persistente
  if ($script:lastInline) {
    # PROTECAO: força quebra limpa da linha inline
    Write-Host ("`r" + (' ' * $script:lastInline.Length) + "`r")
    $script:lastInline = ""
  }

  switch ($Level) {
    "OK" { 
      Write-Host "✔ " -ForegroundColor Green -NoNewline
      Write-Host " '$File' :: $Message" -ForegroundColor DarkGray 
    }
    "FIX" { Write-Host "🛠️ Fix: '$File' :: $Message" -ForegroundColor Green }
    "INFO" { Write-Host "ℹ️ '$File' :: $Message" -ForegroundColor Cyan }
    "WARN" { Write-Host "⚠️ '$File' :: $Message" -ForegroundColor Yellow }
    "ERROR" {
      $script:globalError = $true
      Write-Host "❌ '$File'" -ForegroundColor White -BackgroundColor DarkRed
      if ($Message) { Write-Host "        -> $Message" -ForegroundColor Red }
    }
    default {
      Write-Host "[$Level] '$File' :: $Message" # PROTECAO: fallback determinístico
    }
  }

  try {
    $obj = @{
      time  = $timestamp
      level = $Level
      file  = $File
      msg   = $Message
    } + $Extra

    if ($LogPath) {
      try {
        $json = $obj | ConvertTo-Json -Compress -Depth 5
        Add-Content -LiteralPath $LogPath -Value $json -Encoding UTF8
      }
      catch {
        Write-Host "⚠️ Falha ao persistir log JSONL" -ForegroundColor Yellow # FIX-BUG: evitar catch vazio
      }
    }
  }
  catch {
    Write-Host "❌ Falha estrutural no log" -ForegroundColor Red # FIX-BUG: evitar catch vazio
  }
}

# ================================
# HELPERS
# ================================
function Get-HashSafe {
  param([string]$Path)
  Write-LogInline "🧮 HASHING" (Get-RelativePathSafe $Path) # FIX-BUG: padronização RFC
  try {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash
  }
  catch {
    throw "Falha ao calcular hash: $($_.Exception.Message)"
  }
}

function Get-TreeHash {
  param([string]$Base)

  $result = @{}

  try {
    $items = Get-ChildItem -LiteralPath $Base -Force -ErrorAction Stop
  }
  catch {
    Write-Log "WARN" "falha ao listar diretório → $($_.Exception.Message)" (Get-RelativePathSafe $Base)
    return @{}
  }

  foreach ($item in $items) {

    if ($item.Name -like "*.sha256.json") { continue }

    $rel = Get-RelativePathSafe $item.FullName
    Write-LogInline "TREE-SCAN" $rel # PROTECAO

    if ($item.PSIsContainer) {
      $result[$item.Name] = Get-TreeHash $item.FullName
    }
    else {
      $result[$item.Name] = Get-HashSafe $item.FullName
    }
  }

  return $result
}

function Validate-Tree {
  param(
    [string]$BasePath,
    [object]$Node
  )

  try {
    $items = Get-ChildItem -LiteralPath $BasePath -Force -ErrorAction Stop
  }
  catch {
    Write-Log "ERROR" "falha ao listar diretório → $($_.Exception.Message)" (Get-RelativePathSafe $BasePath)
    $script:hasError = $true
    return
  }

  $fsNames = @{}

  foreach ($item in $items) {

    if ($item.Name -like "*.sha256.json") { continue }

    $rel = Get-RelativePathSafe $item.FullName
    Write-LogInline "JSON-VALIDATE" $rel # PROTECAO

    $fsNames[$item.Name] = $true

    if (-not $Node.PSObject.Properties[$item.Name]) {
      Write-Log "ERROR" "item não presente no json" $rel
      $script:hasError = $true
      continue
    }

    $entry = $Node.$($item.Name)

    if ($item.PSIsContainer) {
      if ($entry -isnot [psobject]) {
        Write-Log "ERROR" "esperado diretório, mas json contém hash" $rel
        $script:hasError = $true
        continue
      }
      Validate-Tree $item.FullName $entry
    }
    else {
      try {
        $realHash = Get-HashSafe $item.FullName
        if ($entry -ne $realHash) {
          Write-Log "ERROR" "hash divergente → arquivo alterado" $rel
          $script:hasError = $true
        }
      }
      catch {
        Write-Log "ERROR" "falha ao calcular hash → $($_.Exception.Message)" $rel
        $script:hasError = $true
      }
    }
  }

  foreach ($prop in $Node.PSObject.Properties.Name) {
    if (-not $fsNames.ContainsKey($prop)) {
      Write-Log "ERROR" "item presente no json mas ausente no filesystem → $prop" (Get-RelativePathSafe $BasePath)
      $script:hasError = $true
    }
  }
}

function ConvertFrom-Sha256 {
  param([string]$ShaPath)

  Write-LogInline "READ-SHA256" (Get-RelativePathSafe $ShaPath)

  try {
    $line = Get-Content -LiteralPath $ShaPath -TotalCount 1 -ErrorAction Stop

    if (-not $line) {
      Write-Log "WARN" "sha256 vazio" (Get-RelativePathSafe $ShaPath)
      return $null
    }

    $line = $line.Trim()

    if ($line -match '^[A-Fa-f0-9]{64}') {
      return $Matches[0].ToUpperInvariant()
    }

    Write-Log "WARN" "sha256 formato inválido" (Get-RelativePathSafe $ShaPath)
    return $null
  }
  catch {
    Write-Log "WARN" "falha ao ler sha256 → $($_.Exception.Message)" (Get-RelativePathSafe $ShaPath)
    return $null
  }
}

function Write-Sha256 {
  param(
    [string]$ShaPath,
    [string]$Hash,
    [string]$FileName
  )

  Write-LogInline "WRITE-SHA256" (Get-RelativePathSafe $ShaPath)

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
    catch {
      Write-Log "WARN" "falha ignorada controladamente → $($_.Exception.Message)" ""
    }
    return $FullPath
  }
}

function main {

  $script:globalError = $false

  Write-Log "INFO" "início processamento" ""

  # ================================
  # LIMPEZA SHA256
  # ================================
  try {
    $shaFiles = Get-ChildItem -Recurse -File -Filter "*.sha256" -ErrorAction Stop
  }
  catch {
    Write-Log "ERROR" "falha ao enumerar arquivos sha256 → $($_.Exception.Message)" ""
    $shaFiles = @()
  }

  foreach ($file in $shaFiles) {

    $shaPath = $file.FullName
    $relPath = Get-RelativePathSafe $shaPath

    Write-LogInline "VERIFY-SHA256" $relPath

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
        if ((Get-HashSafe $expectedPath) -eq $expectedHash) {
          $found = $true
        }
      }

      if (-not $found) {
        foreach ($item in Get-ChildItem -LiteralPath $dir -File) {

          if ($item.FullName -eq $shaPath) { continue }

          if ((Get-HashSafe $item.FullName) -eq $expectedHash) {
            $found = $true

            if (-not $VerifyOnly) {
              $newShaPath = Join-Path $dir ($item.Name + ".sha256")
              if ($newShaPath -ne $shaPath) {
                Move-Item -LiteralPath $shaPath -Destination $newShaPath -Force
                Write-Log "FIX" "sha256 renomeado para corresponder ao arquivo" (Get-RelativePathSafe $newShaPath)
              }
            }
            break
          }
        }
      }

      if (-not $found) {
        if ($VerifyOnly) {
          Write-Log "WARN" "sha256 órfão detectado (não removido)" $relPath
        }
        else {
          Remove-Item -LiteralPath $shaPath -Force
          Write-Host "🗑️ REMOVE-FILE: '$relPath'" -ForegroundColor Red # FIX-BUG: aderência RFC
        }
      }
      else {
        Write-Log "OK" "sha256 válido" $relPath
      }
    }
    catch {
      if (-not $VerifyOnly) {
        Remove-Item -LiteralPath $shaPath -Force
        Write-Host "🗑️ REMOVE-FILE: '$relPath'" -ForegroundColor Red # FIX-BUG: aderência RFC
      }
      else {
        Write-Log "WARN" "sha256 inválido detectado (não removido)" $relPath
      }
    }
  }

  Write-Log "INFO" "fim limpeza sha256" ""

  # ================================
  # JSON TREE
  # ================================
  foreach ($dirName in $specialJsonDirs) {

    $rootBase = Join-Path (Get-Location) $dirName
    if (-not (Test-Path $rootBase)) { continue }

    Write-Log "INFO" "processando árvore JSON" $rootBase

    Get-ChildItem -LiteralPath $rootBase -Directory | ForEach-Object {

      $rootDir = $_
      $jsonPath = Join-Path $rootBase ($rootDir.Name + ".sha256.json")
      $relPath = Get-RelativePathSafe $jsonPath

      Write-LogInline "JSON-ROOT" $relPath

      $script:hasError = $false

      if (-not (Test-Path $jsonPath)) {
        Write-Log "INFO" "json ausente → será criado" $relPath

        if (-not $VerifyOnly) {
          try {
            $tree = Get-TreeHash $rootDir.FullName
            $json = ($tree | ConvertTo-Json -Depth 100 -Compress)

            $tmp = "$jsonPath.tmp"
            [System.IO.File]::WriteAllText($tmp, $json, [System.Text.Encoding]::UTF8)
            Move-Item $tmp $jsonPath -Force

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

      if ($script:hasError) {
        if ($Fix -and -not $VerifyOnly) {
          try {
            $tree = Get-TreeHash $rootDir.FullName
            $json = ($tree | ConvertTo-Json -Depth 100 -Compress)

            $tmp = "$jsonPath.tmp"
            [System.IO.File]::WriteAllText($tmp, $json, [System.Text.Encoding]::UTF8)
            Move-Item $tmp $jsonPath -Force

            Write-Log "FIX" "json regenerado" $relPath
          }
          catch {
            Write-Log "ERROR" "falha ao corrigir json → $($_.Exception.Message)" $relPath
          }
        }
        else {
          Write-Log "ERROR" "json divergente → não corrigido" $relPath
        }
      }
      else {
        Write-Log "OK" "json consistente" $relPath
      }
    }
  }

  # ================================
  # EXECUÇÃO NORMAL
  # ================================
  $hashIndex = @{}

  Get-ChildItem -Recurse -File | Where-Object {

    $full = $_.FullName

    $isSpecial = $false

    foreach ($d in $specialJsonDirs) {
      $specialRoot = Join-Path (Get-Location) $d

      # PROTECAO: comparação determinística de path (evita falso positivo por substring)
      if ($full.StartsWith($specialRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        $isSpecial = $true
        break
      }
    }

    (-not $isSpecial) -and
    ($validExt -contains $_.Extension.ToLowerInvariant())

  } | ForEach-Object {

    $filePath = $_.FullName
    $relPath = Get-RelativePathSafe $filePath
    $shaPath = "$filePath.sha256"
    $dir = Split-Path $filePath -Parent

    Write-LogInline "PROCESS" $relPath # PROTECAO: visibilidade

    try {
      $currentHash = Get-HashSafe $filePath
    }
    catch {
      Write-Log "ERROR" "falha hash" $relPath
      return
    }

    if (-not $hashIndex.ContainsKey($dir)) {
      $hashIndex[$dir] = @{}
    }

    if (-not $hashIndex[$dir].ContainsKey($currentHash)) {
      $hashIndex[$dir][$currentHash] = @()
    }

    $hashIndex[$dir][$currentHash] += $filePath

    $exists = Test-Path $shaPath
    $storedHash = if ($exists) { ConvertFrom-Sha256 $shaPath } else { $null }

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
      if ($Fix) {
        Write-Sha256 $shaPath $currentHash $_.Name
        Write-Log "FIX" "hash divergente corrigido" $relPath
      }
      else {
        Write-Log "ERROR" "hash divergente → não corrigido" $relPath
      }
    }
    else {
      Write-Log "OK" "hash consistente" $relPath
    }

    if ($regenerate -and -not $VerifyOnly) {
      Write-Sha256 $shaPath $currentHash $_.Name
      Write-Log "FIX" "sha256 regenerado" $relPath
    }
  }

  # ================================
  # DEDUPLICAÇÃO
  # ================================
  foreach ($dir in $hashIndex.Keys) {
    foreach ($hash in $hashIndex[$dir].Keys) {

      $files = $hashIndex[$dir][$hash]

      if ($files.Count -le 1) { continue }

      $keep = $files[0]
      $toRemove = $files | Select-Object -Skip 1

      foreach ($file in $toRemove) {

        $rel = Get-RelativePathSafe $file
        $shaPath = "$file.sha256"

        if ($VerifyOnly) {
          Write-Log "WARN" "duplicado por hash detectado (não removido)" $rel @{ hash = $hash }
          continue
        }

        try {
          # REMOVE arquivo principal
          Remove-Item -LiteralPath $file -Force -ErrorAction Stop

          # REMOVE sha256 associado se existir
          if (Test-Path $shaPath) {
            Remove-Item -LiteralPath $shaPath -Force -ErrorAction Stop
            Write-Host "🗑️ REMOVE-FILE (SHA256): '$rel.sha256'" -ForegroundColor Red # FIX-BUG: remoção vinculada
          }

          Write-Host "🗑️ REMOVE-FILE: '$rel'" -ForegroundColor Red # FIX-BUG: aderência RFC log
        }
        catch {
          Write-Log "ERROR" "falha ao remover duplicado → $($_.Exception.Message)" $rel
        }
      }
    }
  }
}

if ($MyInvocation.InvocationName -ne '.') {
  main

  if ($script:globalError) {
    exit 1 # FIX-BUG: aderência ao RFC código de saída
  }
  else {
    exit 0 # FIX-BUG: execução sem erros
  }
}