# ADR 0001 — Adoção de mensageria para detecção de falhas e redistribuição de missões

**Status:** Proposto

**Data:** 2026-11-06

## Contexto

Os AGVs se comunicam por rede sem fio dentro do parque industrial, e essa rede cai com frequência: áreas de sombra, interferência de máquinas, troca de ponto de acesso. Um AGV que fica alguns segundos sem sinal não está necessariamente quebrado, então o sistema precisa diferenciar uma queda rápida de uma falha real antes de mexer na missão.

Quando a falha é real, a missão precisa ir para outro AGV sem que a entrega fique com dois veículos ao mesmo tempo e sem que a mesma carga seja transportada duas vezes. Isso envolve várias etapas que não acontecem no mesmo instante: detectar a falha, confirmar, registrar, escolher um substituto, mandar a ordem e esperar o aceite. Algumas dependem de resposta do AGV, que pode demorar ou nunca chegar.

Os pontos que pesaram na decisão foram:

- a telemetria chega a cada 2 s de todos os AGVs, o que gera volume constante;
- se um serviço reiniciar no meio de uma redistribuição, o evento de falha não pode se perder;
- uma mensagem pode chegar repetida (reentrega depois de timeout ou de queda do consumidor);
- duas redistribuições ao mesmo tempo podem tentar pegar o mesmo AGV livre;
- o operador precisa ser avisado quando algo sai do fluxo normal.

## Decisão

Usar comunicação orientada a eventos com **RabbitMQ** (AMQP 0-9-1) entre os serviços internos e **MQTT sobre TLS** entre os AGVs e o Gateway de Comunicação.

- O **Gateway de Comunicação** mantém as conexões MQTT com os AGVs (QoS 1) e publica no RabbitMQ a telemetria e os aceites já convertidos para eventos internos. Os serviços não falam MQTT diretamente.
- O **Serviço de Monitoramento** consome a telemetria, controla o heartbeat e publica `missao.interrupcao-suspeita` e `agv.falha-confirmada`. A falha só é confirmada depois de 3 tentativas de contato sem resposta (timeout de 2 s cada) ou se o próprio AGV mandar um código de falha.
- O **Serviço de Redistribuição** consome esses eventos em filas duráveis com **ack manual**. O ack só é enviado depois que o resultado está gravado no banco. Se o serviço cair antes disso, o RabbitMQ entrega o evento de novo.
- Chamadas que precisam de resposta imediata continuam síncronas via REST: `solicitarStatus()`, `listarAGVsAptos()`, `enviarOrdemMissao()` e as operações da API de Gestão de Missões.

Como a entrega é **pelo menos uma vez** (at-least-once), o processamento precisa ser idempotente. Isso fica no banco, não no broker:

1. **Eventos repetidos:** antes de processar, o serviço chama `registrarSeNovo(eventoId)`, que faz um `INSERT ... ON CONFLICT DO NOTHING` na tabela de eventos processados. Se o id já existe, o evento é descartado e confirmado.
2. **Mudança de estado da missão:** toda gravação usa lock otimista (`salvar(missao, versaoEsperada)`). Se outra operação mudou a missão antes, a gravação falha e o evento é reavaliado com o estado atual.
3. **Missão substituta única:** a coluna `missao_origem_id` tem restrição `UNIQUE`. Reprocessar o mesmo evento devolve a substituta que já existe em vez de criar outra.
4. **Reserva de AGV:** `reservarSeDisponivel()` é um `UPDATE` condicional que só reserva se o AGV ainda estiver `DISPONIVEL`. Duas redistribuições concorrentes não conseguem pegar o mesmo AGV; a que perde tenta o próximo candidato.
5. **Aceite atrasado:** cada ordem tem um `comandoId`. Se o aceite chega depois do timeout de 30 s, o comando já foi invalidado e o aceite é ignorado.

Com isso, o efeito final no banco é o mesmo de um processamento único, mesmo que a mensagem chegue mais de uma vez. Não existe garantia de entrega exatamente uma vez no transporte; o que existe é deduplicação e controle de concorrência na hora de gravar.

Mensagens que falham repetidamente vão para uma **dead-letter queue**. Quando não há AGV disponível, a redistribuição agenda `missao.reavaliar` com atraso de 60 s.

### Alternativas consideradas

- **REST síncrono com polling:** o monitoramento consultaria cada AGV periodicamente e chamaria a redistribuição direto. É mais simples, mas um serviço fora do ar faria o evento de falha se perder, e o número de requisições cresce com a frota. Descartada.
- **Apache Kafka:** atende bem o volume de telemetria e permite reprocessar o histórico. Mas é mais pesado de operar, e o que mais precisamos aqui (ack por mensagem, dead-letter, reentrega com atraso) o RabbitMQ já oferece de forma direta. Para o tamanho da frota considerado, não se justificou.
- **Só um broker MQTT para tudo:** os serviços consumiriam os tópicos MQTT diretamente. O MQTT não tem fila durável por consumidor com ack manual nem dead-letter da forma que o fluxo de redistribuição precisa. Mantivemos o MQTT apenas na ponta dos AGVs.

## Consequências

**Positivas**

- Uma queda do Serviço de Redistribuição não perde a falha: o evento fica na fila até ser confirmado.
- O monitoramento pode receber telemetria em ritmo alto sem travar o resto do sistema.
- O Serviço de Redistribuição pode ter várias réplicas na mesma fila, e o controle de concorrência no banco impede atribuição duplicada.
- Cada etapa gera um evento e um registro de auditoria, o que permite reconstruir o que aconteceu com cada missão.

**Negativas e riscos**

- O sistema passa a ter consistência eventual: por alguns segundos o painel pode mostrar um estado anterior ao real.
- A idempotência depende de todo consumidor chamar `registrarSeNovo()` e usar lock otimista. Um consumidor novo que esqueça isso pode duplicar efeitos.
- O RabbitMQ vira um componente crítico. Precisa rodar em cluster com filas quorum, senão a falha dele para a detecção.
- A tabela de eventos processados cresce sem parar e precisa de uma rotina de limpeza (por exemplo, apagar ids com mais de 7 dias).
- Depurar um fluxo assíncrono é mais difícil que um fluxo síncrono, porque a sequência de passos fica espalhada entre serviços.

**Custos operacionais e monitoramento**

- Mais um serviço para manter (RabbitMQ), além do Gateway de Comunicação.
- Precisamos acompanhar: tamanho das filas, mensagens na dead-letter, tempo entre a falha confirmada e o aceite do substituto, quantidade de missões em `SemCandidato` e taxa de reentrega de mensagens.
- Os eventos precisam carregar um id de correlação (o id da missão original) para que os logs dos serviços possam ser cruzados.
