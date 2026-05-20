#!/usr/bin/env pwsh
# encoding: utf-8

<#
.SYNOPSIS
  Normalizador determinístico de ROMs com sincronização bidirecional
  de gamelist.xml, deduplicação SHA256 e suporte a JSON Tree virtual.

.DESCRIPTION
  Este script percorre recursivamente o diretório atual executando,
  de forma integrada, determinística, idempotente e fail-safe:

    - Normalização canônica de ROMs
    - Sincronização bidirecional com gamelist.xml
    - Deduplicação segura baseada em SHA256
    - Gerenciamento de integridade .sha256 e JSON Tree
    - Tradução e coerência de metadados
    - Validação estrutural via JSON Tree virtual

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

  NÃO participam do pipeline principal de:
    - normalização ROM
    - deduplicação ROM
    - correlação estrutural ROM

  exceto:
    - gamelist.xml
    - arquivos .sha256
    - .sha256.json
    - brs.json
    - operações explícitas de integridade/SHA256
    - conteúdo contido em $specialJsonDirs    

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
    - JSON Tree MUST operar como banco estrutural virtual de .sha256
      (Pasta de arquivos virtual)
    - JSON Tree NÃO possui hash próprio e MUST NOT ser hasheado
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
    - entrada JSON Tree
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
          * alterar JSON Tree
          * alterar hashes
        - deduplicação MUST continuar sendo:
            - calculada
            - validada
            - correlacionada
            - reportada

          * e MUST NOT alterar arquivos.
      - toda operação normativa de:
          * consolidação
          * sincronização
          * remoção
          * correção
          * rename

        MUST ser interpretada apenas como
        validação/auditoria lógica sem mutação física.      
        - avisos e logs exibidos normlamente    

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
    4. JSON Tree derivada de integridade
    5. Metadados derivados

  ============================================================
  2. JSON Tree VIRTUAL ($specialJsonDirs)
  ============================================================

  JSON Tree MUST operar como representação hierárquica virtual
  equivalente a um conjunto expandido de arquivos .sha256
  convencionais.

  Cada entrada hash do JSON Tree MUST ser tratada como
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
    - JSON Tree NÃO possui hash próprio
    - JSON Tree MUST NOT ser hasheado
    - JSON Tree MUST NOT participar da deduplicação
    - Apenas arquivos reais participam da deduplicação

  Cada entrada string do JSON representa semanticamente um
  arquivo .sha256 convencional.

  A única diferença entre:
    - entrada JSON Tree
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
    - JSON Tree virtual derivada

  Toda operação de:
    - rename
    - deduplicação
    - sincronização XML
    - integridade
    - remoção
    - validação estrutural

  MUST refletir simultaneamente:
    - filesystem
    - JSON Tree correspondente

    preservando consistência lógica bidirecional.

  JSON Tree NÃO altera a hierarquia lógica do root ROM.
    Ela representa apenas mecanismo virtual de consolidação
    estrutural de hashes.

  JSON Tree MUST ser tratada como estrutura derivada
  sincronizada bidirecionalmente com o estado de integridade
  do filesystem.
    O filesystem real permanece a autoridade física primária.

  ============================================================
  3. GAMELIST.XML
  ============================================================

  ROM é qualquer arquivo cujo conjunto de extensões encadeadas
  resulte em extensão final válida de conteúdo executável/emulável.

  - Gamelist.xml deve ter a sintaxe preservada;
  - deve ter edição e estrutura ediutada com segurança;
  - não pode ser corrompido;
  - cada edição de tag deve ser fail-safe com fallback para valor anterior;
  - manter compatibilidade com o batocera e não quebrar a estrutura
  - não editar tags e valores fora da tag <game>
  - manter e preservar identaçÃo usando espaços: 2
  - remoção de dados, quando necessária, segura (garantia de que atende deduplicação e preservação)

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
        na hierarquia lógica ROM correlacionada ao gamelist.xml      
        * exções enquadradas, como:
          - pastas contidos em $specialJsonDirs, como `roms/<sistema>/<nomejogo>/`,
            que contem apenas mais um único nivem de diretório;
          - JSON Tree reflete F.S., com objetivo principal de unificar múltiplos sha256
            contexto lógico não é o mesmo que ROM/<sistema>
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

    O root relativo MUST permanecer consistente
    por tipo estrutural:

      - XML:
          relativo a roms/<sistema>/

      - JSON Tree, logs e hashes:
          relativo a roms/

    Todo path armazenado em:
      - JSON Tree
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
          - JSON Tree → filesystem

  3.3 Influência normativa do XML
    - Quando gamelist.xml existir:
        * ele MUST influenciar o nome final da ROM
        * IDs MUST ser extraídos EXCLUSIVAMENTE dele
        * XML torna-se autoridade normativa auxiliar

    Em caso de divergência entre:
      - basename do filename
      - metadado XML correlacionado

    o XML MUST possuir precedência nominal auxiliar
    apenas sobre componentes semanticamente equivalentes
    ao nome do jogo.

    Idioma, extensões, integridade estrutural e
    correlação física MUST continuar derivados
    primariamente do filesystem real.        

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

    - MUST NOT existir múltiplas entradas <game>
      com o mesmo valor de subtag <name>

      - em caso de duplicidade:
          * MUST detectar
          * MUST logar WARN/ERROR
          * MUST consolidar deterministicamente (aquela com <path> válido)
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

    Comparações textuais SHOULD utilizar
    normalização Unicode canônica estável
    (NFC) antes de operações semânticas,
    sem alterar o conteúdo persistido final.  

    - um único ciclo estrutural de descoberta
    - reutilizado por:
        * normalização
        * XML
        * hashing
        * JSON Tree
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

  5.0 Identificar ROMs tradudizadas atraves de./brs.json
      (formato e regras no item 18.)

      Se o nome da ROM (para um <sistema> específico) constar como traduzido:

      - MUST preferir BR
      - MUST adicionar `br` à tag <lang>, caso já não exista, conforme regra específica
      - MUST adicionar ` (BR)` ao filename, incluindo arquivo .sha256
        caso já não esteja presente

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
    - PREFERÊNCIA 2: basename original do filename contendo [id]

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
  7. NORMALIZAÇÃO DO BASENAME e DESC
  ============================================================
  
  [BASENAME]
    
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

  [DESC]

      A tag <desc> do xml NÃO pode estar todo em uppercase
      ou lowercase, devendo seguir um padrão adequado de
      texto:

        - Primeirta letra da uma frase: maiúsla;
        - Nomes próprios cm a primeira em maiúsculas;
        - Demais letras em minúsculas.

      A excução e ajuste deve ocorrer idenpendetemente de haver
      necessidade de traudção, mas apenas após aquela etapa.

      Deve ser segura, sem estragar/quebrar o texto.      

  ============================================================
  8. EXTENSÕES
  ============================================================

  Parsing:
    - MUST ocorrer da direita para esquerda

  Cadeias:
    - ".sfc.7z", ".iso.zip", etc...,  são válidas
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
    - criado se ausente

  ============================================================
  10. HASH, ÓRFÃOS E CORRELAÇÃO
  ============================================================

  Antes da remoção de hash órfão, o sistema MUST tentar:

    1. localizar filename original (mesmo diretório)
    2. localizar arquivo com hash correspondente
    3. correlacionar rename legítimo
    4. correlacionar XML/JSON Tree

  Somente após falha total:
    - hash MAY ser removido

  ============================================================
  11. DEDUPLICAÇÃO
  ============================================================

  A análise de deduplicação MUST ocorrer:
    - em TODOS os modos operacionais;
    - inclusive `-VerifyOnly`.

  A aplicação física da deduplicação:
    - MUST NOT ocorrer em `-VerifyOnly`.

  A deduplicação MUST operar de forma:
    - determinística;
    - idempotente;
    - fail-safe;
    - estruturalmente correlacionada.

  ============================================================
  11.1 CRITÉRIO DEFINITIVO
  ============================================================

  O critério definitivo de equivalência MUST ser:

    - SHA256 do conteúdo binário bruto.

  Regras:
    - nome;
    - path;
    - timestamps;
    - atributos do filesystem;
    - metadata externa;

    MUST NOT possuir precedência sobre o hash
    na definição de equivalência física.

  Apenas arquivos reais participam da deduplicação.

  JSON Tree:
    - MUST refletir deduplicação;
    - MUST NOT participar como entidade física.

  ============================================================
  11.2 ESCOPO
  ============================================================

  A deduplicação aplica-se a:

    - ROMs;
    - arquivos correlacionados ao pipeline;
    - assets participantes de integridade;
    - mídias correlacionadas via XML;
    - conteúdo localizado em $specialJsonDirs.

  MUST refletir consistentemente em:
    - filesystem;
    - .sha256;
    - JSON Tree;
    - gamelist.xml.

  ============================================================
  11.3 GARANTIAS ESTRUTURAIS
  ============================================================

  MUST:
    - preservar ao menos um arquivo válido;
    - preservar consistência estrutural;
    - preservar integridade XML;
    - preservar integridade JSON Tree;
    - preservar rastreabilidade.

  MUST NOT:
    - remover todos os equivalentes;
    - criar backups artificiais;
    - criar "__dup";
    - criar nomes ambíguos;
    - sobrescrever arquivos arbitrariamente;
    - produzir referências órfãs deliberadamente.

  ============================================================
  11.4 SELEÇÃO CANÔNICA
  ============================================================

  Quando múltiplos arquivos forem equivalentes
  por SHA256:

    - apenas um MUST sobreviver fisicamente.

  A seleção MUST ser determinística.

  Ordem normativa de prioridade:

    1. nome estruturalmente mais canônico;
    2. maior coerência ROM ↔ XML;
    3. menor distância estrutural;
    4. menor necessidade de mutação corretiva;
    5. ordem ordinal estável de enumeração.

  SHOULD priorizar:
    - paths válidos;
    - estrutura compatível com Batocera;
    - correlação XML íntegra;
    - nomenclatura convergente.

  ============================================================
  11.5 DETECÇÃO HEURÍSTICA DE CÓPIAS NOMINAIS
  ============================================================

  O pipeline MUST detectar arquivos cuja nomenclatura
  indique claramente cópia redundante/manual.

  Aplica-se a:
    - ROMs convencionais;
    - ROMs baseadas em diretório;
    - conteúdo em $specialJsonDirs;
    - assets correlacionados;
    - entradas XML correspondentes.

  Indicadores heurísticos MAY incluir:

    - "copy"
    - "copia"
    - "copie"
    - "(2)"
    - "(3)"
    - "(4)"
    - "_copy"
    - "- Copy"
    - "copy of"

  Regras:
    - detecção SHOULD ser case-insensitive;
    - detecção MUST considerar contexto semântico;
    - detecção MUST evitar falso positivo parcial.

  Exemplos que MUST NOT gerar remoção automática:
    - "Copycat"
    - "Copyright"
    - "Copia"
    - nomes semanticamente legítimos.

  Remoção heurística automática MUST ocorrer apenas se:

    - existir correlação estrutural válida;
    - existir equivalente principal coerente;
    - o arquivo não for representante único;
    - não existir ambiguidade estrutural crítica.

  Em caso de ambiguidade:
    - MUST emitir WARN;
    - MUST NOT remover automaticamente.

  ============================================================
  11.6 DEDUPLICAÇÃO XML
  ============================================================

  MUST detectar:
    - múltiplas entradas `<game>`
      apontando para o mesmo `<path>`;
    - múltiplas entradas semanticamente equivalentes;
    - referências XML inválidas;
    - referências XML órfãs.

  Quando múltiplas entradas XML referenciarem
  arquivos equivalentes:

    - referências redundantes MUST ser removidas;
    - apenas a referência canônica MUST sobreviver;
    - XML MUST permanecer consistente;
    - paths MUST permanecer válidos.

  MUST preservar:
    - encoding XML;
    - estrutura XML;
    - compatibilidade Batocera;
    - indentação consistente.

  MUST NOT:
    - utilizar replace textual inseguro;
    - alterar conteúdo fora de `<game>`;
    - corromper estrutura semântica XML.

  ============================================================
  11.7 DEDUPLICAÇÃO DE MÍDIA
  ============================================================

  Assets de mídia correlacionados via subtags de `<game>`
  MUST participar da deduplicação conforme item 19.

  MUST:
    - remover redundâncias;
    - consolidar referências XML;
    - remover mídias órfãs;
    - preservar asset canônico final.

  Múltiplos `<game>` MAY compartilhar
  o mesmo asset final legítimo.

  ============================================================
  11.8 HASHES E JSON TREE
  ============================================================

  A deduplicação MUST sincronizar:
    - arquivos `.sha256`;
    - JSON Tree;
    - referências derivadas.

  MUST detectar:
    - hashes órfãos;
    - hashes inconsistentes;
    - entradas JSON órfãs;
    - entradas JSON inconsistentes.

  Em `-Fix`:
    - hashes órfãos MUST ser removidos;
    - entradas JSON órfãs MUST ser removidas;
    - inconsistências MUST ser corrigidas.

  Fora de `-Fix`:
    - MUST apenas reportar.

  ============================================================
  11.9 COMPORTAMENTO POR MODO OPERACIONAL
  ============================================================

  Em `-VerifyOnly`:

    - MUST:
        * calcular;
        * validar;
        * correlacionar;
        * auditar;
        * reportar.

    - MUST NOT:
        * remover;
        * renomear;
        * sincronizar;
        * alterar XML;
        * alterar JSON Tree;
        * alterar hashes;
        * alterar mídia;
        * alterar ROMs.

  Em `-Fix`:
    - correções MUST ser aplicadas fisicamente.

  ============================================================
  11.10 RESILIÊNCIA E SEGURANÇA
  ============================================================

  O pipeline MUST:
    - validar estado pós-operação;
    - validar integridade estrutural final;
    - impedir perda total;
    - operar com rollback lógico determinístico;
    - preservar rastreabilidade completa.

  MUST NOT:
    - depender apenas de ExitCode;
    - assumir rename bem-sucedido sem validação;
    - produzir estado parcialmente inconsistente.

  ============================================================
  11.11 IDEMPOTÊNCIA
  ============================================================

  Após convergência:

    - execuções subsequentes MUST NOT produzir
      alterações adicionais;

    - a seleção canônica MUST permanecer estável;

    - XML, JSON Tree, hashes e filesystem
      MUST permanecer sincronizados.    

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
    - busca a partir de ./brs.json (path relativo a partir do script, vid 18.)
      * apenas se o arquivo existir

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

- operações de rename MUST possuir
  validação pós-operação e rollback lógico
  determinístico em caso de falha parcial.  

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
  - JSON Tree consistente com filesystem
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

  18. ARQUIVO brs.json

  Se existir, identifica ROMs traduzidas, mesmo que não haja tag no xml
  ou equivalente (BR) no filename.

  Deve-se, usá-lo para buscar pelo nome do JOGO, limidado pelo diretório
  que identifica o sistema.  

  Não editado nem alterado - serve apenas como fonte de consulta

  formato:

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
      * cusca insensitive-case

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
  5. Correlação filesystem/XML/JSON Tree/hash.
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
    ROMs, gamelist.xml, .sha256 e JSON Tree.

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
  - JSON Tree consistente.
  - .sha256 consistente.
  - Sem falhas silenciosas.
  - Estrutura XML preservada.
  - Script idempotente e fail-safe.

19. DEDUPLICAÇÃO DE ARQUIVOS DE MÍDIA E
    ELIMINAÇÃO DE MÍDIA ÓRFÃ
    (NÃO REFERENCIADA POR SUBTAGS DE <game>)

  Escopo:
    - aplica-se exclusivamente a arquivos de mídia
      referenciados por subtags válidas de `<game>`
      em `gamelist.xml`;
    - aplica-se tipicamente ao subtree:
        `<sistema>/media/`
      sem depender rigidamente deste path;
    - apenas mídias efetivamente correlacionadas
      ao XML participam do pipeline.

  Disponibilidade:
    - funcional apenas quando `-Fix` fornecido;
    - sem `-Fix`:
        * MUST operar apenas em modo análise;
        * MUST emitir `WARN`;
        * MUST NOT:
            - renomear;
            - remover;
            - sincronizar;
            - alterar XML.

  Objetivos:
    - deduplicar assets de mídia;
    - eliminar arquivos órfãos;
    - estabilizar nomenclatura;
    - preservar compatibilidade Batocera;
    - reduzir redundância estrutural.

  ============================================================
  19.1 SUBTAGS DE MÍDIA SUPORTADAS
  ============================================================

  O pipeline MUST detectar referências de mídia
  exclusivamente dentro de subtags válidas de `<game>`.

  Inclui:
    - <image>
    - <thumbnail>
    - <marquee>
    - <video>
    - <manual>
    - <fanart>
    - <titleshot>
    - <miximage>
    - equivalentes semanticamente compatíveis

  Regras:
    - subtags desconhecidas MUST ser ignoradas;
    - tags fora de `<game>` MUST NOT ser alteradas;
    - paths MUST preservar case original;
    - correlação MUST ser determinística.

  ============================================================
  19.2 DEFINIÇÃO DE MÍDIA ÓRFÃ
  ============================================================

  Arquivo órfão é qualquer arquivo de mídia que:

    - exista fisicamente no filesystem;
    - esteja localizado em diretório monitorado;
    - não possua referência válida
      em nenhuma subtag suportada de `<game>`.

  Em `-Fix`:
    - arquivos órfãos MUST ser removidos.

  Fora de `-Fix`:
    - MUST apenas reportar.

  Antes da remoção:
    - MUST validar:
        * path;
        * acessibilidade;
        * unicidade;
        * inexistência de referência XML indireta;
        * inexistência de correlação pós-normalização.

  A enumeração de mídia órfã MUST limitar-se
  a diretórios previamente correlacionados
  por referências válidas do XML.        

  ============================================================
  19.3 NORMALIZAÇÃO CANÔNICA DE MÍDIA
  ============================================================

  Cada arquivo de mídia válido MUST ser renomeado para:

    `{nome-canonico}-{last12sha256}.{originalext}`

  Onde:

    `{nome-canonico}`
      = nome derivado prioritariamente da subtag:
          `<title>`
        do `<game>` proprietário.

      Fallbacks determinísticos MAY utilizar:
        - <name>
        - basename correlacionado da ROM

      apenas se `<title>` inexistente.

    `{nome-canonico}` MUST:
      - ser normalizado;
      - ser filesystem-safe;
      - remover caracteres inválidos;
      - remover trailing spaces/dots;
      - colapsar whitespace;
      - preservar legibilidade;
      - preservar semântica relevante;
      - possuir tamanho seguro para path final.

    `{last12sha256}`
      = últimos 12 caracteres HEXADECIMAIS UPPERCASE
        do SHA256 binário bruto do conteúdo do arquivo.

    `{originalext}`
      = extensão original preservada.

  Regras:
    - hash MUST ser calculado sobre conteúdo bruto;
    - hashing MUST ser determinístico;
    - metadados/timestamps MUST NOT influenciar;
    - extensão MUST NOT ser alterada;
    - casing da extensão SHOULD ser preservado.

  ============================================================
  19.4 DEDUPLICAÇÃO
  ============================================================

  Critério definitivo:
    - SHA256 do conteúdo binário.

  Quando o filename destino já existir:

    - se o conteúdo for equivalente:
        * MUST considerar duplicação legítima;
        * MUST remover o arquivo redundante;
        * MUST preservar apenas uma mídia física;
        * MUST consolidar referências XML.

    - se o conteúdo divergir:
        * MUST abortar operação específica;
        * MUST emitir ERROR;
        * MUST NOT sobrescrever arquivos.

  Garantias:
    - ao menos um asset MUST sobreviver;
    - MUST NOT criar "__dup";
    - MUST NOT gerar nomes ambíguos;
    - MUST NOT destruir referências válidas.

  ============================================================
  19.5 SINCRONIZAÇÃO XML
  ============================================================

  Toda alteração de mídia MUST refletir no XML.

  O pipeline MUST:

    - atualizar TODAS as referências correlacionadas;
    - atualizar referências cruzadas entre múltiplos `<game>`;
    - consolidar referências duplicadas;
    - preservar estrutura XML;
    - preservar encoding XML;
    - preservar indentação compatível com Batocera.

  Atualização MUST ser:
    - estrutural;
    - baseada em parsing XML;
    - determinística;
    - fail-safe.

  MUST NOT utilizar:
    - replace textual cego;
    - replace global inseguro;
    - mutação fora de `<game>`.

  Em falha:
    - MUST preservar estado anterior válido;
    - MUST abortar operação parcial inconsistente.

  ============================================================
  19.6 PRESERVAÇÃO ESTRUTURAL
  ============================================================

  O pipeline MUST preservar a estrutura original
  de diretórios tanto quanto possível.

  Regras:
    - arquivos MUST permanecer no mesmo diretório;
    - MUST NOT mover arquivos entre subpastas;
    - MUST NOT achatar hierarquia;
    - MUST NOT renomear diretórios;
    - MUST NOT criar estrutura paralela artificial.

  Apenas o basename do arquivo MAY ser alterado.

  ============================================================
  19.7 CORRELAÇÃO ESTRUTURAL
  ============================================================

  A mídia MUST permanecer correlacionada ao `<game>`
  proprietário após normalização e deduplicação.

  MUST preservar:
    - integridade relacional;
    - compatibilidade Batocera;
    - consistência ROM ↔ mídia ↔ XML.

  Quando múltiplos `<game>` compartilharem
  o mesmo asset legítimo:

    - apenas um arquivo físico SHOULD sobreviver;
    - múltiplas referências XML MAY apontar
      para o mesmo asset final.

  ============================================================
  19.8 RESILIÊNCIA E SEGURANÇA
  ============================================================

  MUST:
    - validar existência física pós-operação;
    - validar XML pós-sincronização;
    - utilizar escrita atômica quando aplicável;
    - impedir perda total por falha parcial;
    - preservar rastreabilidade completa.

  MUST NOT:
    - sobrescrever mídia arbitrariamente;
    - modificar conteúdo binário;
    - alterar extensões;
    - remover assets sem validação;
    - operar fora do escopo correlacionado.

  ============================================================
  19.9 IDEMPOTÊNCIA
  ============================================================

  O processo MUST ser idempotente.

  Após convergência:
    - execuções subsequentes MUST NOT produzir
      alterações adicionais;
    - nomes finais MUST permanecer estáveis;
    - referências XML MUST permanecer estáveis.

  ============================================================
  19.10 LOG E AUDITORIA
  ============================================================

  MUST registrar:
    - mídia renomeada;
    - mídia deduplicada;
    - mídia órfã removida;
    - referências XML atualizadas;
    - colisões detectadas;
    - falhas de correlação;
    - operações abortadas.

  Logs SHOULD:
    - utilizar paths relativos;
    - preservar rastreabilidade;
    - ser determinísticos;
    - ser legíveis por máquina.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
# FIX-BUG: expõe switches aceitos por main via PSBoundParameters
param(
  [switch]$VerifyOnly,
  [switch]$Fix
)

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

$MediaSubtagSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
@(
  'image', 'thumbnail', 'marquee', 'video', 'manual', 'fanart',
  'titleshot', 'titlescreen', 'miximage', 'screenshot', 'cover',
  'backcover', 'boxart', 'boxback', 'wheel', 'logo', 'bezel',
  'cartridge', 'physicalmedia', 'map', 'music'
) | ForEach-Object { [void]$MediaSubtagSet.Add($_) }

$MediaExtensionSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
@(
  '.png', '.jpg', '.jpeg', '.bmp', '.gif', '.webp', '.svg',
  '.mp4', '.m4v', '.avi', '.mkv', '.mov', '.webm',
  '.pdf', '.txt', '.cbz', '.cbr',
  '.mp3', '.ogg', '.wav', '.flac'
) | ForEach-Object { [void]$MediaExtensionSet.Add($_) }

$reserved = @(
  'CON', 'PRN', 'AUX', 'NUL',
  'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
  'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9'
)

$IdiomaPriority = @('BR', 'PT', 'USA')

# PROTECAO: bootstrap antecipado do estado global
if (-not $script:PipelineState) {
  $script:PipelineState = @{}
}

$script:PipelineState.BrsIndexes = @{}
$script:PipelineState.PendingBrsSave = @{}

# ================= CORE HELPERS =================

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

function Load-BrsIndexes {

  $script:PipelineState.BrsIndexes = @{}

  Get-ChildItem `
    -Recurse `
    -File `
    -Filter brs.json `
    -ErrorAction SilentlyContinue | ForEach-Object {

    $brsFilePath = $_.FullName

    try {

      $json = Get-Content `
        -LiteralPath $brsFilePath `
        -Raw `
        -Encoding UTF8 |
      ConvertFrom-Json -ErrorAction Stop

      $script:PipelineState.BrsIndexes[
      (Get-FullPathSafe -PathValue $brsFilePath)
      ] = $json
    }
    catch {

      Write-InlineLog `
        "⚠️ BRS_LOAD_FAIL :: $(Format-ExceptionCause $_ 'LOAD_BRS_FILE' $brsFilePath)" `
        Yellow `
        -forceNewLine
    }
  }
}

function Save-PendingBrsIndexes {

  foreach ($path in $script:PipelineState.PendingBrsSave.Keys) {

    if (-not $script:PipelineState.BrsIndexes.ContainsKey($path)) {
      continue
    }

    $json = $script:PipelineState.BrsIndexes[$path]

    $serialized = $json | ConvertTo-Json -Depth 100

    Set-Content `
      -LiteralPath $path `
      -Value $serialized `
      -Encoding UTF8
  }
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

      # FIX-BUG:
      # remove grupos técnicos RFC 7 antes da validação de idioma
      if (
        $normalized -match `
          '^(REV(?:ISION)?|BETA|PROTO|PROTOTYPE|DEMO|SAMPLE|BUILD)\b'
      ) {
        return ''
      }      

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
    '(?i)\s*[\[\(]?\b(beta|proto|prototype|sample|demo|build|rev(?:ision)?)\b[^)\]]*[\)\]]?',
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

function Get-PathExtensionSafe {
  param([string]$PathValue)

  if (-not $PathValue) {
    return ''
  }

  try {
    return [IO.Path]::GetExtension($PathValue)
  }
  catch {

    # FIX-BUG: impede fatal por path textual inválido
    $text = $PathValue.Trim()

    if (-not $text) {
      return ''
    }

    $leaf = @(
      $text -split '[\\/]'
    )[-1]

    if (-not $leaf) {
      return ''
    }

    $dotIndex = $leaf.LastIndexOf('.')

    if (
      $dotIndex -lt 0 `
        -or `
        $dotIndex -eq ($leaf.Length - 1)
    ) {
      return ''
    }

    $extension = $leaf.Substring($dotIndex)

    if ($extension -match '^[.][A-Za-z0-9]{1,16}$') {
      return $extension
    }

    return ''
  }
}

function Get-FullPathSafe {
  param([string]$PathValue)

  if (-not $PathValue) {
    return $PathValue
  }

  try {
    return [IO.Path]::GetFullPath($PathValue)
  }
  catch {

    # FIX-BUG: impede fatal por path longo ou textual inválido
    $text = $PathValue.Trim()

    if (-not $text) {
      return $PathValue
    }

    try {
      if ([IO.Path]::IsPathRooted($text)) {
        return $text
      }

      return Join-Path (Get-Location).Path $text
    }
    catch {
      return $text
    }
  }
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
  $ext = Get-PathExtensionSafe -PathValue $name



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

$script:BrsIndex = @{}

function Initialize-BrsIndex {

  $script:BrsIndex = @{}

  $brsPath = Join-Path $PSScriptRoot 'brs.json'

  if (-not (Test-Path -LiteralPath $brsPath)) {
    return
  }

  try {

    $raw = Get-Content `
      -LiteralPath $brsPath `
      -Raw `
      -ErrorAction Stop

    if (-not $raw.Trim()) {
      return
    }

    $parsed = $raw | ConvertFrom-Json -ErrorAction Stop

    function __WalkBrsNode {
      param(
        [object]$Node,
        [string[]]$PathStack
      )

      # FIX-BUG: ConvertFrom-Json retorna PSCustomObject
      if (
        ($Node -isnot [psobject]) `
          -and `
        ($Node -isnot [System.Management.Automation.PSCustomObject])
      ) {
        return
      }

      foreach ($prop in $Node.PSObject.Properties) {

        if ($prop.Name -eq 'arquivos') {

          if ($prop.Value -isnot [System.Collections.IEnumerable]) {
            continue
          }

          $systemName = $null

          if ($PathStack.Count -gt 0) {
            $systemName = $PathStack[-1].ToLowerInvariant()
          }

          if (-not $systemName) {
            continue
          }

          if (-not $script:BrsIndex.ContainsKey($systemName)) {
            $script:BrsIndex[$systemName] = @{}
          }

          foreach ($item in $prop.Value) {

            if (-not ($item -is [string])) {
              continue
            }

            $normalized = $item

            $normalized = $normalized -replace '[\[\(\.].*$', ''
            $normalized = $normalized.Trim().ToLowerInvariant()

            if (-not $normalized) {
              continue
            }

            $script:BrsIndex[$systemName][$normalized] = $true
          }

          continue
        }

        if ($prop.Value -is [psobject]) {

          __WalkBrsNode `
            -Node $prop.Value `
            -PathStack ($PathStack + $prop.Name)
        }
      }
    }

    __WalkBrsNode `
      -Node $parsed `
      -PathStack @()
  }
  catch {
    throw (Format-ExceptionCause $_ 'LOAD_BRS_INDEX' $brsPath)
  }
}

function Test-BrsTranslatedRom {
  param(
    [object]$Entry,
    [string]$BaseName
  )

  if (-not $Entry) {
    return $false
  }

  if (-not $BaseName) {
    return $false
  }

  $relative = $Entry.Relative

  if (-not $relative) {
    return $false
  }

  $segments = $relative -split '[\\/]'

  if ($segments.Count -lt 2) {
    return $false
  }

  $systemName = $segments[0].ToLowerInvariant()

  if (-not $script:BrsIndex.ContainsKey($systemName)) {
    return $false
  }

  $lookup = $BaseName

  $lookup = $lookup -replace '[\[\(\.].*$', ''
  $lookup = $lookup.Trim().ToLowerInvariant()

  if (-not $lookup) {
    return $false
  }

  return $script:BrsIndex[$systemName].ContainsKey($lookup)
}

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

function Format-ExceptionCause {
  param(
    [object]$ErrorRecord,
    [string]$Operation,
    [string]$Path
  )

  $ex = $null

  if ($ErrorRecord -is [System.Management.Automation.ErrorRecord]) {
    $ex = $ErrorRecord.Exception
  }
  elseif ($ErrorRecord -is [System.Exception]) {
    $ex = $ErrorRecord
  }

  $parts = @("OP=$Operation")

  if ($Path) {
    $parts += "PATH=[$Path]"
  }

  if (-not $ex) {
    $parts += "CAUSE=Exceção ausente"
    return ($parts -join ' ')
  }

  $parts += "TYPE=$($ex.GetType().FullName)"

  if ($ex -is [System.Xml.XmlException]) {
    $parts += "LINE=$($ex.LineNumber)"
    $parts += "POSITION=$($ex.LinePosition)"
  }

  if ($ex.InnerException) {
    $innerMessage = (
      $ex.InnerException.Message -replace '\s+', ' '
    ).Trim()

    $parts += "INNER=[$innerMessage]"
  }

  $message = (
    $ex.Message -replace '\s+', ' '
  ).Trim()

  if ($message) {
    $parts += "CAUSE=[$message]"
  }

  return ($parts -join ' ')
}

function Read-GamelistXml {
  param([string]$XmlPath)

  $settings = New-Object System.Xml.XmlReaderSettings
  $settings.DtdProcessing = [System.Xml.DtdProcessing]::Ignore
  $settings.CheckCharacters = $true
  $settings.IgnoreWhitespace = $false

  $reader = $null
  $stringReader = $null

  try {

    $xml = New-Object System.Xml.XmlDocument
    $xml.PreserveWhitespace = $true

    # FIX-BUG: remove BOM textual duplicado antes do parse XML
    $content = [System.IO.File]::ReadAllText(
      $XmlPath,
      [System.Text.UTF8Encoding]::new($false, $true)
    ).TrimStart([char]0xFEFF)

    $stringReader = New-Object System.IO.StringReader($content)

    $reader = [System.Xml.XmlReader]::Create(
      $stringReader,
      $settings
    )

    $xml.Load($reader)

    if (
      -not $xml.DocumentElement `
        -or `
        $xml.DocumentElement.Name -ne 'gameList'
    ) {
      throw "Raiz XML inválida: esperado gameList"
    }

    return $xml
  }
  finally {

    if ($reader) {
      $reader.Dispose()
    }

    if ($stringReader) {
      $stringReader.Dispose()
    }
  }
}

function Write-AtomicTextFile {
  param(
    [string]$Path,
    [string]$Content,
    [System.Text.Encoding]$Encoding
  )

  $dir = Split-Path -Path $Path -Parent
  $leaf = Split-Path -Path $Path -Leaf
  $tmp = Join-Path $dir ".$leaf.$([guid]::NewGuid().ToString('N')).tmp"
  $backup = Join-Path $dir ".$leaf.$([guid]::NewGuid().ToString('N')).bak"
  $pending = $null
  $saved = $false

  try {
    [System.IO.File]::WriteAllText($tmp, $Content, $Encoding)

    # PROTECAO: valida escrita antes da substituição
    if (-not (Test-Path -LiteralPath $tmp)) {
      throw "OP=WRITE_ATOMIC PATH=[$Path] CAUSE=TMP não criado"
    }

    $tmpInfo = Get-Item -LiteralPath $tmp -ErrorAction Stop

    # FIX-BUG: valida arquivo temporário estruturalmente
    if ($tmpInfo.Length -eq 0 -and $Content.Length -gt 0) {
      throw "OP=WRITE_ATOMIC PATH=[$Path] CAUSE=TMP inválido"
    }

    $lastError = $null

    for ($attempt = 1; $attempt -le 8; $attempt++) {

      try {

        # FIX-BUG: substitui arquivo existente sem caminho de criação duplicada
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
          [System.IO.File]::Replace(
            $tmp,
            $Path,
            $backup,
            $true
          )
        }
        else {
          [System.IO.File]::Move($tmp, $Path)
        }

        $saved = $true
        break
      }
      catch {

        $lastError = $_

        if ($attempt -lt 8) {

          Write-InlineLog `
            "⚠️ WRITE_ATOMIC_RETRY :: OP=WRITE_ATOMIC PATH=[$Path] ATTEMPT=$attempt CAUSE=[$($_.Exception.Message)]" `
            Yellow `
            -forceNewLine

          Start-Sleep -Milliseconds (250 * $attempt)
          continue
        }
      }
    }

    if (-not $saved) {

      $pending = Join-Path $dir (
        ".$leaf.pending-$((Get-Date).ToString('yyyyMMddHHmmssfff')).tmp"
      )

      # PROTECAO: preserva conteúdo novo para reaplicação manual/automática
      [System.IO.File]::Copy(
        $tmp,
        $pending,
        $true
      )

      if ($lastError) {
        throw (
          "OP=WRITE_ATOMIC PATH=[$Path] PENDING=[$pending] " +
          "CAUSE=[$($lastError.Exception.Message)]"
        )
      }

      throw "OP=WRITE_ATOMIC PATH=[$Path] PENDING=[$pending] CAUSE=substituição não concluída"
    }

    if (-not (Test-Path -LiteralPath $Path)) {
      throw "OP=WRITE_ATOMIC PATH=[$Path] CAUSE=destino ausente após substituição"
    }

    if (Test-Path -LiteralPath $backup -PathType Leaf) {
      Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue
    }
  }
  finally {
    if (($saved -or $pending) -and (Test-Path -LiteralPath $tmp)) {
      Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
  }
}

function Get-FileHashCached {
  param([string]$Path)

  $key = Get-FullPathSafe -PathValue $Path

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

    $normalizedRoot = (Get-FullPathSafe -PathValue $root).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $normalizedPath = Get-FullPathSafe -PathValue $Path

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

    $normalizedRoot = (Get-FullPathSafe -PathValue $root).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $normalizedPath = Get-FullPathSafe -PathValue $FilePath

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

  # PROTECAO: VerifyOnly não altera JSON Tree RFC 0
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

    # PROTECAO: VerifyOnly não altera JSON Tree RFC 0
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

function Invoke-JsonTreeIntegrityAudit {
  param(
    [switch]$Fix,
    [switch]$VerifyOnly
  )

  $canMutate = (
    $Fix `
      -and `
      -not $VerifyOnly
  )

  foreach ($jsonPath in @($script:PipelineState.JsonTrees.Keys | Sort-Object)) {

    $root = $script:PipelineState.JsonTrees[$jsonPath]

    if (-not $root) {
      continue
    }

    $treeRoot = Split-Path $jsonPath -Parent

    $jsonFile = [IO.Path]::GetFileNameWithoutExtension($jsonPath)
    $virtualRootName = [IO.Path]::GetFileNameWithoutExtension($jsonFile)

    if (-not $virtualRootName) {
      continue
    }

    function __WalkJsonTreeIntegrity {
      param(
        [object]$Node,
        [string[]]$Segments
      )

      foreach ($prop in @($Node.PSObject.Properties)) {

        $value = $prop.Value

        if ($value -is [string]) {

          $relativeParts = @($virtualRootName) + $Segments + @($prop.Name)

          $filePath = Get-FullPathSafe -PathValue (
            (Join-Path $treeRoot ($relativeParts -join [IO.Path]::DirectorySeparatorChar))
          )

          if ($value -notmatch '^[A-Fa-f0-9]{64}$') {

            Write-InlineLog `
              "⚠️ JSON_HASH_INVALID :: $(Get-RelativePathSafe $filePath)" `
              Yellow `
              -forceNewLine

            if ($canMutate) {
              # FIX-BUG: remove entrada JSON Tree sem hash válido RFC 11.8
              Remove-JsonTreeEntry $filePath
            }

            continue
          }

          if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {

            Write-InlineLog `
              "⚠️ JSON_ORPHAN_ENTRY :: $(Get-RelativePathSafe $filePath)" `
              Yellow `
              -forceNewLine

            if ($canMutate) {
              # FIX-BUG: remove entrada JSON Tree órfã RFC 11.8
              Remove-JsonTreeEntry $filePath
            }

            continue
          }

          $actualHash = Get-FileHashCached $filePath

          if (
            -not $actualHash.Equals(
              $value,
              [StringComparison]::OrdinalIgnoreCase
            )
          ) {

            Write-InlineLog `
              "⚠️ JSON_HASH_MISMATCH :: $(Get-RelativePathSafe $filePath)" `
              Yellow `
              -forceNewLine

            if ($canMutate) {
              # FIX-BUG: corrige hash divergente em JSON Tree RFC 11.8
              Set-JsonTreeHashEntry `
                -FilePath $filePath `
                -Hash $actualHash
            }
          }

          continue
        }

        if ($value -and $value.PSObject) {

          __WalkJsonTreeIntegrity `
            -Node $value `
            -Segments (@($Segments) + @($prop.Name))
        }
        else {

          Write-InlineLog `
            "⚠️ JSON_NODE_INVALID :: $jsonPath :: $($prop.Name)" `
            Yellow `
            -forceNewLine
        }
      }
    }

    __WalkJsonTreeIntegrity `
      -Node $root `
      -Segments @()
  }
}

function Load-JsonTrees {

  foreach ($dir in $specialJsonDirs) {

    $root = Join-Path (Get-Location) $dir

    if (-not (Test-Path -LiteralPath $root)) {
      continue
    }

    # FIX-BUG: cria JSON Tree ausente RFC 2
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

      $jsonTreePath = $_.FullName

      try {

        $json = Get-Content `
          -LiteralPath $jsonTreePath `
          -Raw `
          -ErrorAction Stop

        $parsed = $json | ConvertFrom-Json -ErrorAction Stop

        if (-not $parsed) {
          $parsed = [pscustomobject]@{}
        }

        $script:PipelineState.JsonTrees[$jsonTreePath] = $parsed
      }
      catch {
        throw (Format-ExceptionCause $_ 'LOAD_JSON_TREE' $jsonTreePath)
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

  try {

    $romRoots = @(
      Get-ChildItem `
        -Directory `
        -ErrorAction Stop
    )
  }
  catch {

    Write-InlineLog `
      "❌ XML_DISCOVERY_FAIL :: $(Format-ExceptionCause $_ 'ENUMERATE_GAMELIST_ROOT' (Get-Location).Path)" `
      Red `
      -forceNewLine

    return
  }

  $romRoots | Where-Object {

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

      $xml = Read-GamelistXml `
        -XmlPath $xmlPath

      $script:PipelineState.XmlMap[$xmlPath] = $xml
    }
    catch {

      Write-InlineLog `
        "❌ XML_LOAD_FAIL :: $(Format-ExceptionCause $_ 'PARSE_GAMELIST_XML' $xmlPath)" `
        Red `
        -forceNewLine

      continue
    }
  }
}

function Save-PendingXml {

  foreach ($xmlPath in @($script:PipelineState.PendingXmlSave.Keys)) {

    try {

      if (-not $script:PipelineState.XmlMap.ContainsKey($xmlPath)) {
        throw "XML pendente ausente no mapa carregado"
      }

      $xml = $script:PipelineState.XmlMap[$xmlPath]

      # FIX-BUG: preserva declaração XML e estrutura RFC 3.7
      $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
      $settings = New-Object System.Xml.XmlWriterSettings
      $settings.Indent = $true
      $settings.OmitXmlDeclaration = $false
      $settings.Encoding = $utf8NoBom

      # FIX-BUG: StringWriter padrão gera UTF-16 incompatível com RFC XML
      $memoryStream = New-Object System.IO.MemoryStream
      $xw = $null

      try {

        $xw = [System.Xml.XmlWriter]::Create(
          $memoryStream,
          $settings
        )

        $xml.Save($xw)

        $xw.Flush()

        $content = [System.Text.Encoding]::UTF8.GetString(
          $memoryStream.ToArray()
        ).TrimStart([char]0xFEFF)
      }
      finally {

        if ($xw) {
          $xw.Dispose()
        }

        $memoryStream.Dispose()
      }

      # PROTECAO: valida XML serializado antes da escrita
      $validationXml = New-Object System.Xml.XmlDocument
      $validationXml.PreserveWhitespace = $true
      $validationXml.LoadXml($content)

      Write-AtomicTextFile `
        -Path $xmlPath `
        -Content $content `
        -Encoding $utf8NoBom

      Write-InlineLog `
        "✔ XML-SYNC :: $(Get-RelativePathSafe $xmlPath)" `
        DarkGreen `
        -forceNewLine

      [void]$script:PipelineState.PendingXmlSave.Remove($xmlPath)
    }
    catch {

      Write-InlineLog `
        "❌ XML_SAVE_FAIL :: $(Format-ExceptionCause $_ 'SAVE_GAMELIST_XML' $xmlPath)" `
        Red `
        -forceNewLine
    }
  }
}

function Save-PendingXmlRealtime {

  if (
    $script:FixMode `
      -and `
      -not $script:VerifyOnlyMode
  ) {

    # FIX-BUG: persiste mutações XML confirmadas entre etapas
    Save-PendingXml
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

    $extLower = (Get-PathExtensionSafe -PathValue $_.Name).ToLowerInvariant()

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
    (Get-FullPathSafe -PathValue $_.FullName)
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
      $key = Get-FullPathSafe -PathValue $full

      if ($script:PipelineState.FileMap.ContainsKey($key)) {

        $entry = $script:PipelineState.FileMap[$key]

        if ($entry.XmlNode) {

          Write-InlineLog `
            "⚠️ XML_DUPLICATE_PATH :: $relative" `
            Yellow `
            -forceNewLine

          # FIX-BUG: remove referência XML redundante somente em modo corretivo
          if (
            $script:FixMode `
              -and `
              -not $script:VerifyOnlyMode
          ) {

            Remove-XmlNode ([pscustomobject]@{
                XmlNode = $game
                XmlPath = $xmlPath
              })
          }

          continue
        }

        $entry.XmlNode = $game
        $entry.XmlPath = $xmlPath
      }
      else {

        Write-InlineLog `
          "⚠️ XML_ORPHAN_PATH :: $relative" `
          Yellow `
          -forceNewLine

        # FIX-BUG: remove referência XML órfã somente em modo corretivo
        if (
          $script:FixMode `
            -and `
            -not $script:VerifyOnlyMode
        ) {

          Remove-XmlNode ([pscustomobject]@{
              XmlNode = $game
              XmlPath = $xmlPath
            })
        }
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
  # FIX-BUG: extrai idioma ANTES da sanitização estrutural
  $idioma = Get-IdiomaSeguro $resolvedBase

  # FIX-BUG: integração RFC 18 brs.json
  if (
    (-not $idioma) `
      -and `
    (Test-BrsTranslatedRom `
        -Entry $Entry `
        -BaseName $resolvedBase)
  ) {
    $idioma = '(BR)'
  }

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
      # FIX-BUG: Get-PreferredIdioma já retorna "(XX)"
      $preferredIdioma = $preferredIdioma.Trim()

      if (
        $preferredIdioma.StartsWith('(') `
          -and `
          $preferredIdioma.EndsWith(')')
      ) {
        $base += " $preferredIdioma"
      }
      else {
        $base += " ($preferredIdioma)"
      }
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
      # FIX-BUG: Get-PreferredIdioma já retorna "(XX)"
      $preferredIdioma = $preferredIdioma.Trim()

      if (
        $preferredIdioma.StartsWith('(') `
          -and `
          $preferredIdioma.EndsWith(')')
      ) {
        $base += " $preferredIdioma"
      }
      else {
        $base += " ($preferredIdioma)"
      }
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

  # FIX-BUG: fail-safe estrutural de extensão RFC 4
  if (
    -not $parsed.Extensions `
      -or `
      $parsed.Extensions.Count -eq 0
  ) {
    return $null
  }

  foreach ($ext in $parsed.Extensions) {

    if (
      -not $ext `
        -or `
        -not $ext.Trim()
    ) {
      return $null
    }
  }  

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

function Get-DedupNominalCopyScore {
  param([object]$Entry)

  if (
    -not $Entry `
      -or `
      -not $Entry.Parsed `
      -or `
      -not $Entry.Parsed.Base
  ) {
    return 0
  }

  $base = (
    $Entry.Parsed.Base `
      -replace '\s{2,}', ' '
  ).Trim()

  if (-not $base) {
    return 0
  }

  $normalized = $base.ToLowerInvariant()

  if ($normalized -eq 'copia') {
    return 0
  }

  # PROTECAO: heurística só reordena candidatos com SHA256 idêntico
  $copyPattern = (
    '(^|[\s._-])copy(\s+of)?($|[\s._-])' +
    '|(^|[\s._-])(copia|copie)($|[\s._-])' +
    '|[\s._-]\(\d+\)(?=$|[\s._-])'
  )

  if ($normalized -match $copyPattern) {
    return 1
  }

  return 0
}

function Get-DedupCanonicalNameScore {
  param([object]$Entry)

  if (
    -not $Entry `
      -or `
      -not $Entry.File
  ) {
    return 999999
  }

  if (-not $Entry.Canonical) {
    return 999999
  }

  if (
    $Entry.File.Name.Equals(
      $Entry.Canonical,
      [StringComparison]::Ordinal
    )
  ) {
    return 0
  }

  if (
    $Entry.File.Name.Equals(
      $Entry.Canonical,
      [StringComparison]::OrdinalIgnoreCase
    )
  ) {
    return 1
  }

  return (
    100 +
    [Math]::Abs($Entry.File.Name.Length - $Entry.Canonical.Length)
  )
}

function Get-DedupXmlCoherenceScore {
  param([object]$Entry)

  if (
    -not $Entry `
      -or `
      -not $Entry.XmlNode `
      -or `
      -not $Entry.XmlPath
  ) {
    return 2
  }

  $pathNode = $Entry.XmlNode.SelectSingleNode('path')

  if (
    -not $pathNode `
      -or `
      -not $pathNode.InnerText
  ) {
    return 1
  }

  $relative = $pathNode.InnerText.Trim()
  $relative = $relative -replace '^[.][\\/]', ''

  $systemRoot = Split-Path $Entry.XmlPath -Parent
  $xmlFull = Get-FullPathSafe -PathValue (
    (Join-Path $systemRoot $relative)
  )

  $entryFull = Get-FullPathSafe -PathValue $Entry.File.FullName

  if (
    $xmlFull.Equals(
      $entryFull,
      [StringComparison]::OrdinalIgnoreCase
    )
  ) {
    return 0
  }

  return 1
}

function Get-DedupStructuralDistance {
  param([object]$Entry)

  if (
    -not $Entry `
      -or `
      -not $Entry.Relative
  ) {
    return 999999
  }

  return (
    ($Entry.Relative -split '[\\/]').Count
  )
}

function Get-DedupMutationScore {
  param([object]$Entry)

  if (
    -not $Entry `
      -or `
      -not $Entry.File
  ) {
    return 999999
  }

  $score = 0

  if (
    $Entry.Canonical `
      -and `
      -not $Entry.File.Name.Equals(
        $Entry.Canonical,
        [StringComparison]::Ordinal
      )
  ) {
    $score++
  }

  $shaPath = "$($Entry.File.FullName).sha256"

  if (Test-Path -LiteralPath $shaPath) {

    $stored = ConvertFrom-Sha256 $shaPath

    if (
      -not $stored `
        -or `
        -not $Entry.Hash `
        -or `
        -not $stored.Hash.Equals(
          $Entry.Hash,
          [StringComparison]::OrdinalIgnoreCase
        ) `
        -or `
        $stored.FileName -cne $Entry.File.Name
    ) {
      $score++
    }
  }
  else {
    $score++
  }

  if (Test-IsSpecialJsonPath $Entry.File.FullName) {

    $jsonPath = Get-JsonTreePath $Entry.File.FullName

    if (
      -not $jsonPath `
        -or `
        -not $script:PipelineState.JsonTrees.ContainsKey($jsonPath)
    ) {
      $score++
    }
  }

  return $score
}

function Select-CanonicalDuplicate {
  param([object[]]$Entries)

  $ordered = $Entries | Sort-Object `
  @{ Expression   = {

      # FIX-BUG: penaliza cópias nominais apenas em grupo SHA256 idêntico
      return Get-DedupNominalCopyScore $_
    } ; Ascending = $true
  },
  @{ Expression   = {

      # FIX-BUG: nome mais canônico RFC 11
      return Get-DedupCanonicalNameScore $_
    } ; Ascending = $true
  },
  @{ Expression   = {

      # FIX-BUG: preserva coerência ROM XML RFC 11.4/11.6
      return Get-DedupXmlCoherenceScore $_
    } ; Ascending = $true
  },
  @{ Expression   = {

      # FIX-BUG: menor distância estrutural RFC 11.4
      return Get-DedupStructuralDistance $_
    } ; Ascending = $true
  },
  @{ Expression   = {

      # FIX-BUG: menor mutação corretiva RFC 11.4
      return Get-DedupMutationScore $_
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

function Invoke-GlobalDeduplication {
  param([switch]$VerifyOnly)

  foreach ($hash in @($script:PipelineState.DuplicateIndex.Keys | Sort-Object)) {

    $entries = @(
      $script:PipelineState.DuplicateIndex[$hash] |
      Where-Object { -not $_.Removed } |
      Sort-Object Relative
    )

    if ($entries.Count -le 1) {
      continue
    }

    foreach ($e in $entries) {
      if (-not $e.Canonical) {
        $e.Canonical = Get-CanonicalName $e
      }
    }

    foreach ($e in $entries) {

      if ((Get-DedupNominalCopyScore $e) -gt 0) {

        Write-InlineLog `
          "⚠️ DEDUP_COPY_HEURISTIC :: $(Get-RelativePathSafe $e.File.FullName)" `
          Yellow `
          -forceNewLine
      }
    }

    $keep = Select-CanonicalDuplicate $entries

    if (
      -not $keep `
        -or `
        -not (Test-Path -LiteralPath $keep.File.FullName -PathType Leaf)
    ) {

      Write-InlineLog `
        "❌ DEDUP_ABORT_NO_SURVIVOR :: $hash" `
        Red `
        -forceNewLine

      continue
    }

    $keepHash = Get-FileHashCached $keep.File.FullName

    if (
      -not $keepHash.Equals(
        $hash,
        [StringComparison]::OrdinalIgnoreCase
      )
    ) {

      Write-InlineLog `
        "❌ DEDUP_ABORT_HASH_DRIFT :: $(Get-RelativePathSafe $keep.File.FullName)" `
        Red `
        -forceNewLine

      continue
    }

    $remove = @(
      $entries | Where-Object {
        -not $_.File.FullName.Equals(
          $keep.File.FullName,
          [StringComparison]::OrdinalIgnoreCase
        )
      }
    )

    if (
      $remove.Count -eq 0 `
        -or `
        $remove.Count -ge $entries.Count
    ) {

      Write-InlineLog `
        "❌ DEDUP_ABORT_LOSS_GUARD :: $hash" `
        Red `
        -forceNewLine

      continue
    }

    foreach ($entry in $remove) {

      if (
        -not (Test-Path `
            -LiteralPath $entry.File.FullName `
            -PathType Leaf)
      ) {
        continue
      }

      $entryHash = Get-FileHashCached $entry.File.FullName

      if (
        -not $entryHash.Equals(
          $keepHash,
          [StringComparison]::OrdinalIgnoreCase
        )
      ) {

        Write-InlineLog `
          "❌ DEDUP_SKIP_HASH_DRIFT :: $(Get-RelativePathSafe $entry.File.FullName)" `
          Red `
          -forceNewLine

        continue
      }

      $eventName = if ($VerifyOnly) {
        'DEDUP_PENDING'
      }
      else {
        'DEDUP'
      }

      Write-InlineLog `
        "🗑️ $eventName :: $(Get-RelativePathSafe $entry.File.FullName)" `
        Yellow `
        -forceNewLine

      if ($VerifyOnly) {
        continue
      }

      $sha = "$($entry.File.FullName).sha256"

      try {

        if (Test-Path -LiteralPath $sha) {

          # FIX-BUG: remove hash pareado antes do arquivo deduplicado
          Remove-Item `
            -LiteralPath $sha `
            -Force `
            -ErrorAction Stop
        }

        Remove-Item `
          -LiteralPath $entry.File.FullName `
          -Force `
          -ErrorAction Stop

        if (Test-Path -LiteralPath $entry.File.FullName -PathType Leaf) {
          throw "OP=DEDUP_REMOVE PATH=[$($entry.File.FullName)] CAUSE=arquivo redundante permaneceu após remoção"
        }

        $entry.Removed = $true

        $mapKey = Get-FullPathSafe -PathValue $entry.File.FullName

        [void]$script:PipelineState.FileMap.Remove($mapKey)

        Remove-XmlNode $entry
        Remove-JsonTreeEntry $entry.File.FullName
      }
      catch {

        Write-InlineLog `
          "❌ DEDUP_FAIL :: $(Format-ExceptionCause $_ 'DEDUP_REMOVE' $entry.File.FullName)" `
          Red `
          -forceNewLine
      }
    }
  }
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

    Save-PendingXmlRealtime
  }
}

function Test-IsPathUnderRoot {
  param(
    [string]$RootPath,
    [string]$TargetPath
  )

  if (
    -not $RootPath `
      -or `
      -not $TargetPath
  ) {
    return $false
  }

  $rootFull = (Get-FullPathSafe -PathValue $RootPath).TrimEnd('\', '/')
  $targetFull = Get-FullPathSafe -PathValue $TargetPath

  $rootPrefix = $rootFull + [IO.Path]::DirectorySeparatorChar

  return $targetFull.StartsWith(
    $rootPrefix,
    [StringComparison]::OrdinalIgnoreCase
  )
}

function Resolve-GamelistMediaPath {
  param(
    [string]$XmlPath,
    [string]$PathValue
  )

  if (
    -not $XmlPath `
      -or `
      -not $PathValue `
      -or `
      -not $PathValue.Trim()
  ) {
    return $null
  }

  $systemRoot = Split-Path $XmlPath -Parent
  $raw = $PathValue.Trim()

  $pathPart = $raw -replace '^[.][\\/]', ''

  if ([IO.Path]::IsPathRooted($pathPart)) {
    $full = Get-FullPathSafe -PathValue $pathPart
  }
  else {
    $full = Get-FullPathSafe -PathValue (
      (Join-Path $systemRoot $pathPart)
    )
  }

  if (
    -not (Test-IsPathUnderRoot `
        -RootPath $systemRoot `
        -TargetPath $full)
  ) {
    return $null
  }

  $rootFull = (Get-FullPathSafe -PathValue $systemRoot).TrimEnd('\', '/')

  $relative = $full.Substring(
    $rootFull.Length
  ).TrimStart('\', '/')

  if (-not $relative) {
    return $null
  }

  return [pscustomobject]@{
    FullName = $full
    Relative = $relative
  }
}

function ConvertTo-GamelistMediaPath {
  param(
    [string]$XmlPath,
    [string]$FilePath
  )

  if (
    -not $XmlPath `
      -or `
      -not $FilePath
  ) {
    return $null
  }

  $systemRoot = Split-Path $XmlPath -Parent

  if (
    -not (Test-IsPathUnderRoot `
        -RootPath $systemRoot `
        -TargetPath $FilePath)
  ) {
    return $null
  }

  $rootFull = (Get-FullPathSafe -PathValue $systemRoot).TrimEnd('\', '/')
  $full = Get-FullPathSafe -PathValue $FilePath

  $relative = $full.Substring(
    $rootFull.Length
  ).TrimStart('\', '/')

  if (-not $relative) {
    return $null
  }

  return "./$($relative.Replace('\', '/'))"
}

function Format-MediaCanonicalBase {
  param([string]$Text)

  if (
    -not $Text `
      -or `
      -not $Text.Trim()
  ) {
    return $null
  }

  $base = Format-NomeCanonico $Text

  if (-not $base) {
    return $null
  }

  $base = Remove-InvalidFileNameChars $base

  if (-not $base) {
    return $null
  }

  $base = (
    $base `
      -replace '\s{2,}', ' '
  ).Trim(' ', '.', '-', '_')

  if (-not $base) {
    return $null
  }

  if ($base.Length -gt 120) {
    $base = $base.Substring(0, 120).Trim(' ', '.', '-', '_')
  }

  if (-not $base) {
    return $null
  }

  return $base
}

function Get-MediaOwnerBase {
  param([object]$GameNode)

  if (-not $GameNode) {
    return $null
  }

  $candidates = @()

  $titleNode = $GameNode.SelectSingleNode('title')

  if (
    $titleNode `
      -and `
      $titleNode.InnerText `
      -and `
      $titleNode.InnerText.Trim()
  ) {
    $candidates += $titleNode.InnerText.Trim()
  }

  $nameNode = $GameNode.SelectSingleNode('name')

  if (
    $nameNode `
      -and `
      $nameNode.InnerText `
      -and `
      $nameNode.InnerText.Trim()
  ) {
    $candidates += $nameNode.InnerText.Trim()
  }

  $pathNode = $GameNode.SelectSingleNode('path')

  if (
    $pathNode `
      -and `
      $pathNode.InnerText `
      -and `
      $pathNode.InnerText.Trim()
  ) {

    $romFileName = [IO.Path]::GetFileName(
      $pathNode.InnerText.Trim().Replace(
        '/',
        [IO.Path]::DirectorySeparatorChar
      )
    )

    if ($romFileName) {

      $parsedRom = Extract-Extensions $romFileName

      if ($parsedRom) {
        $candidates += $parsedRom.Base
      }
      else {
        $candidates += [IO.Path]::GetFileNameWithoutExtension($romFileName)
      }
    }
  }

  foreach ($candidate in $candidates) {

    $base = Format-MediaCanonicalBase $candidate

    if ($base) {
      return $base
    }
  }

  return $null
}

function Get-MediaCanonicalFileName {
  param(
    [object]$Reference,
    [string]$FilePath,
    [string]$Hash
  )

  if (
    -not $Reference `
      -or `
      -not $FilePath `
      -or `
      -not $Hash `
      -or `
      $Hash.Length -lt 12
  ) {
    return $null
  }

  $extension = Get-PathExtensionSafe -PathValue $FilePath

  if (-not $extension) {
    return $null
  }

  $base = Get-MediaOwnerBase $Reference.GameNode

  if (-not $base) {
    return $null
  }

  $shortHash = $Hash.Substring(
    $Hash.Length - 12,
    12
  ).ToUpperInvariant()

  $maxNameLength = 180
  $availableBaseLength = (
    $maxNameLength -
    $shortHash.Length -
    $extension.Length -
    1
  )

  if ($availableBaseLength -lt 1) {
    return $null
  }

  if ($base.Length -gt $availableBaseLength) {
    $base = $base.Substring(
      0,
      $availableBaseLength
    ).Trim(' ', '.', '-', '_')
  }

  if (-not $base) {
    return $null
  }

  $name = "$base-$shortHash$extension"

  return Remove-InvalidFileNameChars $name
}

function Get-GamelistMediaReferences {

  $result = [pscustomobject]@{
    ByPath         = @{}
    AllXmlRefs     = @{}
    MonitoredDirs  = @{}
    ReferenceCount = 0
  }

  foreach ($xmlPath in @($script:PipelineState.XmlMap.Keys | Sort-Object)) {

    $xml = $script:PipelineState.XmlMap[$xmlPath]

    $gameNodes = @($xml.SelectNodes("//game"))

    for ($gameIndex = 0; $gameIndex -lt $gameNodes.Count; $gameIndex++) {

      $game = $gameNodes[$gameIndex]

      foreach ($child in @($game.ChildNodes)) {

        if ($child.NodeType -ne [System.Xml.XmlNodeType]::Element) {
          continue
        }

        $rawPath = $child.InnerText

        if (
          -not $rawPath `
            -or `
            -not $rawPath.Trim()
        ) {
          continue
        }

        # PROTECAO: tags desconhecidas com path impedem remoção órfã
        if (Get-PathExtensionSafe -PathValue ($rawPath.Trim())) {

          $anyResolved = Resolve-GamelistMediaPath `
            -XmlPath $xmlPath `
            -PathValue $rawPath

          if ($anyResolved) {
            $result.AllXmlRefs[$anyResolved.FullName] = $true
          }
        }

        $tagName = $child.LocalName

        if (-not $MediaSubtagSet.Contains($tagName)) {
          continue
        }

        $resolved = Resolve-GamelistMediaPath `
          -XmlPath $xmlPath `
          -PathValue $rawPath

        if (-not $resolved) {

          Write-InlineLog `
            "❌ MEDIA_PATH_INVALID :: $xmlPath :: <$tagName>" `
            Red `
            -forceNewLine

          continue
        }

        if (
          -not (Test-Path `
              -LiteralPath $resolved.FullName `
              -PathType Leaf)
        ) {

          Write-InlineLog `
            "⚠️ MEDIA_MISSING :: $(Get-RelativePathSafe $resolved.FullName)" `
            Yellow `
            -forceNewLine

          continue
        }

        $fullKey = Get-FullPathSafe -PathValue $resolved.FullName

        if (-not $result.ByPath.ContainsKey($fullKey)) {

          $result.ByPath[$fullKey] = [pscustomobject]@{
            FullName = $fullKey
            Refs     = @()
          }
        }

        $reference = [pscustomobject]@{
          XmlPath   = $xmlPath
          XmlNode   = $child
          GameNode  = $game
          GameIndex = $gameIndex
          TagName   = $tagName
          RawPath   = $rawPath.Trim()
          FullName  = $fullKey
          SortKey   = "{0}|{1:D8}|{2}|{3}" -f `
            $xmlPath,
          $gameIndex,
          $tagName,
          $rawPath.Trim()
        }

        $result.ByPath[$fullKey].Refs += $reference
        $result.ReferenceCount++

        $mediaDir = Split-Path $fullKey -Parent

        if ($mediaDir) {
          $result.MonitoredDirs[$mediaDir] = $true
        }
      }
    }
  }

  return $result
}

function Set-MediaXmlReference {
  param(
    [object]$Reference,
    [string]$NewFullPath,
    [switch]$CanMutate
  )

  if (
    -not $Reference `
      -or `
      -not $Reference.XmlNode `
      -or `
      -not $NewFullPath
  ) {
    return
  }

  $newValue = ConvertTo-GamelistMediaPath `
    -XmlPath $Reference.XmlPath `
    -FilePath $NewFullPath

  if (-not $newValue) {

    Write-InlineLog `
      "❌ MEDIA_XML_PATH_FAIL :: OP=CONVERT_MEDIA_XML_PATH PATH=[$NewFullPath] CAUSE=caminho fora do root do gamelist" `
      Red `
      -forceNewLine

    return
  }

  if ($Reference.XmlNode.InnerText -eq $newValue) {
    return
  }

  $eventName = if ($CanMutate) {
    'MEDIA_XML'
  }
  else {
    'MEDIA_XML_PENDING'
  }

  Write-InlineLog `
    "✏️ $eventName :: $($Reference.RawPath) -> $newValue" `
    DarkGreen `
    -forceNewLine

  if (-not $CanMutate) {
    return
  }

  $Reference.XmlNode.InnerText = $newValue

  $script:PipelineState.PendingXmlSave[
  $Reference.XmlPath
  ] = $true

  Save-PendingXmlRealtime
}

function Select-MediaSurvivor {
  param([object[]]$Entries)

  $ordered = $Entries | Sort-Object `
  @{ Expression   = {

      if (
        $_.TargetExists `
          -and `
          $_.TargetHash `
          -and `
          $_.TargetHash.Equals(
          $_.Hash,
          [StringComparison]::OrdinalIgnoreCase
        )
      ) {
        return 0
      }

      return 1
    } ; Ascending = $true
  },
  @{ Expression   = {

      if ($_.TargetIsSource) {
        return 0
      }

      return 1
    } ; Ascending = $true
  },
  @{ Expression   = {

      if ($_.TargetRelative) {
        return $_.TargetRelative.Length
      }

      return 999999
    } ; Ascending = $true
  },
  @{ Expression   = {

      if ($_.TargetRelative) {
        return $_.TargetRelative
      }

      return $_.FullName
    } ; Ascending = $true
  },
  @{ Expression   = {
      return $_.FullName
    } ; Ascending = $true
  }

  return (
    $ordered |
    Select-Object -First 1
  )
}

function Test-MediaOrphanRemovalCandidate {
  param([string]$FilePath)

  if (-not $FilePath) {
    return $false
  }

  $name = [IO.Path]::GetFileNameWithoutExtension($FilePath)

  if (-not $name) {
    return $false
  }

  $normalized = (
    $name `
      -replace '\s{2,}', ' '
  ).Trim().ToLowerInvariant()

  if (
    -not $normalized `
      -or `
      $normalized -eq 'copia'
  ) {
    return $false
  }

  # PROTECAO: remove órfão de mídia apenas com marcador nominal de duplicata
  $copyPattern = (
    '(^|[\s._-])copy(\s+of)?($|[\s._-])' +
    '|(^|[\s._-])(copia|copie)($|[\s._-])' +
    '|[\s._-]\([2-9][0-9]*\)(?=$|[\s._-])' +
    '|[\s._-]\([2-9][0-9]*\)$' +
    '|\([2-9][0-9]*\)$'
  )

  return ($normalized -match $copyPattern)
}

function Invoke-MediaMaintenance {
  param(
    [switch]$Fix,
    [switch]$VerifyOnly,
    [switch]$RemoveOrphans
  )

  $canMutate = (
    $Fix `
      -and `
      -not $VerifyOnly
  )

  if (-not $canMutate) {

    Write-InlineLog `
      "⚠️ MEDIA_RFC19_ANALYSIS_ONLY :: -Fix ausente ou VerifyOnly ativo" `
      Yellow `
      -forceNewLine
  }

  $state = Get-GamelistMediaReferences

  if ($state.ReferenceCount -eq 0) {
    return
  }

  $mediaEntries = @()

  foreach ($media in @($state.ByPath.Values | Sort-Object FullName)) {

    try {

      $hash = Get-FileHashCached $media.FullName

      $ownerRef = @(
        $media.Refs |
        Sort-Object SortKey |
        Select-Object -First 1
      )[0]

      $canonicalName = Get-MediaCanonicalFileName `
        -Reference $ownerRef `
        -FilePath $media.FullName `
        -Hash $hash

      if (-not $canonicalName) {

        Write-InlineLog `
          "❌ MEDIA_CANONICAL_FAIL :: OP=CANONICAL_MEDIA_NAME PATH=[$($media.FullName)] CAUSE=nome canônico vazio" `
          Red `
          -forceNewLine

        continue
      }

      $targetPath = Get-FullPathSafe -PathValue (
        (Join-Path (Split-Path $media.FullName -Parent) $canonicalName)
      )

      $targetExists = Test-Path `
        -LiteralPath $targetPath `
        -PathType Leaf

      $targetHash = $null

      if ($targetExists) {

        $targetHash = Get-FileHashCached $targetPath

        if (
          -not $targetHash.Equals(
            $hash,
            [StringComparison]::OrdinalIgnoreCase
          )
        ) {

          Write-InlineLog `
            "❌ MEDIA_COLLISION :: $(Get-RelativePathSafe $targetPath)" `
            Red `
            -forceNewLine

          continue
        }
      }

      $targetRelative = ConvertTo-GamelistMediaPath `
        -XmlPath $ownerRef.XmlPath `
        -FilePath $targetPath

      $mediaEntries += [pscustomobject]@{
        FullName       = $media.FullName
        Refs           = $media.Refs
        Hash           = $hash
        TargetPath     = $targetPath
        TargetRelative = $targetRelative
        TargetExists   = $targetExists
        TargetHash     = $targetHash
        TargetIsSource = $media.FullName.Equals(
          $targetPath,
          [StringComparison]::Ordinal
        )
      }
    }
    catch {

      Write-InlineLog `
        "❌ MEDIA_FAIL :: $(Format-ExceptionCause $_ 'ANALYZE_MEDIA' $media.FullName)" `
        Red `
        -forceNewLine
    }
  }

  foreach ($group in @($mediaEntries | Group-Object Hash)) {

    $entries = @($group.Group)

    if ($entries.Count -eq 0) {
      continue
    }

    $survivor = Select-MediaSurvivor $entries

    if (-not $survivor) {
      continue
    }

    $finalPath = $survivor.TargetPath
    $finalExists = Test-Path `
      -LiteralPath $finalPath `
      -PathType Leaf

    if ($finalExists) {

      $finalHash = Get-FileHashCached $finalPath

      if (
        -not $finalHash.Equals(
          $survivor.Hash,
          [StringComparison]::OrdinalIgnoreCase
        )
      ) {

        Write-InlineLog `
          "❌ MEDIA_ABORT_COLLISION :: $(Get-RelativePathSafe $finalPath)" `
          Red `
          -forceNewLine

        continue
      }
    }

    $samePhysical = $survivor.FullName.Equals(
      $finalPath,
      [StringComparison]::OrdinalIgnoreCase
    )

    $sameExactPath = $survivor.FullName.Equals(
      $finalPath,
      [StringComparison]::Ordinal
    )

    if (-not $sameExactPath) {

      $eventName = if ($canMutate) {
        'MEDIA_RENAME'
      }
      else {
        'MEDIA_RENAME_PENDING'
      }

      Write-InlineLog `
        "✏️ $eventName :: $(Get-RelativePathSafe $survivor.FullName) -> $(Get-RelativePathSafe $finalPath)" `
        DarkGreen `
        -forceNewLine

      if ($canMutate) {

        try {

          if ($finalExists -and -not $samePhysical) {
            # PROTECAO: destino equivalente preservado contra sobrescrita
          }
          else {

            $targetName = [IO.Path]::GetFileName($finalPath)
            $sourceName = [IO.Path]::GetFileName($survivor.FullName)

            $requiresCaseFix = (
              $sourceName -ieq $targetName `
                -and `
                $sourceName -cne $targetName
            )

            if ($requiresCaseFix) {

              $tempName = "$targetName.__media_rename_tmp__"
              $tempPath = Join-Path `
              (Split-Path $survivor.FullName -Parent) `
                $tempName

              if (Test-Path -LiteralPath $tempPath) {
                throw "OP=MEDIA_RENAME_CASE_TEMP SOURCE=[$($survivor.FullName)] TARGET=[$tempPath] CAUSE=destino temporário já existe"
              }

              Rename-Item `
                -LiteralPath $survivor.FullName `
                -NewName $tempName `
                -ErrorAction Stop

              Rename-Item `
                -LiteralPath $tempPath `
                -NewName $targetName `
                -ErrorAction Stop
            }
            else {

              Rename-Item `
                -LiteralPath $survivor.FullName `
                -NewName $targetName `
                -ErrorAction Stop
            }

            if (-not (Test-Path -LiteralPath $finalPath -PathType Leaf)) {
              throw "OP=MEDIA_RENAME_VALIDATE SOURCE=[$($survivor.FullName)] TARGET=[$finalPath] CAUSE=destino ausente após Rename-Item"
            }

            $script:PipelineState.HashCache[$finalPath] = $survivor.Hash
          }
        }
        catch {

          Write-InlineLog `
            "❌ MEDIA_RENAME_FAIL :: $(Format-ExceptionCause $_ 'RENAME_MEDIA' $survivor.FullName)" `
            Red `
            -forceNewLine

          continue
        }
      }
    }

    $state.AllXmlRefs[$finalPath] = $true

    foreach ($entry in $entries) {

      foreach ($ref in @($entry.Refs | Sort-Object SortKey)) {

        Set-MediaXmlReference `
          -Reference $ref `
          -NewFullPath $finalPath `
          -CanMutate:$canMutate
      }

      if (
        $entry.FullName.Equals(
          $survivor.FullName,
          [StringComparison]::OrdinalIgnoreCase
        ) `
          -and `
          -not (
          $finalExists `
            -and `
            -not $samePhysical
        )
      ) {
        continue
      }

      if (
        $entry.FullName.Equals(
          $finalPath,
          [StringComparison]::OrdinalIgnoreCase
        )
      ) {
        continue
      }

      if (
        -not (Test-Path `
            -LiteralPath $entry.FullName `
            -PathType Leaf)
      ) {
        continue
      }

      $eventName = if ($canMutate) {
        'MEDIA_DEDUP'
      }
      else {
        'MEDIA_DEDUP_PENDING'
      }

      Write-InlineLog `
        "🗑️ $eventName :: $(Get-RelativePathSafe $entry.FullName)" `
        Yellow `
        -forceNewLine

      if ($canMutate) {

        try {

          Remove-Item `
            -LiteralPath $entry.FullName `
            -Force `
            -ErrorAction Stop
        }
        catch {

          Write-InlineLog `
            "❌ MEDIA_DEDUP_FAIL :: $(Format-ExceptionCause $_ 'DEDUP_MEDIA' $entry.FullName)" `
            Red `
            -forceNewLine
        }
      }
    }
  }

  if (-not $RemoveOrphans) {
    return
  }

  $referencedMediaHashes = @{}

  foreach ($media in @($state.ByPath.Values | Sort-Object FullName)) {

    if (
      -not $media.FullName `
        -or `
      -not (Test-Path -LiteralPath $media.FullName -PathType Leaf)
    ) {
      continue
    }

    try {

      $mediaHash = Get-FileHashCached $media.FullName
      $referencedMediaHashes[$mediaHash] = $true
    }
    catch {

      Write-InlineLog `
        "❌ MEDIA_REF_HASH_FAIL :: $(Format-ExceptionCause $_ 'HASH_REFERENCED_MEDIA' $media.FullName)" `
        Red `
        -forceNewLine
    }
  }

  foreach ($dir in @($state.MonitoredDirs.Keys | Sort-Object)) {

    try {

      $files = Get-ChildItem `
        -LiteralPath $dir `
        -File `
        -ErrorAction Stop

      foreach ($file in $files) {

        $full = Get-FullPathSafe -PathValue $file.FullName
        $extension = Get-PathExtensionSafe -PathValue $file.Name

        if (-not $MediaExtensionSet.Contains($extension)) {
          continue
        }

        if ($state.AllXmlRefs.ContainsKey($full)) {
          continue
        }

        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
          continue
        }

        if (-not (Test-MediaOrphanRemovalCandidate $full)) {

          Write-InlineLog `
            "⚠️ MEDIA_ORPHAN_PRESERVED :: $(Get-RelativePathSafe $full)" `
            Yellow `
            -forceNewLine

          continue
        }

        $orphanHash = Get-FileHashCached $full

        if (-not $referencedMediaHashes.ContainsKey($orphanHash)) {

          Write-InlineLog `
            "⚠️ MEDIA_ORPHAN_PRESERVED_NO_EQUIV :: $(Get-RelativePathSafe $full)" `
            Yellow `
            -forceNewLine

          continue
        }

        $eventName = if ($canMutate) {
          'MEDIA_ORPHAN_REMOVE'
        }
        else {
          'MEDIA_ORPHAN_PENDING'
        }

        Write-InlineLog `
          "⚠️ $eventName :: $(Get-RelativePathSafe $full)" `
          Yellow `
          -forceNewLine

        if ($canMutate) {

          Remove-Item `
            -LiteralPath $full `
            -Force `
            -ErrorAction Stop
        }
      }
    }
    catch {

      Write-InlineLog `
        "❌ MEDIA_ORPHAN_SCAN_FAIL :: $(Format-ExceptionCause $_ 'SCAN_MEDIA_ORPHANS' $dir)" `
        Red `
        -forceNewLine
    }
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
          throw "OP=TRANSLATE_NETWORK_CHECK CAUSE=Rede indisponível"
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

function Format-DescriptionText {
  param([string]$Text)

  if (-not $Text) {
    return $Text
  }

  $normalized = $Text

  # FIX-BUG: normaliza whitespace estrutural XML
  $normalized = [regex]::Replace(
    $normalized,
    '\s+',
    ' '
  ).Trim()

  if (-not $normalized) {
    return $normalized
  }

  # PROTECAO: evita destruir textos já corretamente formatados
  $allUpper = (
    $normalized -ceq $normalized.ToUpperInvariant()
  )

  $allLower = (
    $normalized -ceq $normalized.ToLowerInvariant()
  )

  if (-not $allUpper -and -not $allLower) {
    return $normalized
  }

  # FIX-BUG: preserva siglas estruturais e nomes técnicos
  $tokens = $normalized -split ' '

  $normalizedTokens = foreach ($token in $tokens) {

    if (
      $token.Length -le 4 `
        -and `
        $token -cmatch '^[A-Z0-9]+$'
    ) {
      $token
    }
    else {
      $token.ToLowerInvariant()
    }
  }

  $lower = ($normalizedTokens -join ' ')

  $formatted = [regex]::Replace(
    $lower,
    '(^|[.!?]\s+)(\p{L})',
    {
      param($m)

      return (
        $m.Groups[1].Value +
        $m.Groups[2].Value.ToUpperInvariant()
      )
    }
  )

  return $formatted.Trim()
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
      throw "OP=ACQUIRE_MUTEX CAUSE=Outra instância já está em execução"
    }

    $script:VerifyOnlyMode = $VerifyOnly
    $script:FixMode = $Fix

    Write-InlineLog "ℹ️ PIPELINE :: INITIALIZE" Cyan -forceNewLine

    Load-JsonTrees
    Load-BrsIndexes
    Initialize-BrsIndex
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
              throw "OP=PARSE_COLLISION_NAME SOURCE=[$($entry.File.Name)] TARGET=[$newName] CAUSE=extensão canônica inválida"
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
                "OP=RESOLVE_NAME_COLLISION CAUSE=destino alternativo ocupado " +
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

        # FIX-BUG: normaliza descrição XML RFC objetivo
        if ($entry.XmlNode) {

          $descNode = $entry.XmlNode.SelectSingleNode('desc')

          if (
            $descNode `
              -and `
              $descNode.InnerText
          ) {

            $normalizedDesc = Format-DescriptionText(
              $descNode.InnerText
            )

            if (
              $normalizedDesc `
                -and `
                $normalizedDesc -cne $descNode.InnerText
            ) {

              if (-not $VerifyOnly) {

                $descNode.InnerText = $normalizedDesc

                $script:PipelineState.PendingXmlSave[
                $Entry.XmlPath
                ] = $true
              }
            }
          }
        }

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
              throw "OP=RENAME_CASE_TEMP SOURCE=[$oldFullPath] TARGET=[$tempPath] CAUSE=destino temporário já existe"
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

            throw "OP=RENAME_VALIDATE SOURCE=[$oldFullPath] TARGET=[$newFullPath] CAUSE=destino ausente após Rename-Item"
          }

          $oldMapKey = Get-FullPathSafe -PathValue $oldFullPath

          $newMapKey = Get-FullPathSafe -PathValue $newFullPath

          # FIX-BUG: garante hash estrutural disponível RFC 2/RFC 11
          if (-not $srcHash) {
            $srcHash = Get-FileHashCached $newFullPath
          }          

          # FIX-BUG: sincroniza JSON Tree pós-rename RFC 2
          if (Test-IsSpecialJsonPath $oldFullPath) {
            Remove-JsonTreeEntry $oldFullPath
          }

          if (Test-IsSpecialJsonPath $newFullPath) {

            # FIX-BUG: garante hash válido pós-rename
            if (-not $srcHash) {
              $srcHash = Get-FileHashCached $newFullPath
            }

            Set-JsonTreeHashEntry `
              -FilePath $newFullPath `
              -Hash $srcHash
          }

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

          Save-PendingXmlRealtime
        }
      }
      catch {

        Write-InlineLog `
          "❌ NORMALIZE_FAIL :: $(Format-ExceptionCause $_ 'NORMALIZE_ENTRY' $entry.File.FullName)" `
          Red `
          -forceNewLine
      }
    }

    # FIX-BUG: integra deduplicação e órfãos de mídia RFC 19
    Invoke-MediaMaintenance `
      -Fix:$Fix `
      -VerifyOnly:$VerifyOnly

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

    Invoke-GlobalDeduplication `
      -VerifyOnly:$VerifyOnly

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

        $requiresShaSync = $false

        # FIX-BUG: recria .sha256 ausente RFC 0 + RFC 11
        if (-not (Test-Path -LiteralPath $shaPath)) {
          $requiresShaSync = $true
        }

        # FIX-BUG: recria hash inválido/corrompido RFC 0
        elseif (
          -not $stored `
            -or `
            $stored.Hash -ne $entry.Hash `
            -or `
            $stored.FileName -cne $entry.File.Name
        ) {
          $requiresShaSync = $true
        }

        # FIX-BUG: valida presença da entrada JSON Tree RFC 2
        if (
          -not $requiresShaSync `
            -and `
          (Test-IsSpecialJsonPath $entry.File.FullName)
        ) {

          $jsonTreePath = Get-JsonTreePath $entry.File.FullName

          if (
            $jsonTreePath `
              -and `
              $script:PipelineState.JsonTrees.ContainsKey($jsonTreePath)
          ) {

            $jsonRoot = $script:PipelineState.JsonTrees[$jsonTreePath]

            $treeRoot = Split-Path $jsonTreePath -Parent

            $relative = $entry.File.FullName.Substring(
              $treeRoot.Length
            ).TrimStart('\', '/')

            $parts = $relative -split '[\\/]'

            $segments = @()

            if ($parts.Count -gt 2) {
              $segments = $parts[1..($parts.Count - 2)]
            }

            $leafName = $parts[-1]

            $target = Get-JsonTreeRoot `
              -Root $jsonRoot `
              -Segments $segments

            if (
              -not $target `
                -or `
                -not $target.PSObject.Properties[$leafName] `
                -or `
                $target.$leafName -ne $entry.Hash
            ) {
              $requiresShaSync = $true
            }
          }
        }

        if (-not $requiresShaSync) {
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
          "❌ SHA_FAIL :: $(Format-ExceptionCause $_ 'SYNC_SHA256' $entry.File.FullName)" `
          Red `
          -forceNewLine
      }
    }

    # FIX-BUG: audita órfãos e divergências JSON Tree RFC 11.8
    Invoke-JsonTreeIntegrityAudit `
      -Fix:$Fix `
      -VerifyOnly:$VerifyOnly

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

    # FIX-BUG: remove órfãos de mídia somente após convergência XML/hash
    Invoke-MediaMaintenance `
      -Fix:$Fix `
      -VerifyOnly:$VerifyOnly `
      -RemoveOrphans

    # ==========================================================
    # SAVE FINAL
    # ==========================================================

    if (-not $VerifyOnly) {

      Save-PendingXml
      Save-PendingJsonTrees
      Save-PendingBrsIndexes
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
      "❌ FATAL :: $(Format-ExceptionCause $_ 'PIPELINE' (Get-Location).Path)" `
      Red `
      -forceNewLine

    exit 1
  }
}
