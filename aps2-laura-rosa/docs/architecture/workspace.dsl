/*
 * Artefato 4 (Models-as-Code) — Structurizr DSL
 * Plataforma de Orquestração de AGVs — Logística de Entregas Autônomas em Parques Industriais
 * Funcionalidade: Recepção de Solicitação via ERP/WMS/MES e Planejamento da Missão
 * Contexto: Integração Empresarial e Solicitação de Transporte · Entidade: SolicitacaoTransporte
 * Modelo equivalente a c4-containers.puml (C4-PlantUML), com visão de Contêineres (N2)
 * e visão de Componentes (N3) da API de Integração e Solicitações.
 */
workspace "Orquestração de AGVs — Recepção de Solicitações" "Dossiê de Arquitetura Viva — APS 2" {

    !identifiers hierarchical

    model {
        operador = person "Operador / Supervisor Logístico" "Acompanha solicitações pendentes, rejeitadas e missões planejadas."
        erp = softwareSystem "ERP / WMS / MES" "Sistemas corporativos que geram ordens de movimentação e recebem o status por webhook." {
            tags "Externo"
        }

        plataforma = softwareSystem "Plataforma de Orquestração de AGVs" "Recebe solicitações, planeja e executa missões de transporte com AGVs." {

            spa = container "Painel de Monitoramento" "Lista de solicitações, motivos de rejeição e fila de missões." "React 18, TypeScript, Vite" {
                tags "Web"
            }
            apigw = container "Gateway de API" "Terminação TLS, validação de JWT e rate limiting por sistema de origem." "Kong 3.7"
            idp = container "Servidor de Identidade" "Emite tokens OAuth 2.0 (client credentials) para ERP/WMS/MES." "Keycloak 24"

            integ = container "API de Integração e Solicitações" "Dono do ciclo de vida da SolicitacaoTransporte." "Java 21, Spring Boot 3.3" {
                integracaoController = component "IntegracaoController" "receberSolicitacao(): valida HMAC e devolve ProtocoloDTO." "Spring MVC @RestController"
                tradutorAcl = component "TradutorSolicitacaoACL" "traduzir(): converte o payload externo para o modelo de domínio (Anti-Corruption Layer)." "Java + MapStruct + Bean Validation"
                solicitacaoService = component "SolicitacaoService" "registrar() com idempotência e registrarDesfecho() da missão." "Spring @Service"
                planejamentoService = component "PlanejamentoService" "processar(): análise paralela, priorização e criação da missão. agendarReprocessamento()." "Spring @Service + @RabbitListener + CompletableFuture"
                politicaPriorizacao = component "PoliticaPriorizacao" "calcularPrioridade(): estratégia intercambiável (prazo, criticidade, prioridade do ERP)." "Strategy Pattern"
                solicitacaoRepository = component "SolicitacaoRepository" "buscarPorIdExterno(), salvar(), atualizarStatus(), vincularMissao() com @Version." "Spring Data JPA"
                outboxRelay = component "OutboxRelay" "Publica no RabbitMQ os eventos gravados na tabela outbox." "Spring @Scheduled + AMQP"
                erpNotifier = component "ErpNotifier" "notificarStatus(): envia webhooks assinados com retry e backoff exponencial." "Spring @RabbitListener + WebClient + Resilience4j"
            }

            orq = container "API de Orquestração de Missões" "MissaoService (criarMissao) e FrotaService (verificarCompatibilidade)." "Java 21, Spring Boot 3.3"
            geo = container "Serviço de Geolocalização" "Validação de hubs e cálculo de rotas preliminares." "Python 3.12, FastAPI, gRPC"

            dbSol = container "Banco de Solicitações" "Solicitações, chave única (sistemaOrigem, idExterno), outbox e log de webhooks." "PostgreSQL 16" {
                tags "Database"
            }
            dbMis = container "Banco de Missões" "Missões de transporte, AGVs e capacidades." "PostgreSQL 16" {
                tags "Database"
            }
            dbGeo = container "Base Cartográfica" "Hubs, corredores logísticos e trechos." "PostgreSQL 16 + PostGIS 3.4" {
                tags "Database"
            }
            rabbit = container "Barramento de Eventos" "solicitacoes.recebidas, solicitacoes.reprocessamento, erp.notificacoes, missoes.encerradas, DLQ." "RabbitMQ 3.13 (quorum queues)" {
                tags "Queue"
            }
        }

        # Entrada da requisição
        erp -> plataforma.idp "Obtém token" "OAuth 2.0 client credentials / HTTPS"
        erp -> plataforma.apigw "receberSolicitacao()" "REST/JSON sobre HTTPS + assinatura HMAC"
        plataforma.apigw -> plataforma.idp "Valida assinatura do JWT" "OIDC JWKS / HTTPS"
        plataforma.apigw -> plataforma.integ.integracaoController "Encaminha requisição autenticada" "HTTP/1.1 + mTLS"
        operador -> plataforma.spa "Acompanha solicitações" "HTTPS"
        plataforma.spa -> plataforma.apigw "Consulta solicitações e missões" "REST/JSON sobre HTTPS"

        # Componentes da API de Integração e Solicitações
        plataforma.integ.integracaoController -> plataforma.integ.tradutorAcl "traduzir()" "Chamada in-process"
        plataforma.integ.integracaoController -> plataforma.integ.solicitacaoService "registrar()" "Chamada in-process"
        plataforma.integ.solicitacaoService -> plataforma.integ.solicitacaoRepository "buscarPorIdExterno() / salvar() / atualizarStatus()" "Chamada in-process"
        plataforma.integ.planejamentoService -> plataforma.integ.solicitacaoRepository "atualizarStatus() / vincularMissao()" "Chamada in-process"
        plataforma.integ.planejamentoService -> plataforma.integ.politicaPriorizacao "calcularPrioridade()" "Chamada in-process"
        plataforma.integ.planejamentoService -> plataforma.geo "validarHubs() / calcularRota()" "gRPC / HTTP2 + TLS"
        plataforma.integ.planejamentoService -> plataforma.orq "verificarCompatibilidade() / criarMissao()" "gRPC / HTTP2 + TLS"
        plataforma.integ.planejamentoService -> plataforma.integ.solicitacaoRepository "Grava outbox (notificarStatus, agendarReprocessamento)" "Chamada in-process"
        plataforma.integ.solicitacaoRepository -> plataforma.dbSol "Lê e grava solicitações e outbox" "JDBC / SQL"
        plataforma.integ.outboxRelay -> plataforma.dbSol "Lê eventos pendentes" "JDBC / SQL"
        plataforma.integ.outboxRelay -> plataforma.rabbit "Publica eventos da outbox" "AMQP 0-9-1 + TLS"
        plataforma.rabbit -> plataforma.integ.planejamentoService "Entrega processar()" "AMQP 0-9-1 + TLS"
        plataforma.rabbit -> plataforma.integ.erpNotifier "Entrega notificarStatus()" "AMQP 0-9-1 + TLS"
        plataforma.rabbit -> plataforma.integ.solicitacaoService "Entrega registrarDesfecho()" "AMQP 0-9-1 + TLS"
        plataforma.integ.erpNotifier -> erp "receberStatus()" "Webhook HTTPS + assinatura HMAC"
        plataforma.integ.erpNotifier -> plataforma.dbSol "Registra tentativas de entrega" "JDBC / SQL"

        # Demais contêineres
        plataforma.orq -> plataforma.dbMis "Lê e grava missões" "JDBC / SQL"
        plataforma.orq -> plataforma.rabbit "Publica MissaoEncerrada" "AMQP 0-9-1 + TLS"
        plataforma.geo -> plataforma.dbGeo "Consulta hubs e grafo de corredores" "SQL / PostGIS"
    }

    views {
        container plataforma "Conteineres" "Visão de Contêineres (C4 Nível 2)" {
            include *
            autolayout tb
        }

        component plataforma.integ "Componentes-Integracao" "Visão de Componentes (C4 Nível 3) — API de Integração e Solicitações" {
            include *
            autolayout tb
        }

        styles {
            element "Person" {
                shape Person
                background #08427b
                color #ffffff
            }
            element "Container" {
                background #438dd5
                color #ffffff
            }
            element "Component" {
                background #85bbf0
                color #000000
            }
            element "Externo" {
                background #999999
                color #ffffff
            }
            element "Web" {
                shape WebBrowser
            }
            element "Database" {
                shape Cylinder
            }
            element "Queue" {
                shape Pipe
            }
        }
    }
}
