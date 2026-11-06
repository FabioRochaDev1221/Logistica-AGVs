@startuml C4_Container_Despacho_AGV
' =====================================================================
' Artefato 4 — Visão Arquitetural Macro C4 — Nível 2 (Contêineres)
' Ferramenta: C4-PlantUML (Models-as-Code)
' Funcionalidade: Despacho de Rota com Checagem de Bateria
'                 e Sincronização de Telemetria
'
' Observação: o arquivo segue o nome exigido na estrutura de entrega
' (workspace.dsl), mas o conteúdo é C4-PlantUML (.puml).
' Renderizar com:  java -jar plantuml.jar workspace.dsl
' =====================================================================

!include <C4/C4_Container>

LAYOUT_TOP_DOWN()

title Plataforma de Orquestração de AGVs — Visão de Contêineres (C4 Nível 2)

' ---------- Pessoas ----------
Person(operador, "Operador Logístico", "Solicita o despacho de missões e acompanha a frota em tempo real.")
Person(supervisor, "Supervisor de Operações", "Recebe alertas operacionais e define prioridades.")

' ---------- Sistemas externos ----------
System_Ext(erp, "ERP / WMS / MES", "Sistemas corporativos que geram Solicitações de Transporte e recebem o status das missões.")
System_Ext(frota, "Frota de AGVs", "Veículos autônomos com firmware embarcado: bateria, navegação e sensores.")

' ---------- Sistema em foco ----------
System_Boundary(plataforma, "Plataforma de Orquestração de AGVs") {

    Container(painel, "Painel de Monitoramento", "React 18, TypeScript, Leaflet", "SPA para despacho de missões, mapa da frota em tempo real e alertas.")

    Container(api, "API de Orquestração de Missões", "Node.js 20, NestJS", "Núcleo de domínio: DespachoController, OrquestradorMissaoService, AlocacaoFrotaService e ReservaRotaService. Aplica a checagem de bateria antes do despacho.")

    Container(geo, "Serviço de Geolocalização", "Python 3.12, FastAPI, gRPC server", "Calcula rota, ETA e consumo estimado (Wh). Sincroniza posição e detecta desvios.")

    Container(agvgw, "AGV Gateway", "Go 1.22, gRPC", "Adaptador anticorrupção entre o domínio e o firmware: consulta bateria e envia comandos de rota e recarga.")

    Container(telemetria, "Serviço de Telemetria", "Node.js 20, MQTT.js", "Consome a telemetria dos AGVs, persiste séries temporais e publica TelemetriaSincronizada e BateriaCriticaDetectada.")

    Container(notificador, "Serviço de Notificações em Tempo Real", "Node.js 20, Socket.IO", "Consome eventos de domínio e faz push para o painel.")

    Container(integracao, "Adaptador de Integração Empresarial", "Java 21, Spring Boot", "Traduz pedidos do ERP/WMS/MES em Solicitações de Transporte e devolve o status das missões.")

    ContainerDb(pg, "Banco Operacional", "PostgreSQL 16", "Missões, AGVs, Hubs, Corredores Logísticos e histórico de rastreabilidade.")

    ContainerDb(tsdb, "Banco de Telemetria", "PostgreSQL 16 + TimescaleDB", "Séries temporais de posição, velocidade e nível de bateria.")

    ContainerDb(redis, "Cache de Reservas de Rota", "Redis 7", "Travas distribuídas com TTL dos trechos de corredor (SET NX PX).")

    ContainerQueue(rabbit, "Barramento de Eventos de Domínio", "RabbitMQ 3.13", "Exchange topic 'agv.dominio': MissaoIniciada, RotaReservada, BateriaCriticaDetectada, MissaoConcluida.")

    ContainerQueue(mqtt, "Broker de Telemetria", "EMQX 5 (MQTT 5)", "Tópicos agv/{id}/telemetria com QoS 1. Recebe uma mensagem a cada 500 ms por AGV.")
}

' ---------- Relações: usuários ----------
Rel(operador, painel, "Despacha missões e acompanha a frota", "HTTPS")
Rel(supervisor, painel, "Visualiza alertas e indicadores", "HTTPS")

' ---------- Relações: fluxo de despacho (síncrono) ----------
Rel(painel, api, "despacharMissao(DespachoRequestDTO)", "REST/JSON sobre HTTPS")
Rel(api, pg, "buscarPorId / salvar missão", "SQL sobre TCP 5432")
Rel(api, geo, "calcularRota(origem, destino)", "gRPC / HTTP/2 (Protobuf)")
Rel(api, agvgw, "consultarBateria / enviarComandoRota / enviarParaRecarga", "gRPC / HTTP/2 (Protobuf)")
Rel(api, redis, "reservarTrechos (trava com TTL)", "RESP sobre TCP 6379")
Rel(agvgw, frota, "lerEstadoBateria / carregarRota / irParaEstacao", "gRPC sobre mTLS, Wi-Fi industrial / 5G privado")

' ---------- Relações: eventos de domínio (assíncrono) ----------
Rel(api, rabbit, "Publica MissaoIniciada, RotaReservada, BateriaCriticaDetectada", "AMQP 0-9-1")
Rel(rabbit, notificador, "Entrega eventos de domínio", "AMQP 0-9-1")
Rel(rabbit, integracao, "Entrega MissaoConcluida e Falha Registrada", "AMQP 0-9-1")
Rel(notificador, painel, "atualizarPainel(evento)", "WebSocket (WSS)")

' ---------- Relações: sincronização de telemetria (assíncrono) ----------
Rel(frota, mqtt, "Publica TelemetriaDTO a cada 500 ms", "MQTT 5 sobre TLS, QoS 1")
Rel(mqtt, telemetria, "Entrega agv/+/telemetria", "MQTT 5 sobre TLS")
Rel(telemetria, geo, "atualizarPosicao(agvId, PosicaoDTO)", "gRPC / HTTP/2")
Rel(telemetria, tsdb, "Grava séries temporais", "SQL sobre TCP 5432")
Rel(telemetria, rabbit, "Publica TelemetriaSincronizada, BateriaCriticaDetectada", "AMQP 0-9-1")

' ---------- Relações: integração empresarial ----------
Rel(erp, integracao, "Envia pedidos de movimentação", "REST/JSON sobre HTTPS")
Rel(integracao, api, "Cria Solicitação de Transporte", "REST/JSON sobre HTTPS")
Rel(integracao, erp, "Notifica status e conclusão", "Webhook HTTPS")

SHOW_LEGEND()
@enduml
