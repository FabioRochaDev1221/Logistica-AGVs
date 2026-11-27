@startuml C4_Conteineres_ReservaRota
' C4 Nível 2 (Contêineres) em C4-PlantUML
' Foco: Gestão de Reserva de Rota e Resolução de Conflitos em Corredores
' Mostra apenas os contêineres que participam da funcionalidade.
!include https://raw.githubusercontent.com/plantuml-stdlib/C4-PlantUML/master/C4_Container.puml

LAYOUT_TOP_DOWN()
title C4 Nível 2 (Contêineres) - Foco: Reserva de Rota e Resolução de Conflitos em Corredores

Person(supervisor, "Supervisor de Operações", "Define prioridades e acompanha conflitos")
Person(operador, "Operador Logístico", "Monitora reservas e conflitos")

System_Boundary(orq, "Sistema de Orquestração de Entregas Autônomas") {
    Container(web, "Portal de Operações", "React 18 / TypeScript", "Mapa de corredores, reservas e alertas")
    Container(api, "API Gateway / BFF", "Node.js 20 / NestJS", "Entrada única e push em tempo real")
    Container(alertas, "Serviço de Alertas", "Node.js 20", "Alertas de conflito e bloqueio")
    Container(missoes, "Serviço de Missões", "Java 21 / Spring Boot 3", "Solicita, ativa e libera a ReservaRota")
    Container(roteamento, "Serviço de Reserva de Rota", "Python 3.12 / FastAPI", "Reserva trechos, resolve conflitos e libera trechos percorridos")
    Container(telemetria, "Serviço de Telemetria", "Go 1.22", "Posição em tempo real e bloqueios")
    Container(gatewayFrota, "Gateway da Frota AGV", "Go 1.22", "Traduz comandos para VDA 5050")
    ContainerQueue(broker, "Barramento de Eventos", "Apache Kafka 3.7", "RotaReservada, ConflitoDetectado, TrechoLiberado, PosicaoAtualizada")
    ContainerQueue(mqtt, "Broker MQTT", "Eclipse Mosquitto 2", "Tópicos VDA 5050 e posições RTLS")
    ContainerDb(cache, "Locks de Trechos", "Redis 7", "Locks atômicos SET NX PX + Lua")
    ContainerDb(dbOper, "Banco Operacional", "PostgreSQL 16", "Schema rotas: reservas e conflitos")
    ContainerDb(dbHist, "Banco de Rastreabilidade", "TimescaleDB 2.14", "Histórico de posições e conflitos")
}

System_Ext(rtls, "Infraestrutura RTLS", "Posição e ocupação dos corredores")
System_Ext(frota, "Frota AGV", "AGVs compatíveis com VDA 5050")

Rel(supervisor, web, "Define prioridades", "HTTPS")
Rel(operador, web, "Monitora reservas", "HTTPS")
Rel(web, api, "API e tempo real", "REST/HTTPS + WSS")
Rel(api, roteamento, "Consulta reservas e conflitos", "REST/HTTP JSON")
Rel(alertas, api, "Envia alertas", "gRPC streaming")

Rel(missoes, roteamento, "reservarRota / ativarReserva / liberarReserva", "REST/HTTP JSON")
Rel(missoes, gatewayFrota, "enviarRota", "gRPC HTTP/2")

Rel(roteamento, rtls, "consultarOcupacao", "REST/HTTPS JSON")
Rel(roteamento, cache, "adquirir / transferir / liberar locks", "RESP TCP")
Rel(roteamento, dbOper, "Persiste ReservaRota", "PostgreSQL wire / psycopg 3")
Rel(roteamento, gatewayFrota, "Rota recalculada / pausarAgv", "gRPC HTTP/2")
Rel(roteamento, broker, "Publica eventos de reserva", "Kafka")

Rel(telemetria, roteamento, "recalcularRota", "gRPC HTTP/2")
Rel(telemetria, broker, "Publica PosicaoAtualizada", "Kafka")
Rel(telemetria, dbHist, "Grava histórico", "PostgreSQL wire / pgx")
Rel(broker, roteamento, "PosicaoAtualizada", "Kafka")
Rel(broker, alertas, "ConflitoDetectado", "Kafka")

BiRel(gatewayFrota, mqtt, "order / state", "MQTT 5 - VDA 5050")
BiRel(mqtt, frota, "order / state", "MQTT 5 - VDA 5050")
Rel(rtls, mqtt, "Publica posições", "MQTT 5")
Rel(mqtt, telemetria, "Posições", "MQTT 5")

SHOW_LEGEND()
@enduml
