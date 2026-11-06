# Logística de AGVs: Redistribuição de Missão por Falha de AGV

> **APS 2 — Modelagem de Software** · Engenharia de Software · UniSenai
> **Docente:** Sidney L. da Silva · **Aluno:** Allan Camargo · **Branch:** `allan`
> **Projeto da equipe:** Sistema de Orquestração de Entregas Autônomas (Allan Camargo, Alyson Hian, Fabio Rocha, Laura Rosa, Jhonatan)

| | |
|---|---|
| **Funcionalidade crítica** | Redistribuição de missão quando o AGV falha durante a entrega |
| **Foco** | Política de Redistribuição e Regra de Continuidade |
| **Entidade de domínio principal** | `MissaoTransporte` |
| **Transição crítica** | `Interrompida → Falha` |
| **Abordagem** | Diagrams-as-Code (Mermaid e PlantUML) e Models-as-Code (C4-PlantUML), versionados no Git |

## Sobre a funcionalidade

Os AGVs transportam materiais entre pontos do parque industrial. Se um deles falha no meio de uma missão (pane, bateria crítica ou perda de comunicação), o sistema precisa perceber, confirmar que não foi só uma queda rápida de sinal e passar a entrega para outro AGV.

A regra principal é que a missão que falhou não é reaproveitada. Ela termina em `Falha`, e a entrega continua numa **missão substituta**, com id próprio e ligada à original pelo `missaoOrigemId`. Assim o histórico mostra o que cada AGV fez, e a entrega nunca fica com dois AGVs ao mesmo tempo.

Resumo do fluxo:

1. O Serviço de Monitoramento detecta a falha pela telemetria ou pela falta de heartbeat (mais de 6 s).
2. A missão vai para `Interrompida` e o sistema tenta falar com o AGV 3 vezes.
3. Sem resposta, a falha é confirmada e a missão vai para `Falha`.
4. Se a política permitir, é criada a missão substituta.
5. Se a carga estava em cima do AGV quebrado, o operador precisa confirmar a transferência antes do despacho.
6. Um AGV elegível (bateria, capacidade e rota) é reservado sem conflito com outras redistribuições e recebe a ordem.
7. Com o aceite do novo AGV, a substituta entra em execução e o operador é avisado.

## Dossiê de arquitetura

Toda a documentação está em [`aps2-allan-camargo/`](aps2-allan-camargo/). O README de lá traz as regras de negócio, os contratos dos serviços, os diagramas renderizados e a matriz de rastreabilidade.

| Artefato | Arquivo | Ferramenta |
|---|---|---|
| Documentação completa | [aps2-allan-camargo/README.md](aps2-allan-camargo/README.md) | Markdown |
| Diagrama de sequência | [sequencia.mmd](aps2-allan-camargo/docs/diagrams/sequencia.mmd) | Mermaid |
| Diagrama de atividades com raias | [atividades.puml](aps2-allan-camargo/docs/diagrams/atividades.puml) ([svg](aps2-allan-camargo/docs/diagrams/atividades.svg)) | PlantUML |
| Diagrama de estados da `MissaoTransporte` | [estados.mmd](aps2-allan-camargo/docs/diagrams/estados.mmd) | Mermaid |
| Visão C4 de contêineres | [container.puml](aps2-allan-camargo/docs/architecture/container.puml) ([svg](aps2-allan-camargo/docs/architecture/container.svg)) | C4-PlantUML |
| ADR 0001 (mensageria) | [adr-0001.md](aps2-allan-camargo/docs/architecture/adr-0001.md) | Markdown (Nygard) |

### Estrutura do repositório

```text
Logistica-AGVs/
├── aps2-allan-camargo/
│   ├── docs/
│   │   ├── architecture/
│   │   │   ├── adr-0001.md        Registro de decisão arquitetural
│   │   │   ├── container.puml     C4 nível 2 (fonte)
│   │   │   └── container.svg      C4 nível 2 (imagem gerada)
│   │   └── diagrams/
│   │       ├── sequencia.mmd      Diagrama de sequência
│   │       ├── atividades.puml    Diagrama de atividades (fonte)
│   │       ├── atividades.svg     Diagrama de atividades (imagem gerada)
│   │       └── estados.mmd        Máquina de estados da MissaoTransporte
│   └── README.md                  Documentação do dossiê
└── README.md                      Este arquivo
```

## Arquitetura em poucas palavras

- **Interface Web** (React/TypeScript) para o operador, com alertas por WebSocket.
- **API de Gestão de Missões**, **Serviço de Monitoramento** e **Serviço de Redistribuição** em Java 21/Spring Boot.
- **Gateway de Comunicação** (Node.js) falando MQTT/TLS com os AGVs.
- **RabbitMQ** para os eventos entre serviços, com ack manual e dead-letter.
- **PostgreSQL** para missões, reservas de AGV, eventos processados e auditoria.

A escolha da mensageria e o tratamento de mensagens repetidas estão justificados na [ADR 0001](aps2-allan-camargo/docs/architecture/adr-0001.md).

## Como visualizar

No GitHub, os diagramas Mermaid aparecem renderizados no [README do dossiê](aps2-allan-camargo/README.md), e os diagramas PlantUML aparecem pelos arquivos `.svg`. Os comandos para validar e gerar as imagens localmente estão na seção 12 do README do dossiê.
