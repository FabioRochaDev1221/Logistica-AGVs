@startuml C4_Component_Recarga_AGV
' =====================================================================
' Artefato 4 — Visão Arquitetural Macro C4 — Nível 3 (Componentes)
' Ferramenta: C4-PlantUML (Models-as-Code)
' Funcionalidade: Recarga Programada e Balanceamento de Frota
'
' Zoom no contêiner "API de Orquestração de Missões" (Node.js 20, NestJS),
' o mesmo contêiner da visão C4 Nível 2 do dossiê de Despacho.
'
' Observação: o arquivo segue o nome exigido na estrutura de entrega
' (workspace.dsl), mas o conteúdo é C4-PlantUML (.puml).
' Renderizar com:  java -jar plantuml.jar workspace.dsl
' =====================================================================

!include <C4/C4_Component>

LAYOUT_TOP_DOWN()

title API de Orquestração de Missões — Componentes de Recarga Programada e Balanceamento (C4 Nível 3)

' ---------- Pessoas e sistemas externos ----------
Person(supervisor, "Supervisor de Operações", "Ajusta parâmetros das políticas e acompanha a energia da frota.")
System_Ext(estacoes, "Estações de Recarga", "Carregadores industriais com controlador OPC UA (slots, corrente, temperatura).")

' ---------- Contêineres vizinhos (C4 Nível 2) ----------
Container(painel, "Painel de Monitoramento", "React 18, TypeScript", "SPA de operação e supervisão.")
Container(telemetria, "Serviço de Telemetria", "Node.js 20, MQTT.js", "Últimas leituras de bateria e séries temporais.")
Container(geo, "Serviço de Geolocalização", "Python 3.12, FastAPI, gRPC", "Posição dos AGVs e estações mais próximas.")
Container(agvgw, "AGV Gateway", "Go 1.22, gRPC", "Comandos ao firmware dos AGVs.")
ContainerDb(pg, "Banco Operacional", "PostgreSQL 16", "AGVs, missões, estações e sessões de recarga.")
ContainerDb(redis, "Redis", "Redis 7", "Filas BullMQ e travas de slot com TTL.")
ContainerQueue(rabbit, "Barramento de Eventos de Domínio", "RabbitMQ 3.13", "Exchange topic 'agv.dominio'.")

' ---------- Contêiner em foco ----------
Container_Boundary(api, "API de Orquestração de Missões (Node.js 20, NestJS)") {

    Component(politicaCtrl, "PoliticaEnergiaController", "NestJS REST Controller", "Consulta e ajuste dos parâmetros: limiares de bateria, mínimo operacional, alvo de carga.")

    Component(job, "AgendadorJobs / CicloRecargaWorker", "BullMQ Worker (repeatable job, 60 s)", "Dispara iniciarCicloPlanejamento(). Garante um único ciclo por vez com jobId deduplicado.")

    Component(listener, "BateriaCriticaListener", "NestJS + amqplib consumer", "Consome BateriaCriticaDetectada e antecipa o ciclo enfileirando um job imediato.")

    Component(planejador, "PlanejadorRecargaService", "NestJS Service", "Orquestra o ciclo: diagnóstico da frota, priorização, reserva de slot e comando de recarga.")

    Component(politica, "PoliticaRecarregamento", "Strategy (TypeScript)", "priorizarCandidatos(): classifica urgência OBRIGATORIA / OPORTUNIDADE e calcula score.")

    Component(balanceador, "BalanceadorFrotaService", "NestJS Service", "calcularCapacidadeFrota() e avaliarLiberacao(): mínimo operacional, vagas de recarga, liberação antecipada.")

    Component(estacaoSvc, "EstacaoRecargaService", "NestJS Service", "Reserva de slots, ciclo de vida da SessaoRecarga e recepção das leituras de carga.")

    Component(opcua, "OpcUaEstacaoAdapter", "node-opcua client", "Adaptador anticorrupção: iniciarCarga, pararCarga e subscription de leituras e acoplamento.")

    Component(frotaRepo, "FrotaRepository", "Prisma ORM", "listarAGVsOperacionais() e atualizarEstado().")

    Component(missaoRepo, "MissaoRepository", "Prisma ORM", "contarPendentes(janelaMin) para estimar a demanda.")

    Component(sessaoRepo, "SessaoRecargaRepository", "Prisma ORM", "Persistência das sessões e transições de estado da recarga.")

    Component(clients, "Clientes gRPC", "@grpc/grpc-js + Protobuf", "Stubs gerados para Telemetria, Geolocalização e AGV Gateway, com deadline de 2 s.")

    Component(publisher, "DomainEventPublisher", "amqplib (publisher confirms)", "Publica RecargaProgramada, RecargaAdiada, RecargaConcluida, AGVDisponibilizado.")
}

' ---------- Relações: supervisão ----------
Rel(supervisor, painel, "Ajusta políticas e acompanha a frota", "HTTPS")
Rel(painel, politicaCtrl, "GET/PUT /politicas/energia", "REST/JSON sobre HTTPS")
Rel(politicaCtrl, politica, "Atualiza parâmetros", "chamada local")

' ---------- Relações: disparo do ciclo ----------
Rel(job, redis, "Consome fila 'ciclo-recarga'", "RESP sobre TCP 6379")
Rel(rabbit, listener, "Entrega BateriaCriticaDetectada", "AMQP 0-9-1")
Rel(listener, redis, "Enfileira ciclo imediato (jobId deduplicado)", "RESP sobre TCP 6379")
Rel(job, planejador, "iniciarCicloPlanejamento(cicloId)", "chamada local assíncrona")

' ---------- Relações: diagnóstico e decisão ----------
Rel(planejador, frotaRepo, "listarAGVsOperacionais / atualizarEstado", "chamada local")
Rel(planejador, balanceador, "calcularCapacidadeFrota", "chamada local")
Rel(planejador, politica, "priorizarCandidatos", "chamada local")
Rel(balanceador, missaoRepo, "contarPendentes(30 min)", "chamada local")
Rel(planejador, clients, "obterUltimasLeituras / localizarEstacoesProximas / enviarParaRecarga", "chamada local")
Rel(planejador, estacaoSvc, "reservarSlot", "chamada local")
Rel(planejador, publisher, "RecargaProgramada / RecargaAdiada", "chamada local")

' ---------- Relações: execução da carga ----------
Rel(estacaoSvc, redis, "Trava de slot (SET NX PX)", "RESP sobre TCP 6379")
Rel(estacaoSvc, sessaoRepo, "Grava transições da SessaoRecarga", "chamada local")
Rel(estacaoSvc, opcua, "iniciarCarga / pararCarga", "chamada local")
Rel(estacaoSvc, balanceador, "avaliarLiberacao(agvId, nivelPct)", "chamada local")
Rel(estacaoSvc, frotaRepo, "atualizarEstado(DISPONIVEL)", "chamada local")
Rel(estacaoSvc, publisher, "RecargaConcluida / AGVDisponibilizado", "chamada local")
Rel(opcua, estacoes, "Métodos e subscriptions (leitura a cada 5 s)", "OPC UA Binary sobre TCP 4840, Security Policy Basic256Sha256")

' ---------- Relações: infraestrutura ----------
Rel(frotaRepo, pg, "Lê e grava AGVs", "SQL sobre TCP 5432")
Rel(missaoRepo, pg, "Lê missões pendentes", "SQL sobre TCP 5432")
Rel(sessaoRepo, pg, "Lê e grava sessões de recarga", "SQL sobre TCP 5432")
Rel(clients, telemetria, "obterUltimasLeituras", "gRPC / HTTP/2 (Protobuf)")
Rel(clients, geo, "localizarEstacoesProximas", "gRPC / HTTP/2 (Protobuf)")
Rel(clients, agvgw, "enviarParaRecarga", "gRPC / HTTP/2 (Protobuf)")
Rel(publisher, rabbit, "Publica eventos de domínio", "AMQP 0-9-1")

SHOW_LEGEND()
@enduml
