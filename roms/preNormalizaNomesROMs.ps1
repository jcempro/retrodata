<#
.SYNOPSIS
    Normalizador determinístico de nomes de arquivos com suporte a idioma, ID ScreenScraper e extensões encadeadas.

.DESCRIPTION
    Este script percorre recursivamente o diretório atual e renomeia arquivos para um formato canônico,
    aplicando regras rígidas de normalização. O comportamento é idempotente e resistente a entradas inconsistentes.

    O objetivo é garantir consistência estrutural e previsibilidade, mesmo em coleções heterogêneas.

    Objetivo 2: impedir a existência de dois ou mais arquivos com o mesmo sha256 dentro do mesmo diretório, 
    ainda que com nomes diferentes.

.RFC
    Especificação de Normalização de Nomes de Arquivos (versão 1.0)

    IMPORTANTE: Nomes de arquivos case-sensitive são tratados de forma consistente (incluindo a forma como o nome
    aparece dentro dos arquivos .xml, .json e .sha256), e o script é seguro para múltiplas
    execuções sem causar renomeações adicionais, incluindo casos de colisão e arquivos de hash

    Se, vários arquivos possuírem o mesmo sh256 o scrip elimina todo, exceto aquele que possui o nome mais próximo do
    resultado canônico, e os outros são renomeados para um nome único
    (ex: "Nome__dup1.ext") ou eliminados caso sejam arquivos de hash (.sha256)

    A iteração se dá exclusivamente por diretório, com consulta ao gamelist.xml como referência.

    Terminologia normativa conforme RFC 2119:
        MUST, MUST NOT, REQUIRED → obrigatório
        SHOULD → recomendado
        MAY → opcional            

    ============================================================
    1. ESTRUTURA CANÔNICA DO NOME
    ============================================================

    O nome final MUST obedecer ao formato:

        <NomeNormalizado>[ espaço (IDIOMA)]?[ espaço [ID]]?.<ext>[.<ext2>...]

    Onde:
        - (IDIOMA) é opcional, mas se presente MUST ser único
        - [ID] é opcional, mas se presente MUST ser único
        - extensões encadeadas são permitidas

    ============================================================
    2. PROCESSAMENTO DE IDIOMA
    ============================================================

    2.1 Extração
        - O script MUST extrair TODOS os conteúdos entre parênteses "()"
        - Conteúdos compostos MAY conter separadores: "/", ",", ";", "-"
        - Tokens MUST ser normalizados (trim + uppercase)

    2.2 Validação
        - Apenas idiomas da whitelist são válidos
        - Tokens inválidos MUST ser descartados

    2.3 Seleção
        - MUST selecionar apenas UM idioma final
        - Prioridade MUST seguir:
            1. BR
            2. PT
            3. USA
            4. Primeiro válido restante

    2.4 Reconstrução
        - O idioma MUST ser reintroduzido no final do basename
        - MUST estar no formato "(XX)"

    2.5 Restrições
        - Múltiplos idiomas MUST NOT aparecer no resultado final
        - Idioma válido MUST NOT ser perdido

    ============================================================
    3. PROCESSAMENTO DE ID (SCREENSCRAPER)
    ============================================================

    3.1 Extração
        - O script MUST extrair conteúdos entre colchetes "[]"
        - Apenas valores numéricos são válidos

    3.2 Seleção
        - MUST selecionar o último ID válido encontrado

    3.3 Reconstrução
        - O ID MUST ser colocado após o idioma (se existir)
        - MUST estar no formato "[12345]"

    3.4 Restrições
        - IDs não numéricos MUST ser descartados
        - Apenas UM ID MUST existir no resultado
        - ID válido MUST NOT ser perdido

    ============================================================
    4. NORMALIZAÇÃO DO NOME BASE
    ============================================================

    4.1 Limpeza
        - O script MUST remover todos os conteúdos "()" e "[]" antes da normalização
        - Conteúdos inválidos MUST ser descartados

    4.2 Transformações
        - MUST aplicar TitleCase usando cultura invariável
        - MUST remover padrões conhecidos irrelevantes:
            - " - The Videogame" no final

    4.3 Artigos invertidos
        - Padrão "Nome, The|A|An" MUST ser convertido para "The Nome"
        - Essa transformação MUST NOT ocorrer se houver hífen no nome base

    4.4 Numeração romana
        - Tokens que representem números romanos válidos MUST ser convertidos para UPPERCASE
        - Tokens inválidos MUST NOT ser alterados

    ============================================================
    5. EXTENSÕES DE ARQUIVO
    ============================================================

    5.1 Extração
        - O parsing MUST ocorrer da direita para a esquerda
        - Apenas extensões da whitelist são válidas

    5.2 Cadeias de extensão
        - Cadeias como ".sfc.7z" são permitidas
        - Todas as extensões MUST ser válidas

    5.3 Limpeza
        - Qualquer conteúdo entre extensões (ex: "(1)") MUST ser removido

    5.4 Restrições
        - Extensões inválidas MUST encerrar o parsing
        - Ordem das extensões MUST ser preservada

    ============================================================
    6. RECONSTRUÇÃO FINAL
    ============================================================

    A reconstrução MUST seguir a ordem:

        NomeNormalizado
        + " (IDIOMA)" (se existir)
        + " [ID]" (se existir)
        + "." + extensões encadeadas

    ============================================================
    7. SEGURANÇA E INTEGRIDADE
    ============================================================

    7.1 Idempotência
        - O script MUST NOT renomear arquivos já normalizados

    7.2 Sistema de arquivos
        - Caracteres inválidos MUST ser removidos
        - Nomes MUST NOT terminar com espaço ou ponto

    7.3 Colisão
        - Em caso de conflito, o script MUST gerar nome único
        - O processo MUST evitar loops infinitos

    7.4 Robustez
        - O script MUST continuar execução mesmo após erros
        - Falhas MUST ser reportadas no console

    ============================================================
    8. LIMITAÇÕES
    ============================================================

        - O script NÃO valida nomes contra bases externas (ex: No-Intro)
        - O script NÃO corrige semanticamente nomes incorretos
        - O script NÃO garante correspondência com nomes oficiais

    ============================================================
    9. GARANTIAS
    ============================================================

        - Idioma válido nunca será perdido
        - ID válido nunca será perdido
        - Estrutura final sempre será consistente
        - Execução é determinística

    10. LOG

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
          - OK    : ✔  (EM COR VERDE)
          - INFO  : ℹ️
          - WARN  : ⚠️
          - ERROR : ❌    
        * utilize caracter unicode (emoji) único para identificar ações executadas e em execução:
          - JSON-VALIDATE : 📄
          - PROCESS       : ⚙️
          - VERIFY        : 🔍
          - CHANGE-NAME   : ✏️
          - SKIP          : ⏭️
          - FIX           : 🛠️
          - FIXED         : ✅

.EXAMPLE
    PS> .\normalize.ps1 -WhatIf

    Simula renomeações sem alterar arquivos.

.EXAMPLE
    PS> .\normalize.ps1

    Executa renomeação real.

.NOTES
    Compatível com PowerShell 5.1 e 7+
    Não cria logs em arquivo; saída apenas em console.

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
      
  [SOBRE COMPARAÇÕES DE HASH E COLISÕES]
    - Short-circuit por tamanho
      * Evita SHA256 em arquivos obviamente diferentes
      * Não influencia decisão de igualdade
    - Mutex global (Global\NormalizeScript_HashMutex)
      * Serializa operações de hash
      * Evita saturação de disco / IO
      * Evita race conditions e corrupção indireta
    - Timeout controlado (30s)
      * Evita deadlock
      * Garante progresso do script  
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param()

# ================= CONFIG =================

$ValidExtensions = @(
  'sha256', 'chd', 'pbp', '7z', 'zip', 'nes', 'smc', 'sfc', 'fig', 'n64', 'z64', 'v64',
  'gb', 'gbc', 'gba', 'nds', '3ds', 'cia', 'iso', 'wbfs', 'rvz', 'sms', 'md', 'smd',
  'gen', 'bin', 'gg', 'gdi', 'cdi', 'cue', 'img', 'cso', 'neo', 'a26', 'pce', 'mvs', 'cp2'
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

  # remove TODOS () e []
  $t = $text -replace '\s*\([^)]*\)', ''
  $t = $t -replace '\s*\[[^\]]*\]', ''

  # 🔥 REMOVE especificamente (1), (2), etc (caso escapem)
  $t = $t -replace '\s*\(\d+\)', ''

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
  $n = ([cultureinfo]::InvariantCulture.TextInfo).ToTitleCase($n)
  return ConvertTo-RomanAwareTitle $n
}

function Extract-Extensions {
  param([string]$fileName)

  if (-not $fileName) { return $null }

  $parts = $fileName -split '\.'
  if ($parts.Count -lt 2) { return $null }

  $exts = @()
  $lastAccepted = $null # PROTECAO: rastreia última extensão válida aceita

  for ($i = $parts.Count - 1; $i -gt 0; $i--) {

    $candidate = $parts[$i]

    # remove lixo tipo "(1)"
    $candidate = $candidate -replace '\s*\(.*?\)', ''
    $candidate = $candidate.Trim()

    if ($ValidExtSet.Contains($candidate)) {

      # FIX-BUG: elimina duplicação consecutiva (ex: exe.exe, cps1.cps1)
      if ($lastAccepted -and $candidate.Equals($lastAccepted, [StringComparison]::OrdinalIgnoreCase)) {
        continue
      }

      $exts = , $candidate + $exts
      $lastAccepted = $candidate
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

function ConvertTo-RomanAwareTitle {
  param([string]$text)

  if (-not $text) { return $null } # FIX-BUG: typo returgan

  $words = $text -split ' '

  $romanRegex = '^(?i:M{0,4}(CM|CD|D?C{0,3})(XC|XL|L?X{0,3})(IX|IV|V?I{0,3}))$'

  for ($i = 0; $i -lt $words.Count; $i++) {
    $w = $words[$i]

    if ($w -match $romanRegex) {
      $words[$i] = $w.ToUpperInvariant()
    }
  }

  return ($words -join ' ')
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

    # FIX-BUG: correção de formatação inválida em string format
    $candidate = "{0}__dup{1}{2}" -f $base, $i, $ext
    $i++

    if ($i -gt 9999) { throw "Colisão infinita" }
  }

  return $candidate
}

# ================= MAIN =================

function main {
  param()

  [int]$total = 0; [int]$renamed = 0; [int]$skipped = 0; [int]$errors = 0

  Get-ChildItem -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {

    $total++

    try {
      $file = $_

      $parsed = Extract-Extensions $file.Name
      if (-not $parsed) { $skipped++; return }

      $rawBase = $parsed.Base
      $exts = $parsed.Extensions

      # PROTECAO: tenta resolver nome completo via mapa externo (ex: gamelist.xml exportado)
      $mapPath = Join-Path $file.DirectoryName "gamelist.map.json"
      $resolvedBase = $rawBase
      $mapLangRaw = $null

      if (Test-Path $mapPath) {
        try {
          $map = Get-Content $mapPath -Raw | ConvertFrom-Json

          $key = $rawBase.ToLowerInvariant()

          if ($map.ContainsKey($key)) {

            $entry = $map[$key]

            if ($entry -is [string]) {
              $resolvedBase = $entry
            }
            elseif ($entry.name) {
              $resolvedBase = $entry.name
            }

            if ($entry.lang) {
              $mapLangRaw = $entry.lang # FIX-BUG: captura lang externa
            }
          }
        }
        catch {
          Write-Host "❌ 📄 MAP_LOAD :: $($_.Exception.Message)" -ForegroundColor Red # PROTECAO: erro estruturado
        }
      }

      # EXTRAÇÃO ANTES DE QUALQUER MODIFICAÇÃO
      $idioma = Get-IdiomaSeguro $resolvedBase

      # FIX-BUG: fallback para idioma vindo do mapa quando ausente no nome
      if (-not $idioma -and $mapLangRaw) {

        $tokens = @()

        foreach ($part in ($mapLangRaw -split '[/,;\-]')) {
          $val = $part.Trim().ToUpperInvariant()
          if ($val -and ($ValidIdiomas -contains $val)) {
            $tokens += $val
          }
        }

        if ($tokens.Count -gt 0) {

          foreach ($p in $IdiomaPriority) {
            if ($tokens -contains $p) {
              $idioma = "($p)"
              break
            }
          }

          if (-not $idioma) {
            $idioma = "($($tokens[0]))"
          }
        }
      }

      $id = Get-IdSeguro $resolvedBase

      # NORMALIZAÇÃO
      $nome = Normalize-Nome $resolvedBase # FIX-BUG: usa nome expandido quando disponível
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
      $targetPath = Join-Path $file.DirectoryName $newName

      if (Test-Path -LiteralPath $targetPath) {

        # FIX-BUG: arquivos de hash (.sha256) não devem ser duplicados
        if ($exts.Count -eq 1 -and $exts[0].Equals('sha256', [StringComparison]::OrdinalIgnoreCase)) {

          Write-Host "⚠️ 🛠️ HASH_DUPLICADO :: removendo $($file.Name)" -ForegroundColor Yellow

          if ($PSCmdlet.ShouldProcess($file.Name, "Remove duplicate hash file")) {
            Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
            Write-Host "✔ 🗑️ REMOVED :: $($file.Name)" -ForegroundColor DarkGreen
            $renamed++
          }

          return
        }

        # 🔒 SHORT-CIRCUIT POR TAMANHO (NÃO DECISIVO)
        $fileSizeA = $file.Length
        $fileSizeB = (Get-Item -LiteralPath $targetPath).Length

        if ($fileSizeA -ne $fileSizeB) {
          # PROTECAO: tamanhos diferentes → não são duplicados → evita hash desnecessário
          $newName = Get-UniqueFileName $file.DirectoryName $newName
        }
        else {

          # 🔒 MUTEX GLOBAL PARA OPERAÇÕES DE HASH
          $mutexName = "Global\NormalizeScript_HashMutex"
          $mutex = New-Object System.Threading.Mutex($false, $mutexName)
          $lockAcquired = $false

          try {
            # PROTECAO: evita concorrência de IO e contenção de disco
            $lockAcquired = $mutex.WaitOne([TimeSpan]::FromSeconds(30))

            if (-not $lockAcquired) {
              Write-Host "⚠️ 🔍 MUTEX_TIMEOUT :: fallback sem hash" -ForegroundColor Yellow
              $newName = Get-UniqueFileName $file.DirectoryName $newName
            }
            else {

              Write-Host "🔍 ⚙️ HASH_COMPARE :: $($file.Name)" -ForegroundColor Cyan

              $hashA = Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256
              $hashB = Get-FileHash -LiteralPath $targetPath -Algorithm SHA256

              if ($hashA.Hash -eq $hashB.Hash) {

                Write-Host "⚠️ 🛠️ DUPLICATE_CONFIRMED :: removendo $($file.Name)" -ForegroundColor Yellow

                if ($PSCmdlet.ShouldProcess($file.Name, "Remove confirmed duplicate")) {
                  Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
                  Write-Host "✔ 🗑️ REMOVED :: $($file.Name)" -ForegroundColor DarkGreen
                  $renamed++
                }

                return
              }
              else {
                # PROTECAO: mesmo tamanho, conteúdo diferente
                $newName = Get-UniqueFileName $file.DirectoryName $newName
              }
            }
          }
          catch {
            Write-Host "❌ 🔍 HASH_COMPARE_FAIL :: $($_.Exception.Message)" -ForegroundColor Red
            # PROTECAO: fallback seguro → NÃO remover sem confirmação
            $newName = Get-UniqueFileName $file.DirectoryName $newName
          }
          finally {
            if ($lockAcquired) {
              $mutex.ReleaseMutex()
            }
            $mutex.Dispose()
          }
        }
      }

      if ($PSCmdlet.ShouldProcess($file.Name, "Rename to $newName")) {
        Rename-Item -LiteralPath $file.FullName -NewName $newName -ErrorAction Stop
        Write-Host "✔ ✏️ $($file.Name) -> $newName" -ForegroundColor DarkGreen # PROTECAO: padronização de log conforme RFC
        $renamed++
      }

    }
    catch {
      $errors++
      Write-Host "❌ $($file.Name) :: $($_.Exception.Message)" -ForegroundColor Red -BackgroundColor Black # PROTECAO: padronização ERROR
    }
  }

  Write-Host ""
  Write-Host "ℹ️ ==== RESUMO ====" -ForegroundColor Cyan
  Write-Host "ℹ️ Total: $total | Renomeados: $renamed | Ignorados: $skipped | Erros: $errors"
}

# AUTO-INVOCAÇÃO SEGURA
if ($MyInvocation.InvocationName -ne '.') {
  main @PSBoundParameters
}