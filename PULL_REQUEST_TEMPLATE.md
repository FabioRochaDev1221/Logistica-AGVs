# Defesa de Arquitetura de Software — Pull Request

## Autor do PR
- **Nome do Estudante:** [Seu Nome Completo]
- **Artefato(s) de Responsabilidade:** [ex: C4 Nível 3, Diagrama de Sequência e ADR 0001]

## O que este PR introduz na Documentação Viva?
Descreva sucintamente as alterações e os novos modelos adicionados à pasta `/docs/`:
- [ ] **Visão Funcional / Estrutural:** Diagrama de Casos de Uso ou Diagrama de Classes e Interfaces.
- [ ] **Visão Comportamental:** Diagrama de Sequência, Atividades (com Raias/Fork-Join) ou Máquina de Estados.
- [ ] **Visão Arquitetural Macro:** Modelo C4 (L1, L2 ou L3 em Structurizr DSL, D2 ou PlantUML).
- [ ] **Governança:** Registros de Decisão Arquitetural (ADR).

## Defesa das Decisões de Design (Justificativa Técnica)
Explique a fundamentação técnica das decisões tomadas neste artefato:
1. **Escolha de Abstrações e Desacoplamento:** Por que as interfaces, visibilidades e relacionamentos foram desenhados dessa forma?
2. **Dinâmica e Resiliência:** Como os fluxos alternativos (`alt/else`), mensagens assíncronas ou guardas de estado tratam falhas no sistema?
3. **Trade-offs:** Quais prós e contras foram considerados no momento da modelagem?

## Consistência Cross-Diagramas (Checklist de Autoverificação)
Antes de solicitar a revisão de um colega, confirme o alinhamento entre os modelos:
- [ ] Os nomes de métodos chamados no Diagrama de Sequência existem nas interfaces do Diagrama de Classes.
- [ ] Os contêineres e componentes citados correspondem exatamente à nomenclatura do Modelo C4 L2/L3.
- [ ] As transições de estado refletem os gatilhos disparados pelas atividades da aplicação.

## Validação da Sintaxe Diagrams-as-Code / Models-as-Code
- **Ferramenta de Compilação/Renderização Utilizada:** [ex: Structurizr CLI, D2 CLI, PlantUML, Mermaid Live]
- **Status da Compilação:** [ ] Código limpo e sem erros de sintaxe ao renderizar.
