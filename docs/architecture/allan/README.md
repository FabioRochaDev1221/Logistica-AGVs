# Redistribuição de Missão por Falha de AGV

**APS 2 — Dossiê de Arquitetura Viva e Modelagem Comportamental as-Code**
Modelagem de Software · Engenharia de Software, 4º período · UniSenai
Aluno: Allan Camargo

## Sumário

1. [Problema](#1-problema)
2. [Objetivo da funcionalidade](#2-objetivo-da-funcionalidade)
3. [Contexto e escopo](#3-contexto-e-escopo)
4. [Regras de negócio e invariantes](#4-regras-de-negócio-e-invariantes)
5. [Contratos públicos dos serviços](#5-contratos-públicos-dos-serviços)
6. [Diagrama de sequência](#6-diagrama-de-sequência)
7. [Diagrama de atividades](#7-diagrama-de-atividades)
8. [Diagrama de estados](#8-diagrama-de-estados)
9. [Visão C4 de contêineres](#9-visão-c4-de-contêineres)
10. [Visão C4 de componentes](#10-visão-c4-de-componentes)
11. [Diagrama de classes e interfaces](#11-diagrama-de-classes-e-interfaces)
12. [ADR 0001](#12-adr-0001)
13. [Matriz de rastreabilidade](#13-matriz-de-rastreabilidade)
14. [Como visualizar e validar](#14-como-visualizar-e-validar)
15. [Considerações finais](#15-considerações-finais)

## 1. Problema

No parque industrial, os materiais são levados de um ponto a outro por AGVs (veículos guiados automaticamente). Cada transporte é uma `MissaoTransporte` atribuída a um único AGV.

Um AGV pode parar no meio do caminho por pane mecânica, bateria crítica ou perda de comunicação. Quando isso acontece, a entrega fica parada e alguém precisa assumir. O problema é fazer essa troca sem perder o histórico da missão original, sem deixar a entrega com dois AGVs ao mesmo tempo e sem mandar outro veículo buscar uma carga que ainda está em cima do AGV quebrado.

## 2. Objetivo da funcionalidade

Detectar a falha do AGV, encerrar a missão original como `Falha` e continuar a entrega numa **missão substituta**, com identidade própria e ligada à original, executada por outro AGV elegível.

A entidade principal é a `MissaoTransporte`. A transição crítica é **`Interrompida → Falha`**.

## 3. Contexto e escopo

**Dentro do escopo**

- detecção por telemetria e por timeout de heartbeat;
- política de tolerância antes de confirmar a falha;
- avaliação da política de redistribuição;
- seleção, reserva e despacho do AGV substituto;
- tratamento de carga embarcada, falta de candidatos e erro de comunicação;
- notificação do operador e auditoria.

**Fora do escopo**

- planejamento de rotas em si (o `RotaService` é tratado como caixa-preta que devolve viabilidade, distância e energia estimada);
- criação das missões originais e o fluxo normal de entrega;
- implementação do sistema. O trabalho é só de modelagem.

**Estrutura do repositório**

```text
docs/
├── adr/
│   └── 0001-redistribuicao-mensageria-rabbitmq.md   ADR da mensageria
└── architecture/
    └── allan/
        ├── README.md            este documento
        ├── sequencia.mmd        sequência (Mermaid)
        ├── atividades.puml      atividades com raias (fonte)
        ├── atividades.svg       atividades com raias (gerado)
        ├── estados.mmd          estados da MissaoTransporte (Mermaid)
        ├── c4-containers.puml   C4 nível 2 (fonte)
        ├── c4-containers.svg    C4 nível 2 (gerado)
        ├── c4-componentes.puml  C4 nível 3 do Serviço de Redistribuição (fonte)
        ├── c4-componentes.svg   C4 nível 3 (gerado)
        ├── classes.puml         classes e interfaces da redistribuição (fonte)
        └── classes.svg          classes e interfaces (gerado)
```

Os diagramas ficam em `docs/architecture/allan/` e as ADRs em `docs/adr/`, como o professor pediu para a avaliação final.

**Escolha das ferramentas**

| Diagrama | Ferramenta | Por quê |
|---|---|---|
| Sequência | Mermaid `sequenceDiagram` | O GitHub renderiza direto e tem `alt`, `loop`, `break`, `opt` e mensagem assíncrona. |
| Estados | Mermaid `stateDiagram-v2` | O GitHub renderiza direto e suporta estado composto e `<<choice>>`. |
| Atividades | PlantUML | O Mermaid não tem raias nem barra de Fork/Join. Por isso o arquivo é `.puml` e não `.mmd`. |
| C4 | C4-PlantUML | A biblioteca C4 já vem dentro do PlantUML (`!include <C4/C4_Container>`), então renderiza sem internet. O C4 do Mermaid ainda é experimental. |

Os arquivos PlantUML usam `!pragma layout smetana`, que é o layout interno do PlantUML, para não depender do Graphviz instalado.

## 4. Regras de negócio e invariantes

### Atores

| Ator | Responsabilidade |
|---|---|
| Operador logístico | Acompanha o painel, recebe alertas, confirma a transferência de carga e assume os casos que não podem ser redistribuídos. |
| AGV | Envia telemetria a cada 2 s, responde a pedidos de status e aceita ou recusa ordens de missão. |
| Sistema (serviços) | Detecta a falha, decide se redistribui, escolhe o substituto e mantém o estado das missões. |

### Entidades

| Entidade | O que guarda |
|---|---|
| `MissaoTransporte` | id, estado, AGV responsável, ponto de coleta, destino, peso, prazo, `cargaEmbarcada`, `cargaLiberada`, `missaoOrigemId` (só na substituta), `redistribuicoes` (quantas vezes a entrega já foi redistribuída), `comandoIdAtivo` da ordem enviada e `versao` para lock otimista. |
| `AGV` | id, estado (`DISPONIVEL`, `RESERVADO`, `EM_MISSAO`, `EM_FALHA`, `MANUTENCAO`), posição, bateria, capacidade, último heartbeat. |
| `ReservaAGV` | id, AGV, missão, status (`ATIVA`, `CONFIRMADA`, `LIBERADA`) e validade (30 s). |
| `EventoProcessado` | id do evento já tratado, para descartar repetições. |
| `RegistroAuditoria` | o que aconteceu com a missão original e a substituta, com horário e AGVs envolvidos. |

### Estados da `MissaoTransporte`

`Criada`, `AguardandoAtribuicao` (subestados `BloqueadaPorCarga`, `ProntaParaDespacho`, `SemCandidato`), `Atribuida`, `EmExecucao` (subestados `DeslocandoParaColeta`, `Carregando`, `EmTransporte`, `Descarregando`), `Interrompida`, `Falha`, `Concluida` e `Cancelada`.

`Falha`, `Concluida` e `Cancelada` são finais.

### Eventos

| Evento | Quem gera | Efeito principal |
|---|---|---|
| `agv.telemetria` | Gateway | Atualiza heartbeat e estado do AGV. |
| `missao.interrupcao-suspeita` | Monitoramento | `EmExecucao → Interrompida`. |
| `agv.recuperado` | Monitoramento | `Interrompida → EmExecucao` com o mesmo AGV. |
| `agv.falha-confirmada` | Monitoramento | `Interrompida → Falha` e início da redistribuição. |
| `missao.carga-liberada` | API de Missões | Substituta sai de `BloqueadaPorCarga`. |
| `missao.aceite` | Gateway | `Atribuida → EmExecucao` na substituta. |
| `missao.reavaliar` | Redistribuição | Nova tentativa de seleção depois de 60 s, ou depois que uma reserva vence. |

### Quando um AGV é considerado indisponível

- reportou `codigoFalha` na telemetria;
- ficou mais de 6 s sem heartbeat (3 ciclos perdidos) e não respondeu a 3 pedidos de status;
- está em `EM_FALHA` ou `MANUTENCAO`;
- já está `RESERVADO` ou `EM_MISSAO`.

### Política de redistribuição

A redistribuição só acontece se:

- a missão original estiver em `Falha`;
- a entrega não tiver sido cancelada;
- o prazo da entrega ainda não tiver vencido;
- a cadeia de missões dessa entrega tiver menos de 3 redistribuições (campo `redistribuicoes` da missão que falhou).

Se alguma condição falhar, a entrega vai para tratamento manual do operador.

### Elegibilidade e critério de seleção do substituto

Um AGV é elegível quando:

1. está `DISPONIVEL` e sem falha ativa;
2. a capacidade de carga é maior ou igual ao peso da missão;
3. o `RotaService` encontra rota viável até o ponto de coleta e depois até o destino;
4. a bateria cobre a energia estimada da rota com **20% de margem**.

Entre os elegíveis, a ordem é pelo menor ETA até o ponto de coleta. A reserva é feita no primeiro da lista que ainda estiver livre.

### Regra de continuidade

A missão original **não volta** a `EmExecucao` em outro AGV. Ela termina em `Falha`, e a entrega continua numa nova `MissaoTransporte` com id próprio e `missaoOrigemId` apontando para a original. Assim dá para saber, pelo histórico, que AGV fez qual parte da entrega.

O ponto de coleta da substituta depende de onde está a carga:

- carga ainda no ponto de coleta: a substituta usa o mesmo ponto de coleta;
- carga em cima do AGV que falhou: a substituta é criada com `cargaLiberada = false` e fica em `BloqueadaPorCarga` até o operador confirmar que a carga foi retirada ou transferida com segurança (`confirmarRecuperacaoCarga`).

Essa regra fica na classe `RegraContinuidade`, dentro do `MissaoService` (seção 11).

### Política de falhas e recuperação

| Situação | Tratamento |
|---|---|
| Queda curta de comunicação | Missão vai para `Interrompida`. Se o AGV responder bem dentro das 3 tentativas, volta para `EmExecucao` com o mesmo AGV. |
| Evento repetido do broker | `jaProcessado(eventoId)` devolve `true` e o evento é descartado. O evento só é marcado no fim (`marcarProcessado`), então um processamento interrompido é refeito. |
| Dois processos querendo o mesmo AGV | A reserva é um `UPDATE` condicional, com índice único de reserva ativa como garantia extra (ADR 0002). Quem perde tenta o próximo candidato. |
| Nenhum candidato elegível | Substituta fica em `SemCandidato`, operador é avisado e uma reavaliação é agendada para 60 s depois. |
| Erro ao enviar a ordem | O gateway reenvia até 3 vezes (MQTT QoS 1). Se não der, a tentativa conta como falha de despacho. |
| AGV não aceita em 30 s ou recusa | Reserva e atribuição são liberadas e o próximo candidato é tentado (até 3 tentativas). |
| Aceite chega depois do timeout | A reserva já foi liberada e o `comandoId` apagado, então `confirmarSeAtiva()` devolve `false` e o aceite é ignorado. |
| Serviço cai no meio do processo | O evento só recebe ack depois de gravado. Se cair antes, o RabbitMQ entrega de novo. Se cair com uma reserva ativa, ela vence em 30 s, o AGV volta a ficar disponível e a missão recebe `missao.reavaliar`. |

### Invariantes

| # | Invariante | Como é garantida |
|---|---|---|
| I1 | Uma entrega tem no máximo uma missão ativa (`Atribuida`, `EmExecucao` ou `Interrompida`) por vez. | A substituta só é criada depois que a original chega em `Falha`. |
| I2 | Um AGV tem no máximo uma reserva ou missão ativa. | `reservarSeDisponivel` com `UPDATE ... WHERE estado = 'DISPONIVEL'` e índice único parcial de reserva ativa (ADR 0002). |
| I3 | Missão em `Falha`, `Concluida` ou `Cancelada` não muda mais de estado. | Máquina de estados sem transição de saída e lock otimista na gravação. |
| I4 | Cada missão original tem no máximo uma substituta. | `UNIQUE(missao_origem_id)` e `buscarSubstitutaDe` antes de criar. |
| I5 | Substituta de missão com carga embarcada não é despachada sem confirmação do operador. | Subestado `BloqueadaPorCarga` só sai com `confirmarRecuperacaoCarga`. |
| I6 | O efeito de um evento é aplicado uma única vez. | Tabela de eventos processados, ack manual e operações idempotentes na API. |

## 5. Contratos públicos dos serviços

Toda mensagem do diagrama de sequência corresponde a uma operação desta seção, no serviço que recebe a mensagem.

### Serviços e operações

**`MonitoramentoAGVService`** (Serviço de Monitoramento)

| Operação | Retorno | Observação |
|---|---|---|
| `onTelemetria(TelemetriaDTO)` | `void` | Consumidor de `agv.telemetria`. |
| `verificarHeartbeats()` | `void` | Agendado a cada 2 s. |
| `listarAGVsAptos(FiltroAGVDTO)` | `AGVStatusDTO[]` | REST. |

**Serviço de Redistribuição** (componentes do C4 nível 3)

| Componente | Operação | Retorno | Observação |
|---|---|---|---|
| `ConsumidorEventos` | `receber(EventoMissao)` | `void` | Um `@RabbitListener` por fila. Chama `jaProcessado`, encaminha, chama `marcarProcessado` e faz o ack. |
| `RedistribuicaoService` | `onInterrupcaoSuspeita(InterrupcaoSuspeitaEvent)` | `void` | |
| `RedistribuicaoService` | `onAgvRecuperado(AgvRecuperadoEvent)` | `void` | Leva ao `retomarMissao`. |
| `RedistribuicaoService` | `onFalhaConfirmada(FalhaConfirmadaEvent)` | `void` | |
| `PoliticaRedistribuicao` | `avaliarPolitica(MissaoDTO)` | `DecisaoRedistribuicaoDTO` | |
| `ControleContinuidade` | `continuarEntrega(MissaoDTO)` | `void` | Assíncrono, recebe a substituta já gravada. |
| `ControleContinuidade` | `onCargaLiberada(CargaLiberadaEvent)` | `void` | |
| `ControleContinuidade` | `onAceiteMissao(AceiteMissaoDTO)` | `void` | |
| `ControleContinuidade` | `onReavaliar(ReavaliarMissaoEvent)` | `void` | Só tenta de novo se a missão ainda está em `AguardandoAtribuicao`. |
| `SelecaoAGVService` | `selecionarCandidatos(CriterioSelecaoDTO)` | `CandidatoDTO[]` | Ordenados por ETA. |
| `ReservaAGVService` | `reservarAGV(CandidatoDTO[], missaoId)` | `ReservaDTO` | Vazio se nenhum reservar. Se a missão já tem reserva ativa, devolve a mesma. |
| `ReservaAGVService` | `confirmarReserva(reservaId)` | `ReservaDTO` | `CONFIRMADA`, ou `LIBERADA` se a reserva já tinha vencido. |
| `ReservaAGVService` | `liberarReserva(reservaId)` | `void` | |
| `ReservaAGVService` | `liberarReservasVencidas()` | `void` | Agendado. Libera o AGV e publica `missao.reavaliar`. |

**`MissaoService`** (API de Gestão de Missões)

| Operação | Retorno | Observação |
|---|---|---|
| `criarMissao(NovaMissaoDTO)` | `MissaoDTO` | Fluxo normal, fora do escopo. |
| `enfileirarParaSelecao(missaoId)` | `MissaoDTO` | `Criada → AguardandoAtribuicao`. |
| `interromperMissao(missaoId, MotivoInterrupcaoDTO)` | `MissaoDTO` | `EmExecucao → Interrompida`. |
| `retomarMissao(missaoId)` | `MissaoDTO` | `Interrompida → EmExecucao`, mesmo AGV. |
| `registrarFalha(missaoId, FalhaDTO)` | `MissaoDTO` | `Interrompida → Falha`. |
| `criarMissaoSubstituta(missaoOrigemId)` | `MissaoDTO` | Idempotente. |
| `confirmarRecuperacaoCarga(missaoId, ConfirmacaoCargaDTO)` | `MissaoDTO` | Chamado pela Interface Web. |
| `atribuirAGV(missaoId, agvId, reservaId)` | `MissaoDTO` | `AguardandoAtribuicao → Atribuida`. Gera o `comandoId` da ordem. |
| `confirmarAceite(missaoId, AceiteMissaoDTO)` | `MissaoDTO` | `Atribuida → EmExecucao`. Idempotente. |
| `liberarAtribuicao(missaoId, motivo)` | `MissaoDTO` | `Atribuida → AguardandoAtribuicao`. |
| `marcarCargaEmbarcada(missaoId)` | `MissaoDTO` | `Carregando → EmTransporte`. |
| `cancelarMissao(missaoId, motivo)` | `MissaoDTO` | Gera o evento `cancelar` da máquina de estados. |

As operações de transição são idempotentes: se a missão já está no estado de destino, devolvem o estado atual sem gravar de novo. Se a versão mudou no meio (`salvar` com `versaoEsperada`), a operação lê a missão de novo e reavalia. Isso permite reprocessar um evento que voltou do broker.

**`RotaService`** (API de Gestão de Missões)

| Operação | Retorno |
|---|---|
| `calcularRota(origem, pontoColeta, destino)` | `RotaDTO` |

**`NotificacaoService`** (API de Gestão de Missões)

| Operação | Retorno | Observação |
|---|---|---|
| `notificarOperador(NotificacaoDTO)` | `void` | Push via WebSocket para a Interface Web. |

**`AGVGateway`** (Gateway de Comunicação)

| Operação | Retorno | Observação |
|---|---|---|
| `solicitarStatus(agvId, timeout)` | `StatusAGVDTO` | Devolve `SEM_RESPOSTA` no timeout. |
| `enviarOrdemMissao(OrdemMissaoDTO)` | `EnvioDTO` | Publica a ordem via MQTT QoS 1, com até 3 reenvios. |

**Mensagens MQTT entre AGV e Gateway** (não são operações de serviço, são tópicos do dispositivo)

| Sentido | Mensagem | Conteúdo |
|---|---|---|
| AGV → Gateway | `telemetria` | mesmo conteúdo do `TelemetriaDTO` |
| AGV → Gateway | `status` | resposta ao pedido de status |
| AGV → Gateway | `aceite(comandoId)` | aceite ou recusa da ordem |
| Gateway → AGV | `pedido de status` | pedido com timeout de 2 s |
| Gateway → AGV | `ordem de missão` | conteúdo do `OrdemMissaoDTO` |

**Repositórios**

| Repositório | Operação | Retorno |
|---|---|---|
| `MissaoRepository` | `salvar(missao, versaoEsperada)` | `MissaoTransporte` (falha se a versão mudou) |
| `MissaoRepository` | `buscarSubstitutaDe(missaoOrigemId)` | `MissaoTransporte` ou vazio |
| `AGVRepository` | `reservarSeDisponivel(reservaId, agvId, missaoId, ttl)` | `boolean` (ADR 0002) |
| `AGVRepository` | `confirmarSeAtiva(reservaId)` | `boolean` |
| `AGVRepository` | `liberar(reservaId)` | `void` |
| `AGVRepository` | `liberarVencidas(agora)` | `ReservaAGV[]` |
| `AGVRepository` | `buscarReservaAtiva(missaoId)` | `ReservaAGV` ou vazio |
| `EventoRepository` | `jaProcessado(eventoId)` | `boolean` |
| `EventoRepository` | `marcarProcessado(eventoId)` | `void` (`INSERT ... ON CONFLICT DO NOTHING`) |
| `EventoRepository` | `registrarAuditoria(AuditoriaDTO)` | `void` |

O broker só tem duas operações nos diagramas: `publicar(topico, evento [, atraso])` e `ack(evento)`. No Serviço de Redistribuição, o `publicar` passa pela interface `PublicadorEventos`.

### DTOs e eventos

| DTO | Campos principais |
|---|---|
| `TelemetriaDTO` | agvId, missaoId, timestamp, posicao, bateriaPct, cargaEmbarcada, codigoFalha? |
| `StatusAGVDTO` | agvId, situacao (`OPERACIONAL`, `COM_FALHA`, `SEM_RESPOSTA`), bateriaPct, posicao |
| `InterrupcaoSuspeitaEvent` | eventoId, missaoId, agvId, motivo (`FALHA_REPORTADA`, `HEARTBEAT_EXPIRADO`), detectadoEm |
| `FalhaConfirmadaEvent` | eventoId, missaoId, agvId, codigoFalha?, tentativasContato |
| `AgvRecuperadoEvent` | eventoId, missaoId, agvId, respondidoEm |
| `CargaLiberadaEvent` | eventoId, missaoId, operadorId |
| `ReavaliarMissaoEvent` | eventoId, missaoId, agendadoPara |
| `MotivoInterrupcaoDTO` | tipo, detectadoEm |
| `FalhaDTO` | codigoFalha?, origem (`AGV`, `HEARTBEAT`), confirmadaEm |
| `MissaoDTO` | id, estado, agvId, missaoOrigemId?, prazo, redistribuicoes, cargaEmbarcada, cargaLiberada, comandoId?, versao |
| `DecisaoRedistribuicaoDTO` | permitida, motivo |
| `CriterioSelecaoDTO` | missaoId, pontoColeta, destino, pesoKg, zona |
| `FiltroAGVDTO` | zona, estado |
| `AGVStatusDTO` | agvId, estado, posicao, bateriaPct, capacidadeKg |
| `RotaDTO` | viavel, distanciaM, energiaEstimadaPct, etaS |
| `CandidatoDTO` | agvId, etaS, rota |
| `ReservaDTO` | reservaId, agvId, missaoId, status, expiraEm |
| `OrdemMissaoDTO` | comandoId, missaoId, agvId, pontoColeta, destino |
| `EnvioDTO` | comandoId, enviadoEm |
| `AceiteMissaoDTO` | eventoId, comandoId, missaoId, agvId, aceito, respondidoEm |
| `ConfirmacaoCargaDTO` | operadorId, procedimento, confirmadoEm |
| `NotificacaoDTO` | tipo, severidade, missaoId, mensagem |
| `AuditoriaDTO` | missaoOrigemId, missaoSubstitutaId?, agvOriginal, agvSubstituto?, resultado |
| `NovaMissaoDTO` | pontoColeta, destino, pesoKg, prazo |

## 6. Diagrama de sequência

Fonte: [sequencia.mmd](sequencia.mmd)

O exemplo usado é a missão M-100, que estava com o AGV-07. Ele falha e a entrega passa para o AGV-12 através da substituta S-101. As caixas agrupam os participantes pelo contêiner onde rodam, o mesmo agrupamento da visão C4. Dentro do Serviço de Redistribuição, cada participante é um componente do C4 nível 3 (seção 10).

Notação usada:

- `->>` é chamada síncrona: quem chama espera a resposta;
- `-)` é mensagem assíncrona: evento no RabbitMQ ou MQTT, notificação sem esperar resposta, ou `continuarEntrega()`, que roda em outra thread;
- `-->>` é retorno, sempre com o DTO;
- `--)` é o ack para o broker.

Pontos que valem destacar:

- A missão passa por `Interrompida` antes de `Falha`. Uma queda rápida de rede não deve gerar redistribuição, por isso o `break` de falha transitória.
- Todo evento passa pelo `ConsumidorEventos`. Ele consulta `jaProcessado()` antes e chama `marcarProcessado()` só no fim, junto com o ack. Se o serviço cair no meio, o evento volta e é processado de novo. Isso funciona porque as operações chamadas na API são idempotentes (seção 5).
- A falha transitória gera o evento `agv.recuperado`, que leva ao `retomarMissao()`. Antes, a máquina de estados tinha o gatilho `agvRecuperado`, mas a sequência não mostrava quem chamava a operação.
- O ack do `FalhaConfirmadaEvent` só sai depois que a substituta foi gravada. Daí em diante, o `ControleContinuidade` conduz a S-101 a partir do estado dela no banco, não da mensagem.
- O `loop` de reserva com `opt reservado = false` mostra a disputa entre duas redistribuições pelo mesmo AGV (ADR 0002).
- No aceite, a reserva é confirmada antes da missão. Se a reserva já venceu, `confirmarSeAtiva()` devolve `false` e o aceite é tratado como atrasado. Assim, um AGV que já foi reservado para outra missão não começa a executar a S-101.

```mermaid
sequenceDiagram
    autonumber

    participant AGV1 as AGV-07 (original)
    participant AGV2 as AGV-12 (substituto)
    participant GW as AGVGateway
    participant BRK as Broker (RabbitMQ)
    box transparent Serviço de Monitoramento
        participant MON as MonitoramentoAGVService
    end
    box transparent Serviço de Redistribuição
        participant CON as ConsumidorEventos
        participant RED as RedistribuicaoService
        participant POL as PoliticaRedistribuicao
        participant CONT as ControleContinuidade
        participant SEL as SelecaoAGVService
        participant RES as ReservaAGVService
        participant AGVR as AGVRepository
        participant EREP as EventoRepository
    end
    box transparent API de Gestão de Missões
        participant MIS as MissaoService
        participant MREP as MissaoRepository
        participant ROT as RotaService
        participant NOT as NotificacaoService
    end
    participant WEB as Interface Web
    actor OP as Operador

    loop A cada 2 s enquanto M-100 está EmExecucao com AGV-07
        AGV1 -) GW: telemetria [MQTT, QoS 1]
        GW -) BRK: publicar("agv.telemetria", TelemetriaDTO)
        BRK -) MON: onTelemetria(TelemetriaDTO)
    end

    Note over AGV1: Pane mecânica, bateria crítica ou perda de rádio

    alt AGV reporta falha (TelemetriaDTO.codigoFalha preenchido)
        AGV1 -) GW: telemetria com codigoFalha [MQTT]
        GW -) BRK: publicar("agv.telemetria", TelemetriaDTO)
        BRK -) MON: onTelemetria(TelemetriaDTO)
    else Nenhum heartbeat há mais de 6 s (3 ciclos perdidos)
        MON ->> MON: verificarHeartbeats()
    end

    MON -) BRK: publicar("missao.interrupcao-suspeita", InterrupcaoSuspeitaEvent)
    BRK -) CON: InterrupcaoSuspeitaEvent
    CON ->>+ EREP: jaProcessado(eventoId)
    EREP -->>- CON: boolean processado
    alt processado = true (evento reentregue pelo broker)
        CON --) BRK: ack(InterrupcaoSuspeitaEvent) sem reprocessar
    else processado = false
        CON ->> RED: onInterrupcaoSuspeita(InterrupcaoSuspeitaEvent)
        RED ->>+ MIS: interromperMissao(M-100, MotivoInterrupcaoDTO)
        MIS ->>+ MREP: salvar(M-100, versaoEsperada)
        MREP -->>- MIS: MissaoTransporte [versao + 1]
        MIS -->>- RED: MissaoDTO [M-100, estado = Interrompida]
        RED -->> CON: void
        CON ->>+ EREP: marcarProcessado(eventoId)
        EREP -->>- CON: void
        CON --) BRK: ack(InterrupcaoSuspeitaEvent)
    end
    Note over CON,EREP: Todo evento consumido passa por jaProcessado(),<br/>marcarProcessado() e só então recebe ack

    Note over MON,GW: Tolerância: até 3 tentativas de contato, timeout de 2 s cada
    loop tentativa = 1..3, enquanto não houver resposta
        MON ->>+ GW: solicitarStatus(AGV-07, timeout = 2 s)
        GW -) AGV1: pedido de status [MQTT]
        alt AGV responde dentro do timeout
            AGV1 --) GW: status [MQTT]
            GW -->> MON: StatusAGVDTO [operacional ou com falha]
        else Timeout
            GW -->>- MON: StatusAGVDTO [SEM_RESPOSTA]
        end
    end

    break AGV respondeu operacional e sem falha (falha transitória)
        MON -) BRK: publicar("agv.recuperado", AgvRecuperadoEvent)
        BRK -) CON: AgvRecuperadoEvent
        CON ->> RED: onAgvRecuperado(AgvRecuperadoEvent)
        RED ->> MIS: retomarMissao(M-100)
        MIS -->> RED: MissaoDTO [M-100, estado = EmExecucao]
        Note over RED,MIS: Mesmo AGV retoma M-100, sem redistribuição
    end

    MON -) BRK: publicar("agv.falha-confirmada", FalhaConfirmadaEvent)
    BRK -) CON: FalhaConfirmadaEvent
    CON ->>+ EREP: jaProcessado(eventoId)
    EREP -->>- CON: boolean processado
    break processado = true (evento duplicado)
        CON --) BRK: ack(FalhaConfirmadaEvent) sem reprocessar
    end

    CON ->> RED: onFalhaConfirmada(FalhaConfirmadaEvent)
    RED ->>+ MIS: registrarFalha(M-100, FalhaDTO)
    MIS ->>+ MREP: salvar(M-100, versaoEsperada)
    MREP -->>- MIS: MissaoTransporte [versao + 1]
    MIS -->>- RED: MissaoDTO [M-100, estado = Falha, cargaEmbarcada]
    Note over MIS: AGV-07 perde a responsabilidade pela entrega

    RED ->>+ POL: avaliarPolitica(MissaoDTO)
    POL -->>- RED: DecisaoRedistribuicaoDTO
    break permitida = false (entrega cancelada, prazo expirado ou 3 redistribuições)
        RED ->> EREP: registrarAuditoria(AuditoriaDTO [sem redistribuição])
        RED -) NOT: notificarOperador(NotificacaoDTO [tratamento manual])
        NOT -) WEB: alerta [WebSocket]
        RED -->> CON: void
        CON ->> EREP: marcarProcessado(eventoId)
        CON --) BRK: ack(FalhaConfirmadaEvent)
    end

    RED ->>+ MIS: criarMissaoSubstituta(M-100)
    MIS ->>+ MREP: buscarSubstitutaDe(M-100)
    MREP -->>- MIS: vazio (ou S-101 já existente, devolvida sem criar outra)
    Note over MIS: RegraContinuidade cria S-101 com id próprio,<br/>missaoOrigemId = M-100 e cargaLiberada = false se a carga está no AGV-07
    MIS ->>+ MREP: salvar(S-101, versao 0)
    MREP -->>- MIS: MissaoTransporte [S-101]
    MIS -->>- RED: MissaoDTO [S-101, estado = AguardandoAtribuicao, missaoOrigemId = M-100]
    Note over MIS,MREP: UNIQUE(missao_origem_id): no máximo uma substituta por missão original
    RED -) CONT: continuarEntrega(MissaoDTO [S-101])
    RED -->> CON: void
    CON ->>+ EREP: marcarProcessado(eventoId)
    EREP -->>- CON: void
    CON --) BRK: ack(FalhaConfirmadaEvent)

    opt cargaLiberada = false (carga está fisicamente no AGV-07)
        CONT -) NOT: notificarOperador(NotificacaoDTO [recuperação de carga necessária])
        NOT -) WEB: alerta [WebSocket]
        WEB -->> OP: S-101 bloqueada até transferência segura
        OP ->> WEB: confirma transferência da carga
        WEB ->>+ MIS: confirmarRecuperacaoCarga(S-101, ConfirmacaoCargaDTO)
        MIS -->>- WEB: MissaoDTO [S-101, cargaLiberada = true]
        MIS -) BRK: publicar("missao.carga-liberada", CargaLiberadaEvent)
        BRK -) CON: CargaLiberadaEvent
        CON ->> CONT: onCargaLiberada(CargaLiberadaEvent)
    end

    loop tentativa de despacho = 1..3, até o aceite
        CONT ->>+ SEL: selecionarCandidatos(CriterioSelecaoDTO)
        SEL ->>+ MON: listarAGVsAptos(FiltroAGVDTO)
        MON -->>- SEL: AGVStatusDTO[] [DISPONIVEL, sem falha ativa]
        Note over SEL: Descarta AGV com capacidade menor que o peso
        loop para cada AGV restante (chamadas em paralelo)
            SEL ->>+ ROT: calcularRota(posicaoAGV, pontoColeta, destino)
            ROT -->>- SEL: RotaDTO [viavel, distancia, energiaEstimada]
        end
        Note over SEL: Descarta rota inviável ou bateria menor que energiaEstimada + 20%
        SEL -->>- CONT: CandidatoDTO[] ordenados por ETA

        CONT ->>+ RES: reservarAGV(CandidatoDTO[], S-101)
        loop para cada candidato, até obter a reserva
            RES ->>+ AGVR: reservarSeDisponivel(reservaId, agvId, S-101, ttl = 30 s)
            AGVR -->>- RES: boolean reservado
            opt reservado = false
                Note over RES,AGVR: Outro processo reservou o AGV antes, tenta o próximo
            end
        end
        RES -->>- CONT: ReservaDTO [AGV-12] ou vazio

        break ReservaDTO vazio (nenhum AGV elegível ou todos já reservados)
            CONT -) NOT: notificarOperador(NotificacaoDTO [sem AGV substituto])
            NOT -) WEB: alerta [WebSocket]
            CONT -) BRK: publicar("missao.reavaliar", ReavaliarMissaoEvent [S-101], atraso = 60 s)
        end

        CONT ->>+ MIS: atribuirAGV(S-101, AGV-12, reservaId)
        MIS ->>+ MREP: salvar(S-101, versaoEsperada)
        MREP -->>- MIS: MissaoTransporte [versao + 1]
        MIS -->>- CONT: MissaoDTO [S-101, estado = Atribuida, comandoId]

        CONT ->>+ GW: enviarOrdemMissao(OrdemMissaoDTO [comandoId])
        GW -->>- CONT: EnvioDTO [comandoId]
        loop reenvio enquanto não houver PUBACK do AGV (máx. 3)
            GW -) AGV2: ordem de missão S-101 [MQTT, QoS 1]
        end

        alt AGV-12 aceita em até 30 s
            AGV2 -) GW: aceite(comandoId) [MQTT]
            GW -) BRK: publicar("missao.aceite", AceiteMissaoDTO)
            BRK -) CON: AceiteMissaoDTO
            CON ->> CONT: onAceiteMissao(AceiteMissaoDTO)
            CONT ->>+ RES: confirmarReserva(reservaId)
            RES ->>+ AGVR: confirmarSeAtiva(reservaId)
            AGVR -->>- RES: boolean confirmada
            RES -->>- CONT: ReservaDTO [CONFIRMADA]
            CONT ->>+ MIS: confirmarAceite(S-101, AceiteMissaoDTO)
            MIS -->>- CONT: MissaoDTO [S-101, estado = EmExecucao]
        else Recusa, timeout de aceite ou erro de comunicação
            CONT ->>+ MIS: liberarAtribuicao(S-101, motivo)
            MIS -->>- CONT: MissaoDTO [S-101, estado = AguardandoAtribuicao]
            CONT ->>+ RES: liberarReserva(reservaId)
            RES -->>- CONT: void
            Note over CONT: Aceite que chegar depois é descartado:<br/>a reserva já foi liberada e o comandoId apagado
        end
    end

    alt S-101 em EmExecucao
        CONT ->>+ EREP: registrarAuditoria(AuditoriaDTO [M-100 para S-101, AGV-07 para AGV-12])
        EREP -->>- CONT: void
        CONT -) NOT: notificarOperador(NotificacaoDTO [missão redistribuída])
        NOT -) WEB: atualização [WebSocket]
        WEB -->> OP: painel mostra M-100 em Falha e S-101 em execução
    else 3 tentativas sem aceite
        CONT ->>+ EREP: registrarAuditoria(AuditoriaDTO [redistribuição sem sucesso])
        EREP -->>- CONT: void
        CONT -) NOT: notificarOperador(NotificacaoDTO [tratamento manual de S-101])
        NOT -) WEB: alerta [WebSocket]
    end
```

## 7. Diagrama de atividades

Fonte: [atividades.puml](atividades.puml) · imagem gerada: [atividades.svg](atividades.svg)

![Diagrama de atividades da redistribuição](atividades.svg)

O diagrama tem quatro raias: AGV / Comunicação, Monitoramento e Detecção, Gestão de Missões e Operador. Separei o Operador numa raia própria porque ele participa de verdade do fluxo: é quem libera a carga embarcada.

Os três pares de Fork/Join foram usados só onde as atividades realmente rodam ao mesmo tempo:

1. **Interromper a missão || tentar contato com o AGV.** São serviços diferentes reagindo ao mesmo evento. O Join é obrigatório porque a decisão "retomar ou falhar" precisa da missão já em `Interrompida` e do resultado das tentativas.
2. **Avaliação de cada candidato.** A avaliação de um AGV não depende da avaliação de outro, então as chamadas ao `RotaService` podem ser feitas ao mesmo tempo. O diagrama mostra o candidato 1 e o candidato N, mas é um ramo por AGV listado. Dentro de cada ramo a ordem é fixa: a bateria só pode ser verificada depois da rota, porque depende da energia estimada. A capacidade é verificada antes do Fork, porque é local e evita calcular rota para um AGV que não carrega o peso. O Join é necessário porque a ordenação por ETA precisa de todos os resultados.
3. **Registrar auditoria || notificar operador.** As duas são independentes. A notificação já é assíncrona no diagrama de sequência.

As decisões têm guardas `[sim]`/`[não]` sobre uma mesma condição, então são mutuamente exclusivas. A escolha do candidato e a reserva ficam dentro de um mesmo `repeat`, com no máximo 3 tentativas de despacho, igual ao `loop` da sequência.

Na versão anterior, o segundo Fork colocava "calcular rota" em paralelo com "verificar bateria e capacidade". Isso estava errado, porque a verificação da bateria usa a energia estimada que vem da rota. Separei a capacidade (antes do Fork) da bateria (depois da rota, no mesmo ramo).

As raias são responsabilidades, não contêineres. "Gestão de Missões" junta o que o Serviço de Redistribuição e a API fazem com a missão. Os nomes das operações em cada ação são os mesmos da sequência e do diagrama de classes.

## 8. Diagrama de estados

Fonte: [estados.mmd](estados.mmd)

```mermaid
stateDiagram-v2
    direction TB

    [*] --> Criada : criarMissao() ou criarMissaoSubstituta()
    Criada --> AguardandoAtribuicao : publicar [dados de coleta e destino válidos] / enfileirarParaSelecao()
    Criada --> Cancelada : cancelar / registrarAuditoria()

    state AguardandoAtribuicao {
        state origemCarga <<choice>>
        state "ProntaParaDespacho" as ProntaParaDespacho
        ProntaParaDespacho : entry / selecionarCandidatos()
        [*] --> origemCarga
        origemCarga --> BloqueadaPorCarga : [missaoOrigem.cargaEmbarcada]
        origemCarga --> ProntaParaDespacho : [sem carga embarcada na origem]
        BloqueadaPorCarga --> ProntaParaDespacho : cargaLiberada [operador confirmou] / confirmarRecuperacaoCarga()
        ProntaParaDespacho --> SemCandidato : reservaVazia / notificarOperador()
        SemCandidato --> ProntaParaDespacho : reavaliar [após 60 s]
    }

    AguardandoAtribuicao --> Atribuida : agvReservado [reservarSeDisponivel() = true] / atribuirAGV()
    AguardandoAtribuicao --> Cancelada : cancelar / registrarAuditoria()

    state "Atribuida" as Atribuida
    Atribuida : entry / enviarOrdemMissao()
    Atribuida : do / aguardar aceite (30 s)
    Atribuida --> EmExecucao : aceiteRecebido [comandoId válido] / confirmarReserva()
    Atribuida --> AguardandoAtribuicao : recusa ou timeoutAceite / liberarAtribuicao(), liberarReserva()

    state EmExecucao {
        [*] --> DeslocandoParaColeta
        DeslocandoParaColeta --> Carregando : chegouNaColeta
        Carregando --> EmTransporte : cargaEmbarcada / marcarCargaEmbarcada()
        EmTransporte --> Descarregando : chegouNoDestino
        Descarregando --> [*] : cargaEntregue
    }

    EmExecucao --> Concluida : entregaConfirmada / registrarAuditoria()
    EmExecucao --> Interrompida : interrupcaoSuspeita [evento novo] / interromperMissao()

    state "Interrompida" as Interrompida
    Interrompida : entry / suspender comandos ao AGV
    Interrompida : do / solicitarStatus() até 3 vezes
    Interrompida --> EmExecucao : agvRecuperado [mesmo AGV e sem falha] / retomarMissao()
    Interrompida --> Falha : falhaConfirmada [3 tentativas sem resposta ou codigoFalha] / registrarFalha()
    Interrompida --> Cancelada : cancelar [operador] / registrarAuditoria()

    state "Falha" as Falha
    Falha : entry / liberar AGV original da responsabilidade
    Falha : exit / avaliarPolitica() e criarMissaoSubstituta()

    Concluida --> [*]
    Cancelada --> [*]
    Falha --> [*]

    note right of Falha
        Estado final da missão original.
        Não existe transição de Falha para EmExecucao.
        A entrega continua numa missão nova
        com id próprio e missaoOrigemId apontando para esta.
    end note

    note left of Atribuida
        Toda transição grava com lock otimista
        (salvar com versaoEsperada).
        Evento fora de ordem ou de um estado
        que não aceita ele é rejeitado.
    end note
```

A transição crítica é:

```text
Interrompida --> Falha : falhaConfirmada [3 tentativas sem resposta ou codigoFalha] / registrarFalha()
```

O evento é o `FalhaConfirmadaEvent`. A guarda garante que a tolerância foi esgotada ou que o próprio AGV reportou a falha. O efeito grava a falha com lock otimista. O `entry` de `Falha` libera o AGV original da responsabilidade, e o `exit` dispara a política e a criação da substituta.

Algumas decisões do modelo:

- **`Falha` é final.** Não existe `Falha → EmExecucao`. Se existisse, a mesma missão poderia ficar com dois AGVs ao longo do tempo e o histórico se perderia (regra de continuidade).
- **A substituta começa em `Criada`** pelo mesmo caminho de qualquer missão. Dentro de `AguardandoAtribuicao`, o `<<choice>>` manda para `BloqueadaPorCarga` quando a origem estava com carga embarcada.
- **`Interrompida → EmExecucao`** só vale para o mesmo AGV (`[mesmo AGV e sem falha]`). É a única volta permitida.
- **Transições de exceção:** recusa ou timeout de aceite (`Atribuida → AguardandoAtribuicao`), interrupção, falha e cancelamento.
- **Proteção contra transições inválidas:** o serviço só aplica um evento se existir transição saindo do estado atual, e a gravação com `versaoEsperada` rejeita eventos que chegaram fora de ordem.

O Mermaid não aceita `entry`/`do`/`exit` em estado composto. Por isso as ações internas ficam nos estados simples: `Atribuida`, `Interrompida`, `Falha` e `ProntaParaDespacho`.

## 9. Visão C4 de contêineres

Fonte: [c4-containers.puml](c4-containers.puml) · imagem gerada: [c4-containers.svg](c4-containers.svg)

![Visão C4 de contêineres](c4-containers.svg)

| Contêiner | Tecnologia | Responsabilidade |
|---|---|---|
| Interface Web de Monitoramento | React, TypeScript | Painel do operador. Recebe alertas por WebSocket. |
| API de Gestão de Missões | Java 21, Spring Boot | Ciclo de vida da missão. Módulos `MissaoService`, `RotaService`, `NotificacaoService`. |
| Serviço de Monitoramento de AGVs | Java 21, Spring Boot | Telemetria, heartbeat e confirmação de falha. |
| Serviço de Redistribuição | Java 21, Spring Boot | Política, seleção, reserva e despacho. |
| Gateway de Comunicação | Node.js, servidor MQTT (Aedes) | Conexão MQTT com os AGVs e tradução para eventos internos. |
| Broker de Mensagens | RabbitMQ 3.13 | Filas duráveis, ack manual, dead-letter e mensagem com atraso. |
| Banco de Dados | PostgreSQL 16 | Missões, AGVs e reservas, eventos processados e auditoria. |

Sobre o que virou contêiner e o que ficou como módulo:

- **`RotaService` e `NotificacaoService`** são módulos da API. Não têm carga nem ciclo de deploy próprios, então não justificam processo separado.
- **Monitoramento** é separado porque recebe telemetria de toda a frota a cada 2 s e precisa escalar sem afetar a API.
- **Redistribuição** é separada porque é um consumidor de eventos que pode ter várias réplicas na mesma fila. Se cair, os eventos esperam no broker, e a API continua atendendo o operador.
- **Gateway** isola o protocolo dos AGVs. Os serviços Java falam só AMQP e REST.

Protocolos: HTTPS/REST entre a Web e a API e entre os serviços; WebSocket para notificações; MQTT sobre TLS (QoS 1) entre os AGVs e o Gateway; AMQP com o RabbitMQ; JDBC com o PostgreSQL.

## 10. Visão C4 de componentes

Fonte: [c4-componentes.puml](c4-componentes.puml) · imagem gerada: [c4-componentes.svg](c4-componentes.svg)

![Visão C4 de componentes do Serviço de Redistribuição](c4-componentes.svg)

É o zoom no contêiner Serviço de Redistribuição da visão de contêineres. Os contêineres em volta (Broker, Banco, API, Monitoramento e Gateway) são os mesmos da seção 9, com os mesmos nomes e tecnologias. Nenhum contêiner ou tecnologia nova foi criada.

| Componente | Responsabilidade | Na sequência |
|---|---|---|
| `ConsumidorEventos` | Recebe os eventos do RabbitMQ, descarta os já processados (`jaProcessado`) e só faz o ack depois de `marcarProcessado`. | `CON` |
| `RedistribuicaoService` | Trata a missão original: interrompe, retoma, registra a falha, aplica a política e pede a substituta. | `RED` |
| `PoliticaRedistribuicao` | `avaliarPolitica()`: missão em `Falha`, entrega não cancelada, prazo válido e menos de 3 redistribuições. | `POL` |
| `ControleContinuidade` | Leva a substituta até o aceite: espera a carga ser liberada, faz até 3 tentativas de despacho e agenda a reavaliação. | `CONT` |
| `SelecaoAGVService` | Elegibilidade (capacidade, rota, bateria com 20% de margem) e ordenação por ETA. | `SEL` |
| `ReservaAGVService` | Reserva, confirmação e liberação do AGV. Libera reservas vencidas. | `RES` |
| `AGVRepository` | Reserva atômica no PostgreSQL (`reservarSeDisponivel`, `confirmarSeAtiva`). | `AGVR` |
| `EventoRepository` | Eventos processados e auditoria. | `EREP` |
| `PublicadorEventos` | Publica `missao.reavaliar` com atraso. | `CONT -) BRK` |
| Clientes REST | Implementam as interfaces `MissaoService`, `RotaService`, `NotificacaoService`, `MonitoramentoAGVService` e `AGVGateway`. | setas para `MIS`, `ROT`, `NOT`, `MON` e `GW` |

Por que a divisão ficou assim:

- **Um consumidor só para todos os eventos.** Na ADR 0001, um dos riscos era um consumidor novo esquecer de verificar se o evento já foi processado. Com o `ConsumidorEventos` na frente, todo evento passa pelo mesmo controle antes de chegar na regra de negócio.
- **Seleção separada da reserva.** A seleção só lê e pode trabalhar com dados um pouco atrasados. A reserva é a única parte que grava o estado do AGV, então é ali que fica o controle de concorrência (ADR 0002).
- **`RedistribuicaoService` separado do `ControleContinuidade`.** O primeiro termina quando a substituta está gravada e o evento de falha recebe ack. O segundo cuida da substituta, que pode ficar minutos esperando a carga ser liberada ou um AGV ficar livre.
- **A `RegraContinuidade` fica na API.** Quem grava a `MissaoTransporte` e garante `UNIQUE(missao_origem_id)` é o `MissaoService`. O Serviço de Redistribuição só pede `criarMissaoSubstituta()`.

## 11. Diagrama de classes e interfaces

Fonte: [classes.puml](classes.puml) · imagem gerada: [classes.svg](classes.svg)

![Diagrama de classes e interfaces da redistribuição](classes.svg)

Cada pacote é um contêiner do C4. O diagrama mostra só o que a redistribuição usa. Os campos de cada DTO estão na seção 5.

**Onde usei interface e onde não usei**

- **Nas fronteiras entre serviços:** `MissaoService`, `RotaService`, `NotificacaoService`, `MonitoramentoAGVService` e `AGVGateway`. O Serviço de Redistribuição depende só da interface, e quem implementa do lado dele é o componente Clientes REST. Se a forma de chamar outro serviço mudar, a regra de negócio não muda.
- **Na persistência e no broker:** `AGVRepository`, `EventoRepository`, `MissaoRepository` e `PublicadorEventos`. A lógica não depende do SQL nem do `RabbitTemplate`.
- **`PoliticaRedistribuicao`, `ControleContinuidade`, `SelecaoAGVService` e `ReservaAGVService` são classes concretas.** Cada uma tem uma implementação só, e uma interface ali não diminuiria o acoplamento. Pelo mesmo motivo não usei Strategy para a política.

**Relacionamentos**

- `-->` associação: o serviço guarda uma referência para outro objeto do mesmo contêiner (injeção de dependência).
- `..>` dependência: uso de uma interface de outro contêiner ou criação de um objeto (`RegraContinuidade` cria a substituta).
- `..|>` realização: `MissaoServiceImpl` implementa `MissaoService`.
- `<|--` herança: todos os eventos estendem `EventoMissao`, que tem o `eventoId` usado para descartar repetições.

**Multiplicidades**

- `MissaoTransporte` origem `0..1` com `0..1` substituta: uma missão tem no máximo uma substituta (I4), e a primeira missão da entrega não tem origem.
- `AGV` `1` com `0..*` `ReservaAGV`, e `MissaoTransporte` `1` com `0..*` `ReservaAGV`: cada tentativa de despacho gera uma reserva, mas só uma pode estar `ATIVA` ou `CONFIRMADA` por AGV e por missão (I2, ADR 0002).
- `MissaoTransporte` `0..*` com `0..1` `AGV`: a missão só tem AGV depois de `atribuirAGV()`.

**Visibilidade e regras na própria classe**

- Os atributos das entidades são privados. O estado só muda pelos métodos (`interromper`, `registrarFalha`, `atribuir`...), que conferem se a transição existe na máquina de estados. Não existe método que tire uma missão de `Falha`, e `estaEncerrada()` devolve `true` para `Falha`, `Concluida` e `Cancelada`.
- A `RegraContinuidade` só aceita uma original em `Falha`. A substituta recebe id próprio, `missaoOrigemId`, `redistribuicoes + 1` e `cargaLiberada = false` quando a carga estava no AGV que falhou. Isso é o que coloca a substituta em `BloqueadaPorCarga`.
- `atribuir()` gera o `comandoIdAtivo`, que vai na ordem para o AGV. `liberarAtribuicao()` apaga esse valor, por isso um aceite atrasado não encontra o comando.
- Eventos e DTOs têm campos públicos porque só carregam dados.

**Métodos da sequência e onde estão**

| Mensagem no diagrama de sequência | Classe ou interface |
|---|---|
| `onTelemetria`, `verificarHeartbeats`, `listarAGVsAptos` | `MonitoramentoAGVService` |
| `solicitarStatus`, `enviarOrdemMissao` | `AGVGateway` |
| `jaProcessado`, `marcarProcessado`, `registrarAuditoria` | `EventoRepository` |
| `onInterrupcaoSuspeita`, `onAgvRecuperado`, `onFalhaConfirmada` | `RedistribuicaoService` |
| `avaliarPolitica` | `PoliticaRedistribuicao` |
| `continuarEntrega`, `onCargaLiberada`, `onAceiteMissao` | `ControleContinuidade` |
| `selecionarCandidatos` | `SelecaoAGVService` |
| `reservarAGV`, `confirmarReserva`, `liberarReserva` | `ReservaAGVService` |
| `reservarSeDisponivel`, `confirmarSeAtiva` | `AGVRepository` |
| `interromperMissao`, `retomarMissao`, `registrarFalha`, `criarMissaoSubstituta`, `confirmarRecuperacaoCarga`, `atribuirAGV`, `confirmarAceite`, `liberarAtribuicao` | `MissaoService` |
| `salvar`, `buscarSubstitutaDe` | `MissaoRepository` |
| `calcularRota` | `RotaService` |
| `notificarOperador` | `NotificacaoService` |
| `publicar("missao.reavaliar", ...)` | `PublicadorEventos` |
| `publicar(...)` do Monitoramento, do Gateway e da API, e `ack(...)` | operações do RabbitMQ, fora do Serviço de Redistribuição |

As mensagens MQTT entre o AGV e o Gateway (`telemetria`, `status`, `aceite`, `ordem de missão`) são tópicos do dispositivo e não viram métodos.

## 12. ADR 0001

Documento completo: [docs/adr/0001-redistribuicao-mensageria-rabbitmq.md](../../adr/0001-redistribuicao-mensageria-rabbitmq.md)

**Decisão:** usar RabbitMQ (AMQP) entre os serviços e MQTT/TLS só entre os AGVs e o Gateway, com filas duráveis e ack manual depois da gravação no banco.

A entrega das mensagens é **pelo menos uma vez**, não exatamente uma vez. O efeito único é obtido no banco com cinco mecanismos que aparecem nos diagramas: deduplicação por `eventoId`, lock otimista na missão, `UNIQUE(missao_origem_id)`, reserva por `UPDATE` condicional e `comandoId` para descartar aceite atrasado.

Alternativas descartadas: REST síncrono com polling (perde eventos quando um serviço cai), Kafka (pesado de operar para esse tamanho de frota e sem dead-letter e reentrega com atraso nativos) e um broker MQTT para tudo (sem fila durável por consumidor com ack manual).

As principais consequências são a consistência eventual no painel, o RabbitMQ como ponto crítico (precisa de cluster) e a limpeza periódica da tabela de eventos processados.

## 13. Matriz de rastreabilidade

| Passo / evento | Operação | Sequência | Atividades | Estados | C4 | ADR |
|---|---|---|---|---|---|---|
| Telemetria e heartbeat | `onTelemetria`, `verificarHeartbeats` | `loop` inicial e `alt` de detecção | `repeat` na raia Monitoramento | `EmExecucao` | AGVs → Gateway → Broker → Monitoramento | MQTT só na ponta |
| Interrupção suspeita | `interromperMissao` | `alt novo = true` | 1º Fork, ramo Gestão | `EmExecucao → Interrompida` | Monitoramento → Broker → Redistribuição → API | ack manual |
| Evento repetido | `registrarSeNovo` | `alt` / `break novo = false` | "evento já registrado?" | sem mudança de estado | Redistribuição → Banco | deduplicação por `eventoId` |
| Tolerância | `solicitarStatus` | `loop tentativa = 1..3` | 1º Fork, ramo Monitoramento | `do` de `Interrompida` | Monitoramento → Gateway | timeout de 2 s, 3 tentativas |
| Falha transitória | `retomarMissao` | `break` de falha transitória | "AGV respondeu operacional?" [sim] | `Interrompida → EmExecucao` | Redistribuição → API | |
| Falha confirmada | `registrarFalha` | após `FalhaConfirmadaEvent` | "Registrar falha da missão original" | **`Interrompida → Falha`** | Redistribuição → API → Banco | lock otimista |
| Política | `avaliarPolitica` | `break permitida = false` | "redistribuição permitida?" | `exit` de `Falha` | Serviço de Redistribuição | |
| Missão substituta | `criarMissaoSubstituta`, `buscarSubstitutaDe` | bloco da S-101 | "Criar missão substituta" | `[*] → Criada → AguardandoAtribuicao` | API → Banco | `UNIQUE(missao_origem_id)` |
| Carga embarcada | `confirmarRecuperacaoCarga`, `onCargaLiberada` | `opt cargaEmbarcada = true` | raia Operador | `BloqueadaPorCarga → ProntaParaDespacho` | Operador → Web → API → Broker | |
| Seleção | `listarAGVsAptos`, `calcularRota`, `selecionarCandidatos` | `loop` por AGV listado | 2º Fork/Join | `entry` de `ProntaParaDespacho` | Redistribuição → Monitoramento e API | |
| Reserva concorrente | `reservarAGV`, `reservarSeDisponivel` | `loop` com `opt reservado = false` | "Reservar ... UPDATE condicional" | `AguardandoAtribuicao → Atribuida` | Redistribuição → Banco | reserva por `UPDATE` condicional |
| Sem candidato | `notificarOperador`, `publicar(missao.reavaliar)` | `break ReservaDTO vazio` | "reserva obtida?" [não] | `ProntaParaDespacho ⇄ SemCandidato` | Redistribuição → Broker | reentrega com atraso |
| Despacho e erro de comunicação | `atribuirAGV`, `enviarOrdemMissao` | `loop reenvio` | `repeat` de reenvio na raia AGV | `entry` de `Atribuida` | Redistribuição → Gateway → AGVs | MQTT QoS 1 |
| Aceite | `onAceiteMissao`, `confirmarAceite`, `confirmarReserva` | `alt AGV-12 aceita` | "aceite recebido em até 30 s?" [sim] | `Atribuida → EmExecucao` | AGVs → Gateway → Broker → Redistribuição | `comandoId` |
| Recusa ou timeout | `liberarAtribuicao`, `liberarReserva` | `else` do aceite | "aceite recebido?" [não] | `Atribuida → AguardandoAtribuicao` | Redistribuição → API | aceite atrasado descartado |
| Resultado | `registrarAuditoria`, `notificarOperador` | `alt` final | 3º Fork/Join | estado final da S-101 | API → Web (WebSocket) | auditoria |

## 14. Como visualizar e validar

**No GitHub:** os blocos Mermaid deste README aparecem renderizados. Os diagramas PlantUML aparecem pelos SVGs gerados a partir dos `.puml`.

**Localmente**, com Node.js e Java 17 ou superior:

```bash
# Mermaid (sequência e estados)
npx -y @mermaid-js/mermaid-cli@11.4.2 -i docs/architecture/allan/sequencia.mmd -o /tmp/sequencia.svg
npx -y @mermaid-js/mermaid-cli@11.4.2 -i docs/architecture/allan/estados.mmd -o /tmp/estados.svg

# PlantUML (atividades e C4). Gera os .svg ao lado dos fontes
curl -sSL -o plantuml.jar https://github.com/plantuml/plantuml/releases/download/v1.2024.7/plantuml-1.2024.7.jar
java -jar plantuml.jar -tsvg -failfast2 docs/architecture/allan/atividades.puml docs/architecture/allan/c4-containers.puml
```

Os comandos terminam com código diferente de zero se houver erro de sintaxe. Não é preciso ter Graphviz, porque os `.puml` usam o layout `smetana`.

No VS Code também dá para ver usando as extensões *Markdown Preview Mermaid Support* e *PlantUML*.

Sempre que um `.puml` mudar, o `.svg` correspondente precisa ser gerado de novo e commitado junto.

## 15. Considerações finais

O ponto que mais influenciou a modelagem foi a regra de não reaproveitar a missão que falhou. Ela fez a máquina de estados ficar com `Falha` como estado final e obrigou a ter uma missão substituta com identidade própria, o que por sua vez trouxe a necessidade de garantir que só exista uma substituta por original.

A outra decisão importante foi aceitar que as mensagens podem chegar repetidas e resolver isso no banco, em vez de supor que o broker entrega exatamente uma vez. Por isso aparecem em todos os diagramas o controle de eventos processados (`jaProcessado` e `marcarProcessado`), o lock otimista e a reserva condicional.

Ficaram de fora coisas que seriam necessárias numa implementação real, como a limpeza da tabela de eventos processados, o cluster do RabbitMQ e o planejamento de rotas. Esses pontos estão registrados como consequências na ADR.
