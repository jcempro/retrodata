#!/usr/bin/env pwsh
# encoding: utf-8

<#
.SYNOPSIS
  Normalizador determinístico de ROMs com sincronização bidirecional
  de gamelist.xml, deduplicação SHA256 e suporte a JSON tree virtual.

.DESCRIPTION
  Este script percorre recursivamente o diretório atual executando,
  de forma integrada, determinística, idempotente e fail-safe:

    - Normalização canônica de ROMs
    - Sincronização bidirecional com gamelist.xml
    - Deduplicação segura baseada em SHA256
    - Gerenciamento de integridade .sha256 e JSON Tree
    - Tradução e coerência de metadados
    - Validação estrutural via JSON tree virtual

  O pipeline MUST compartilhar:
    - enumeração do filesystem
    - cache SHA256
    - parsing XML
    - parsing JSON
    - estado estrutural
    - resultados de correlação

  evitando múltiplas iterações redundantes sobre os mesmos dados.

  Exceto pelas operações de:
    - criação
    - validação
    - atualização
    - remoção
    - sincronização
    - deduplicação
    - integridade

  NÃO são processados, exceto dentro das pastas contidas em
  $specialJsonDirs e, tpdps os quesitos SHA256:
    .xml, .json, .ini, .exe, .sh, .ps1, .bat, .md5
    .mp3, .png, .jpg, .jpeg, .mp4, .avi, .mkv

.RFC
  Especificação Integrada de Normalização, Integridade e JSON Tree
  (versão 3.1)

  Estrutura - Iteração Única - Foco em Desempenho O(N) :
    ENUMERAÇÃO ÚNICA
        ↓
    CORRELAÇÃO
        ↓
    NORMALIZAÇÃO
        ↓
    RENAME
        ↓
    HASH
        ↓
    DEDUP
        ↓
    SYNC XML/JSON/SHA    

  IMPORTANTE:
    - Todo comportamento MUST ser determinístico e idempotente
    - O filesystem real é a origem primária de verdade física
    - XML MAY atuar como fonte auxiliar de reconstrução nominal
    - JSON tree MUST operar como banco estrutural virtual de .sha256
      (Pasta de arquivos virtual)
    - JSON tree NÃO possui hash próprio e MUST NOT ser hasheado
    - Deduplicação SHA256 ocorre em TODOS os modos operacionais
    - Normalização de ROM ocorre em TODOS os modos operacionais
    - Case-sensitive MUST ser preservado quando semanticamente
      relevante
    - Nenhum ID MAY ser inventado, sintetizado ou inferido
      artificialmente

  Correlação é o processo determinístico de associação entre:

    - ROM física
    - hash SHA256
    - entrada XML
    - entrada JSON tree
    - nome canônico esperado

  ============================================================
  0. MODOS OPERACIONAIS
  ============================================================

  O script MUST suportar:

    - MODE NORMALIZE
    - MODE HASH
    - MODE INTEGRATED

  Entretanto:
    - deduplicação SHA256 MUST sempre ocorrer
    - normalização MUST sempre ocorrer
    - sincronização XML MUST sempre ocorrer quando aplicável

  Flags:

    []:
      - cria hashes ausentes
      - NÃO remove .sha256 órfãos
      - NÃO corrige divergências .sha256 automaticamente
      - realiza e aplica normalização completa
      - realiza e aplica deduplicação segura

    [-VerifyOnly]:
      - nenhuma escrita é permitida
      - MUST NOT:
          * corrigir
          * criar
          * remover
          * renomear
          * sincronizar
          * alterar XML
          * alterar JSON tree
          * alterar hashes
        - deduplicação MUST continuar sendo:
            - calculada
            - validada
            - correlacionada
            - reportada

          * e MUST NOT alterar arquivos.

    [-Fix]:
      - remove .sha256 órfãos
      - habilita correção automática
      - recria hashes inválidos (.sha256 e JSON Tree)
      - aplica sincronizações pendentes

  ============================================================
  1. MODELO ESTRUTURAL
  ============================================================

  Ordem normativa de verdade operacional:

    1. Filesystem real
    2. SHA256 validado
    3. gamelist.xml
    4. JSON tree derivada de integridade
    5. Metadados derivados

  ============================================================
  2. JSON TREE VIRTUAL ($specialJsonDirs)
  ============================================================

  JSON tree MUST operar como representação hierárquica virtual
  equivalente a um conjunto expandido de arquivos .sha256
  convencionais.

  Cada entrada hash do JSON tree MUST ser tratada como
  equivalente operacional de:

    <arquivo>.sha256

  Objetivo:
    reduzir custo estrutural em diretórios:
      - altamente aninhados
      - densos em arquivos pequenos
      - contendo grandes volumes de assets

        * como coleções Steam e Windows.
      - consolidar hashes pequenos/aninhados
      - evitar excesso de arquivos .sha256 físicos

  IMPORTANTE:
    - JSON tree NÃO possui hash próprio
    - JSON tree MUST NOT ser hasheado
    - JSON tree MUST NOT participar da deduplicação
    - Apenas arquivos reais participam da deduplicação

  Cada entrada string do JSON representa semanticamente um
  arquivo .sha256 convencional.

  A única diferença entre:
    - entrada JSON tree
    - arquivo .sha256 convencional

  é a forma de armazenamento.

  A semântica operacional MUST permanecer equivalente.

  Estrutura:

  {
    "subdir": {
      "file.bin": "HASH64"
    }
  }

  Regras:
    - diretórios → objetos
    - arquivos → HASH64 ASCII
    - .sha256.json MUST ser ignorado:
        * na enumeração
        * no hashing
        * na deduplicação
        * na normalização
        * como arquivo comum durante validação estrutural
    - JSON inválido MUST gerar ERROR
    - JSON ausente MUST ser criado (exceto VerifyOnly)

  Diretórios contidos em $specialJsonDirs MUST operar sobre
  modelo estrutural híbrido:

    - filesystem real
    - JSON tree virtual derivada

  Toda operação de:
    - rename
    - deduplicação
    - sincronização XML
    - integridade
    - remoção
    - validação estrutural

  MUST refletir simultaneamente:
    - filesystem
    - JSON tree correspondente

  preservando consistência lógica bidirecional.

  JSON tree NÃO altera a hierarquia lógica do root ROM.

  Ela representa apenas mecanismo virtual de consolidação
  estrutural de hashes.

  JSON tree MUST ser tratada como estrutura derivada.

  O filesystem real permanece a autoridade física primária.

  ============================================================
  3. GAMELIST.XML
  ============================================================

  ROM é qualquer arquivo cujo conjunto de extensões encadeadas
  resulte em extensão final válida de conteúdo executável/emulável.

  Exemplos válidos:
    game.sfc
    game.sfc.7z
    game.iso.zip
    game.chd
    game.pc (usado por batocera para steam e windows)

  Arquivos auxiliares NÃO são ROM:
    .sha256
    .sha256.json
    .xml
    .png
    .jpg
    .mp3
    etc.

  3.0 Definição de pasta ROM

    Uma pasta ROM é definida como:

      roms/<sistema>/

    Onde:
      - <sistema> representa a plataforma/emulador
      - gamelist.xml MAY existir apenas neste nível
      - a enumeração MUST partir deste root lógico

    Estruturas válidas:

      Estrutura direta:
        roms/<sistema>/<rom>[.<subext>]*.<ext>

      Estrutura aninhada:
        roms/<sistema>/<jogo>/<rom>[.<subext>]*.<ext>

      Legenda:
      - [.<subext>]* zero ou mais ocorrência de subextensões
        permitidas:
          .sub1.sub2 ...

    Regras:
      - o subdiretório aninhado representa o próprio jogo
      - o nome da ROM MAY divergir parcialmente do diretório pai
      - múltiplos níveis arbitrários NÃO são suportados
      - gamelist.xml MUST permanecer:
            roms/<sistema>/gamelist.xml

      - gamelist.xml MUST NOT existir:
            roms/<sistema>/<jogo>/gamelist.xml

      - Zero efeitos colaterais bidirecionais não intencionais
        MUST ser garantido durante sincronização ROM ↔ XML.

    O pipeline MUST tratar:
      - ROM direta
      - ROM aninhada em pasta do jogo

    como equivalentes semanticamente.

    Subdiretórios de jogo NÃO constituem novo root ROM.

    Toda correlação estrutural MUST permanecer vinculada
    ao root:

      roms/<sistema>/

    Todo path armazenado em:
      - gamelist.xml

    MUST utilizar caminho relativo ao root roms/<sistema>/
    lógico.

    Todo path armazenado em:
      - JSON tree
      - logs
      - hashes derivados

    MUST utilizar caminho relativo ao root roms/ lógico.

  3.1 Detecção
    - gamelist.xml MUST existir apenas no root da pasta ROM.

    - O pipeline MUST NOT procurar, herdar ou processar
      gamelist.xml em subdiretórios aninhados.
    - subníveis MUST NOT ser utilizados

  3.2 Correlação
    - ROM ↔ <path> MUST ser case-sensitive
    - correlação MUST ser determinística
    - Case-sensitive MUST ser preservado integralmente:
          - ROM → XML
          - XML → ROM
          - filename → .sha256
          - JSON tree → filesystem

  3.3 Influência normativa do XML
    - Quando gamelist.xml existir:
        * ele MUST influenciar o nome final da ROM
        * IDs MUST ser extraídos EXCLUSIVAMENTE dele
        * XML torna-se autoridade normativa auxiliar

  3.4 IDs
    Se gamelist.xml existir e a entrada equivalente a
      ROM existir nele e ela possuir ID:
      - IDs MUST ser extraídos apenas do atributo:
          <game id="...">

      - IDs:
          * MUST ser preservados integralmente
          * MUST preservar case original
          * MUST NOT sofrer uppercase/lowercase
          * MUST NOT ser inventados
          * MUST NOT ser sintetizados
          * MUST NOT usar fallback artificial
          * MUST NOT ser inferidos do filename

    - Senão:
      - Se filename possuir [id]:
        - IDs MUST ser extraídos apenas do filename

  3.5 Duplicidade XML
    - MUST NOT existir múltiplas entradas <game>
      apontando para o mesmo <path>

    - Em caso de duplicidade:
        * MUST detectar
        * MUST logar WARN/ERROR
        * MUST consolidar deterministicamente
        * MUST preservar apenas uma entrada válida

  3.6 Direcionalidade
    - PRIMARY:
        ROM → XML

    - SECONDARY:
        XML → ROM
        APENAS se:
            * ROM esperada não existir
            - Se múltiplas ROMs puderem corresponder ao mesmo
              <path> esperado, a sincronização XML → ROM
              MUST ser abortada com WARN/ERROR.

  3.7 Restrições
    - MUST NOT criar ROM inexistente
    - MUST preservar encoding XML
    - MUST preservar estrutura XML
    - MUST evitar mutações fora do escopo

  ============================================================
  4. ESTRUTURA CANÔNICA
  ============================================================

  Enumeração compartilhada significa:

    - um único ciclo estrutural de descoberta
    - reutilizado por:
        * normalização
        * XML
        * hashing
        * JSON tree
        * deduplicação
        * tradução

  O nome final MUST obedecer:

    <NomeNormalizado>[ (IDIOMA)]?[ [ID]]?.<ext>[.<ext2>...]

  Garantias:
    - idioma único
    - ID único
    - extensões encadeadas válidas
    - unicidade determinística
    - consistência estrutural
    - preservação de case relevante

  ============================================================
  5. PROCESSAMENTO DE IDIOMA
  ============================================================

  5.1 Extração
    - MUST extrair conteúdos "()"
    - tokens MAY conter:
      "/", ",", ";", "-"

  5.2 Normalização
    - idioma MUST ser uppercase
    - trim MUST ser aplicado

  5.3 Whitelist
    - BR, PT, USA, JP, EU, ES, FR, DE, IT, JAPAN, WORLD, EUR, entre outras

  5.4 Seleção
    Prioridade:
      1. BR
      2. PT
      3. USA
      4. Primeiro válido

  5.5 Reconstrução
    - MUST existir apenas um idioma
    - formato MUST ser "(XX)"

  5.6 Restrições
    - idioma válido MUST NOT ser perdido (exceto excedentes)

  ============================================================
  6. PROCESSAMENTO DE ID
  ============================================================

  Origem:
    - PREFERÊNCIA 1: gamelist.xml
    - PREFERÊNCIA 2: pré-existência FS: [id]

  Regras:
    - apenas um ID final
    - ID MUST ser case-sensitive
    - ID MUST preservar case original
    - ID MUST NOT ser transformado
    - ID MUST NOT ser gerado artificialmente
    - ID válido MUST NOT ser perdido

  Reconstrução:
    - MUST usar:
        " [ID]"

    - posição:
        após idioma
        antes da extensão

  ============================================================
  7. NORMALIZAÇÃO DO BASENAME
  ============================================================

  MUST:
    - remover conteúdos inválidos
    - aplicar TitleCase invariável
    - preservar extensão
    - preservar numerais romanos válidos
    - numerais romanos MUST ser uppercase
    - corrigir artigos invertidos
    - remover tags irrelevantes
    - preservar localidades válidas
    - conversão de artigos invertidos MUST NOT ocorrer
      quando houver hífen estrutural no basename
    - remover sufixo irrelevante:
        " - The Videogame" e equivalente (com cautela)

  MUST remover:
    - Beta
    - Rev
    - Build
    - Proto
    - Demo
    - Sample
    - Rev
    - versões técnicas (T1.01, Rev 1, ...)
    - numeração irrelevante
    - Qualquer outra coisa entre parênteses que não seja idioma

  Formas:
    - "(BR-XX)" MUST ser preservado integralmente

  ============================================================
  8. EXTENSÕES
  ============================================================

  Parsing:
    - MUST ocorrer da direita para esquerda

  Cadeias:
    - ".sfc.7z" são válidas
    - ".iso.zip" são válidas
    - conteúdos intermediários inválidos entre extensões
      MUST ser removidos:
          game.sfc.(1).7z → game.sfc.7z

  Restrições:
    - extensões inválidas encerram parsing
    - ordem MUST ser preservada

  ============================================================
  9. SHA256 CONVENCIONAL
  ============================================================

  Formato:

    "HASH64  filename.ext"

  Regras:
    - ASCII obrigatório
    - filename MUST ser case-sensitive
    - hash MAY ser lowercase na leitura
    - hash MUST ser uppercase na escrita
    - espaço simples ou múltiplo MUST ser aceito

  ============================================================
  10. HASH, ÓRFÃOS E CORRELAÇÃO
  ============================================================

  Antes da remoção de hash órfão, o sistema MUST tentar:

    1. localizar filename original (mesmo diretório)
    2. localizar arquivo com hash correspondente
    3. correlacionar rename legítimo
    4. correlacionar XML/JSON tree

  Somente após falha total:
    - hash MAY ser removido

  ============================================================
  11. DEDUPLICAÇÃO
  ============================================================

  A análise de deduplicação SHA256 MUST ocorrer:
    - em TODOS os modos
    - inclusive VerifyOnly

  A aplicação física da deduplicação:
    - MUST NOT ocorrer em VerifyOnly

  Critério definitivo:
    - SHA256

  Regras:
    - apenas um arquivo MUST sobreviver
    - seleção MUST ser determinística:
        1. nome mais canônico
        2. menor distância estrutural
        3. ordem ordinal estável
    - timestamps, atributos e metadados do filesystem
      SHOULD NOT ser utilizados como critério
      de equivalência estrutural

  MUST refletir:
    - .sha256
    - JSON tree
    - gamelist.xml

  MUST detectar:
    - hashes órfãos
    - entradas JSON órfãs
    - referências XML inválidas

  Em modo [-Fix]:
    - MUST remover hashes órfãos
    - MUST remover entradas JSON órfãs
    - MUST remover referências XML inválidas

  Garantias:
    - MUST preservar ao menos um arquivo
    - MUST NOT criar backups artificiais
    - MUST NOT usar "__dup" ou equivalente
    - Em nenhuma circunstância todos os arquivos
      equivalentes MAY ser removidos

  Quando múltiplas entradas XML referenciarem arquivos
  deduplicados equivalentes:

    - referências redundantes MUST ser removidas
    - apenas a referência canônica MUST sobreviver

  Aplicado a:
    - Qualquer arquivo tratado

  ============================================================
  12. TRADUÇÃO E METADADOS
  ============================================================

  Tradução:
    - MUST possuir cache
    - MUST detectar pt-BR
    - MUST usar retry/backoff
    - MUST preservar original em falha

  <lang>:
    - (BR)/(BR-*) → pt-BR
    - (PT)        → pt-PT

  ============================================================
  13. OTIMIZAÇÃO
  ============================================================

  O pipeline integrado MUST compartilhar:
    - enumeração
    - cache SHA256
    - parse XML
    - parse JSON
    - análise estrutural

  evitando múltiplas iterações completas.

  - O pipeline MUST evitar reenumeração integral do
    filesystem sempre que o estado compartilhado já
    possuir representação válida reutilizável.

  MAY utilizar:
    - short-circuit por tamanho
    - cache SHA256
    - reaproveitamento intra-execução

  Essas heurísticas MUST NOT alterar o resultado final.

  ============================================================
  14. RESILIÊNCIA E SEGURANÇA
  ============================================================

  PROIBIÇÕES:
    - catch vazio
    - supressão silenciosa
    - loops infinitos
    - DryRun equivalente
    - mutações fora do escopo
    - -ErrorAction SilentlyContinue sem tratamento posterior

  PROTEÇÕES:
    - escrita atômica via .tmp
    - validação pós-operação
    - fallback determinístico
    - fail-safe de deduplicação
    - isolamento de $specialJsonDirs

  ============================================================
  15. GARANTIAS
  ============================================================

  - Execução determinística
  - Idempotência após convergência
  - Idiomas válidos nunca são perdidos (exceto excedentes)
  - IDs válidos nunca são perdidos
  - IDs preservam case original
  - Idiomas permanecem uppercase
  - Numerais romanos permanecem uppercase
  - Estrutura XML preservada
  - Estrutura JSON preservada
  - Compatibilidade Batocera
  - Deduplicação segura
  - JSON tree consistente com filesystem
  - Zero perda total em deduplicação

  ============================================================
  16. LIMITAÇÕES
  ============================================================

  - Não valida No-Intro
  - Não corrige semântica de nomes
  - Não suporta .sha256 multiline
  - Não processa gamelist.xml aninhado
  - Segue Symlink/junction, mas sem tratamento especial
  - Relações multiarquivo (.cue/.bin, multidisc, playlists)
    NÃO recebem tratamento semântico especial além da
    integridade estrutural básica.

  ============================================================
  17. LOG
  ============================================================

  Diretrizes:
    - MUST indicar ação e alvo
    - SHOULD utilizar path relativo
    - SHOULD utilizar rewrite inline
    - MUST preservar rastreabilidade
    - MUST ser legível por máquina

  Status:
    - OK    : ✔
    - INFO  : ℹ️
    - WARN  : ⚠️
    - ERROR : ❌

  Ações:
    - JSON-VALIDATE : 📄
    - PROCESS       : ⚙️
    - VERIFY        : 🔍
    - CHANGE-NAME   : ✏️
    - FIX           : 🛠️
    - FIXED         : ✅
    - HASHING       : 🧮
    - REMOVE-FILE   : 🗑️
    - TRANSLATE     : 🌐
    - SYNC-XML      : 📄➡️💿

  PROTEÇÃO:
    - falha de log MUST NOT interromper execução

[REGRAS DE CONTEXTO GLOBAL]

  [ESTILO, DESIGN & RASTREABILIDADE]
  - Design: Imutabilidade, Baixo Acoplamento e suporte a
    camelCase/snake_case.
  - Rastreabilidade Diff-Friendly: Alterações de código
    minimalistas otimizados para desempenho aliado a análise
    visual de mudanças.

  [CAPACIDADES TÉCNICAS (REAPROVEITÁVEIS)]
  - COMPATIBILIDADE: Identificação de versão/subversão para
    comandos adequados.
  - RESILIÊNCIA: Retry com backoff progressivo e múltiplas
    formas de tentativa.
  - DETERMINISMO: Validação de estado real pós-operação
    (não apenas ExitCode).

  [EVENTOS & TELEMETRIA (CALLBACK)]
  - DESACOPLAMENTO: Script não gerencia arquivos de log,
    apenas em tela
  - AUDITÁVEL: Logs claros, estruturados e informativos para
    cada etapa crítica, incluindo falhas, decisões de lógica
    e resultados de validação.

  [REGRAS DE ARQUITETURA]
  - ISOLAMENTO: Mutex Global obrigatório para prevenir
    paralelismo.
  - MODULARIDADE: Baseado em micro-funções especialistas e
    reutilizáveis.
  - SINCRO: Execução 100% síncrona, bloqueante e sequencial:
  - ESTADO: Barreira de consistência (DISM/CBS) para
    operações de sistema.
  - NATIVO: Uso estrito de comandos nativos do OS, salvo
    exceção declarada.
  - CÓDIGO: Implementado em microfunções reutilizáveis.
  - PIPELINE: MUST reutilizar estado compartilhado e evitar
    revarredura redundante.

  [DIRETRIZES DE IMPLEMENTAÇÃO]
  - IDEMPOTÊNCIA: Seguro para múltiplas execuções.
  - HEADLESS: Operação sem interface gráfica.
  - CIRURGIA: Minimizar diffs; preservar comentários e
    indentação.
  - DETERMINISMO: Linguagem declarativa; regras testáveis.

  [RESTRIÇÕES / VEDAÇÕES]
  - Não prosseguir com sistema inconsistente.
  - Não assumir conectividade de rede.
  - Não depender de módulos externos.
  - Não executar etapas sem validação posterior.

  [ESTRUTURA DE EXECUÇÃO]
  1. Inicialização segura.
  2. Garantia de instância única.
  3. Validação estrutural do ambiente.
  4. Enumeração compartilhada.
  5. Correlação filesystem/XML/JSON tree/hash.
  6. Deduplicação determinística.
  7. Normalização estrutural.
  8. Sincronização XML/JSON/hash.
  9. Finalização auditável.

  [INVOCAÇÃO]
  O script MUST auto detectar:
    1. Execução direta → chama main
    2. Importação → expõe funções públicas

  [CONTRATO DE I/O]
  Entrada:
    ROMs, gamelist.xml, .sha256 e JSON tree.

  Saída:
    Estrutura consistente, determinística,
    sincronizada e deduplicada.

  [CHECKLIST DE CONFORMIDADE (MUST)]
  - Todos os <path> existem.
  - Não existem entradas XML duplicadas.
  - IDs vêm exclusivamente do XML.
  - IDs preservam case-sensitive.
  - Idiomas permanecem uppercase.
  - Numerais romanos permanecem uppercase.
  - JSON tree consistente.
  - .sha256 consistente.
  - Sem falhas silenciosas.
  - Estrutura XML preservada.
  - Script idempotente e fail-safe.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param()

# ================= CONFIG =================

$ValidExtensions = @(
  'sha256', 'chd', 'pc', 'pbp', '7z', 'zip', 'nes', 'smc', 'sfc', 'fig', 'n64', 'z64', 'v64',
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

$reserved = @(
  'CON', 'PRN', 'AUX', 'NUL',
  'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
  'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9'
)

$IdiomaPriority = @('BR', 'PT', 'USA')

# ================= CORE HELPERS =================

function Get-IdiomaTokens {
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

function Get-PreferredIdioma {
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

  $tokens = Get-IdiomaTokens $text
  return Get-PreferredIdioma $tokens
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

  $t = $text

  # FIX-BUG: preserva apenas idiomas válidos RFC 5 + RFC 7
  $t = [regex]::Replace(
    $t,
    '\s*\(([^)]+)\)',
    {
      param($m)

      $raw = $m.Groups[1].Value.Trim()

      if (-not $raw) {
        return ''
      }

      $normalized = $raw.ToUpperInvariant()

      # PROTECAO: preserva formas compostas válidas (BR-XX)
      if (
        $normalized -match '^[A-Z]{2,3}-[A-Z]{2,3}$'
      ) {
        return " ($normalized)"
      }

      $tokens = @()

      foreach ($part in ($normalized -split '[/,;]')) {

        $token = $part.Trim()

        if (-not $token) {
          continue
        }

        # PROTECAO: rejeita grupos mistos inválidos RFC 7
        if (-not ($ValidIdiomas -contains $token)) {
          return ''
        }

        $tokens += $token
      }

      if ($tokens.Count -eq 0) {
        return ''
      }

      $preferred = Get-PreferredIdioma $tokens

      if (-not $preferred) {
        return ''
      }

      return " $preferred"
    }
  )

  # remove IDs existentes (serão reconstruídos)
  $t = $t -replace '\s*\[[^\]]*\]', ''

  # FIX-BUG: remove numeração irrelevante RFC 7
  $t = $t -replace '\s*\(\d+\)', ''

  # normaliza espaços
  $t = $t -replace '\s{2,}', ' '

  return $t.Trim()
}

function Format-NomeCanonico {
  param([string]$nome)

  if (-not $nome) { return $null }

  $n = Remove-NoiseMarkers $nome

  if (-not $n) { return $null }

  # FIX-BUG: remove marcadores técnicos RFC 7
  $n = [regex]::Replace(
    $n,
    '(?i)\s*[\[\(]?\b(beta|proto|prototype|sample|demo|build|rev(?:ision)?)[^)\]]*[\)\]]?',
    ''
  )

  # FIX-BUG: remove versões técnicas RFC 7
  $n = [regex]::Replace(
    $n,
    '(?i)\bT\d+(\.\d+)?\b',
    ''
  )

  # Remoções controladas (conservador)
  # FIX-BUG: normaliza separadores ":" antes da sanitização
  $n = [regex]::Replace(
    $n,
    '\s*:\s*',
    ' - '
  )

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

  # FIX-BUG: remove resíduos estruturais finais
  $n = $n.Trim(' ', '-', '_', '.')

  if (-not $n) {
    return $null
  }

  # TitleCase (controlado)
  $n = ([cultureinfo]::InvariantCulture.TextInfo).ToTitleCase(
    $n.Trim().ToLowerInvariant()
  )

  # restaura siglas comuns
  $n = [regex]::Replace($n, '\b(Usa|Snk|Neo Geo|Hd|Vr|Tv|Rpg|Rts|Fps)\b', {
      param($m)
      $m.Value.ToUpperInvariant()
    })

  return Format-RomanAwareTitle $n
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
    # FIX-BUG: remove apenas lixo numérico intermediário
    $candidate = $candidate -replace '^\(\d+\)$', ''
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

function Format-RomanAwareTitle {
  param([string]$text)

  if (-not $text) { return $null } # FIX-BUG: typo returgan

  $words = $text -split ' '

  $romanRegex = '^(?=.+)(?i:M{0,4}(CM|CD|D?C{0,3})(XC|XL|L?X{0,3})(IX|IV|V?I{0,3}))$'

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



  if ($reserved -contains $base.ToUpperInvariant()) {
    $base = "_$base" # PROTECAO
  }

  if (-not $base) {
    $base = "file" # PROTECAO: evita nome vazio
  }

  return "$base$ext"
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

# ================= PIPELINE STATE =================

$specialJsonDirs = @('windows', 'steam')

$script:PipelineState = @{
  Files           = @()
  FileMap         = @{}
  XmlMap          = @{}
  JsonTrees       = @{}
  HashCache       = @{}
  DuplicateIndex  = @{}
  PendingXmlSave  = @{}
  PendingJsonSave = @{}
}

function Get-RelativePathSafe {
  param([string]$FullPath)

  try {

    $base = (Get-Location).Path

    $baseUri = [uri](
      ($base.TrimEnd('\', '/')) + '/'
    )

    $targetUri = [uri]$FullPath

    $relative = $baseUri.MakeRelativeUri($targetUri)

    return [uri]::UnescapeDataString(
      $relative.ToString()
    ).Replace('/', [IO.Path]::DirectorySeparatorChar)
  }
  catch {
    try {
      $base = (Get-Location).Path.TrimEnd('\', '/')
      if ($FullPath.StartsWith($base, [StringComparison]::Ordinal)) {
        return $FullPath.Substring($base.Length).TrimStart('\', '/')
      }
    }
    catch {
      # PROTECAO: fallback determinístico
    }

    return $FullPath
  }
}

function Write-AtomicTextFile {
  param(
    [string]$Path,
    [string]$Content,
    [System.Text.Encoding]$Encoding
  )

  $tmp = "$Path.tmp"

  try {
    [System.IO.File]::WriteAllText($tmp, $Content, $Encoding)

    # PROTECAO: valida escrita antes da substituição
    if (-not (Test-Path -LiteralPath $tmp)) {
      throw "TMP não criado"
    }

    $tmpInfo = Get-Item -LiteralPath $tmp -ErrorAction Stop

    # FIX-BUG: valida arquivo temporário estruturalmente
    if ($tmpInfo.Length -eq 0 -and $Content.Length -gt 0) {
      throw "TMP inválido"
    }

    Move-Item `
      -LiteralPath $tmp `
      -Destination $Path `
      -Force `
      -ErrorAction Stop

    if (-not (Test-Path -LiteralPath $Path)) {
      throw "Falha pós-escrita atômica"
    }
  }
  finally {
    if (Test-Path -LiteralPath $tmp) {
      Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
  }
}

function Get-FileHashCached {
  param([string]$Path)

  $key = [IO.Path]::GetFullPath($Path)

  if ($script:PipelineState.HashCache.ContainsKey($key)) {
    return $script:PipelineState.HashCache[$key]
  }

  Write-InlineLog "🧮 HASHING :: $(Get-RelativePathSafe $Path)" Cyan

  $hash = (
    Get-FileHash `
      -LiteralPath $Path `
      -Algorithm SHA256 `
      -ErrorAction Stop
  ).Hash.ToUpperInvariant()

  $script:PipelineState.HashCache[$key] = $hash

  return $hash
}

function ConvertFrom-Sha256 {
  param([string]$ShaPath)

  try {

    if (-not (Test-Path -LiteralPath $ShaPath)) {
      return $null
    }

    $line = Get-Content `
      -LiteralPath $ShaPath `
      -TotalCount 1 `
      -ErrorAction Stop

    if (-not $line) {
      return $null
    }

    $line = $line.Trim()

    # RFC:
    # HASH64 + whitespace + filename
    if (
      $line -notmatch `
        '^(?<hash>[A-Fa-f0-9]{64})\s+(?<file>.+)$'
    ) {
      return $null
    }

    $hash = $Matches['hash'].ToUpperInvariant()

    # preserva case original
    $fileName = $Matches['file'].Trim()

    if (-not $fileName) {
      return $null
    }

    # PROTECAO:
    # traversal / path injection / separadores
    if (
      $fileName.Contains('..') `
        -or `
        $fileName.IndexOfAny(@([char]'/', [char]'\')) -ge 0
    ) {
      return $null
    }

    # PROTECAO:
    # filename inválido
    foreach ($c in [IO.Path]::GetInvalidFileNameChars()) {

      if ($fileName.Contains($c)) {
        return $null
      }
    }

    # PROTECAO:
    # multiline acidental
    if (
      $fileName.Contains("`r") `
        -or `
        $fileName.Contains("`n")
    ) {
      return $null
    }

    return [pscustomobject]@{
      Hash     = $hash
      FileName = $fileName
    }
  }
  catch {

    Write-InlineLog `
      "⚠️ SHA256_PARSE_FAIL :: $(Get-RelativePathSafe $ShaPath)" `
      Yellow `
      -forceNewLine

    return $null
  }
}

function Write-Sha256File {
  param(
    [string]$FilePath,
    [string]$Hash
  )

  $shaPath = "$FilePath.sha256"

  $content = "$Hash  $([IO.Path]::GetFileName($FilePath))"

  Write-AtomicTextFile `
    -Path $shaPath `
    -Content $content `
    -Encoding ([System.Text.Encoding]::ASCII)
}

function Test-IsSpecialJsonPath {
  param([string]$Path)

  foreach ($dir in $specialJsonDirs) {

    $root = Join-Path (Get-Location) $dir

    $normalizedRoot = [IO.Path]::GetFullPath($root).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $normalizedPath = [IO.Path]::GetFullPath($Path)

    # FIX-BUG: evita falso positivo estrutural
    if (
      $normalizedPath.StartsWith(
        $normalizedRoot,
        [StringComparison]::Ordinal
      )
    ) {
      return $true
    }
  }

  return $false
}

function Get-JsonTreePath {
  param([string]$FilePath)

  foreach ($dir in $specialJsonDirs) {

    $root = Join-Path (Get-Location) $dir

    $normalizedRoot = [IO.Path]::GetFullPath($root).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $normalizedPath = [IO.Path]::GetFullPath($FilePath)

    # FIX-BUG: evita colisão parcial de path
    if (
      $normalizedPath.StartsWith(
        $normalizedRoot,
        [StringComparison]::Ordinal
      )
    ) {

      $relative = $normalizedPath.Substring($normalizedRoot.Length).TrimStart('\', '/')

      $parts = $relative -split '[\\/]'

      if ($parts.Count -lt 2) {
        return $null
      }

      return (Join-Path $root ($parts[0] + ".sha256.json"))
    }
  }

  return $null
}

function Get-JsonTreeRoot {
  param(
    [object]$Root,
    [string[]]$Segments,
    [switch]$Create
  )

  $cursor = $Root

  foreach ($segment in $Segments) {

    if (-not $cursor.PSObject.Properties[$segment]) {

      if (-not $Create) {
        return $null
      }

      $cursor | Add-Member `
        -MemberType NoteProperty `
        -Name $segment `
        -Value ([pscustomobject]@{})
    }

    $cursor = $cursor.$segment
  }

  return $cursor
}

function Set-JsonTreeHashEntry {
  param(
    [string]$FilePath,
    [string]$Hash
  )

  $jsonPath = Get-JsonTreePath $FilePath

  if (-not $jsonPath) {
    return
  }

  if (-not $script:PipelineState.JsonTrees.ContainsKey($jsonPath)) {
    return
  }

  $root = $script:PipelineState.JsonTrees[$jsonPath]

  $treeRoot = Split-Path $jsonPath -Parent

  $relative = $FilePath.Substring($treeRoot.Length).TrimStart('\', '/')

  $parts = $relative -split '[\\/]'

  if ($parts.Count -lt 2) {
    return
  }

  $segments = @()

  if ($parts.Count -gt 2) {
    $segments = $parts[1..($parts.Count - 2)]
  }

  $leafName = $parts[-1]

  $target = Get-JsonTreeRoot `
    -Root $root `
    -Segments $segments `
    -Create

  # PROTECAO: VerifyOnly não altera JSON tree RFC 0
  if ($script:VerifyOnlyMode) {
    return
  }

  $target | Add-Member `
    -MemberType NoteProperty `
    -Name $leafName `
    -Value $Hash `
    -Force

  $script:PipelineState.PendingJsonSave[$jsonPath] = $true
}

function Remove-JsonTreeEntry {
  param([string]$FilePath)

  $jsonPath = Get-JsonTreePath $FilePath

  if (-not $jsonPath) {
    return
  }

  if (-not $script:PipelineState.JsonTrees.ContainsKey($jsonPath)) {
    return
  }

  $root = $script:PipelineState.JsonTrees[$jsonPath]

  $treeRoot = Split-Path $jsonPath -Parent

  $relative = $FilePath.Substring($treeRoot.Length).TrimStart('\', '/')

  $parts = $relative -split '[\\/]'

  if ($parts.Count -lt 2) {
    return
  }

  $segments = @()

  if ($parts.Count -gt 2) {
    $segments = $parts[1..($parts.Count - 2)]
  }

  $stack = @()
  $cursor = $root

  foreach ($segment in $segments) {

    $stack += [pscustomobject]@{
      Parent = $cursor
      Name   = $segment
    }

    if (-not $cursor.PSObject.Properties[$segment]) {
      return
    }

    $cursor = $cursor.$segment
  }

  $leafName = $parts[-1]

  $target = Get-JsonTreeRoot `
    -Root $root `
    -Segments $segments

  if ($target -and $target.PSObject.Properties[$leafName]) {

    # PROTECAO: VerifyOnly não altera JSON tree RFC 0
    if ($script:VerifyOnlyMode) {
      return
    }

    $target.PSObject.Properties.Remove($leafName)

    for ($i = $stack.Count - 1; $i -ge 0; $i--) {

      $node = $stack[$i]

      $child = $node.Parent.$($node.Name)

      if (
        $child `
          -and `
          $child.PSObject.Properties.Count -eq 0
      ) {

        $node.Parent.PSObject.Properties.Remove($node.Name)
      }
      else {
        break
      }
    }    

    $script:PipelineState.PendingJsonSave[$jsonPath] = $true
  }
}

function Load-JsonTrees {

  foreach ($dir in $specialJsonDirs) {

    $root = Join-Path (Get-Location) $dir

    if (-not (Test-Path -LiteralPath $root)) {
      continue
    }

    # FIX-BUG: cria JSON tree ausente RFC 2
    Get-ChildItem `
      -LiteralPath $root `
      -Directory `
      -ErrorAction SilentlyContinue | ForEach-Object {

      $jsonTreePath = Join-Path $_.FullName "$($_.Name).sha256.json"

      if (-not (Test-Path -LiteralPath $jsonTreePath)) {

        $emptyTree = [pscustomobject]@{}

        $script:PipelineState.JsonTrees[$jsonTreePath] = $emptyTree

        if (-not $script:VerifyOnlyMode) {
          $script:PipelineState.PendingJsonSave[$jsonTreePath] = $true
        }
      }
    }

    Get-ChildItem `
      -LiteralPath $root `
      -Filter *.sha256.json `
      -File `
      -ErrorAction SilentlyContinue | ForEach-Object {

      try {

        $json = Get-Content `
          -LiteralPath $_.FullName `
          -Raw `
          -ErrorAction Stop

        $parsed = $json | ConvertFrom-Json -ErrorAction Stop

        if (-not $parsed) {
          $parsed = [pscustomobject]@{}
        }

        $script:PipelineState.JsonTrees[$_.FullName] = $parsed
      }
      catch {
        throw "JSON inválido: $($_.FullName)"
      }
    }
  }
}

function Save-PendingJsonTrees {

  foreach ($jsonPath in $script:PipelineState.PendingJsonSave.Keys) {

    $json = (
      $script:PipelineState.JsonTrees[$jsonPath] |
      ConvertTo-Json -Depth 100
    )

    Write-AtomicTextFile `
      -Path $jsonPath `
      -Content $json `
      -Encoding ([System.Text.Encoding]::UTF8)

    Write-InlineLog `
      "✔ JSON-SYNC :: $(Get-RelativePathSafe $jsonPath)" `
      DarkGreen `
      -forceNewLine
  }
}

function Load-Gamelists {

  Get-ChildItem `
    -Directory `
    -ErrorAction SilentlyContinue | Where-Object {

    # FIX-BUG: restringe gamelist.xml ao root ROM imediato
    $_.Parent `
      -and `
      $_.Parent.FullName -eq (Get-Location).Path `
      -and `
    (
      Test-Path `
        -LiteralPath (Join-Path $_.FullName "gamelist.xml")
    )

  } | ForEach-Object {

    $xmlPath = Join-Path $_.FullName "gamelist.xml"

    if (-not (Test-Path -LiteralPath $xmlPath)) {
      return
    }

    try {

      [xml]$xml = Get-Content `
        -LiteralPath $xmlPath `
        -Raw `
        -ErrorAction Stop

      $script:PipelineState.XmlMap[$xmlPath] = $xml
    }
    catch {
      throw "Falha XML: $xmlPath"
    }
  }
}

function Save-PendingXml {

  foreach ($xmlPath in $script:PipelineState.PendingXmlSave.Keys) {

    $xml = $script:PipelineState.XmlMap[$xmlPath]

    # FIX-BUG: preserva declaração XML e estrutura RFC 3.7
    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Indent = $true
    $settings.OmitXmlDeclaration = $false
    $settings.Encoding = [System.Text.Encoding]::UTF8

    $sw = New-Object System.IO.StringWriter

    try {

      $xw = [System.Xml.XmlWriter]::Create($sw, $settings)

      $xml.Save($xw)

      $xw.Flush()

      $content = $sw.ToString()
    }
    finally {

      if ($xw) {
        $xw.Dispose()
      }

      $sw.Dispose()
    }

    Write-AtomicTextFile `
      -Path $xmlPath `
      -Content $content `
      -Encoding ([System.Text.Encoding]::UTF8)

    Write-InlineLog `
      "✔ XML-SYNC :: $(Get-RelativePathSafe $xmlPath)" `
      DarkGreen `
      -forceNewLine
  }
}

function Initialize-SharedFileIndex {

  $script:PipelineState.Files = @()
  $script:PipelineState.FileMap = @{}
  $script:PipelineState.DuplicateIndex = @{}
  $script:PipelineState.HashCache = @{}

  Get-ChildItem `
    -Recurse `
    -File `
    -ErrorAction SilentlyContinue | ForEach-Object {

    $extLower = [IO.Path]::GetExtension($_.Name).ToLowerInvariant()

    if (
      $blocked -contains $extLower `
        -or $extLower -eq '.sha256' `
        -or $_.Name -like '*.sha256.json'
    ) {
      return
    }

    $parsed = Extract-Extensions $_.Name

    if (-not $parsed) {
      return
    }

    $entry = [pscustomobject]@{
      File      = $_
      Parsed    = $parsed
      Relative  = Get-RelativePathSafe $_.FullName
      Hash      = $null
      XmlNode   = $null
      XmlPath   = $null
      Canonical = $null
      Removed   = $false # PROTECAO: estado estrutural deduplicação/rename
    }

    $script:PipelineState.Files += $entry

    # FIX-BUG: preserva case-sensitive estrutural RFC 3.2
    $script:PipelineState.FileMap[
    [IO.Path]::GetFullPath($_.FullName)
    ] = $entry
  }
}

function Resolve-XmlCorrelation {

  foreach ($xmlPath in $script:PipelineState.XmlMap.Keys) {

    $xml = $script:PipelineState.XmlMap[$xmlPath]

    foreach ($game in @($xml.SelectNodes("//game"))) {

      $pathNode = $game.SelectSingleNode("path")

      if (-not $pathNode) {
        continue
      }

      $relative = $pathNode.InnerText.Trim()

      $relative = $relative -replace '^[.][\\/]', ''

      $systemRoot = Split-Path $xmlPath -Parent

      $full = Join-Path $systemRoot $relative

      # FIX-BUG: preserva correlação case-sensitive RFC 3.2
      $key = [IO.Path]::GetFullPath($full)

      if ($script:PipelineState.FileMap.ContainsKey($key)) {

        $entry = $script:PipelineState.FileMap[$key]

        if ($entry.XmlNode) {

          # FIX-BUG: aborta ambiguidade estrutural XML RFC 3.5
          throw "XML duplicado para path correlacionado: $relative"
        }

        $entry.XmlNode = $game
        $entry.XmlPath = $xmlPath
      }
    }
  }
}

function Get-CanonicalName {
  param([object]$Entry)

  $parsed = $Entry.Parsed

  $rawBase = $parsed.Base

  $resolvedBase = $rawBase

  $id = $null

  if ($Entry.XmlNode) {

    $xmlName = $Entry.XmlNode.SelectSingleNode("name")
    $xmlId = $Entry.XmlNode.Attributes["id"]

    if (
      $xmlName `
        -and `
        $xmlName.InnerText
    ) {
      $resolvedBase = $xmlName.InnerText.Trim()
    }

    if (
      $xmlId `
        -and `
        $xmlId.Value
    ) {
      $id = "[" + $xmlId.Value.Trim() + "]"
    }
  }

  if (-not $id) {
    $id = Get-IdSeguro $resolvedBase
  }

  # FIX-BUG: extrai idioma ANTES da sanitização estrutural
  $idioma = Get-IdiomaSeguro $resolvedBase

  if ($idioma) {
    $idioma = "(" + $idioma.Trim('()').ToUpperInvariant() + ")"
  }

  # FIX-BUG: remove TODOS os grupos antes da canonicalização
  $normalizedBase = [regex]::Replace(
    $resolvedBase,
    '\s*\([^)]*\)',
    ''
  )

  $normalizedBase = [regex]::Replace(
    $normalizedBase,
    '\s*\[[^\]]*\]',
    ''
  )

  $normalizedBase = (
    $normalizedBase `
      -replace '\s{2,}', ' '
  ).Trim()

  $nome = Format-NomeCanonico $normalizedBase

  # FIX-BUG: fail-safe estrutural pós-format
  $nome = [regex]::Replace(
    $nome,
    '\s*\([^)]*\)',
    ''
  ).Trim()

  # FIX-BUG: remove TODOS os grupos "[]" residuais RFC 6
  $nome = [regex]::Replace(
    $nome,
    '\s*\[[^\]]*\]',
    ''
  ).Trim()

  # FIX-BUG: normalização estrutural pós-limpeza
  $nome = (
    $nome `
      -replace '\s{2,}', ' '
  ).Trim()

  if (-not $nome) {
    return $null
  }

  $base = $nome

  # PROTECAO: reconstrói exatamente UM idioma
  if ($idioma) {
    $base += " $idioma"
  }

  # PROTECAO: reconstrói exatamente UM ID
  if ($id) {
    $base += " $id"
  }

  # FIX-BUG: convergência estrutural final
  $base = (
    $base `
      -replace '\s{2,}', ' '
  ).Trim()

  # FIX-BUG: fail-safe final contra múltiplos "()"
  $allIdiomas = [regex]::Matches(
    $base,
    '\(([^)]*)\)'
  )

  if ($allIdiomas.Count -gt 1) {

    $tokens = @()

    foreach ($m in $allIdiomas) {

      $token = $m.Groups[1].Value.Trim().ToUpperInvariant()

      if (
        $token `
          -and `
        ($ValidIdiomas -contains $token)
      ) {
        $tokens += $token
      }
    }

    $preferredIdioma = Get-PreferredIdioma $tokens

    $base = [regex]::Replace(
      $base,
      '\s*\([^)]*\)',
      ''
    ).Trim()

    if ($preferredIdioma) {
      $base += " $preferredIdioma"
    }

    if ($id) {
      $base += " $id"
    }

    $base = (
      $base `
        -replace '\s{2,}', ' '
    ).Trim()
  }

  # FIX-BUG: fail-safe final contra múltiplos "[]"
  $allIds = [regex]::Matches(
    $base,
    '\[([^\]]+)\]'
  )

  if ($allIds.Count -gt 1) {

    $resolvedId = Get-IdSeguro $base

    $base = [regex]::Replace(
      $base,
      '\s*\[[^\]]*\]',
      ''
    ).Trim()

    if ($idioma) {
      $base += " $idioma"
    }

    if ($resolvedId) {
      $base += " $resolvedId"
    }

    $base = (
      $base `
        -replace '\s{2,}', ' '
    ).Trim()
  }

  # FIX-BUG: elimina resíduos duplicados estruturais finais
  $base = (
    $base `
      -replace '\s{2,}', ' '
  ).Trim()

  # FIX-BUG: garante exatamente UM idioma RFC 5
  $idiomaMatches = [regex]::Matches(
    $base,
    '\(([^)]*)\)'
  )

  if ($idiomaMatches.Count -gt 1) {

    $tokens = @()

    foreach ($m in $idiomaMatches) {

      $token = $m.Groups[1].Value.Trim().ToUpperInvariant()

      if (
        $token `
          -and `
        ($ValidIdiomas -contains $token)
      ) {
        $tokens += $token
      }
    }

    $preferredIdioma = Get-PreferredIdioma $tokens

    $base = [regex]::Replace(
      $base,
      '\s*\([^)]*\)',
      ''
    ).Trim()

    if ($preferredIdioma) {
      $base += " $preferredIdioma"
    }

    if ($id) {
      $base += " $id"
    }

    $base = (
      $base `
        -replace '\s{2,}', ' '
    ).Trim()
  }

  # FIX-BUG: garante exatamente UM ID RFC 6
  $idMatches = [regex]::Matches(
    $base,
    '\[([^\]]+)\]'
  )

  if ($idMatches.Count -gt 1) {

    $resolvedId = Get-IdSeguro $base

    $base = [regex]::Replace(
      $base,
      '\s*\[[^\]]*\]',
      ''
    ).Trim()

    if ($idioma) {
      $base += " $idioma"
    }

    if ($resolvedId) {
      $base += " $resolvedId"
    }

    $base = (
      $base `
        -replace '\s{2,}', ' '
    ).Trim()
  }

  # FIX-BUG: remove resíduos estruturais órfãos finais
  $base = $base.Trim(' ', '.', '-', '_')

  $newName = "$base.$($parsed.Extensions -join '.')"

  $safeName = Remove-InvalidFileNameChars $newName

  # FIX-BUG: proteção pós-normalização extrema
  if (
    -not $safeName `
      -or `
      $safeName.StartsWith('.')
  ) {
    return $null
  }

  return $safeName
}

function Build-SharedHashIndex {

  $script:PipelineState.DuplicateIndex = @{}

  foreach ($entry in $script:PipelineState.Files) {

    if ($entry.Removed) {
      continue
    }

    # PROTECAO: evita hashing de arquivo inexistente
    if (-not (Test-Path -LiteralPath $entry.File.FullName)) {
      continue
    }

    $hash = Get-FileHashCached $entry.File.FullName

    $entry.Hash = $hash

    if (-not $script:PipelineState.DuplicateIndex.ContainsKey($hash)) {
      $script:PipelineState.DuplicateIndex[$hash] = @()
    }

    $script:PipelineState.DuplicateIndex[$hash] += $entry
  }
}

function Select-CanonicalDuplicate {
  param([object[]]$Entries)

  $ordered = $Entries | Sort-Object `
  @{ Expression   = {

      $relative = $_.Relative

      if (-not $relative) {
        return 999999
      }

      # FIX-BUG: menor profundidade estrutural RFC 11
      return (
        ($relative -split '[\\/]').Count
      )
    } ; Ascending = $true 
  },
  @{ Expression   = {

      # FIX-BUG: nome mais canônico RFC 11
      if ($_.Canonical) {
        return $_.Canonical.Length
      }

      return 999999
    } ; Ascending = $true 
  },
  @{ Expression   = {

      if ($_.Canonical) {
        return $_.Canonical
      }

      return $_.File.Name
    } ; Ascending = $true 
  },
  @{ Expression   = {

      # PROTECAO: ordem ordinal estável RFC 11
      return $_.Relative
    } ; Ascending = $true 
  }

  # FIX-BUG: estabiliza sobrevivente deterministicamente RFC 11
  return (
    $ordered |
    Select-Object -First 1
  )
}
function Update-XmlPath {
  param(
    [object]$Entry,
    [string]$NewName
  )

  if (-not $Entry.XmlNode) {
    return
  }

  $pathNode = $Entry.XmlNode.SelectSingleNode("path")

  if (-not $pathNode) {
    return
  }

  $oldRelative = $pathNode.InnerText

  $currentRelative = $pathNode.InnerText.Trim()

  $currentRelative = $currentRelative -replace '^[.][\\/]', ''

  $currentDir = Split-Path `
    -Path $currentRelative `
    -Parent

  if (
    $currentDir `
      -and `
      $currentDir -ne '.'
  ) {
    $newRelative = "./$currentDir/$NewName"
  }
  else {
    $newRelative = "./$NewName"
  }

  if ($oldRelative -ne $newRelative) {

    # PROTECAO: VerifyOnly não altera estado XML RFC 0
    if ($script:VerifyOnlyMode) {
      return
    }

    $pathNode.InnerText = $newRelative

    $script:PipelineState.PendingXmlSave[
    $Entry.XmlPath
    ] = $true
  }
}

function Remove-XmlNode {
  param([object]$Entry)

  if (-not $Entry.XmlNode) {
    return
  }

  $parent = $Entry.XmlNode.ParentNode

  if ($parent) {

    # PROTECAO: VerifyOnly não altera XML RFC 0
    if ($script:VerifyOnlyMode) {
      return
    }

    [void]$parent.RemoveChild($Entry.XmlNode)

    $script:PipelineState.PendingXmlSave[
    $Entry.XmlPath
    ] = $true
  }
}

function Invoke-TranslateBatch {
  param([string[]]$texts)

  if (-not $texts -or $texts.Count -eq 0) { return @() }

  if (-not $script:TranslationEnabled) {
    return $texts
  }

  $results = @()
  $batchSize = 5
  $delimiter = "|||SEP|||"

  for ($i = 0; $i -lt $texts.Count; $i += $batchSize) {

    $batch = $texts[$i..([math]::Min($i + $batchSize - 1, $texts.Count - 1))]

    $joined = ($batch -join " $delimiter ")

    $translatedBatch = $null

    for ($retry = 0; $retry -lt 3; $retry++) {
      try {

        # PROTECAO: fail-fast offline RFC rede
        if (-not [System.Net.NetworkInformation.NetworkInterface]::GetIsNetworkAvailable()) {
          throw "Rede indisponível"
        }

        $uri = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=pt&dt=t&q=$([uri]::EscapeDataString($joined))"

        $res = Invoke-RestMethod `
          -Uri $uri `
          -Method Get `
          -TimeoutSec 3

        $translatedRaw = ($res[0] | ForEach-Object { $_[0] }) -join ''
        $translatedBatch = $translatedRaw -split [regex]::Escape($delimiter)

        Start-Sleep -Milliseconds 200
        break
      }
      catch {

        # PROTECAO: backoff determinístico
        Start-Sleep -Seconds (2 * ($retry + 1))

        if ($retry -eq 2) {
          $translatedBatch = $batch
        }
      }
    }

    for ($j = 0; $j -lt $batch.Count; $j++) {

      $original = $batch[$j]

      $translated = if (
        $translatedBatch `
          -and `
          $j -lt $translatedBatch.Count
      ) {
        $translatedBatch[$j].Trim()
      }
      else {
        $original
      }

      if (-not $translated) {
        $translated = $original # PROTECAO: preserva conteúdo original
      }

      $results += $translated
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
  try {
    $width = $Host.UI.RawUI.BufferSize.Width
  }
  catch {
    $width = 120
  }

  $padLength = [Math]::Max(0, $width - $message.Length - 1)
  $padding = ' ' * $padLength

  Write-Host -NoNewline ("`r" + $message + $padding) -ForegroundColor $color
}

function main {
  param(
    [switch]$VerifyOnly,
    [switch]$Fix
  )

  $mutex = New-Object `
    System.Threading.Mutex(
    $false,
    "Global\ROM_Normalizer_Mutex"
  )

  $lockAcquired = $false

  try {

    $lockAcquired = $mutex.WaitOne(0)

    if (-not $lockAcquired) {
      throw "Outra instância já está em execução"
    }

    $script:VerifyOnlyMode = $VerifyOnly

    Write-InlineLog "ℹ️ PIPELINE :: INITIALIZE" Cyan -forceNewLine

    Load-JsonTrees
    Load-Gamelists
    Initialize-SharedFileIndex
    Resolve-XmlCorrelation

    # ==========================================================
    # NORMALIZAÇÃO + RENAME
    # RFC:
    # ENUMERAÇÃO → CORRELAÇÃO → NORMALIZAÇÃO → RENAME
    # ==========================================================

    foreach ($entry in $script:PipelineState.Files) {

      if ($entry.Removed) {
        continue
      }

      try {

        $entry.Canonical = Get-CanonicalName $entry

        if (-not $entry.Canonical) {
          continue
        }

        # FIX-BUG: convergência final RFC 4/5/6
        $entry.Canonical = (
          $entry.Canonical `
            -replace '\s{2,}', ' '
        ).Trim()

        $currentName = $entry.File.Name
        $newName = $entry.Canonical

        if (
          $currentName.Equals(
            $newName,
            [StringComparison]::Ordinal
          )
        ) {
          continue
        }

        $targetPath = Join-Path `
          $entry.File.DirectoryName `
          $newName

        if (
          (Test-Path -LiteralPath $targetPath) `
            -and `
          (-not $targetPath.Equals(
              $entry.File.FullName,
              [StringComparison]::OrdinalIgnoreCase
            ))
        ) {

          $srcHash = Get-FileHashCached $entry.File.FullName
          $dstHash = Get-FileHashCached $targetPath

          # PROTECAO:
          # colisão real por conteúdo diferente RFC 4 + RFC 11
          if (
            -not $srcHash.Equals(
              $dstHash,
              [StringComparison]::OrdinalIgnoreCase
            )
          ) {

            $parsedCollision = Extract-Extensions $newName

            if (-not $parsedCollision) {
              throw "Falha estrutural collision parsing"
            }

            $shortHash = $srcHash.Substring(0, 8)

            $collisionBase =
            "$($parsedCollision.Base) {$shortHash}"

            $resolvedName =
            "$collisionBase.$($parsedCollision.Extensions -join '.')"

            $resolvedDir = $entry.File.DirectoryName

            $resolvedPath = Join-Path `
              $resolvedDir `
              $resolvedName

            # FAIL-SAFE:
            # evita colisão impossível extremamente rara
            if (
              (Test-Path -LiteralPath $resolvedPath) `
                -and `
              (-not $resolvedPath.Equals(
                  $entry.File.FullName,
                  [StringComparison]::OrdinalIgnoreCase
                ))
            ) {

              throw (
                "COLLISION_IMPOSSIBLE :: " +
                "SOURCE=[$($entry.File.Name)] " +
                "TARGET=[$resolvedName]"
              )
            }

            Write-InlineLog `
            (
              "⚠️ COLLISION_RESOLVED :: " +
              "SOURCE=[$($entry.File.Name)] " +
              "TARGET=[$resolvedName]"
            ) `
              Yellow `
              -forceNewLine

            $newName = $resolvedName
            $targetPath = $resolvedPath
          }
          else {

            Write-InlineLog `
            (
              "⚠️ DUPLICATE_ALREADY_EXISTS :: " +
              "SOURCE=[$($entry.File.Name)] " +
              "TARGET=[$newName]"
            ) `
              Yellow `
              -forceNewLine

            continue
          }
        }

        Write-InlineLog `
          "✏️ CHANGE-NAME :: $currentName -> $newName" `
          DarkGreen `
          -forceNewLine

        $oldXmlPathValue = $null

        if ($Entry.XmlNode) {

          $pathNode = $Entry.XmlNode.SelectSingleNode("path")

          if ($pathNode) {
            $oldXmlPathValue = $pathNode.InnerText
          }
        }

        Update-XmlPath `
          -Entry $entry `
          -NewName $newName

        if (-not $VerifyOnly) {

          $oldFullPath = $entry.File.FullName

          $newFullPath = Join-Path `
            $entry.File.DirectoryName `
            $newName

          # FIX BUG:
          # Windows não diferencia case no filesystem.
          # Renames apenas de capitalização exigem rename intermediário.

          $requiresCaseFix = (
            $currentName -ieq $newName `
              -and `
              $currentName -cne $newName
          )

          if ($requiresCaseFix) {

            $__TAG_FORCE = ".__rename_tmp__"

            $tempName = "$newName$__TAG_FORCE"

            $tempPath = Join-Path `
              $entry.File.DirectoryName `
              $tempName

            if (Test-Path -LiteralPath $tempPath) {
              throw "Colisão temporária de rename"
            }

            Rename-Item `
              -LiteralPath $oldFullPath `
              -NewName $tempName `
              -ErrorAction Stop

            Rename-Item `
              -LiteralPath $tempPath `
              -NewName $newName `
              -ErrorAction Stop
          }
          else {

            Rename-Item `
              -LiteralPath $oldFullPath `
              -NewName $newName `
              -ErrorAction Stop
          }

          if (-not (Test-Path -LiteralPath $newFullPath)) {

            # FIX-BUG: rollback XML pós-falha
            if (
              $Entry.XmlNode `
                -and `
                $oldXmlPathValue
            ) {

              $rollbackPathNode = $Entry.XmlNode.SelectSingleNode("path")

              if ($rollbackPathNode) {
                $rollbackPathNode.InnerText = $oldXmlPathValue
              }
            }

            throw "Falha pós-rename"
          }

          $oldMapKey = [IO.Path]::GetFullPath(
            $oldFullPath
          )

          $newMapKey = [IO.Path]::GetFullPath(
            $newFullPath
          )

          $entry.File = Get-Item `
            -LiteralPath $newFullPath `
            -ErrorAction Stop

          $entry.Relative = Get-RelativePathSafe `
            $newFullPath

          # FIX-BUG: sincroniza índice estrutural pós-rename
          $script:PipelineState.FileMap.Remove(
            $oldMapKey
          )

          $script:PipelineState.FileMap[
          $newMapKey
          ] = $entry
        }
      }
      catch {

        Write-InlineLog `
          "❌ NORMALIZE_FAIL :: $($_.Exception.Message)" `
          Red `
          -forceNewLine
      }
    }

    # ==========================================================
    # HASH
    # RFC:
    # HASH APENAS APÓS CONVERGÊNCIA NOMINAL
    # ==========================================================

    Build-SharedHashIndex

    # ==========================================================
    # DEDUPLICAÇÃO GLOBAL
    # RFC:
    # DEDUP SOBRE SNAPSHOT FINAL CONVERGIDO
    # ==========================================================

    foreach ($hash in $script:PipelineState.DuplicateIndex.Keys) {

      $entries = @(
        $script:PipelineState.DuplicateIndex[$hash] |
        Where-Object { -not $_.Removed }
      )

      if ($entries.Count -le 1) {
        continue
      }

      foreach ($e in $entries) {
        if (-not $e.Canonical) {
          $e.Canonical = Get-CanonicalName $e
        }
      }

      $keep = Select-CanonicalDuplicate $entries

      $remove = @(
        $entries | Where-Object {
          $_.File.FullName -ne $keep.File.FullName
        }
      )

      foreach ($entry in $remove) {

        Write-InlineLog `
          "🗑️ DEDUP :: $(Get-RelativePathSafe $entry.File.FullName)" `
          Yellow `
          -forceNewLine

        Remove-XmlNode $entry
        Remove-JsonTreeEntry $entry.File.FullName

        if (-not $VerifyOnly) {

          Remove-Item `
            -LiteralPath $entry.File.FullName `
            -Force `
            -ErrorAction Stop          
          
          $entry.Removed = $true

          $sha = "$($entry.File.FullName).sha256"

          if (Test-Path -LiteralPath $sha) {

            Remove-Item `
              -LiteralPath $sha `
              -Force `
              -ErrorAction SilentlyContinue
          }
        }
      }
    }

    # ==========================================================
    # SHA256
    # ==========================================================

    foreach ($entry in $script:PipelineState.Files) {

      if ($entry.Removed) {
        continue
      }

      try {

        $shaPath = "$($entry.File.FullName).sha256"

        $stored = ConvertFrom-Sha256 $shaPath

        if (
          $stored `
            -and `
            $stored.Hash -eq $entry.Hash `
            -and `
            $stored.FileName -eq $entry.File.Name
        ) {
          continue
        }

        Write-InlineLog `
          "🛠️ SHA-SYNC :: $(Get-RelativePathSafe $entry.File.FullName)" `
          Cyan `
          -forceNewLine

        if (-not $VerifyOnly) {

          Write-Sha256File `
            -FilePath $entry.File.FullName `
            -Hash $entry.Hash
        }

        if (Test-IsSpecialJsonPath $entry.File.FullName) {

          Set-JsonTreeHashEntry `
            -FilePath $entry.File.FullName `
            -Hash $entry.Hash
        }
      }
      catch {
        Write-InlineLog `
          "❌ SHA_FAIL :: $($_.Exception.Message)" `
          Red `
          -forceNewLine
      }
    }

    # ==========================================================
    # HASH ÓRFÃO
    # ==========================================================

    Get-ChildItem `
      -Recurse `
      -File `
      -Filter *.sha256 `
      -ErrorAction SilentlyContinue | ForEach-Object {

      $shaPath = $_.FullName

      $target = $shaPath -replace '\.sha256$', ''

      # PROTECAO: target ainda existe
      if (Test-Path -LiteralPath $target) {
        return
      }

      $parsedSha = ConvertFrom-Sha256 $shaPath

      $correlated = $false

      if ($parsedSha) {

        $expectedPath = Join-Path `
          $_.DirectoryName `
          $parsedSha.FileName

        # FIX-BUG: correlaciona rename legítimo RFC 10
        if (Test-Path -LiteralPath $expectedPath) {
          $correlated = $true
        }

        # FIX-BUG: correlaciona por SHA256 RFC 10
        if (-not $correlated) {

          foreach ($entry in $script:PipelineState.Files) {

            if ($entry.Removed) {
              continue
            }

            if (-not $entry.Hash) {
              continue
            }

            if (
              $entry.Hash.Equals(
                $parsedSha.Hash,
                [StringComparison]::OrdinalIgnoreCase
              )
            ) {
              $correlated = $true
              break
            }
          }
        }
      }

      if ($correlated) {

        Write-InlineLog `
          "ℹ️ HASH_CORRELATED :: $(Get-RelativePathSafe $shaPath)" `
          DarkCyan `
          -forceNewLine

        return
      }

      Write-InlineLog `
        "⚠️ ORPHAN_HASH :: $(Get-RelativePathSafe $shaPath)" `
        Yellow `
        -forceNewLine

      if ($Fix -and -not $VerifyOnly) {

        Remove-Item `
          -LiteralPath $shaPath `
          -Force `
          -ErrorAction Stop
      }
    }

    # ==========================================================
    # SAVE FINAL
    # ==========================================================

    if (-not $VerifyOnly) {

      Save-PendingXml
      Save-PendingJsonTrees
    }

    Write-InlineLog `
      "✔ PIPELINE :: COMPLETE" `
      Green `
      -forceNewLine
  }
  finally {

    if ($lockAcquired) {
      $mutex.ReleaseMutex()
    }

    $mutex.Dispose()
  }
}

# AUTO-INVOCAÇÃO SEGURA
if ($MyInvocation.InvocationName -ne '.') {

  try {

    main @PSBoundParameters

    exit 0
  }
  catch {

    Write-InlineLog `
      "❌ FATAL :: $($_.Exception.Message)" `
      Red `
      -forceNewLine

    exit 1
  }
}