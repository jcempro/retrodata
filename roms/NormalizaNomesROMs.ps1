<#
.SYNOPSIS
    Normalizador determinístico de nomes de arquivos com suporte a idioma, ID ScreenScraper e extensões encadeadas.

.DESCRIPTION
    Este script percorre recursivamente o diretório atual e renomeia arquivos para um formato canônico,
    aplicando regras rígidas de normalização. O comportamento é idempotente, determinístico e resiliente
    a entradas inconsistentes.
   
    Exceto pelo processamento de criação/validação/atualização de hash, não são
    processados os arquivos com extenções:
      .xml, .json, .ini, .exe, .sh, .ps1, .bat. sha256, .md5
      .mp3, .png, .jpg, .jpeg, .mp4, .avi, .mkv

    Objetivos:
        1. Garantir consistência estrutural e previsibilidade em coleções heterogêneas
        2. Impedir a coexistência de múltiplos arquivos com o mesmo SHA256 no mesmo diretório,
           independentemente do nome
        3. Sincronizar bidirecionalmente nomes de ROMs com gamelist.xml quando presente
        4. Garantir coerência de metadados e tradução segura para pt-BR

.RFC
    Especificação de Normalização de Nomes de Arquivos (versão 2.0)

    IMPORTANTE:
        - Nomes case-sensitive MUST ser tratados de forma consistente, incluindo referências em arquivos
          .xml, .json e .sha256
        - O script MUST ser seguro para múltiplas execuções sem gerar renomeações adicionais
        - Casos de colisão e arquivos de hash são tratados de forma determinística

    ============================================================
    0. ESCOPO E SINCRONIA COM GAMELIST.XML
    ============================================================

    0.1 Detecção
        - O script MUST detectar se o diretório contém 'gamelist.xml'
        - O gamelist.xml DEVE estar imediatamente no root de qualquer subpasta de ROMs
          (ex.: roms/snes/gamelist.xml, NÃO roms/snes/collection/gamelist.xml)
        - O script NÃO DEVE processar múltiplos níveis de subpastas para encontrar gamelist.xml

    0.2 Correlação
        - O script DEVE verificar se cada arquivo ROM está correlacionado na tag <path> da sub tag <game>
        - A operação DEVE ocorrer APENAS sobre ROMs referenciadas por <path> e seus metadados
        - O script DEVE garantir compatibilidade total com batocera

    0.3 Sincronia bidirecional
        - O nome físico DEVE corresponder ao conteúdo de <path>
        - Renomeações DEVEM atualizar o XML imediatamente
        - O script MUST ser capaz de sincronizar tanto de ROM → XML quanto de XML → ROM
        - Zero efeitos colaterais não intencionais inferidos bidirecionalmente DEVEM ser garantidos

    0.4 Direcionalidade da sincronia
          - Modo PRIMARY: ROM → XML (renomeia ROM, atualiza <path> no XML)
          - Modo SECONDARY: XML → ROM (APENAS se ROM referenciada não existir)
          - O script NÃO DEVE criar ROMs inexistentes a partir do XML
          - Se ROM ausente e referenciada no XML: LOG como WARN, pular operação                

    ============================================================
    1. ESTRUTURA CANÔNICA DO NOME
    ============================================================

    O nome final MUST obedecer ao formato:

        <NomeNormalizado>[ (IDIOMA)]?[ [ID]]?.<ext>[.<ext2>...]

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
   
   2.2 Validação e whitelist
        - Whitelist de idiomas válidos: BR, PT, USA, JP, EU, ES, FR, DE, IT
        - Tokens fora da whitelist NÃO SÃO idiomas
        - Apenas tokens na whitelist são elegíveis para seleção        

    2.3 Seleção
        - MUST selecionar apenas UM idioma final
        - Prioridade MUST seguir:
            1. BR
            2. PT
            3. USA
            4. Primeiro válido restante

    2.4 Reconstrução
        - O idioma MUST ser reintroduzido ao final do basename
        - MUST estar no formato "(XX)"

    2.5 Restrições
        - Múltiplos idiomas MUST NOT aparecer no resultado final
        - Um idioma válido MUST NOT ser perdido

    ============================================================
    3. PROCESSAMENTO DE ID (SCREENSCRAPER)
    ============================================================

    3.1 Extração
        - O script MUST extrair conteúdos entre colchetes "[]"
        - Apenas valores numéricos são válidos

    3.2 Seleção
        - MUST selecionar o último ID válido encontrado

    3.3 Reconstrução
        - O ID MUST ser posicionado após o idioma (se existir)
        - MUST estar no formato "[12345]"

    3.4 Restrições
        - IDs não numéricos MUST ser descartados
        - Apenas UM ID MUST existir no resultado
        - Um ID válido MUST NOT ser perdido

    ============================================================
    4. NORMALIZAÇÃO DO NOME BASE
    ============================================================

    4.1 Limpeza
        - O script MUST remover conteúdos "()" e "[]" antes da normalização
        - Conteúdos inválidos MUST ser descartados

    4.2 Transformações
        - MUST aplicar TitleCase usando cultura invariável
        - MUST remover padrões irrelevantes conhecidos:
            - " - The Videogame" (quando presente no final)

    4.3 Artigos invertidos
        - Padrão "Nome, The|A|An" MUST ser convertido para "The Nome"
        - Essa transformação MUST NOT ocorrer se houver hífen no nome base

    4.4 Numeração romana
        - Tokens válidos MUST ser convertidos para UPPERCASE
        - Tokens inválidos MUST NOT ser alterados

    4.5 Regras adicionais para basename
        - MUST capitalizar basename preservando extensão
        - MUST impor consistência de case
        - Numeração romana (II, IV, etc.) DEVEM ser totalmente maiúsculas

    4.6 Parênteses (regra de decisão)
        - O script DEVE primeiro extrair possíveis idiomas (Seção 2.1)
        - Conteúdos entre parênteses QUE NÃO SEJAM idiomas válidos:
            * Tags técnicas como "Beta", "Rev", "Build", "Proto", "Demo", "Sample"
            * Números isolados como "(1)", "(2)"
            * Versões como "(v1.0)", "(T-101)"
        - DEVEM ser removidos COMPLETAMENTE, incluindo os parênteses e espaço precedente
        - CONTEÚDOS QUE SÃO localidades válidas (BR, PT, USA, etc.) 
            * DEVEM ser preservados conforme seção 2.4
        - Formas compostas como "(BR-XX)" DEVEM ser preservadas integralmente

    4.7 Sufixo de identificação
        - MUST sufixar " [id]" (sanitizado) antes da extensão usando <game id>
        - A unicidade do nome DEVE ser garantida via [id]

    4.8 Garantia de unicidade (cadeia de fallback)
        - PRIORIDADE 1: [id] do ScreenScraper (Seção 3)
          * Se [id] ausente ou colidir, o script DEVE não deve gerar [fallback_id]
          * o conteúdo de id não deve ser o case alterado, ou seja, ele deve ser preservado
            independente da origem (basename / .xml)
        - Garantia: TODO nome final DEVE conter um identificador único entre colchetes
        - O processo de fallback NÃO DEVE violar idempotência        

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
        - Conteúdos entre extensões (ex: "(1)") MUST ser removidos

    5.4 Restrições
        - Extensões inválidas MUST encerrar o parsing
        - A ordem original das extensões MUST ser preservada

    ============================================================
    6. RECONSTRUÇÃO FINAL
    ============================================================

    A reconstrução MUST seguir a ordem:

        NomeNormalizado
        + " (IDIOMA)" (se existir)
        + " [ID]" (se existir)
        + "." + extensões encadeadas

    6.1 Definição da tag <lang>
        - Se o nome normalizado contiver "(BR)" ou "(BR-*)", <lang> DEVE ser 'PT-BR'
        - Se o nome contiver "(PT)", <lang> DEVE ser 'PT-PT' (prioridade menor que BR)
        - Para outros idiomas válidos, <lang> DEVE seguir ISO 639-1
        - A tag DEVE ser inserida/atualizada no nó <game> correspondente no gamelist.xml        

    ============================================================
    7. TRADUÇÃO (<desc> → pt-BR)
    ============================================================

    7.1 Fonte de tradução
        - DEVE traduzir via API REST pública com controle de rate limit
        - MUST implementar cache para evitar requisições duplicadas

    7.2 Detecção de pt-BR pré-existente
        - O script DEVE detectar conteúdo já em pt-BR
        - Quando aplicável, DEVE pular tradução

    7.3 Qualidade da tradução
        - Se saída == entrada após tentativas, MUST manter original
        - Se saída for sem sentido (nomes técnicos), MUST manter original

    7.4 Processamento em lote
        - DEVE enviar pequenos lotes (ex.: 5) com delimitadores rastreáveis
        - Mesmo quando mal traduzidas, DEVE manter separação clara entre entradas individuais
        - MUST preservar contexto original

    7.5 Backoff
        - MUST implementar backoff exponencial com limite de tentativas
        - DEVE ser resiliente a falhas de rede

    ============================================================
    8. HASH E INTEGRIDADE
    ============================================================

    8.1 Arquivos .sha256
        - Se existir *.sha256, DEVE ser renomeado para casar com a ROM (case-sensitive)
        - O basename dentro do .sha256 DEVE ser atualizado para refletir o novo nome da ROM
        - Arquivos .sha256 MUST ser considerados derivados
        - Se o arquivo alvo for removido, seus hashes associados MUST ser removidos
        - Hashes órfãos MUST NOT ser preservados

    ============================================================
    9. DEDUPLICAÇÃO POR HASH
    ============================================================

    9.1 Critério primário
        - O SHA256 MUST ser o único fator decisório para igualdade de conteúdo
        - Se múltiplos arquivos possuírem o mesmo SHA256:
            * EXACTAMENTE UM arquivo MUST ser preservado
            * Os demais arquivos MUST ser removidos
        - O arquivo preservado MUST ser aquele com nome mais próximo do formato canônico

    9.2 Critério de seleção (determinístico)
        - A escolha do arquivo a ser preservado MUST ser determinística
        - O critério MUST considerar:
            1. Nome já normalizado (preferencial)
            2. Menor distância para o nome canônico esperado
            3. Em caso de empate, ordenação lexicográfica estável (ordinal)

    9.3 Fail-safe
        - O sistema MUST garantir que ao menos um arquivo seja preservado
        - Em nenhuma circunstância todos os arquivos equivalentes podem ser removidos
        - Em caso de erro durante remoção, o processo MUST abortar a operação de deduplicação
          daquele conjunto antes de violar essa garantia

    9.4 Restrições
        - Criação de cópias de backup de arquivos duplicados MUST NOT ocorrer
        - Renomeação para sufixos artificiais (ex: "__dup") MUST NOT ser utilizada

    ============================================================
    10. OTIMIZAÇÃO DE DESEMPENHO
    ============================================================

    - O processo de comparação MAY utilizar heurísticas para redução de custo computacional, incluindo:
        * Comparação prévia por tamanho de arquivo (short-circuit)
        * Cache em memória de hashes SHA256 já calculados
        * Reutilização de resultados dentro do mesmo ciclo de execução
    - O cache de hashes MUST ser consistente durante toda a execução
    - Essas heurísticas MUST NOT influenciar a decisão final de igualdade
    - Metadados (timestamp, atributos, etc.) SHOULD NOT ser utilizados como critério de comparação,
      por não serem fontes confiáveis de equivalência

    ============================================================
    11. SEGURANÇA E INTEGRIDADE
    ============================================================

    11.1 Idempotência
        - O script MUST NOT renomear arquivos já normalizados
        - O processo de deduplicação MUST ser idempotente após convergência
        - Reexecução NÃO DEVE produzir deriva

    11.2 Sistema de arquivos
        - Caracteres inválidos MUST ser removidos
        - Nomes MUST NOT terminar com espaço ou ponto
        - MUST proteger contra caracteres inválidos, nomes reservados, ROM ausente

    11.3 Colisão
        - Em caso de conflito, o script MUST gerar nome único
        - O processo MUST evitar loops infinitos

    11.4 Robustez
        - O script MUST continuar execução mesmo após falhas
        - Erros MUST ser reportados no console
        - 'catch' vazio é PROIBIDO. Toda falha DEVE ser tratada/reportada

    11.5 Validação
        - Pré-checagem DEVE verificar integridade (entry 'main', delimitadores)
        - MUST preservar encoding e estrutura do XML (zero mutações indevidas)
        - Blocos anti-bug DEVEM conter "// PROTECAO: <descrição>"

    ============================================================
    12. GARANTIAS
    ============================================================

    - Idiomas válidos nunca serão perdidos
    - IDs válidos nunca serão perdidos
    - A estrutura final será sempre consistente
    - Execução determinística e reproduzível
    - Deduplicação segura sem risco de perda total de dados
    - Preservação de diretórios e paths relativos
    - Imposição de unicidade efetiva sensível a maiúsc./minúsc. (evitar colisões)

    ============================================================
    13. LIMITAÇÕES
    ============================================================

    - NÃO valida nomes contra bases externas (ex: No-Intro)
    - NÃO corrige semanticamente nomes incorretos
    - NÃO garante correspondência com nomes oficiais
    - NÃO processa gamelist.xml em subdiretórios aninhados

    ============================================================
    14. LOG
    ============================================================

    Diretrizes:
        - O log MUST indicar a ação tomada
        - MUST incluir o caminho do arquivo (preferencialmente relativo)
        - SHOULD utilizar reescrita inline e, new line apenas quando apropriado, 
          preservando histórico legível e sem flooding de mensagens
        - MUST evitar poluição visual mantendo rastreabilidade
        - MUST ser legível por máquina
        - SHOULD utilizar cores e destaques para status

    Status (emoji + cor):
        - OK    : ✔ (verde)
        - INFO  : ℹ️
        - WARN  : ⚠️
        - ERROR : ❌ (com destaque)

    Ações:
        - JSON-VALIDATE : 📄
        - PROCESS       : ⚙️
        - VERIFY        : 🔍
        - CHANGE-NAME   : ✏️
        - SKIP          : ⏭️
        - FIX           : 🛠️
        - FIXED         : ✅
        - TRANSLATE     : 🌐
        - SYNC-XML      : 📄➡️💿

[REGRAS DE CONTEXTO GLOBAL]

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
  - CÓDIGO: Implementado em microfunções reutilizáveis, evitando reimplementar funcionalidade

  [DIRETRIZES DE IMPLEMENTAÇÃO]
  - IDEMPOTÊNCIA: Seguro para múltiplas execuções no mesmo ambiente.
  - HEADLESS: Operação plena sem interface gráfica ou interação de usuário.
  - CIRURGIA: Minimizar diffs; sem refatoração estética; preservar comentários/indent.
  - DETERMINISMO: Linguagem declarativa; regras testáveis.

  [RESTRIÇÕES / VEDAÇÕES]
  - Não prosseguir com sistema em estado inconsistente ou pendente.
  - Não assumir conectividade de rede (Offline-First por padrão)
    configurável para Online-First.
  - Não depender de módulos externos ou bibliotecas não nativas.
  - Não executar etapas sem validação de sucesso posterior.

  [ESTRUTURA DE EXECUÇÃO]
  1. Inicialização segura (ExecutionPolicy, TLS, Context Check).
  2. Garantia de instância única (Global Mutex).
  3. Validação de pré-requisitos e pilha de manutenção do SO.
  4. Detecção e validação de gamelist.xml.
  5. Orquestração modular com validação individual de cada micro-função.
  6. Finalização auditável com log rastreável e saída determinística.

  [INVOCAÇÃO]
  O script sempre auto identifica se foi importado ou executado:
  1. Se executado diretamente executa função main repassando parâmetros 
      recebidos por linha de comando ou variáveis de ambiente.
  2. Se importado expõe as funções públicas para serem chamadas por outros
      scripts sem executar nada
        
  [CONTRATO DE I/O]
  Entrada: Árvore com 'gamelist.xml' e ROMs.
  Saída:   Arquivos renomeados, XML sincronizado, <desc> em pt-BR,
           hashes consistentes e nomes sem colisão.

  [CHECKLIST DE CONFORMIDADE (MUST)]
  - Todos os <path> correspondem aos arquivos reais.
  - Nomes contêm " [id]" e são únicos.
  - Regras de parênteses aplicadas; localidades preservadas.
  - <lang>='pt-br' quando (BR)/(BR-*) presente.
  - .sha256 (se houver) alinhado à ROM (case sensitive).
  - Sem falhas silenciosas; erros logados em tela/reportados.
  - Encoding/estrutura do XML inalterados fora do escopo.
  - Script deve ser idempotente, fail-safe e auditável.
  - Tradução controlada: detecta pt-BR, backoff, cache, mantém original se falha.
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


$blocked = @(
  '.xml', '.json', '.ini', '.exe', '.sh', '.ps1', '.bat',
  '.md5', '.mp3', '.png', '.jpg', '.jpeg', '.mp4', '.avi', '.mkv'
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

  # FIX-BUG: remove TODOS os parênteses, inclusive idiomas (RFC 1 + 2.5 + idempotência)
  $t = [regex]::Replace($text, '\s*\([^)]+\)', '')

  # remove IDs existentes (serão reconstruídos)
  $t = $t -replace '\s*\[[^\]]*\]', ''

  # remove resíduos numéricos em parênteses
  $t = $t -replace '\s*\(\d+\)', ''

  # normaliza espaços
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

  $name = $name.TrimEnd(' ', '.')

  # PROTECAO: nomes reservados Windows (RFC 11.2)
  $base = [IO.Path]::GetFileNameWithoutExtension($name)
  $ext = [IO.Path]::GetExtension($name)

  $reserved = @(
    'CON', 'PRN', 'AUX', 'NUL',
    'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
    'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9'
  )

  if ($reserved -contains $base.ToUpperInvariant()) {
    $base = "_$base" # PROTECAO
  }

  if (-not $base) {
    $base = "file" # PROTECAO: evita nome vazio
  }

  return "$base$ext"
}

function Get-UniqueFileName {
  param($dir, $name, $fileFullPath)

  # PROTECAO: unicidade deve ser garantida exclusivamente via ID/hash (RFC 4.8)
  if (-not (Test-Path -LiteralPath (Join-Path $dir $name))) {
    return $name
  }

  try {
    $hash = Get-FileHash -LiteralPath $fileFullPath -Algorithm SHA256 -ErrorAction Stop
    $fallback = $hash.Hash.Substring(0, 8)
  }
  catch {
    # PROTECAO: fallback determinístico mínimo
    $fallback = [Math]::Abs($fileFullPath.GetHashCode()).ToString("X8").Substring(0, 8)
  }

  $base = [IO.Path]::GetFileNameWithoutExtension($name)
  $ext = [IO.Path]::GetExtension($name)

  # FIX-BUG: substitui/força ID no nome ao invés de sufixo incremental
  $base = $base -replace '\s\[[^\]]+\]$', ''
  $candidate = "$base [$fallback]$ext"

  if (Test-Path -LiteralPath (Join-Path $dir $candidate)) {
    throw "Colisão determinística não resolvível para: $candidate" # PROTECAO
  }

  return $candidate
}

# ================= TRANSLATION ENGINE =================

$script:__translateCache = @{}

function Test-Portuguese {
  param([string]$text)

  if (-not $text) { return $false }

  $score = 0
  if ($text -match '\b(de|da|do|para|com|uma|não|que|em)\b') { $score++ }
  if ($text -match '[ãõçáéíóú]') { $score++ }

  return ($score -ge 2) # PROTECAO
}

function Invoke-TranslateBatch {
  param([string[]]$texts)

  if (-not $texts -or $texts.Count -eq 0) { return @() }

  $results = @()
  $batchSize = 5
  $delimiter = "|||SEP|||"

  for ($i = 0; $i -lt $texts.Count; $i += $batchSize) {

    $batch = $texts[$i..([math]::Min($i + $batchSize - 1, $texts.Count - 1))]

    $joined = ($batch -join " $delimiter ")

    for ($retry = 0; $retry -lt 3; $retry++) {
      try {

        $uri = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=pt&dt=t&q=$([uri]::EscapeDataString($joined))"
        $res = Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec 10

        $translatedRaw = ($res[0] | ForEach-Object { $_[0] }) -join ''
        $split = $translatedRaw -split [regex]::Escape($delimiter)

        for ($j = 0; $j -lt $batch.Count; $j++) {

          $original = $batch[$j]
          $translated = if ($j -lt $split.Count) { $split[$j].Trim() } else { $original }

          if (-not $translated -or $translated -eq $original) {
            $translated = $original # PROTECAO
          }

          $results += $translated
        }

        Start-Sleep -Milliseconds 200
        break
      }
      catch {
        Start-Sleep -Seconds (2 * ($retry + 1)) # PROTECAO
      }
    }
  }

  return $results
}

# PROTECAO: controle global de flooding e cache
$script:__lastLog = $null
$script:__hashLogCache = @{}

# PROTECAO: engine de log inline com controle de flooding (RFC 10)
$script:__logState = @{
  lastLine = ''
  lastType = ''
}

function Write-InlineLog {
  param(
    [string]$message,
    [string]$color = 'White',
    [switch]$forceNewLine
  )

  # evita flooding (mensagem idêntica)
  if (-not $forceNewLine -and $script:__logState.lastLine -eq $message) {
    return
  }

  $script:__logState.lastLine = $message

  if ($forceNewLine) {
    Write-Host $message -ForegroundColor $color
    return
  }

  # sobrescreve linha atual
  $padLength = [Math]::Max(0, $Host.UI.RawUI.BufferSize.Width - $message.Length - 1)
  $padding = ' ' * $padLength

  Write-Host -NoNewline ("`r" + $message + $padding) -ForegroundColor $color
}

function main {
  param()

  # PROTECAO: mutex global para evitar concorrência (RFC ARQUITETURA)
  $mutex = New-Object System.Threading.Mutex($false, "Global\ROM_Normalizer_Mutex")
  $lockAcquired = $false

  try {
    $lockAcquired = $mutex.WaitOne(0)

    if (-not $lockAcquired) {
      Write-Host "❌ ERROR :: Outra instância em execução" -ForegroundColor Red
      return
    }

    [int]$total = 0; [int]$renamed = 0; [int]$skipped = 0; [int]$errors = 0

    # PROTECAO: valida estrutura mínima Batocera
    $valid = Get-ChildItem -Directory | Where-Object {
      Test-Path (Join-Path $_.FullName "gamelist.xml")
    }

    if (-not $valid) {
      Write-Host "❌ ERROR :: Estrutura inválida - gamelist.xml ausente" -ForegroundColor Red
      return
    }      

    Get-ChildItem -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {

      # PROTECAO: exclusão de extensões proibidas (RFC cabeçalho)
      $extLower = [IO.Path]::GetExtension($_.Name).ToLowerInvariant()

      # .sha256 é tratado separadamente no pipeline → não deve entrar como ROM
      if ($blocked -contains $extLower -or $extLower -eq '.sha256') {
        Write-InlineLog "⏭️ SKIP :: BLOCKED_EXT :: $($_.Name)" DarkGray
        $skipped++
        return
      }

      $total++

      try {
        $file = $_

        $parsed = Extract-Extensions $file.Name
        if (-not $parsed) {
          Write-InlineLog "⏭️ SKIP :: $($file.Name)" DarkGray
          $skipped++; return 
        }

        $rawBase = $parsed.Base
        $exts = $parsed.Extensions

        # PROTECAO: tenta resolver nome completo via mapa externo (ex: gamelist.xml exportado)
        $mapPath = Join-Path $file.DirectoryName "gamelist.json"
        $xmlPath = Join-Path $file.DirectoryName "gamelist.xml" # PROTECAO: fallback XML
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
                $mapLangRaw = $entry.lang
              }
            }
          }
          catch {
            Write-Host "❌ 📄 MAP_LOAD :: $($_.Exception.Message)" -ForegroundColor Red
          }
        }
        elseif (Test-Path $xmlPath) {
          try {
            # FIX-BUG: suporte direto a gamelist.xml quando JSON inexistente
            [xml]$xml = Get-Content $xmlPath -Raw

            # FIX-BUG: escape seguro de string para XPath (suporta aspas simples)
            function ConvertTo-XPathLiteral {
              param([string]$value)

              if ($value -notmatch "'") {
                return "'$value'"
              }

              if ($value -notmatch '"') {
                return '"' + $value + '"'
              }

              # fallback: concatenação segura
              $parts = $value -split "'"
              $xpath = "concat("

              for ($i = 0; $i -lt $parts.Count; $i++) {
                if ($i -gt 0) {
                  $xpath += ", ""'"", "
                }
                $xpath += "'" + $parts[$i] + "'"
              }

              $xpath += ")"
              return $xpath
            }
          
            # FIX-BUG: usa path relativo padrão "./"
            # FIX-BUG: busca deve usar nome REAL do arquivo (RFC 0.2 correlação)
            $searchName = ("./" + $file.Name).ToLowerInvariant()
            $escaped = ConvertTo-XPathLiteral $searchName

            $node = $xml.SelectSingleNode("//game[translate(path, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz') = $escaped]")

            if ($node) {
              # ================= TRADUÇÃO <desc> =================

              $descNode = $node.SelectSingleNode("desc")

              if ($descNode -and $descNode.InnerText -and -not (Test-Portuguese $descNode.InnerText)) {

                $original = $descNode.InnerText
                $key = $original.ToLowerInvariant()

                if (-not $script:__translateCache.ContainsKey($key)) {

                  $translated = Invoke-TranslateBatch @($original)

                  if ($translated.Count -gt 0) {
                    $script:__translateCache[$key] = $translated[0]
                  }
                  else {
                    $script:__translateCache[$key] = $original # PROTECAO
                  }
                }

                $descNode.InnerText = $script:__translateCache[$key]
              }

              # FIX-BUG: atualização obrigatória da tag <lang>
              if ($idioma) {

                $langValue = $null

                if ($idioma -match '\(BR') {
                  $langValue = 'pt-br'
                }
                elseif ($idioma -eq '(PT)') {
                  $langValue = 'pt-pt'
                }
                else {
                  $langValue = $idioma.Trim('()').ToLowerInvariant()
                }

                if ($node.lang) {
                  $node.lang = $langValue
                }
                else {
                  $newLang = $xml.CreateElement("lang")
                  $newLang.InnerText = $langValue
                  $node.AppendChild($newLang) | Out-Null
                }

                $xml.Save($xmlPath)
              }            

              if ($node.name) {
                $resolvedBase = $node.name
              }

              if ($node.lang) {
                $mapLangRaw = $node.lang.InnerText
              }
            }
          }
          catch {
            Write-Host "❌ 📄 XML_LOAD :: $($_.Exception.Message)" -ForegroundColor Red
          }
        }
        else {
          # PROTECAO: ROM ausente referenciada no XML
          Write-InlineLog "⚠️ WARN :: XML_REF_SEM_ROM :: $searchName" Yellow -forceNewLine
        }

        # EXTRAÇÃO ANTES DE QUALQUER MODIFICAÇÃO        
        $idioma = Get-IdiomaSeguro $resolvedBase

        # FIX-BUG: normalização obrigatória para uppercase (RFC 2.1)
        if ($idioma) {
          $idioma = "(" + $idioma.Trim('()').ToUpperInvariant() + ")"
        }

        # FIX-BUG: garante que idioma válido nunca seja perdido
        if (-not $idioma) {
          $fallbackIdioma = Get-IdiomaSeguro $rawBase
          if ($fallbackIdioma) {
            $idioma = $fallbackIdioma # PROTECAO: fallback obrigatório
          }
        }

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
              $idioma = "(" + $tokens[0].ToUpperInvariant() + ")"
            }
          }
        }

        $id = Get-IdSeguro $resolvedBase

        # NORMALIZAÇÃO
        $nome = Normalize-Nome $resolvedBase # FIX-BUG: usa nome expandido quando disponível
        if (-not $nome) {
          Write-Host "⚠️ WARN :: SKIP :: Nome vazio após normalização :: $($file.Name)" -ForegroundColor Yellow
          $skipped++
          return
        }

        # RECONSTRUÇÃO CANÔNICA
        $newBase = $nome
        if ($idioma) { $newBase += " $idioma" }        
        # FIX-BUG: remoção de fallback_id (nova regra RFC 4.8)
        # PROTECAO: ID só deve existir se extraído de origem válida
        # NÃO gerar identificador artificial em nenhuma hipótese

        $newBase = $nome
        if ($idioma) { $newBase += " $idioma" }
        if ($raw -match '^\d+$') {
          $validIds += $raw
        }

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

            # PROTECAO: evita reprocessamento redundante
            if ($file.Name -eq $newName) {
              $skipped++
              return
            }

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
            Write-InlineLog "⏭️ SKIP :: NO_MATCH_SIZE :: $(newName)" DarkGray            
            $skipped++
            return
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

                # PROTECAO: evita spam de comparação repetida
                if (-not $script:__hashLogCache) { $script:__hashLogCache = @{} }

                if (-not $script:__hashLogCache.ContainsKey($file.FullName)) {
                  Write-InlineLog "🔍 PROCESS :: HASH_COMPARE :: $($file.Name)" Cyan
                  $script:__hashLogCache[$file.FullName] = $true
                }

                $hashA = Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256
                $hashB = Get-FileHash -LiteralPath $targetPath -Algorithm SHA256

                if ($hashA.Hash -eq $hashB.Hash) {

                  Write-Host "⚠️ 🛠️ DUPLICATE_CONFIRMED :: avaliando preservação determinística" -ForegroundColor Yellow

                  # FIX-BUG: seleção determinística do melhor candidato
                  $candidateA = $file.Name
                  $candidateB = (Split-Path $targetPath -Leaf)

                  $normalizedA = $candidateA.Equals($newName, [StringComparison]::Ordinal)
                  $normalizedB = $candidateB.Equals($newName, [StringComparison]::Ordinal)

                  function __distance($a, $b) {
                    # PROTECAO: aproximação simples determinística
                    return [Math]::Abs($a.Length - $b.Length)
                  }

                  if ($normalizedA -and -not $normalizedB) {
                    $remove = $candidateB
                    $removePath = $targetPath
                  }
                  elseif ($normalizedB -and -not $normalizedA) {
                    $remove = $candidateA
                    $removePath = $file.FullName
                  }
                  else {
                    $distA = __distance $candidateA $newName
                    $distB = __distance $candidateB $newName

                    if ($distA -lt $distB) {
                      $remove = $candidateB
                      $removePath = $targetPath
                    }
                    elseif ($distB -lt $distA) {
                      $remove = $candidateA
                      $removePath = $file.FullName
                    }
                    else {
                      # desempate lexicográfico estável
                      if ($candidateA -lt $candidateB) {
                        $remove = $candidateB
                        $removePath = $targetPath
                      }
                      else {
                        $remove = $candidateA
                        $removePath = $file.FullName
                      }
                    }
                  }

                  if ($PSCmdlet.ShouldProcess($remove, "Remove duplicate determinístico")) {
                    Remove-Item -LiteralPath $removePath -Force -ErrorAction Stop

                    # FIX-BUG: remove hash associado ao arquivo removido
                    $hashFile = "$removePath.sha256"
                    if (Test-Path $hashFile) {
                      Remove-Item -LiteralPath $hashFile -Force -ErrorAction SilentlyContinue
                      Write-Host "✔ 🗑️ HASH_REMOVED :: $(Split-Path $hashFile -Leaf)" -ForegroundColor DarkGreen
                    }

                    Write-InlineLog "✔ REMOVED :: $remove" DarkGreen -forceNewLine
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

          # FIX-BUG: sincroniza arquivo .sha256 associado
          # PROTECAO: resolve corretamente nome do .sha256 (com ou sem extensão intermediária)
          # PROTECAO: resolve corretamente nome do .sha256 (opcional)
          $hashCandidates = @(
            "$($file.FullName).sha256",
            (Join-Path $file.DirectoryName ([IO.Path]::GetFileNameWithoutExtension($file.Name) + ".sha256"))
          )

          $oldHashFile = $hashCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
          # FIX-BUG: garante coerência com extensões encadeadas (ex: .chd, .zip, etc)
          $newHashFile = (Join-Path $file.DirectoryName $newName) + ".sha256"
          $newHashFile = $newHashFile -replace '\.\.', '.' # PROTECAO
          
          # PROTECAO: .sha256 é opcional e deve existir no momento da operação
          if ($oldHashFile -and (Test-Path -LiteralPath $oldHashFile)) {
            try {
              Rename-Item -LiteralPath $oldHashFile -NewName (Split-Path $newHashFile -Leaf) -ErrorAction Stop

              # PROTECAO: valida existência real após rename
              if (Test-Path -LiteralPath $newHashFile) {
                $content = Get-Content -LiteralPath $newHashFile -Raw -ErrorAction Stop
                $content = $content -replace [regex]::Escape($file.Name), $newName
                Set-Content -LiteralPath $newHashFile -Value $content -Encoding ASCII -ErrorAction Stop
              }
              else {
                Write-Host "⚠️ WARN :: HASH_RENAME_SKIP :: $(Split-Path $oldHashFile -Leaf)" -ForegroundColor Yellow
              }
            }
            catch {
              Write-Host "❌ HASH_SYNC_FAIL :: $($_.Exception.Message)" -ForegroundColor Red
            }
          }

          # PROTECAO: evita flooding - log consolidado por evento único
          if ($script:__lastLog -ne $newName) {
            Write-InlineLog "✔ CHANGE-NAME :: $($file.Name) -> $newName" DarkGreen
            $script:__lastLog = $newName
          }
          # PROTECAO: evita flooding - log consolidado por evento único
          if ($script:__lastLog -ne $newName) {
            Write-InlineLog "✔ CHANGE-NAME :: $($file.Name) -> $newName" DarkGreen
            $script:__lastLog = $newName
          }
          $renamed++
        }

      }
      catch {
        $errors++
        Write-InlineLog "❌ ERROR :: $($file.Name) :: $($_.Exception.Message)" Red -forceNewLine
      }
    }

  }
  finally {
    if ($lockAcquired) {
      $mutex.ReleaseMutex()
    }
    $mutex.Dispose()
  }    

  # FIX-BUG: remoção de hashes órfãos após processamento
  Get-ChildItem -Recurse -File -Filter *.sha256 -ErrorAction SilentlyContinue | ForEach-Object {
    try {
      $hashFile = $_
      $targetFile = $hashFile.FullName -replace '\.sha256$', ''

      if (-not (Test-Path $targetFile)) {

        Write-InlineLog "⚠️ FIX :: ORPHAN_HASH :: $($hashFile.Name)" Yellow -forceNewLine

        if ($PSCmdlet.ShouldProcess($hashFile.Name, "Remove orphan hash")) {
          Remove-Item -LiteralPath $hashFile.FullName -Force -ErrorAction Stop
          Write-Host "✔ 🗑️ HASH_REMOVED :: $($hashFile.Name)" -ForegroundColor DarkGreen
        }
      }
    }
    catch {
      Write-Host "❌ HASH_ORPHAN_FAIL :: $($_.Exception.Message)" -ForegroundColor Red
    }
  }

  Write-Host ""
  Write-Host "" # flush linha inline
  Write-InlineLog "ℹ️ ==== RESUMO ====" Cyan -forceNewLine
}

# AUTO-INVOCAÇÃO SEGURA
if ($MyInvocation.InvocationName -ne '.') {
  main @PSBoundParameters
}
  