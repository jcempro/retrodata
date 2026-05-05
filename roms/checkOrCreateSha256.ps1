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

3. TRATAMENTO ESPECIAL: DIRETÓRIO 'WINDOWS' e `steam`

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

   Formato: JSONL (uma linha por evento)
   Campos obrigatórios:
   - time   : ISO timestamp (yyyy-MM-dd HH:mm:ss)
   - level  : OK | FIX | INFO | WARN | ERROR
   - file   : caminho relativo (preferencial) ou absoluto
   - msg    : mensagem descritiva
   - Extra  : campos adicionais conforme necessidade

   Cores no console (humanos):
   - OK    : Verde escuro
   - FIX   : Verde claro
   - INFO  : Ciano
   - WARN  : Amarelo
   - ERROR : Branco sobre fundo vermelho (com msg em vermelho)

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

   Parse-Sha256:
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
   - Escopo: por diretório 'windows' e `steam` validation
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
   - Isolamento do diretório 'windows' e `steam` da varredura normal (regex exclusion)

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
   - Se encontrar mais de um → log WARN de cada, mas
     mantém o primeiro encontrado

10. LIMITAÇÕES CONHECIDAS (deciões de escopo e trade-offs)

    - Não suporta .sha256 com múltiplas linhas
    - Não renomeia .sha256 automaticamente quando ROM renomeada (exceto se 
      identificar hash correspondente no mesmo diretório)
    - JSON tree se ajusta à realidade do filesystem, como se fosse
      um espelho virtual, removendo e incluindo, mas alteração de hash, somente
      se houver parametro -Fix, caso contrário, apenas log de divergência
    - Suporte a symlinks/junctions (apenas se o sistema de arquivos e PowerShell
      permitirem, sem tratamento especial)

11. EXEMPLOS DE USO

    # Verificação completa com regeneração
    .\script.ps1

    # Apenas validar (modo somente leitura)
    .\script.ps1 -VerifyOnly    

    # Log customizado
    .\script.ps1 -LogPath "C:\logs\audit.jsonl"

12. CÓDIGOS DE SAÍDA (NÃO EXPLÍCITOS NO SCRIPT ATUAL)

    - 0 : Execução bem sucedida (sem erros críticos)
    - 1 : Erros detectados (hashes divergentes, JSON inválidos)
    - Nota: Script atual não define $LASTEXITCODE explicitamente


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
param(
  [switch]$Fix,
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
      $script:globalError = $true # PROTECAO: rastreio de erro global para exit code
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

    if ($LogPath) {
      # FIX-BUG: variável sempre definida via param
      try {
        $json = $obj | ConvertTo-Json -Compress -Depth 5
        Add-Content -LiteralPath $LogPath -Value $json -Encoding UTF8
      }
      catch {
        # PROTECAO: falha de log não interrompe execução
      }
    }
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

function New-TreeHash {
  param([string]$Base)

  $result = @{}

  try {
    $items = Get-ChildItem -LiteralPath $Base -Force -ErrorAction Stop
  }
  catch {
    Write-Log "WARN" "falha ao listar diretório → $($_.Exception.Message)" (Get-RelativePathSafe $Base) # PROTECAO
    return @{}
  }

  $items | ForEach-Object {

    # PROTECAO: ignorar qualquer .sha256.json (novo padrão fora da pasta não entra aqui, mas mantém compatibilidade)
    if ($_.Name -like "*.sha256.json") { return }

    if ($_.PSIsContainer) {
      $result[$_.Name] = New-TreeHash $_.FullName
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

  try {
    $items = Get-ChildItem -LiteralPath $BasePath -Force -ErrorAction Stop
  }
  catch {
    Write-Log "ERROR" "falha ao listar diretório → $($_.Exception.Message)" (Get-RelativePathSafe $BasePath) # PROTECAO
    $script:hasError = $true
    return
  }

  $fsNames = @{}

  $items | ForEach-Object {

    # PROTECAO: ignorar qualquer .sha256.json
    if ($_.Name -like "*.sha256.json") { return }

    $fsNames[$_.Name] = $true

    if (-not $Node.PSObject.Properties[$_.Name]) {
      Write-Log "ERROR" "item não presente no json" (Get-RelativePathSafe $_.FullName)
      $script:hasError = $true
      return
    }

    $entry = $Node.$($_.Name)

    if ($_.PSIsContainer) {
      if ($entry -isnot [psobject]) {
        Write-Log "ERROR" "esperado diretório, mas json contém hash" (Get-RelativePathSafe $_.FullName)
        $script:hasError = $true
        return
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

  # FIX-BUG: validação reversa (JSON → FS)
  foreach ($prop in $Node.PSObject.Properties.Name) {
    if (-not $fsNames.ContainsKey($prop)) {
      Write-Log "ERROR" "item presente no json mas ausente no filesystem → $prop" (Get-RelativePathSafe $BasePath)
      $script:hasError = $true
    }
  }
}

function Parse-Sha256 {
  param([string]$ShaPath)

  try {
    $line = Get-Content -LiteralPath $ShaPath -TotalCount 1 -ErrorAction Stop

    if (-not $line) {
      Write-Log "WARN" "sha256 vazio" (Get-RelativePathSafe $ShaPath) # PROTECAO: visibilidade de erro
      return $null
    }

    $line = $line.Trim()

    if ($line -match '^[A-Fa-f0-9]{64}') {
      return $Matches[0].ToUpperInvariant()
    }

    Write-Log "WARN" "sha256 formato inválido" (Get-RelativePathSafe $ShaPath) # PROTECAO
    return $null
  }
  catch {
    Write-Log "WARN" "falha ao ler sha256 → $($_.Exception.Message)" (Get-RelativePathSafe $ShaPath) # PROTECAO
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
    catch {
      Write-Log "WARN" "falha ignorada controladamente → $($_.Exception.Message)" ""
    }

    return $FullPath
  }
}

function main {

  $script:globalError = $false # PROTECAO: estado global consolidado

  # ================================
  # LIMPEZA SHA256
  # ================================
  try {
    $shaFiles = Get-ChildItem -Recurse -File -Filter "*.sha256" -ErrorAction Stop
  }
  catch {
    Write-Log "ERROR" "falha ao enumerar arquivos sha256 → $($_.Exception.Message)" "" # PROTECAO
    $shaFiles = @()
  }

  $shaFiles | ForEach-Object {

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
        catch {
          Write-Log "WARN" "falha ignorada controladamente → $($_.Exception.Message)" ""
        }
      }

      if (-not $found) {
        foreach ($item in Get-ChildItem -LiteralPath $dir -File) {

          if ($item.FullName -eq $shaPath) { continue }

          try {
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
          catch {
            Write-Log "WARN" "falha ao verificar hash durante varredura → $($_.Exception.Message)" (Get-RelativePathSafe $item.FullName)
          }
        }
      }

      # FIX-BUG: evitar remoção de sha256 válido quando hash correspondente foi encontrado
      if (-not $found) {
        if ($VerifyOnly) {
          Write-Log "WARN" "sha256 órfão detectado (não removido)" $relPath
        }
        else {
          Remove-Item -LiteralPath $shaPath -Force -ErrorAction Stop
          Write-Log "FIX" "sha256 órfão removido" $relPath
        }
      }
      else {
        Write-Log "OK" "sha256 válido vinculado a arquivo existente" $relPath
      }
    }
    catch {
      if (-not $VerifyOnly) {
        Remove-Item -LiteralPath $shaPath -Force -ErrorAction Stop
        Write-Log "FIX" "sha256 inválido removido" $relPath
      }
      else {
        Write-Log "WARN" "sha256 inválido detectado (não removido)" $relPath
      }
    }
  }

  # ================================
  # WINDOWS JSON VALIDATION
  # ================================
  $windowsRoot = Join-Path (Get-Location) "steam"

  if (Test-Path $windowsRoot) {

    Get-ChildItem -LiteralPath $windowsRoot -Directory | ForEach-Object {

      $rootDir = $_
      $jsonPath = Join-Path $windowsRoot ($rootDir.Name + ".sha256.json")
      $relPath = Get-RelativePathSafe $jsonPath

      $script:hasError = $false

      if (-not (Test-Path $jsonPath)) {

        Write-Log "INFO" "json ausente → será criado" $relPath

        if (-not $VerifyOnly) {
          try {
            $tree = New-TreeHash $rootDir.FullName
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

      if ($script:hasError) {
        if ($Fix -and -not $VerifyOnly) {
          try {
            $tree = New-TreeHash $rootDir.FullName
            $json = ($tree | ConvertTo-Json -Depth 100 -Compress)

            $tmp = "$jsonPath.tmp"
            [System.IO.File]::WriteAllText($tmp, $json, [System.Text.Encoding]::UTF8)
            Move-Item -LiteralPath $tmp -Destination $jsonPath -Force

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
  Get-ChildItem -Recurse -File | Where-Object {
    $_.FullName -notmatch '\\steam\\' -and
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
  # EXIT CODE
  # ================================
  if ($script:globalError) {
    exit 1
  }
  else {
    exit 0
  }
}

# PROTECAO: execução apenas quando não importado (dot-sourced)
if ($MyInvocation.InvocationName -ne '.') {
  main
}