# ADR 0002 — Reserva atômica de AGVs e controle de concorrência na redistribuição

**Status:** Proposto

**Data:** 2026-11-27

**Relacionada a:** [ADR 0001](0001-redistribuicao-mensageria-rabbitmq.md)

## Contexto

Na ADR 0001, o Serviço de Redistribuição foi pensado para ter várias réplicas consumindo a mesma fila do RabbitMQ. Isso significa que duas falhas de AGV que aconteçam quase ao mesmo tempo (por exemplo, M-100 com o AGV-07 e M-200 com o AGV-09) podem ser tratadas em paralelo por réplicas diferentes.

As duas redistribuições chamam `selecionarCandidatos()`, que consulta o Serviço de Monitoramento e o `RotaService`. Essa consulta só lê dados e leva algum tempo, porque calcula uma rota por candidato. Se o AGV-12 for o melhor candidato para as duas, as duas listas vão começar por ele.

Os dados que pesaram na decisão:

- o estado do AGV fica numa linha da tabela `agv` no PostgreSQL, que já é o banco do projeto;
- essa mesma linha é atualizada pelo Monitoramento a cada 2 s com heartbeat, posição e bateria;
- a reserva vale 30 s, o mesmo tempo de espera do aceite;
- o processamento é pelo menos uma vez (ADR 0001), então a mesma redistribuição também pode rodar duas vezes.

## Problema

Garantir que um AGV seja reservado por no máximo uma missão ao mesmo tempo (invariante I2), mesmo com duas redistribuições concorrentes e com eventos reprocessados, sem segurar bloqueios durante as chamadas remotas da seleção.

## Alternativas consideradas

- **Bloqueio pessimista (`SELECT ... FOR UPDATE`).** Resolve o conflito, mas o bloqueio teria que durar da leitura até a gravação. Se ele começar antes da seleção, fica preso durante as chamadas ao `RotaService`, e bloquear vários candidatos em ordens diferentes pode causar deadlock. Se ele for usado só no momento de reservar, faz o mesmo que o `UPDATE` condicional, com uma ida a mais ao banco.
- **Controle otimista (coluna `versao` na linha do AGV).** Funciona bem na `MissaoTransporte`, que muda pouco. Na linha do AGV, a versão mudaria a cada 2 s por causa da telemetria, e a reserva falharia por conflito mesmo quando ninguém mais estivesse tentando reservar aquele AGV.
- **Operação atômica no PostgreSQL (`UPDATE` condicional).** O teste "está disponível?" e a gravação "agora está reservado" acontecem no mesmo comando. Não há intervalo entre ler e gravar.
- **Restrição de unicidade para reservas ativas.** Um índice único parcial impede duas reservas ativas para o mesmo AGV. Sozinho, ele só funciona depois que o conflito acontece, por isso faz mais sentido como garantia extra.
- **Lock distribuído (Redis ou outro serviço de lock).** Precisaria de uma tecnologia nova só para isso, e o estado do AGV continuaria no PostgreSQL. Um lock com tempo de expiração pode vencer enquanto o processo ainda está trabalhando, e aí dois processos acham que têm o lock.

## Decisão

Reservar o AGV com uma **operação atômica no PostgreSQL**, protegida por **índices únicos parciais** para reservas ativas. Não usamos lock distribuído nem bloqueio durante a seleção.

A seleção continua só lendo. A disputa é resolvida no momento da reserva, dentro de `AGVRepository.reservarSeDisponivel()`, numa transação curta:

```sql
BEGIN;

UPDATE agv
   SET estado = 'RESERVADO'
 WHERE id = :agvId
   AND estado = 'DISPONIVEL';
-- 0 linhas alteradas: outro processo reservou antes. ROLLBACK e devolve false.

INSERT INTO reserva_agv (id, agv_id, missao_id, status, expira_em)
VALUES (:reservaId, :agvId, :missaoId, 'ATIVA', now() + interval '30 seconds');

COMMIT;
```

```sql
CREATE UNIQUE INDEX ux_reserva_ativa_agv
    ON reserva_agv (agv_id)    WHERE status IN ('ATIVA', 'CONFIRMADA');

CREATE UNIQUE INDEX ux_reserva_ativa_missao
    ON reserva_agv (missao_id) WHERE status IN ('ATIVA', 'CONFIRMADA');
```

Quando duas transações tentam o mesmo `UPDATE`, a segunda espera a primeira terminar e o PostgreSQL avalia o `WHERE` de novo. Como o AGV já está `RESERVADO`, nenhuma linha muda. Isso vale no nível de isolamento padrão (`READ COMMITTED`).

O `ReservaAGVService` percorre os candidatos em ordem de ETA. Quem recebe `false` tenta o próximo. Se nenhum for reservado, a substituta vai para `SemCandidato` e recebe `missao.reavaliar` em 60 s.

As outras operações da reserva também são condicionais:

| Operação | Condição | Se nenhuma linha mudar |
|---|---|---|
| `confirmarSeAtiva(reservaId)` | `status = 'ATIVA' AND expira_em > now()`. O AGV passa para `EM_MISSAO`. | Se a reserva já está `CONFIRMADA`, devolve `true` (aceite repetido). Se está `LIBERADA`, devolve `false` e o aceite é tratado como atrasado. |
| `liberar(reservaId)` | `status = 'ATIVA'`. O AGV volta para `DISPONIVEL`. | Nada a fazer. |
| `liberarVencidas(agora)` | `status = 'ATIVA' AND expira_em < agora`. | Nada a fazer. |

No aceite, o `ControleContinuidade` confirma a reserva **antes** de chamar `confirmarAceite()` na API. Se a reserva já venceu e o AGV foi para outra missão, a S-101 não entra em `EmExecucao` com um AGV que não é mais dela.

A rotina `liberarReservasVencidas()` roda de tempos em tempos no `ReservaAGVService`. Ela cobre o caso em que o serviço caiu com uma reserva ativa: o AGV volta a ficar disponível e a missão recebe `missao.reavaliar`.

## Justificativa

O conflito só existe no instante em que o AGV muda de `DISPONIVEL` para `RESERVADO`. Um comando atômico resolve exatamente esse instante, sem bloquear nada durante a seleção, que é a parte demorada.

O PostgreSQL já guarda o estado dos AGVs e é a fonte da verdade. Colocar o controle de concorrência em outro lugar criaria duas fontes que podem discordar.

O índice único parcial entra porque a regra não deveria depender só de cada `UPDATE` estar escrito certo. Se algum caminho do código esquecer a condição, o banco recusa a segunda reserva ativa.

## Relação com a idempotência dos eventos

São dois problemas diferentes e um mecanismo não substitui o outro:

- `jaProcessado()` e `marcarProcessado()` (ADR 0001) evitam aplicar **o mesmo evento** duas vezes. Eles não ajudam quando são **dois eventos diferentes**, como as falhas de M-100 e M-200, disputando o mesmo AGV. Esse caso é resolvido pela reserva atômica.
- O evento só é marcado como processado no fim. Por isso, depois de uma queda, o mesmo evento pode ser processado de novo. A reserva precisa aguentar isso: `reservarAGV()` primeiro procura uma reserva ativa da missão (`buscarReservaAtiva`) e, se existir, devolve a mesma. Se dois processamentos do mesmo evento rodarem ao mesmo tempo, o índice `ux_reserva_ativa_missao` impede que a mesma substituta reserve dois AGVs.
- O aceite repetido chega a ser filtrado pelo `jaProcessado()`. Mesmo se passar, `confirmarSeAtiva()` devolve `true` para uma reserva já confirmada e não muda nada.

Resumindo: a deduplicação cuida da repetição, a reserva atômica cuida da concorrência, e o lock otimista continua cuidando das transições da `MissaoTransporte`.

## Vantagens

- Não entra nenhuma tecnologia nova. Tudo fica no PostgreSQL que o projeto já usa.
- Não existe bloqueio durante a seleção, então uma redistribuição lenta não trava as outras.
- Não há deadlock, porque cada transação mexe em um AGV só.
- A telemetria pode continuar atualizando a linha do AGV sem causar conflito na reserva.
- A invariante I2 é garantida pelo banco mesmo se o código tiver um erro.

## Desvantagens

- Quem perde a disputa já gastou a seleção daquele candidato e precisa tentar o próximo. Com poucos AGVs livres, isso pode levar mais rápido a `SemCandidato`.
- A regra fica dividida entre o código (`UPDATE` condicional) e o esquema do banco (índices). Quem mexer em uma parte precisa conhecer a outra.
- O nome do estado (`DISPONIVEL`, `RESERVADO`) passa a fazer parte do SQL. Mudar o enum exige mudar a consulta.
- O controle depende de todos os serviços usarem o mesmo banco para o estado do AGV. Se um dia o Monitoramento tiver banco próprio, essa decisão precisa ser revista.

## Consequências

- O Monitoramento grava heartbeat, posição, bateria e `EM_FALHA`, mas não pode trocar `RESERVADO` ou `EM_MISSAO` por `DISPONIVEL`. Só o fluxo de reserva faz essas mudanças.
- A tabela `reserva_agv` guarda o histórico de todas as tentativas, inclusive as liberadas. Isso ajuda na auditoria, mas a tabela cresce e precisa de limpeza, como a de eventos processados.
- Precisamos acompanhar quantas reservas são perdidas por disputa e quantas vencem sem confirmação. Muitas reservas vencidas indicam queda do serviço ou AGV que não responde.
- Fica uma limitação: se o serviço cair logo depois do ack da falha e antes da primeira reserva, a substituta fica em `AguardandoAtribuicao` sem reserva e sem `missao.reavaliar` agendada. Neste modelo, ela aparece parada no painel e o operador decide o que fazer.
