# Logística de AGVs — APS2

**Autor:** Jhonatan de Souza Gonçalves

## 1. Sobre o projeto

Este projeto apresenta a modelagem de um sistema de logística de entregas utilizando AGVs (Automated Guided Vehicles), veículos guiados automaticamente para transportar materiais em ambientes industriais.

A documentação utiliza Mermaid e a abordagem Diagrams-as-Code (DaC), permitindo manter os diagramas versionados no Git.

## 2. Objetivos

- Modelar a arquitetura do sistema de logística.
- Representar a comunicação entre os componentes.
- Documentar o processo de despacho de rotas.
- Verificar disponibilidade, bateria e condições da rota.
- Representar os estados operacionais dos AGVs.
- Manter a documentação versionada no GitHub.

## 3. Diagramas desenvolvidos

### 3.1. Diagrama C4 Nível 2 — Contêineres

Arquivo: [c4-containers.mmd](docs/architecture/c4-containers.mmd)

Representa a arquitetura do sistema e seus principais contêineres:

- Interface do Operador
- Orquestrador de AGVs
- Serviço de Despacho
- Serviço de Monitoramento
- Banco de Dados

### 3.2. Diagrama de Sequência — Despacho e Bateria

Arquivo: [despacho-bateria.mmd](docs/diagrams/despacho-bateria.mmd)

Representa a comunicação entre os participantes durante o despacho de uma entrega, considerando a disponibilidade do AGV, a bateria e as condições da rota.

### 3.3. Diagrama de Atividades — Despacho de Rota

Arquivo: [atividades-despacho.mmd](docs/diagrams/atividades-despacho.mmd)

Representa o fluxo de despacho, incluindo verificações paralelas de bateria e desobstrução da rota, utilizando pontos de FORK e JOIN.

### 3.4. Diagrama de Estados — Veículo AGV

Arquivo: [estados-agv.mmd](docs/diagrams/estados-agv.mmd)

Representa os estados operacionais de um AGV:

- Disponível
- Em Carregamento
- Em Trânsito
- Em Falha Operacional

## 4. Regras de negócio

- O despacho deve ser bloqueado quando a bateria estiver abaixo de 20%.
- O nível mínimo de bateria para despacho é de 20%.
- O carregamento é considerado concluído quando a bateria atinge pelo menos 90%.
- O despacho depende da disponibilidade do AGV e da desobstrução da rota.

## 5. Estrutura da documentação

```
aps2-jhonatan-souza/
├── docs/
│   ├── architecture/
│   │   └── c4-containers.mmd
│   └── diagrams/
│       ├── despacho-bateria.mmd
│       ├── atividades-despacho.mmd
│       └── estados-agv.mmd
└── README.md
```

## 6. Tecnologias e ferramentas

- Mermaid v11
- Visual Studio Code
- Git
- GitHub
- Markdown

## 7. Como visualizar os diagramas

1. Acesse https://mermaid.live/
2. Abra o arquivo .mmd desejado.
3. Copie seu conteúdo para o Mermaid Live Editor.
4. Visualize o diagrama renderizado.

Também é possível utilizar uma extensão Mermaid no Visual Studio Code.

## 8. Validação

Os quatro diagramas originais foram validados pelo revisor utilizando o analisador oficial do Mermaid v11, sem erros de sintaxe.

As alterações realizadas após a revisão deverão ser validadas novamente.

## 9. Considerações finais

Os quatro diagramas oferecem visões complementares do sistema, documentando sua arquitetura, comunicação, fluxo de atividades e comportamento operacional.

A documentação serve como referência para o desenvolvimento, manutenção e evolução do sistema.
