
# Logística de AGVs

## 1. Sobre o projeto

Este projeto apresenta a modelagem de um sistema de logística de entregas utilizando AGVs (Automated Guided Vehicles), veículos guiados automaticamente para transportar materiais em ambientes industriais.

O objetivo é representar a arquitetura do sistema, o processo de despacho de entregas, as verificações de segurança e os estados operacionais dos veículos.

A documentação utiliza Mermaid e a abordagem Diagrams-as-Code (DaC), permitindo manter os diagramas como arquivos de texto versionados no Git.

## 2. Objetivos

- Modelar a arquitetura do sistema de logística.
- Representar a comunicação entre os componentes.
- Documentar o processo de despacho de rotas.
- Verificar disponibilidade, bateria e condições da rota.
- Representar os estados operacionais dos AGVs.
- Manter a documentação versionada no GitHub.

## 3. Diagramas desenvolvidos

### 3.1. Diagrama C4 Nível 2 — Contêineres

Arquivo: [c4-containers.mmd](diagramas/c4-containers.mmd)

Representa a estrutura do sistema e seus principais contêineres:

- Interface do Operador
- Orquestrador de AGVs
- Serviço de Despacho
- Serviço de Monitoramento
- Banco de Dados

Também apresenta as relações entre os serviços, o operador e os AGVs.

### 3.2. Diagrama de Sequência — Despacho e Bateria

Arquivo: [despacho-bateria.mmd](diagramas/despacho-bateria.mmd)

Representa a sequência de comunicação durante o despacho de uma entrega.

O sistema verifica a disponibilidade do AGV e seu nível de bateria antes de enviar a rota.

Caso o AGV esteja indisponível ou sua bateria seja insuficiente, o despacho não é autorizado.

### 3.3. Diagrama de Atividades — Despacho de Rota

Arquivo: [atividades-despacho.mmd](diagramas/atividades-despacho.mmd)

Representa o fluxo de atividades necessário para realizar o despacho de uma entrega.

O modelo apresenta duas verificações paralelas:

- Verificação do nível de bateria do AGV.
- Verificação da desobstrução da rota.

O fluxo utiliza pontos identificados como FORK e JOIN para representar visualmente o início das verificações paralelas e a sincronização dos resultados.

O despacho somente é autorizado quando ambas as condições são aprovadas.

### 3.4. Diagrama de Estados — Veículo AGV

Arquivo: [estados-agv.mmd](diagramas/estados-agv.mmd)

Representa os estados operacionais de um AGV:

- Disponível
- Em Carregamento
- Em Trânsito
- Em Falha Operacional

O diagrama também apresenta os eventos que provocam as transições entre esses estados, como despacho autorizado, entrega concluída, bateria baixa e falhas operacionais.

## 4. Estrutura do projeto

    Logistica-AGVs/
    ├── diagramas/
    │   ├── c4-containers.mmd
    │   ├── despacho-bateria.mmd
    │   ├── atividades-despacho.mmd
    │   └── estados-agv.mmd
    └── README.md

## 5. Tecnologias e ferramentas

- Mermaid: criação de diagramas como código.
- Visual Studio Code: edição e visualização dos arquivos.
- Git: controle de versões.
- GitHub: armazenamento e colaboração.
- Markdown: documentação do projeto.

## 6. Como visualizar os diagramas

Os arquivos `.mmd` contêm a sintaxe Mermaid.

Para visualizar os diagramas graficamente, é possível utilizar o Mermaid Live Editor:

https://mermaid.live/

Também é possível utilizar uma extensão de visualização Mermaid compatível com o Visual Studio Code.

Para visualizar no VS Code:

1. Abra o projeto Logistica-AGVs.
2. Entre na pasta `diagramas`.
3. Abra o arquivo `.mmd` desejado.
4. Utilize o comando de pré-visualização da extensão Mermaid instalada.

## 7. Considerações finais

Os quatro diagramas oferecem visões complementares do sistema.

O C4 representa sua arquitetura, o diagrama de sequência apresenta a comunicação entre os participantes, o diagrama de atividades descreve o fluxo de despacho e o diagrama de estados representa o comportamento operacional dos AGVs.

Essa documentação serve como referência para o desenvolvimento e a evolução do sistema.
