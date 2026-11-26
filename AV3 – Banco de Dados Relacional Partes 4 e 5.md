# AV3 – Banco de Dados Relacional: Partes 4 e 5

Projeto: Gestão de Serviços, Projetos e Ordens de Serviço · SGBD: MySQL 8.0.16+ · Banco: `gestao_servicos`

## Parte 4 – Documentação do Banco de Dados (Dicionário de Dados)

O banco `gestao_servicos` possui 14 tabelas (charset `utf8mb4`, engine InnoDB). Legenda das colunas: **PK** = chave primária, **FK** = chave estrangeira, **UK** = chave única (UNIQUE), **NN** = NOT NULL.

### 4.1 clientes

Empresas contratantes dos serviços.

| Campo | Tipo | Chave | Nulo | Restrições / descrição |
| --- | --- | --- | --- | --- |
| id | INT | PK | NN | AUTO\_INCREMENT. Identificador do cliente. |
| nome | VARCHAR(191) | UK | NN | Nome fantasia; não pode repetir. |
| razao\_social | VARCHAR(191) | UK | NN | Razão social; não pode repetir. |
| ramo\_atuacao | VARCHAR(191) | – | NN | Segmento de atuação (ex.: Energia, Logística). |
| ativo | BOOLEAN | – | NN | DEFAULT TRUE. Indica se o cliente está ativo. |

### 4.2 departamentos

Departamentos internos da empresa prestadora.

| Campo | Tipo | Chave | Nulo | Restrições / descrição |
| --- | --- | --- | --- | --- |
| id | INT | PK | NN | AUTO\_INCREMENT. |
| responsavel\_id | INT | FK | Aceita NULL | Referencia `funcionarios(id)` (`fk_departamento_responsavel_funcionario`). Gestor do departamento. A FK é criada via ALTER TABLE por causa da dependência circular com `funcionarios`. |
| nome | VARCHAR(191) | UK | NN | Nome do departamento; único. |

### 4.3 funcionarios

Usuários do sistema (gestores e técnicos).

| Campo | Tipo | Chave | Nulo | Restrições / descrição |
| --- | --- | --- | --- | --- |
| id | INT | PK | NN | AUTO\_INCREMENT. |
| departamento\_id | INT | FK | NN | Referencia `departamentos(id)`. |
| usuario | VARCHAR(191) | UK | NN | Login do usuário; único. |
| senha\_hash | VARCHAR(255) | – | NN | Hash da senha (nunca a senha em texto puro). |
| nome | VARCHAR(191) | – | NN | Nome completo. |
| tipo | ENUM('gestor','tecnico') | – | NN | DEFAULT 'tecnico'. Perfil do funcionário. |
| ativo | BOOLEAN | – | NN | DEFAULT TRUE. |

### 4.4 locais\_operacionais

Unidades/locais de operação de cada cliente.

| Campo | Tipo | Chave | Nulo | Restrições / descrição |
| --- | --- | --- | --- | --- |
| id | INT | PK | NN | AUTO\_INCREMENT. |
| cliente\_id | INT | FK | NN | Referencia `clientes(id)`. |
| descricao | VARCHAR(191) | – | NN | Descrição do local. |
| tipo | ENUM('offshore','onshore') | – | NN | Tipo do ambiente de operação. |

Restrição adicional: `uk_local_id_cliente` UNIQUE (id, cliente\_id), necessária para a FK composta de `ordens_servico`, que garante que o local pertence ao mesmo cliente da OS.

### 4.5 projetos

Projetos contratados por um cliente.

| Campo | Tipo | Chave | Nulo | Restrições / descrição |
| --- | --- | --- | --- | --- |
| id | INT | PK | NN | AUTO\_INCREMENT. |
| cliente\_id | INT | FK | NN | Referencia `clientes(id)`. |
| data\_inicio | DATETIME | – | Aceita NULL | Início do projeto. |
| data\_fim | DATETIME | – | Aceita NULL | Término do projeto. |
| status | ENUM('em\_planejamento','em\_andamento','pausado','concluido') | – | NN | DEFAULT 'em\_planejamento'. |
| nome | VARCHAR(191) | – | NN | Nome do projeto. |
| ativo | BOOLEAN | – | NN | DEFAULT TRUE. |

Restrições adicionais:

- `uk_projeto_id_cliente` UNIQUE (id, cliente\_id): permite a FK composta de `ordens_servico`.
- `chk_projeto_datas`: `data_fim` deve ser maior ou igual a `data_inicio` (quando ambas existem).
- `chk_projeto_concluido`: projeto com status 'concluido' exige `data_fim` preenchida.

### 4.6 feriados

Calendário de feriados usado no cálculo de prazos em dias úteis.

| Campo | Tipo | Chave | Nulo | Restrições / descrição |
| --- | --- | --- | --- | --- |
| id | INT | PK | NN | AUTO\_INCREMENT. |
| data | DATE | UK (com descricao) | NN | Data do feriado. |
| descricao | VARCHAR(191) | UK (com data) | NN | Nome do feriado. |
| abrangencia | ENUM('nacional','estadual','municipal') | – | NN | DEFAULT 'nacional'. |
| uf | CHAR(2) | – | Aceita NULL | Estado (obrigatório para estadual e municipal). |
| municipio | VARCHAR(191) | – | Aceita NULL | Município (obrigatório só para municipal). |

Restrições adicionais: `uk_feriado` UNIQUE (data, descricao); `chk_feriado_abrangencia` exige: nacional sem uf/município, estadual com uf e sem município, municipal com uf e município.

### 4.7 sla\_config

Configuração padrão de SLA por tipo de serviço e criticidade.

| Campo | Tipo | Chave | Nulo | Restrições / descrição |
| --- | --- | --- | --- | --- |
| id | INT | PK | NN | AUTO\_INCREMENT. |
| tipo | ENUM('instalacao','manutencao') | UK (com criticidade) | NN | Tipo de serviço. |
| criticidade | ENUM('baixo','medio','alto','muito\_alto','urgente') | UK (com tipo) | NN | Nível de criticidade. |
| prazo\_dias\_uteis | INT | – | NN | Prazo em dias úteis. |

Restrições adicionais: `config_unica` UNIQUE (tipo, criticidade); `chk_sla_prazo_positivo` (prazo\_dias\_uteis > 0).

### 4.8 ordens\_servico

Tabela central do sistema: ordens de serviço (OS).

| Campo | Tipo | Chave | Nulo | Restrições / descrição |
| --- | --- | --- | --- | --- |
| id | INT | PK | NN | AUTO\_INCREMENT. |
| departamento\_id | INT | FK | NN | Referencia `departamentos(id)`. |
| cliente\_id | INT | FK | NN | Referencia `clientes(id)`. |
| solicitante\_id | INT | FK | NN | Referencia `funcionarios(id)`. Quem abriu a OS. |
| responsavel\_id | INT | FK | Aceita NULL | Referencia `funcionarios(id)`. Responsável pela execução. |
| projeto\_id | INT | FK (composta) | Aceita NULL | Referencia `projetos(id, cliente_id)`. |
| local\_id | INT | FK (composta) | Aceita NULL | Referencia `locais_operacionais(id, cliente_id)`. |
| anterior\_id | INT | FK | Aceita NULL | Autorrelacionamento com `ordens_servico(id)`: OS anterior. |
| parecer\_tecnico | TEXT | – | Aceita NULL | Parecer técnico final. |
| tipo | ENUM('instalacao','manutencao') | – | NN | DEFAULT 'instalacao'. |
| criticidade | ENUM('baixo','medio','alto','muito\_alto','urgente') | – | NN | DEFAULT 'medio'. |
| titulo | VARCHAR(191) | – | NN | Título da OS. |
| descricao | TEXT | – | NN | Descrição detalhada. |
| status | ENUM('em\_andamento','aguardando','validacao\_testes','bloqueado','concluido') | – | NN | DEFAULT 'em\_andamento'. |
| data\_criacao | DATETIME | – | NN | DEFAULT CURRENT\_TIMESTAMP. |
| data\_inicio | DATETIME | – | Aceita NULL | Início da execução. |
| data\_fim | DATETIME | – | Aceita NULL | Fim da execução. |
| data\_limite\_sla | DATETIME | – | Aceita NULL | Prazo final calculado pelo SLA. |
| sla\_manual | BOOLEAN | – | NN | DEFAULT FALSE. Indica SLA definido manualmente. |
| prazo\_dias\_uteis | INT | – | Aceita NULL | Prazo manual (só com SLA manual). |
| justificativa\_sla\_manual | TEXT | – | Aceita NULL | Justificativa do SLA manual. |
| ativo | BOOLEAN | – | NN | DEFAULT TRUE. |

Restrições adicionais:

- As FKs compostas `fk_os_projeto` (projeto\_id, cliente\_id) e `fk_os_local` (local\_id, cliente\_id) garantem que projeto e local pertençam ao mesmo cliente da OS.
- `chk_os_datas`: `data_fim` maior ou igual a `data_inicio`.
- `chk_os_concluida_com_data_fim`: OS 'concluido' exige `data_fim`.
- `chk_os_sla_manual`: se `sla_manual = 0`, prazo e justificativa devem ser NULL; se `sla_manual = 1`, prazo deve ser maior que 0 e a justificativa obrigatória.
- Índices: `idx_os_criticidade_limite` (criticidade, data\_limite\_sla), `idx_os_departamento_status` (departamento\_id, status), `idx_os_responsavel_status` (responsavel\_id, status).

### 4.9 anexos

Arquivos anexados às OS.

| Campo | Tipo | Chave | Nulo | Restrições / descrição |
| --- | --- | --- | --- | --- |
| id | INT | PK | NN | AUTO\_INCREMENT. |
| os\_id | INT | FK | NN | Referencia `ordens_servico(id)`. |
| enviado\_por\_id | INT | FK | NN | Referencia `funcionarios(id)`. |
| nome | VARCHAR(255) | – | NN | Nome do arquivo. |
| tipo\_mime | VARCHAR(100) | – | NN | Tipo MIME (ex.: image/png). |
| tamanho\_bytes | BIGINT | – | NN | Tamanho em bytes (trigger exige valor positivo). |
| caminho | VARCHAR(191) | UK | NN | Caminho de armazenamento; único. |
| data\_upload | DATETIME(6) | – | NN | DEFAULT CURRENT\_TIMESTAMP(6). |
| descricao | TEXT | – | Aceita NULL | Descrição do anexo. |

Índice: `idx_anexos_os_data` (os\_id, data\_upload).

### 4.10 auditoria

Histórico de alterações das OS.

| Campo | Tipo | Chave | Nulo | Restrições / descrição |
| --- | --- | --- | --- | --- |
| id | INT | PK | NN | AUTO\_INCREMENT. |
| os\_id | INT | FK | NN | Referencia `ordens_servico(id)`. |
| funcionario\_id | INT | FK | Aceita NULL | Referencia `funcionarios(id)`. NULL = alteração automática/sistema. |
| data\_modificacao | DATETIME(6) | – | NN | DEFAULT CURRENT\_TIMESTAMP(6). |
| acao | ENUM('insercao','atualizacao','exclusao') | – | NN | Tipo da ação. |
| campo\_alterado | VARCHAR(191) | – | Aceita NULL | Campo modificado. |
| dado\_antigo | TEXT | – | Aceita NULL | Valor anterior. |
| dado\_novo | TEXT | – | Aceita NULL | Novo valor. |
| justificativa | TEXT | – | Aceita NULL | Motivo da alteração. |

Índice: `idx_auditoria_os_data` (os\_id, data\_modificacao).

### 4.11 equipes

Tabela associativa (N:N) entre funcionários e OS: define a equipe de cada OS.

| Campo | Tipo | Chave | Nulo | Restrições / descrição |
| --- | --- | --- | --- | --- |
| funcionario\_id | INT | PK (composta) + FK | NN | Referencia `funcionarios(id)`. |
| os\_id | INT | PK (composta) + FK | NN | Referencia `ordens_servico(id)`. |

A PK composta (funcionario\_id, os\_id) impede o mesmo funcionário duas vezes na mesma OS.

### 4.12 apontamento\_horas

Horas trabalhadas por funcionário em cada OS.

| Campo | Tipo | Chave | Nulo | Restrições / descrição |
| --- | --- | --- | --- | --- |
| id | INT | PK | NN | AUTO\_INCREMENT. |
| funcionario\_id | INT | FK | NN | Referencia `funcionarios(id)`. |
| os\_id | INT | FK | NN | Referencia `ordens_servico(id)`. |
| data\_trabalho | DATE | – | NN | Dia em que o trabalho foi feito. |
| duracao\_minutos | INT | – | NN | CHECK `chk_duracao_positiva` (maior que 0). |
| descricao | TEXT | – | Aceita NULL | Atividade realizada. |
| data\_criacao | DATETIME(6) | – | NN | DEFAULT CURRENT\_TIMESTAMP(6). |

Índice: `idx_apontamentos_funcionario_data` (funcionario\_id, data\_trabalho).

### 4.13 auditoria\_projetos

Histórico de alterações dos projetos.

| Campo | Tipo | Chave | Nulo | Restrições / descrição |
| --- | --- | --- | --- | --- |
| id | INT | PK | NN | AUTO\_INCREMENT. |
| projeto\_id | INT | FK | NN | Referencia `projetos(id)`. |
| funcionario\_id | INT | FK | Aceita NULL | Referencia `funcionarios(id)`. NULL = alteração automática. |
| data\_modificacao | DATETIME(6) | – | NN | DEFAULT CURRENT\_TIMESTAMP(6). |
| acao | ENUM('insercao','atualizacao','exclusao') | – | NN | Tipo da ação. |
| campo\_alterado | VARCHAR(191) | – | Aceita NULL | Campo modificado. |
| dado\_antigo | TEXT | – | Aceita NULL | Valor anterior. |
| dado\_novo | TEXT | – | Aceita NULL | Novo valor. |
| justificativa | TEXT | – | Aceita NULL | Motivo da alteração. |

Índice: `idx_auditoria_projetos_data` (projeto\_id, data\_modificacao).

### 4.14 projetos\_departamentos

Tabela associativa (N:N) entre projetos e departamentos envolvidos.

| Campo | Tipo | Chave | Nulo | Restrições / descrição |
| --- | --- | --- | --- | --- |
| projeto\_id | INT | PK (composta) + FK | NN | Referencia `projetos(id)`. |
| departamento\_id | INT | PK (composta) + FK | NN | Referencia `departamentos(id)`. |

### 4.15 Resumo dos relacionamentos (chaves estrangeiras)

| Tabela (filha) | Coluna(s) | Referencia (pai) | Cardinalidade |
| --- | --- | --- | --- |
| funcionarios | departamento\_id | departamentos(id) | N:1 |
| departamentos | responsavel\_id | funcionarios(id) | N:1 (opcional) |
| locais\_operacionais | cliente\_id | clientes(id) | N:1 |
| projetos | cliente\_id | clientes(id) | N:1 |
| ordens\_servico | departamento\_id | departamentos(id) | N:1 |
| ordens\_servico | cliente\_id | clientes(id) | N:1 |
| ordens\_servico | solicitante\_id, responsavel\_id | funcionarios(id) | N:1 |
| ordens\_servico | (projeto\_id, cliente\_id) | projetos(id, cliente\_id) | N:1 (opcional) |
| ordens\_servico | (local\_id, cliente\_id) | locais\_operacionais(id, cliente\_id) | N:1 (opcional) |
| ordens\_servico | anterior\_id | ordens\_servico(id) | N:1 (autorrelacionamento) |
| anexos | os\_id, enviado\_por\_id | ordens\_servico(id), funcionarios(id) | N:1 |
| auditoria | os\_id, funcionario\_id | ordens\_servico(id), funcionarios(id) | N:1 |
| equipes | funcionario\_id, os\_id | funcionarios(id), ordens\_servico(id) | N:N |
| apontamento\_horas | funcionario\_id, os\_id | funcionarios(id), ordens\_servico(id) | N:1 |
| auditoria\_projetos | projeto\_id, funcionario\_id | projetos(id), funcionarios(id) | N:1 |
| projetos\_departamentos | projeto\_id, departamento\_id | projetos(id), departamentos(id) | N:N |

A tabela `feriados` e a tabela `sla_config` não possuem chaves estrangeiras: são tabelas de parametrização consultadas para calcular `data_limite_sla`.

### 4.16 Objetos programáveis do banco

| Tipo | Nome | Finalidade |
| --- | --- | --- |
| View | vw\_resumo\_ordens | Resumo das OS com cliente, departamento, responsável, SLA e total de minutos. |
| View | vw\_horas\_funcionario | Quantidade de apontamentos e minutos trabalhados por funcionário. |
| View | vw\_projetos\_clientes | Projetos com seu cliente e a quantidade de OS. |
| Function | fn\_total\_horas\_os(os\_id) | Total de horas apontadas em uma OS. |
| Function | fn\_quantidade\_os\_funcionario(funcionario\_id) | Quantidade de OS em que o funcionário está na equipe. |
| Function | fn\_status\_cliente(cliente\_id) | Retorna ATIVO, INATIVO ou NAO ENCONTRADO. |
| Function | fn\_media\_horas\_departamento(departamento\_id) | Média de horas por apontamento no departamento. |
| Function | fn\_os\_atrasadas\_cliente(cliente\_id) | Quantidade de OS não concluídas com SLA vencido. |
| Function | fn\_percentual\_conclusao\_projeto(projeto\_id) | Percentual de OS concluídas do projeto. |
| Procedure | sp\_listar\_os\_cliente | Lista as OS de um cliente. |
| Procedure | sp\_resumo\_departamentos | Total de OS e concluídas por departamento. |
| Procedure | sp\_registrar\_apontamento | Registra horas trabalhadas, validando a duração. |
| Procedure | sp\_atualizar\_status\_os | Altera o status da OS com validação e auditoria. |
| Procedure | sp\_relatorio\_horas\_periodo | Horas por funcionário em um período. |
| Procedure | sp\_processar\_fila\_os | Move as OS 'aguardando' para 'em\_andamento' usando cursor, por criticidade. |
| Trigger | trg\_os\_auditoria\_insert | Grava auditoria ao criar uma OS. |
| Trigger | trg\_os\_auditoria\_update | Grava auditoria quando o status da OS muda. |
| Trigger | trg\_os\_preencher\_data\_fim | Preenche `data_fim` ao concluir a OS. |
| Trigger | trg\_apontamento\_validar | Bloqueia apontamento com duração menor ou igual a zero. |
| Trigger | trg\_projeto\_auditoria\_update | Grava auditoria quando o status do projeto muda. |
| Trigger | trg\_anexo\_validar\_tamanho | Bloqueia anexo com tamanho menor ou igual a zero. |

## Parte 5 – Conexão do projeto API ao banco de dados

### 5.1 Funcionalidade escolhida

**Atualizar o status de uma Ordem de Serviço e informar o andamento do projeto.**

Endpoint: `PATCH /api/ordens-servico/:id/status`

Objetos armazenados utilizados (o enunciado pede pelo menos um de cada):

- **Procedimento armazenado:** `sp_atualizar_status_os`
- **Função armazenada:** `fn_percentual_conclusao_projeto`

### 5.2 Problema que está sendo resolvido

Quando um técnico muda o status de uma OS (por exemplo, de "em andamento" para "aguardando"), a API precisa garantir que a regra de negócio esteja dentro do banco, e não espalhada pelo código da aplicação:

- validar se o status informado existe e se a OS existe;
- gravar a alteração e registrar a auditoria (quem alterou, valor antigo, valor novo e justificativa) de forma consistente, uma única vez, via trigger;
- devolver ao cliente da API o novo percentual de conclusão do projeto ao qual a OS pertence.

Ao usar a procedure e a function, a mesma regra vale para qualquer sistema que acesse o banco, e a API fica apenas como camada de transporte (HTTP para SQL).

### 5.3 Código SQL

Objetos já existentes em `select.sql` (reaproveitados pela API, sem alteração):

```sql
-- Procedimento: valida o status, atualiza a OS e deixa o trigger gravar a auditoria
CALL sp_atualizar_status_os(5, 'aguardando', 5, 'Teste de atualização via procedure');

-- Função: percentual de OS concluídas do projeto da OS
SELECT projeto_id,
       fn_percentual_conclusao_projeto(projeto_id) AS percentual_conclusao
FROM ordens_servico
WHERE id = 5;

-- Conferência da auditoria gravada pelo trigger trg_os_auditoria_update
SELECT id, os_id, funcionario_id, acao, dado_antigo, dado_novo, justificativa
FROM auditoria
WHERE os_id = 5
ORDER BY id;
```

### 5.4 Código da API (Node.js + Express + mysql2)

Observação: como o código do projeto API não veio no arquivo enviado, usei Node.js com Express e mysql2, que é uma stack comum. Se a sua API usa outra tecnologia (Spring Boot, .NET, Flask etc.), a lógica é a mesma: abrir conexão, executar `CALL` e depois o `SELECT` com a função.

Arquivo `db.js` (conexão com o banco):

```javascript
const mysql = require('mysql2/promise');

const pool = mysql.createPool({
  host: process.env.DB_HOST || 'localhost',
  port: process.env.DB_PORT || 3306,
  user: process.env.DB_USER || 'root',
  password: process.env.DB_PASSWORD || '',
  database: 'gestao_servicos',
  waitForConnections: true,
  connectionLimit: 10,
});

module.exports = pool;
```

Arquivo `server.js` (rota que usa a procedure e a function):

```javascript
const express = require('express');
const pool = require('./db');

const app = express();
app.use(express.json());

app.patch('/api/ordens-servico/:id/status', async (req, res) => {
  const osId = Number(req.params.id);
  const { status, funcionario_id, justificativa } = req.body;

  if (!status || !funcionario_id) {
    return res.status(400).json({ erro: 'Informe status e funcionario_id' });
  }

  try {
    // 1) PROCEDIMENTO ARMAZENADO: valida, atualiza e audita
    const [resultadoCall] = await pool.query(
      'CALL sp_atualizar_status_os(?, ?, ?, ?)',
      [osId, status, funcionario_id, justificativa || null]
    );
    // CALL devolve [ [linhas do SELECT final], OkPacket ]
    const retornoProcedure = resultadoCall[0][0];

    // 2) FUNÇÃO ARMAZENADA: percentual de conclusão do projeto da OS
    const [linhas] = await pool.query(
      `SELECT projeto_id,
              fn_percentual_conclusao_projeto(projeto_id) AS percentual_conclusao
         FROM ordens_servico
        WHERE id = ?`,
      [osId]
    );

    return res.json({
      ordem_servico: retornoProcedure,
      projeto: linhas[0] || null,
    });
  } catch (err) {
    // SIGNAL SQLSTATE '45000' da procedure = erro de regra de negócio
    if (err.sqlState === '45000') {
      const naoEncontrada = err.sqlMessage.includes('não encontrada');
      return res.status(naoEncontrada ? 404 : 400).json({ erro: err.sqlMessage });
    }
    console.error(err);
    return res.status(500).json({ erro: 'Erro interno do servidor' });
  }
});

app.listen(3000, () => console.log('API em http://localhost:3000'));
```

Instalação e execução:

```bash
npm init -y
npm install express mysql2
node server.js
```

### 5.5 Retorno obtido

Requisição (pode ser feita no Postman, Insomnia ou com curl):

```bash
curl -X PATCH http://localhost:3000/api/ordens-servico/5/status \
  -H "Content-Type: application/json" \
  -d '{"status":"aguardando","funcionario_id":5,"justificativa":"Teste de atualização via procedure"}'
```

Resposta esperada (HTTP 200), considerando a massa de dados de `insert.sql`, em que a OS 5 está "em\_andamento" e pertence ao projeto 5, que ainda não tem nenhuma OS concluída:

```json
{
  "ordem_servico": {
    "os_atualizada": 5,
    "status_anterior": "em_andamento",
    "status_atual": "aguardando",
    "observacao": "Status atualizado e auditoria registrada"
  },
  "projeto": {
    "projeto_id": 5,
    "percentual_conclusao": "0.00"
  }
}
```

Casos de erro tratados (também vêm da procedure):

| Situação | Resposta |
| --- | --- |
| Status fora da lista permitida (ex.: "xpto") | HTTP 400, `{"erro": "Status inválido"}` |
| OS inexistente (ex.: id 999) | HTTP 404, `{"erro": "Ordem de serviço não encontrada"}` |
| Mesmo status que a OS já tinha | HTTP 200, com a observação "Status já era o informado; nada alterado" |

Para a entrega: execute a requisição, tire um print da resposta no Postman (ou terminal) e outro da consulta de auditoria da seção 5.3, que deve mostrar uma nova linha para a OS 5 com `dado_antigo = em_andamento` e `dado_novo = aguardando`, e cole os prints nesta seção. Antes de testar, rode na ordem `create.sql`, `insert.sql` e `select.sql` (este último cria as functions, procedures e triggers).
