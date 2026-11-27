# ADR 0001 — Validações paralelas antes do despacho

## Status

Proposta.

## Contexto

O sistema de logística de AGVs precisa garantir que os veículos possuam bateria suficiente e que a rota esteja desobstruída antes de iniciar uma entrega.

A ausência dessas verificações pode provocar interrupções e falhas operacionais.

## Decisão

Realizar as verificações de bateria e rota em paralelo, sincronizando os resultados antes de autorizar o despacho.

O despacho será autorizado somente quando:

- O AGV estiver disponível.
- O nível de bateria for igual ou superior a 20%.
- A rota estiver desobstruída.

Caso a bateria esteja abaixo de 20%, o despacho será bloqueado e a recarga será solicitada.

A recarga será considerada concluída quando a bateria atingir pelo menos 90%.

## Alternativas consideradas

- Realizar as verificações sequencialmente.
- Realizar as verificações em paralelo.

A segunda alternativa foi escolhida por reduzir potencialmente o tempo de espera antes do despacho.

## Consequências positivas

- Maior segurança operacional.
- Menor risco de interrupções.
- Redução potencial do tempo de processamento.
- Separação das responsabilidades entre os serviços.

## Consequências negativas

- Maior complexidade na sincronização dos resultados.
- Necessidade de tratamento de falhas e timeouts.
- Dependência da comunicação entre os serviços.

## Consistência arquitetural

Esta decisão está representada nos diagramas de sequência, atividades, estados e no modelo C4 Nível 2.
