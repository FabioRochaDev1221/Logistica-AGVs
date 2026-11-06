# Dossiê de Arquitetura Viva — Recepção de Solicitação via ERP/WMS/MES e Planejamento da Missão

> **APS 2 — Modelagem de Software · Engenharia de Software**
> **Projeto da equipe:** Logística de Entregas Autônomas em Parques Industriais (Orquestração de AGVs)
> **Contexto delimitado:** Integração Empresarial e Solicitação de Transporte
> **Entidade de domínio principal:** `SolicitacaoTransporte`
> **Autora:** Laura Rosa
> **Paradigma:** Diagrams-as-Code (Mermaid, PlantUML) + Models-as-Code (C4-PlantUML, Structurizr DSL)

---

## Sumário

1. [A funcionalidade crítica](#1-a-funcionalidade-crítica)
2. [Contrato de operações (base da consistência)](#2-contrato-de-operações-base-da-consistência)
3. [Artefato 1 — Diagrama de Sequência](#3-artefato-1--diagrama-de-sequência)
4. [Artefato 2 — Diagrama de Atividades com Raias](#4-artefato-2--diagrama-de-atividades-com-raias)
5. [Artefato 3 — Diagrama de Transição de Estados](#5-artefato-3--diagrama-de-transição-de-estados)
6. [Artefato 4 — Visão Arquitetural C4](#6-artefato-4--visão-arquitetural-c4)
7. [Artefato 5 — ADR 0001](#7-artefato-5--adr-0001)
8. [Matriz de consistência entre modelos](#8-matriz-de-consistência-entre-modelos)
9. [Concorrência e proteção contra estados inválidos](#9-concorrência-e-proteção-contra-estados-inválidos)
10. [Estrutura do repositório e como renderizar](#10-estrutura-do-repositório-e-como-renderizar)

---

## 1. A funcionalidade crítica

**Recepção de Solicitação via ERP/WMS/MES e Planejamento da Missão.** É a porta de entrada de todo o fluxo logístico. Segundo a Visão de Domínio, a **Solicitação de Transporte** "é a entidade que inicia o fluxo logístico". Sem ela, nenhuma missão existe e nenhum AGV se move.

| Por que é crítica | Referência na Visão de Domínio |
|---|---|
| Uma ordem reenviada pelo ERP não pode virar duas missões e dois AGVs para a mesma carga. | Seção 8.2 **Integração Empresarial** · Regra de **Exclusividade** |
| O núcleo de orquestração deve ficar desacoplado dos formatos de ERP/WMS/MES. | Seção 2 **Contextos Delimitados** · Seção 8.2 ("mantendo o núcleo desacoplado") |
| Só podem ser aceitas solicitações com hubs válidos, material compatível e peso dentro da capacidade da frota. | Regras de **Capacidade** e **Compatibilidade** · Seção 3.6 **Hub Logístico** |
| Uma solicitação crítica pode passar à frente das que já estão na fila. | Política de **Priorização** |
| O ERP precisa saber se a ordem foi aceita, rejeitada ou atendida. | Seção 8.2 (devolve status e conclusão) · Seção 9 **Rastreabilidade** |

### Fluxo resumido

1. O ERP/WMS/MES obtém um token OAuth 2.0 e envia a solicitação assinada (HMAC).
2. A **Anti-Corruption Layer** traduz o *payload* para o modelo de domínio. Erros estruturais retornam **422** na hora.
3. A **chave de idempotência** `(sistemaOrigem, idExterno)` detecta reenvios, que retornam **200** com o protocolo existente.
4. Uma solicitação nova é gravada como `RECEBIDA` junto com o evento na **outbox** (mesma transação), e o ERP recebe **202 Accepted** com o protocolo.
5. **De forma assíncrona**, o `PlanejamentoService` passa a solicitação para `EM_ANALISE` e executa **em paralelo**: validação dos hubs, compatibilidade da frota e cálculo da rota preliminar.
6. Resultado da análise:
   - **aprovada:** a solicitação é priorizada, a `MissaoTransporte` é criada como `PLANEJADA` e a solicitação passa a `EM_ATENDIMENTO`;
   - **rejeitada:** a solicitação passa a `REJEITADA`, com os motivos;
   - **sem rota:** a solicitação passa a `PENDENTE_ROTA` e é reprocessada com *backoff*.
7. O ERP é notificado por **webhook** com retry. Mais tarde, quando a missão termina, a solicitação passa a `ATENDIDA` e o ERP é avisado novamente.

### Principais DTOs

| DTO | Campos relevantes |
|---|---|
| `SolicitacaoExternaDTO` | Formato do ERP: `codDeposito`, `codMaterial`, `qtd`, `unidade`, `prioridadeErp`, `dataLimite`, `idExterno` |
| `ResultadoTraducaoDTO` | `comando: ComandoCriarSolicitacao`, `violacoes[]` |
| `ComandoCriarSolicitacao` | Formato do domínio: `sistemaOrigem`, `idExterno`, `hubOrigemId`, `hubDestinoId`, `tipoMaterial`, `pesoKg`, `prioridade`, `prazo` |
| `ProtocoloDTO` | `protocolo`, `status`, `duplicada`, `recebidaEm` |
| `ValidacaoHubsDTO` | `origemAtivo`, `destinoAtivo`, `erros[]` |
| `CompatibilidadeDTO` | `agvsCompativeis`, `erros[]` |
| `RotaDTO` | `trechos[]`, `distanciaM`, `etaSeg`, `rotaValida` |
| `PrioridadeDTO` | `nivel`, `score`, `furaFila` |
| `MissaoDTO` | `missaoId`, `status`, `posicaoFila` |
| `StatusSolicitacaoDTO` | `protocolo`, `idExterno`, `status`, `missaoId`, `motivos[]`, `etaPrevisto`, `eventId` |

---

## 2. Contrato de operações (base da consistência)

> **Regra de Consistência:** toda mensagem enviada a uma linha de vida B no Diagrama de Sequência corresponde a uma operação pública declarada na classe/interface B abaixo. Isso foi verificado automaticamente: **23 mensagens, 0 inconsistências**.

```mermaid
%% Contrato de operações públicas — base da Regra de Consistência do Diagrama de Sequência
%% Toda mensagem enviada a uma linha de vida corresponde a uma operação abaixo.
classDiagram
    direction LR

    class IErpCallback {
        <<interface · sistema externo>>
        +receberStatus(s: StatusSolicitacaoDTO) void
    }
    class IIntegracaoController {
        <<interface>>
        +receberSolicitacao(req: SolicitacaoExternaDTO) ProtocoloDTO
    }
    class ITradutorSolicitacaoACL {
        <<interface>>
        +traduzir(ext: SolicitacaoExternaDTO) ResultadoTraducaoDTO
    }
    class ISolicitacaoService {
        <<interface>>
        +registrar(cmd: ComandoCriarSolicitacao) ProtocoloDTO
        +registrarDesfecho(evt: MissaoEncerradaEvent) void
    }
    class ISolicitacaoRepository {
        <<interface>>
        +buscarPorIdExterno(sistemaOrigem: String, idExterno: String) Optional~SolicitacaoTransporte~
        +salvar(s: SolicitacaoTransporte) SolicitacaoTransporte
        +atualizarStatus(id: UUID, novo: StatusSolicitacao, versao: long) SolicitacaoTransporte
        +vincularMissao(id: UUID, missaoId: UUID, versao: long) SolicitacaoTransporte
    }
    class IPlanejamentoService {
        <<interface>>
        +processar(evt: SolicitacaoRecebidaEvent) void
        +agendarReprocessamento(id: UUID, backoff: Duration) void
    }
    class IGeolocalizacaoService {
        <<interface>>
        +validarHubs(origemId: UUID, destinoId: UUID) ValidacaoHubsDTO
        +calcularRota(req: RotaRequestDTO) RotaDTO
    }
    class IFrotaService {
        <<interface>>
        +verificarCompatibilidade(req: CompatibilidadeRequestDTO) CompatibilidadeDTO
    }
    class IPoliticaPriorizacao {
        <<interface>>
        +calcularPrioridade(c: CriteriosPrioridadeDTO) PrioridadeDTO
    }
    class IMissaoService {
        <<interface>>
        +criarMissao(cmd: CriarMissaoDTO) MissaoDTO
    }
    class IErpNotifier {
        <<interface>>
        +notificarStatus(s: StatusSolicitacaoDTO) void
    }
    class SolicitacaoTransporte {
        <<Aggregate Root>>
        -id: UUID
        -sistemaOrigem: String
        -idExterno: String
        -hubOrigemId: UUID
        -hubDestinoId: UUID
        -tipoMaterial: TipoMaterial
        -pesoKg: BigDecimal
        -prioridade: NivelPrioridade
        -prazo: Instant
        -status: StatusSolicitacao
        -missaoId: UUID
        -tentativasRota: int
        -versao: long
        +transitar(gatilho: GatilhoSolicitacao) void
    }
    class StatusSolicitacao {
        <<enumeration>>
        RECEBIDA
        EM_ANALISE
        PENDENTE_ROTA
        PRIORIZADA
        EM_ATENDIMENTO
        ATENDIDA
        REJEITADA
        CANCELADA
        NAO_ATENDIDA
    }

    IIntegracaoController ..> ITradutorSolicitacaoACL
    IIntegracaoController ..> ISolicitacaoService
    ISolicitacaoService ..> ISolicitacaoRepository
    ISolicitacaoService ..> IPlanejamentoService : AMQP
    ISolicitacaoService ..> IErpNotifier : AMQP
    IPlanejamentoService ..> ISolicitacaoRepository
    IPlanejamentoService ..> IGeolocalizacaoService : gRPC
    IPlanejamentoService ..> IFrotaService : gRPC
    IPlanejamentoService ..> IPoliticaPriorizacao
    IPlanejamentoService ..> IMissaoService : gRPC
    IPlanejamentoService ..> IErpNotifier : AMQP
    IMissaoService ..> ISolicitacaoService : AMQP
    IErpNotifier ..> IErpCallback : Webhook HTTPS
    ISolicitacaoRepository --> SolicitacaoTransporte
    SolicitacaoTransporte --> StatusSolicitacao
```

---

## 3. Artefato 1 — Diagrama de Sequência

📄 Fonte: [`docs/diagrams/sequencia.mmd`](docs/diagrams/sequencia.mmd)

| Notação | Significado | Exemplos no diagrama |
|---|---|---|
| `->>` (seta cheia) | Chamada **síncrona bloqueante** | `receberSolicitacao()`, `traduzir()`, `registrar()`, `validarHubs()` (gRPC), `criarMissao()` (gRPC), `receberStatus()` (webhook) |
| `-)` (seta aberta) | Mensagem **assíncrona / mensageria** | `processar()` (AMQP via outbox), `notificarStatus()` (AMQP), `agendarReprocessamento()` (fila com atraso), `registrarDesfecho()` (AMQP) |
| `-->>` (tracejada) | **Retorno com DTO** | `ResultadoTraducaoDTO`, `ProtocoloDTO`, `RotaDTO`, `PrioridadeDTO`, `MissaoDTO` |

**Fragmentos combinados usados:**
- `alt/else`: *payload* inválido × válido; reenvio × solicitação inédita; aprovada × rejeitada × sem rota.
- `par`: as três validações da análise, executadas em paralelo.
- `loop`: retry do webhook com *backoff* exponencial.
- `opt`: desfecho da missão, que chega mais tarde.

```mermaid
%% Artefato 1 — Diagrama de Sequência
%% Funcionalidade: Recepção de Solicitação via ERP/WMS/MES e Planejamento da Missão
%% Contexto: Integração Empresarial e Solicitação de Transporte · Entidade: SolicitacaoTransporte
%% Convenção: ->> chamada síncrona bloqueante | -) mensagem assíncrona | -->> retorno (DTO)
sequenceDiagram
    autonumber
    participant ERP as ERP / WMS / MES<br/>«Sistema externo»
    participant CTL as IntegracaoController<br/>«REST»
    participant ACL as TradutorSolicitacaoACL<br/>«Anti-Corruption Layer»
    participant SVC as SolicitacaoService
    participant REP as SolicitacaoRepository<br/>«PostgreSQL»
    participant PLN as PlanejamentoService<br/>«consumidor AMQP»
    participant GEO as GeolocalizacaoService<br/>«gRPC»
    participant FRT as FrotaService<br/>«gRPC»
    participant PRI as PoliticaPriorizacao<br/>«Strategy»
    participant MIS as MissaoService<br/>«Orquestração · gRPC»
    participant NTF as ErpNotifier<br/>«Webhook»

    ERP->>CTL: receberSolicitacao(SolicitacaoExternaDTO) [POST /api/v1/integracao/solicitacoes]
    CTL->>ACL: traduzir(SolicitacaoExternaDTO)
    ACL-->>CTL: ResultadoTraducaoDTO {comando, violacoes}

    alt violacoes.size > 0 (schema ou código de hub desconhecido)
        CTL-->>ERP: 422 Unprocessable Entity — ErroValidacaoDTO {violacoes}
    else violacoes.size == 0
        CTL->>SVC: registrar(ComandoCriarSolicitacao)
        SVC->>REP: buscarPorIdExterno(sistemaOrigem, idExterno)
        REP-->>SVC: Optional~SolicitacaoTransporte~

        alt solicitação já registrada (reenvio do ERP)
            SVC-->>CTL: ProtocoloDTO {protocolo existente, status atual, duplicada: true}
            CTL-->>ERP: 200 OK — ProtocoloDTO
        else idExterno inédito
            SVC->>REP: salvar(SolicitacaoTransporte {status: RECEBIDA} + outbox SolicitacaoRecebida)
            REP-->>SVC: SolicitacaoTransporte {id, versao: 0}
            SVC-->>CTL: ProtocoloDTO {protocolo, status: RECEBIDA}
            CTL-->>ERP: 202 Accepted — ProtocoloDTO

            SVC-)PLN: processar(SolicitacaoRecebidaEvent) [AMQP fila solicitacoes.recebidas, via outbox]
            PLN->>REP: atualizarStatus(id, EM_ANALISE, versao 0)
            REP-->>PLN: SolicitacaoTransporte {versao: 1}

            par Validar hubs de origem e destino
                PLN->>GEO: validarHubs(hubOrigemId, hubDestinoId)
                GEO-->>PLN: ValidacaoHubsDTO {origemAtivo, destinoAtivo, erros}
            and Verificar compatibilidade da frota
                PLN->>FRT: verificarCompatibilidade(CompatibilidadeRequestDTO {tipoMaterial, pesoKg})
                FRT-->>PLN: CompatibilidadeDTO {agvsCompativeis, erros}
            and Calcular rota preliminar
                PLN->>GEO: calcularRota(RotaRequestDTO {origem, destino, restricoes})
                GEO-->>PLN: RotaDTO {trechos, distanciaM, etaSeg, rotaValida}
            end

            Note over PLN: consolidarAnalise(): erros = hubs + frota + (rota.etaSeg > prazoSeg ? PRAZO_INVIAVEL)
            alt erros.size == 0 E rota.valida == true
                PLN->>PRI: calcularPrioridade(CriteriosPrioridadeDTO {prioridadeErp, prazo, criticidadeMaterial})
                PRI-->>PLN: PrioridadeDTO {nivel, score, furaFila}
                PLN->>REP: atualizarStatus(id, PRIORIZADA, versao 1)
                REP-->>PLN: SolicitacaoTransporte {versao: 2}
                PLN->>MIS: criarMissao(CriarMissaoDTO {solicitacaoId, rota, prioridade})
                MIS-->>PLN: MissaoDTO {missaoId, status: PLANEJADA, posicaoFila}
                PLN->>REP: vincularMissao(id, missaoId, versao 2)
                REP-->>PLN: SolicitacaoTransporte {status: EM_ATENDIMENTO, versao: 3}
                PLN-)NTF: notificarStatus(StatusSolicitacaoDTO {ACEITA, missaoId, etaPrevisto}) [AMQP fila erp.notificacoes]

                loop Até resposta 2xx ou 5 tentativas (backoff exponencial 1 s → 16 s)
                    NTF->>ERP: receberStatus(StatusSolicitacaoDTO) [Webhook HTTPS + assinatura HMAC]
                    ERP-->>NTF: 204 No Content | 5xx
                end

                opt Missão encerrada no contexto de Orquestração (assíncrono, minutos depois)
                    MIS-)SVC: registrarDesfecho(MissaoEncerradaEvent {missaoId, CONCLUIDA}) [AMQP]
                    SVC->>REP: atualizarStatus(id, ATENDIDA, versao 3)
                    REP-->>SVC: SolicitacaoTransporte {versao: 4}
                    SVC-)NTF: notificarStatus(StatusSolicitacaoDTO {ATENDIDA}) [AMQP]
                end
            else erros.size > 0
                PLN->>REP: atualizarStatus(id, REJEITADA, versao 1)
                REP-->>PLN: SolicitacaoTransporte {versao: 2}
                PLN-)NTF: notificarStatus(StatusSolicitacaoDTO {REJEITADA, motivos}) [AMQP]
            else erros.size == 0 E rota.valida == false (corredor bloqueado)
                PLN->>REP: atualizarStatus(id, PENDENTE_ROTA, versao 1)
                REP-->>PLN: SolicitacaoTransporte {versao: 2}
                PLN-)PLN: agendarReprocessamento(id, backoff) [AMQP fila com atraso]
            end
        end
    end
```

---

## 4. Artefato 2 — Diagrama de Atividades com Raias

📄 Fontes: [`docs/diagrams/atividades.puml`](docs/diagrams/atividades.puml) (PlantUML, **versão canônica**) e [`docs/diagrams/atividades.mmd`](docs/diagrams/atividades.mmd) (Mermaid, equivalente).

> **Por que duas versões?** O Mermaid não tem raias (swimlanes) nativas; elas são simuladas com `subgraph`, e o layout fica difícil de ler. O PlantUML tem raias verdadeiras e barras de fork/join formais. As duas versões contêm as mesmas ações, guardas e barras de sincronização.

**Raias (5):** ERP/WMS/MES · Integração Empresarial · Planejamento da Solicitação · Serviços de Apoio (Geolocalização, Frota) · Orquestração de Missões.

**Nós de decisão com guardas mutuamente exclusivas:**

| Decisão | Guardas |
|---|---|
| Requisição autenticada? | `[token.valido == true E hmac.valido == true]` / `[token.valido == false OU hmac.valido == false]` |
| Payload válido? | `[violacoes.size == 0]` / `[violacoes.size > 0]` |
| Solicitação já registrada? | `[idExterno já existe]` / `[idExterno inédito]` |
| Resultado da análise? | `[erros.size > 0]` / `[erros.size == 0 E rota.valida == false]` / `[erros.size == 0 E rota.valida == true]` |
| Há tentativas restantes? | `[tentativasRota < 5]` / `[tentativasRota ≥ 5]` |

**Concorrência (3 pares de Fork/Join):**

- **Fork 1 / Join 1:** o *ERP registra o protocolo e aguarda o callback* ‖ a *Integração publica `SolicitacaoRecebida` (outbox → AMQP)*. Mostra o desacoplamento temporal entre os dois sistemas.
- **Fork 2 / Join 2:** *Validar hubs* ‖ *Verificar compatibilidade da frota* ‖ *Calcular rota preliminar*. A consolidação só acontece depois que as três terminam.
- **Fork 3 / Join 3:** *Enfileirar missão para alocação de AGV* ‖ *Notificar o ERP (ACEITA) → ERP atualiza a ordem*.

![Diagrama de Atividades (PlantUML)](docs/diagrams/img/atividades.png)

<details>
<summary><b>Versão Mermaid (renderizada nativamente pelo GitHub)</b></summary>

```mermaid
%% Artefato 2 — Diagrama de Atividades com Raias (versão Mermaid)
%% Funcionalidade: Recepção de Solicitação via ERP/WMS/MES e Planejamento da Missão
%% Raias: ERP/WMS/MES | Integração Empresarial | Planejamento da Solicitação | Serviços de Apoio | Orquestração de Missões
%% Versão canônica com raias estritas: atividades.puml (mesmas ações, guardas, forks e joins)
flowchart TB
    subgraph L1["🏭 Raia 1 — ERP / WMS / MES (Sistema corporativo)"]
        INI(((Início)))
        A1[Gerar ordem de movimentação de material]
        A2[Enviar solicitação — POST + OAuth 2.0 + HMAC]
        A3[Registrar erro de integração]
        A4[Corrigir dados e reenviar]
        A5[Manter protocolo já registrado]
        A6[Registrar protocolo e aguardar callback]
        A7[Tratar rejeição da ordem]
        A8[Atualizar ordem com missaoId e ETA]
        FIM1(((Fim)))
        FIM2(((Fim)))
    end

    subgraph L2["🔌 Raia 2 — Integração Empresarial (Controller, ACL, SolicitacaoService)"]
        B1[Autenticar requisição]
        D1{Requisição autenticada?}
        B2[Responder 401 Unauthorized]
        B3[Traduzir payload para o modelo de domínio — ACL]
        D2{Payload válido?}
        B4[Responder 422 com violações]
        D3{Solicitação já registrada?}
        B5[Responder 200 com protocolo existente]
        B6[Persistir RECEBIDA + outbox — mesma transação]
        B7[Responder 202 Accepted com protocolo]
        FK1@{ shape: fork, label: "Fork 1" }
        B8[Publicar SolicitacaoRecebida — outbox → AMQP]
        JN1@{ shape: fork, label: "Join 1" }
        B9[Notificar ERP: REJEITADA com motivos — webhook]
        B10[Notificar ERP: ACEITA com missaoId — webhook]
    end

    subgraph L3["🧭 Raia 3 — Planejamento da Solicitação (PlanejamentoService, Priorização)"]
        C1[Mudar solicitação para EM_ANALISE]
        FK2@{ shape: fork, label: "Fork 2" }
        JN2@{ shape: fork, label: "Join 2" }
        C2[Consolidar análise — inclui viabilidade do prazo]
        D4{Resultado da análise?}
        C3[Mudar para PENDENTE_ROTA e aguardar backoff]
        D5{Há tentativas restantes?}
        C4[Mudar solicitação para REJEITADA]
        C5[Calcular prioridade — Política de Priorização]
        C6[Mudar solicitação para PRIORIZADA]
        C7[Vincular missão e mudar para EM_ATENDIMENTO]
        FK3@{ shape: fork, label: "Fork 3" }
        JN3@{ shape: fork, label: "Join 3" }
    end

    subgraph L4["🗺️ Raia 4 — Serviços de Apoio (Geolocalização, Frota)"]
        E1[Validar hubs de origem e destino]
        E2[Verificar compatibilidade da frota — material e peso]
        E3[Calcular rota preliminar]
    end

    subgraph L5["⚙️ Raia 5 — Orquestração de Missões (MissaoService)"]
        F1[Criar MissaoTransporte PLANEJADA]
        F2[Enfileirar missão para alocação de AGV]
    end

    INI --> A1 --> A2 --> B1 --> D1
    D1 -->|"[token.valido == false OU hmac.valido == false]"| B2 --> A3 --> FIM1
    D1 -->|"[token.valido == true E hmac.valido == true]"| B3 --> D2
    D2 -->|"[violacoes.size > 0]"| B4 --> A4 --> FIM1
    D2 -->|"[violacoes.size == 0]"| D3
    D3 -->|"[idExterno já existe]"| B5 --> A5 --> FIM1
    D3 -->|"[idExterno inédito]"| B6 --> B7 --> FK1
    FK1 --> A6 --> JN1
    FK1 --> B8 --> JN1
    JN1 --> C1 --> FK2
    FK2 --> E1 --> JN2
    FK2 --> E2 --> JN2
    FK2 --> E3 --> JN2
    JN2 --> C2 --> D4
    D4 -->|"[erros.size > 0]"| C4
    D4 -->|"[erros.size == 0 E rota.valida == false]"| C3 --> D5
    D5 -->|"[tentativasRota < 5]"| C1
    D5 -->|"[tentativasRota ≥ 5]"| C4
    C4 --> B9 --> A7 --> FIM2
    D4 -->|"[erros.size == 0 E rota.valida == true]"| C5 --> C6 --> F1 --> C7 --> FK3
    FK3 --> F2 --> JN3
    FK3 --> B10 --> A8 --> JN3
    JN3 --> FIM2

    classDef decisao fill:#fff4d6,stroke:#b8860b,color:#222
    classDef terminal fill:#222,stroke:#222,color:#fff
    class D1,D2,D3,D4,D5 decisao
    class INI,FIM1,FIM2 terminal
```

</details>

---

## 5. Artefato 3 — Diagrama de Transição de Estados

📄 Fonte: [`docs/diagrams/estados.mmd`](docs/diagrams/estados.mmd) · Entidade: **`SolicitacaoTransporte`** (agregado raiz)

- **Estado inicial** `[*]` → `RECEBIDA`.
- **Superestado composto** `EM_ANALISE`, com **3 regiões concorrentes** (subestados `VALIDANDO_HUBS → HUBS_AVALIADOS`, `VERIFICANDO_FROTA → FROTA_AVALIADA` e `CALCULANDO_ROTA → ROTA_AVALIADA`). É o equivalente, na máquina de estados, do Fork 2 / Join 2 das Atividades e do `par` da Sequência.
- **Estados terminais:** `ATENDIDA`, `REJEITADA`, `CANCELADA` e `NAO_ATENDIDA` (todos → `[*]`).
- **Ações internas** (`entry /`, `do /`, `exit /`) em `RECEBIDA`, `PENDENTE_ROTA` (entry e exit), `PRIORIZADA`, `EM_ATENDIMENTO` (entry e do) e nos quatro terminais.
- **Sintaxe formal `Gatilho [Guarda] / Efeito()`** em todas as transições externas. Exemplos:
  - `solicitacaoRecebida [token.valido E idExterno inédito] / registrarProtocolo()`
  - `analiseConcluida [erros.size == 0 E rota.valida == true] / calcularPrioridade()`
  - `backoffExpirado [tentativasRota ≥ 5] / registrarMotivo(ROTA_INDISPONIVEL)`
  - `cancelamentoRecebido [missao.status == PLANEJADA OU missao.status == AGUARDANDO_ALOCACAO] / cancelarMissao()`

```mermaid
%% Artefato 3 — Diagrama de Transição de Estados
%% Entidade de domínio: SolicitacaoTransporte (agregado raiz do contexto Integração Empresarial e Solicitação de Transporte)
%% Sintaxe das transições: Gatilho [CondiçãoDeGuarda] / AçãoDeEfeito()
%% EM_ANALISE é um superestado com 3 regiões concorrentes (equivalente ao Fork/Join do Diagrama de Atividades)
stateDiagram-v2
    direction TB

    state "RECEBIDA" as Recebida
    state "PENDENTE_ROTA" as PendenteRota
    state "PRIORIZADA" as Priorizada
    state "EM_ATENDIMENTO" as EmAtendimento
    state "ATENDIDA" as Atendida
    state "REJEITADA" as Rejeitada
    state "CANCELADA" as Cancelada
    state "NAO_ATENDIDA" as NaoAtendida

    Recebida : entry / gravarOutbox(SolicitacaoRecebida)
    PendenteRota : entry / agendarReprocessamento(backoff)
    PendenteRota : exit / incrementarTentativa()
    Priorizada : entry / registrarPrioridade()
    EmAtendimento : entry / notificarERP(ACEITA)
    EmAtendimento : do / acompanharMissao()
    Atendida : entry / notificarERP(ATENDIDA)
    Rejeitada : entry / notificarERP(REJEITADA)
    Cancelada : entry / notificarERP(CANCELADA)
    NaoAtendida : entry / notificarERP(NAO_ATENDIDA)

    [*] --> Recebida : solicitacaoRecebida [token.valido E idExterno inédito] / registrarProtocolo()
    Recebida --> EmAnalise : eventoConsumido [status == RECEBIDA] / iniciarAnalise()

    state "EM_ANALISE" as EmAnalise {
        state "VALIDANDO_HUBS" as ValidandoHubs
        state "HUBS_AVALIADOS" as HubsAvaliados
        state "VERIFICANDO_FROTA" as VerificandoFrota
        state "FROTA_AVALIADA" as FrotaAvaliada
        state "CALCULANDO_ROTA" as CalculandoRota
        state "ROTA_AVALIADA" as RotaAvaliada
        [*] --> ValidandoHubs
        ValidandoHubs --> HubsAvaliados : respostaHubs / registrarResultado()
        HubsAvaliados --> [*]
        --
        [*] --> VerificandoFrota
        VerificandoFrota --> FrotaAvaliada : respostaFrota / registrarResultado()
        FrotaAvaliada --> [*]
        --
        [*] --> CalculandoRota
        CalculandoRota --> RotaAvaliada : respostaRota / registrarResultado()
        RotaAvaliada --> [*]
    }

    EmAnalise --> Priorizada : analiseConcluida [erros.size == 0 E rota.valida == true] / calcularPrioridade()
    EmAnalise --> Rejeitada : analiseConcluida [erros.size > 0] / registrarMotivos()
    EmAnalise --> PendenteRota : analiseConcluida [erros.size == 0 E rota.valida == false] / registrarMotivo(SEM_ROTA)

    PendenteRota --> EmAnalise : backoffExpirado [tentativasRota < 5] / iniciarAnalise()
    PendenteRota --> Rejeitada : backoffExpirado [tentativasRota ≥ 5] / registrarMotivo(ROTA_INDISPONIVEL)

    Priorizada --> EmAtendimento : missaoCriada [missao.status == PLANEJADA] / vincularMissao()
    Priorizada --> Cancelada : cancelamentoRecebido [origem == sistemaOrigem] / registrarCancelamento()

    EmAtendimento --> Atendida : missaoConcluida [missao.status == CONCLUIDA] / registrarDesfecho()
    EmAtendimento --> Priorizada : missaoFalhou [tentativasMissao < 3] / desvincularMissao()
    EmAtendimento --> NaoAtendida : missaoFalhou [tentativasMissao ≥ 3] / registrarDesfecho()
    EmAtendimento --> Cancelada : cancelamentoRecebido [missao.status == PLANEJADA OU missao.status == AGUARDANDO_ALOCACAO] / cancelarMissao()

    Atendida --> [*]
    Rejeitada --> [*]
    Cancelada --> [*]
    NaoAtendida --> [*]

    classDef sucesso fill:#e8f5e9,stroke:#2e7d32,color:#1b5e20
    classDef erro fill:#ffebee,stroke:#c62828,color:#b71c1c
    classDef pausa fill:#fff8e1,stroke:#f9a825,color:#5d4037
    class Atendida sucesso
    class Rejeitada,Cancelada,NaoAtendida erro
    class PendenteRota pausa
```

---

## 6. Artefato 4 — Visão Arquitetural C4

📄 Fontes:
- [`docs/architecture/c4-containers.puml`](docs/architecture/c4-containers.puml): **C4-PlantUML**, Visão de Contêineres (Nível 2). É o artefato exigido.
- [`docs/architecture/workspace.dsl`](docs/architecture/workspace.dsl): **Structurizr DSL** (Models-as-Code) com o mesmo modelo, contendo a visão de Contêineres (N2) e a visão de **Componentes (N3) da API de Integração e Solicitações**. Validado com `structurizr-cli validate`.

Cada contêiner informa sua **tecnologia** (React 18, Kong 3.7, Keycloak 24, Java 21/Spring Boot 3.3, Python 3.12/FastAPI, PostgreSQL 16, PostGIS 3.4, RabbitMQ 3.13), e cada conector informa seu **protocolo** (HTTPS + HMAC, OAuth 2.0, OIDC JWKS, mTLS, gRPC/HTTP2, AMQP 0-9-1, JDBC, webhook HTTPS).

### C4 Nível 2 — Contêineres (C4-PlantUML)

![C4 Contêineres](docs/diagrams/img/c4-containers.png)

### C4 Nível 3 — Componentes da API de Integração e Solicitações (gerado a partir do `workspace.dsl`)

| Componente | Responsabilidade |
|---|---|
| `IntegracaoController` | Recebe `receberSolicitacao()` e valida a assinatura HMAC |
| `TradutorSolicitacaoACL` | Anti-Corruption Layer: traduz o formato do ERP para o modelo de domínio |
| `SolicitacaoService` | Registra a solicitação com idempotência e registra o desfecho da missão |
| `PlanejamentoService` | Faz a análise paralela, a priorização, a criação da missão e o reprocessamento |
| `PoliticaPriorizacao` | *Strategy* da Política de Priorização |
| `SolicitacaoRepository` | Persistência com lock otimista (`@Version`) e outbox |
| `OutboxRelay` | Publica no RabbitMQ os eventos gravados na outbox |
| `ErpNotifier` | Envia o webhook `receberStatus()` com retry e DLQ |

![C4 Componentes](docs/diagrams/img/c4-componentes-integracao.png)

---

## 7. Artefato 5 — ADR 0001

📄 [`docs/architecture/adr-0001.md`](docs/architecture/adr-0001.md)

**ADR 0001 — Recepção assíncrona de solicitações com Anti-Corruption Layer, idempotência e Transactional Outbox (202 Accepted + Webhook).** Status: **Aprovado**.

Em resumo, a recepção acontece em duas fases:
- **síncrona (menos de 200 ms):** autentica, traduz pela ACL, verifica a idempotência, grava com outbox e responde **202**;
- **assíncrona:** faz a análise paralela, a priorização e a criação da missão, e informa o resultado ao ERP por **webhook** com retry.

A decisão protege o domínio dos formatos externos, impede missões duplicadas e garante que nenhum evento se perca.

---

## 8. Matriz de consistência entre modelos

| # | Mensagem (Sequência) | Ação (Atividades) / Raia | Transição (Máquina de Estados) | Contêiner (C4) |
|---|---|---|---|---|
| 1 | `ERP→CTL receberSolicitacao()` | Enviar solicitação / ERP → Autenticar requisição / Integração | Gatilho `solicitacaoRecebida` (guarda `token.valido`) | ERP → Kong → API de Integração |
| 2 | `CTL→ACL traduzir()` + `alt violacoes` | Traduzir payload (ACL) + decisão "Payload válido?" | — (nenhum estado é criado se o *payload* for inválido) | API de Integração (`TradutorSolicitacaoACL`) |
| 3 | `SVC→REP buscarPorIdExterno()` + `alt` reenvio | Decisão "Solicitação já registrada?" | Guarda `[idExterno inédito]` da transição inicial | API de Integração → PostgreSQL 16 |
| 4 | `SVC→REP salvar(RECEBIDA + outbox)` | Persistir RECEBIDA + outbox | `[*] → RECEBIDA / registrarProtocolo()` · `entry / gravarOutbox()` | API de Integração → Banco de Solicitações |
| 5 | `CTL-->>ERP 202` + `SVC-)PLN processar()` | **Fork 1**: Registrar protocolo ‖ Publicar SolicitacaoRecebida | `RECEBIDA → EM_ANALISE : eventoConsumido` | Outbox → RabbitMQ → `PlanejamentoService` |
| 6 | `PLN→REP atualizarStatus(EM_ANALISE)` | Mudar solicitação para EM_ANALISE / Planejamento | Entrada no superestado `EM_ANALISE` | API de Integração → PostgreSQL 16 |
| 7 | `par` `validarHubs()` ‖ `verificarCompatibilidade()` ‖ `calcularRota()` | **Fork 2 / Join 2** / Serviços de Apoio | 3 regiões concorrentes de `EM_ANALISE` | API de Integração → Geolocalização e Orquestração (gRPC) |
| 8 | `Note consolidarAnalise()` + `alt` com 3 ramos | Consolidar análise + decisão "Resultado da análise?" | 3 transições `analiseConcluida [...]` | API de Integração |
| 9 | `PLN→PRI calcularPrioridade()` + `atualizarStatus(PRIORIZADA)` | Calcular prioridade + Mudar para PRIORIZADA | `EM_ANALISE → PRIORIZADA / calcularPrioridade()` | API de Integração (`PoliticaPriorizacao`) |
| 10 | `PLN→MIS criarMissao()` | Criar MissaoTransporte PLANEJADA / Orquestração | Gatilho `missaoCriada [missao.status == PLANEJADA]` | API de Integração → API de Orquestração (gRPC) |
| 11 | `PLN→REP vincularMissao()` | Vincular missão e mudar para EM_ATENDIMENTO | `PRIORIZADA → EM_ATENDIMENTO / vincularMissao()` | API de Integração → PostgreSQL 16 |
| 12 | `PLN-)NTF notificarStatus(ACEITA)` + `loop` `NTF→ERP receberStatus()` | **Fork 3**: Notificar ERP (ACEITA) ‖ Enfileirar missão | `EM_ATENDIMENTO : entry / notificarERP(ACEITA)` | RabbitMQ → `ErpNotifier` → ERP (webhook) |
| 13 | `else erros.size > 0` → `REJEITADA` + `notificarStatus(REJEITADA)` | Mudar para REJEITADA → Notificar ERP: REJEITADA | `EM_ANALISE → REJEITADA [erros.size > 0]` · `entry / notificarERP(REJEITADA)` | API de Integração → ERP |
| 14 | `else rota.valida == false` → `PENDENTE_ROTA` + `PLN-)PLN agendarReprocessamento()` | Mudar para PENDENTE_ROTA + decisão "Há tentativas restantes?" | `EM_ANALISE → PENDENTE_ROTA` · `PENDENTE_ROTA → EM_ANALISE [tentativasRota < 5]` | RabbitMQ (`solicitacoes.reprocessamento`) |
| 15 | `opt` `MIS-)SVC registrarDesfecho()` → `ATENDIDA` | (após o atendimento da missão) | `EM_ATENDIMENTO → ATENDIDA : missaoConcluida` | API de Orquestração → RabbitMQ → API de Integração |

---

## 9. Concorrência e proteção contra estados inválidos

| Risco | Mecanismo de proteção | Onde aparece nos modelos |
|---|---|---|
| O ERP reenvia a mesma ordem (timeout) e gera duas missões | Índice `UNIQUE (sistema_origem, id_externo)` + `buscarPorIdExterno()` antes de gravar. Se duas requisições chegarem ao mesmo tempo, a violação da chave única vira resposta **200** com o protocolo existente. | Sequência (`alt` reenvio) · Atividades (decisão) · Estados (guarda `idExterno inédito`) |
| Solicitação gravada, mas evento não publicado (ou o contrário) | **Transactional Outbox** + `OutboxRelay`. | Sequência (`salvar + outbox`) · Estados (`entry / gravarOutbox`) · C4 N3 · ADR |
| O mesmo evento é consumido duas vezes (AMQP entrega "pelo menos uma vez") | A guarda `[status == RECEBIDA]` em `eventoConsumido` faz o segundo consumo virar no-op. Lock otimista em `atualizarStatus(id, novo, versao)`. | Estados · Sequência (parâmetro `versao`) |
| As 3 validações paralelas gravam resultados ao mesmo tempo | Os resultados são agregados em memória (`CompletableFuture.allOf`) e há **uma única** transição `analiseConcluida` após o Join. Nenhuma região altera o status sozinha. | Atividades (Join 2) · Estados (regiões concorrentes → transição única) |
| Cancelamento do ERP chega durante a criação da missão | Lock otimista: a transação perdedora recebe `OptimisticLockException` e é reavaliada contra o novo estado. A guarda de `cancelamentoRecebido` só permite cancelar se a missão ainda não saiu da fila. | Estados (guardas de cancelamento) |
| Transição não prevista (ex.: `REJEITADA → PRIORIZADA`) | `SolicitacaoTransporte.transitar()` valida a tabela de transições e lança `TransicaoInvalidaException`. Estados terminais não têm transição de saída. | Estados · Interfaces (`transitar`) |
| Webhook do ERP fora do ar | Retry com *backoff* exponencial (5 tentativas) e depois DLQ + alerta ao operador. O status no banco não depende da entrega do webhook. | Sequência (`loop`) · ADR |
| Corredor bloqueado temporariamente | `PENDENTE_ROTA` com até 5 reprocessamentos antes de rejeitar. | Sequência · Atividades (laço) · Estados |

---

## 10. Estrutura do repositório e como renderizar

```
aps2-laura-rosa/
├── docs/
│   ├── architecture/
│   │   ├── workspace.dsl          <-- Structurizr DSL (C4 N2 + N3), validado
│   │   ├── c4-containers.puml     <-- C4-PlantUML (Visão de Contêineres)
│   │   └── adr-0001.md            <-- Registro de Decisão Arquitetural
│   └── diagrams/
│       ├── sequencia.mmd          <-- Mermaid — Diagrama de Sequência
│       ├── atividades.mmd         <-- Mermaid — Diagrama de Atividades
│       ├── atividades.puml        <-- PlantUML — Diagrama de Atividades (raias estritas)
│       ├── estados.mmd            <-- Mermaid — Máquina de Estados
│       ├── interfaces.mmd         <-- Mermaid — Contrato de operações públicas
│       └── img/                   <-- PNGs gerados a partir dos fontes acima
└── README.md
```

**Renderização:**

```bash
# Mermaid
npx -y @mermaid-js/mermaid-cli -i docs/diagrams/sequencia.mmd -o docs/diagrams/img/sequencia.png -b white

# PlantUML / C4-PlantUML (stdlib C4 já vem embutida no plantuml.jar)
java -jar plantuml.jar -tpng -o img docs/diagrams/atividades.puml
java -jar plantuml.jar -tpng -o ../diagrams/img docs/architecture/c4-containers.puml

# Structurizr DSL
structurizr-cli validate -workspace docs/architecture/workspace.dsl
structurizr-cli export   -workspace docs/architecture/workspace.dsl -format plantuml/c4plantuml
```

Todos os fontes foram compilados sem erros com Mermaid CLI 11.16, PlantUML 1.2024.7 e Structurizr CLI 2024.07.03.
