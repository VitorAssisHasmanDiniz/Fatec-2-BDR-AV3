-- ============================================================
-- ARQUIVO 3 DE 3: VIEWS, FUNCTIONS, PROCEDURES, TRIGGERS E CONSULTAS DE TESTE
-- Execute depois do 01_criacao.sql e do 02_insercao.sql.
-- Pode ser reexecutado quantas vezes quiser (faz DROP IF EXISTS antes de criar).
-- Se rodar de novo depois de testar, rode 01 e 02 antes para restaurar os dados.
-- ============================================================

USE gestao_servicos;

-- Remove functions e procedures antigas (os triggers somem junto com as tabelas)
DROP FUNCTION IF EXISTS fn_total_horas_os;
DROP FUNCTION IF EXISTS fn_quantidade_os_funcionario;
DROP FUNCTION IF EXISTS fn_status_cliente;
DROP FUNCTION IF EXISTS fn_media_horas_departamento;
DROP FUNCTION IF EXISTS fn_os_atrasadas_cliente;
DROP FUNCTION IF EXISTS fn_percentual_conclusao_projeto;
DROP PROCEDURE IF EXISTS sp_listar_os_cliente;
DROP PROCEDURE IF EXISTS sp_resumo_departamentos;
DROP PROCEDURE IF EXISTS sp_registrar_apontamento;
DROP PROCEDURE IF EXISTS sp_atualizar_status_os;
DROP PROCEDURE IF EXISTS sp_relatorio_horas_periodo;
DROP PROCEDURE IF EXISTS sp_processar_fila_os;

-- 3. VIEWS (consultas reutilizáveis)
CREATE OR REPLACE VIEW vw_resumo_ordens AS
SELECT os.id, os.titulo, os.status, os.criticidade, c.nome AS cliente,
       d.nome AS departamento, f.nome AS responsavel,
       COALESCE(os.prazo_dias_uteis, s.prazo_dias_uteis) AS prazo_dias_uteis,
       os.data_limite_sla,
       COALESCE(h.total_minutos, 0) AS total_minutos
FROM ordens_servico os
INNER JOIN departamentos d ON d.id = os.departamento_id
INNER JOIN clientes c ON c.id = os.cliente_id
LEFT JOIN funcionarios f ON f.id = os.responsavel_id
LEFT JOIN sla_config s ON s.tipo = os.tipo AND s.criticidade = os.criticidade
LEFT JOIN (SELECT os_id, SUM(duracao_minutos) AS total_minutos
           FROM apontamento_horas GROUP BY os_id) h ON h.os_id = os.id;

CREATE OR REPLACE VIEW vw_horas_funcionario AS
SELECT f.id, f.nome, d.nome AS departamento,
       COUNT(a.id) AS quantidade_apontamentos,
       COALESCE(SUM(a.duracao_minutos),0) AS minutos_trabalhados
FROM funcionarios f
INNER JOIN departamentos d ON d.id = f.departamento_id
LEFT JOIN apontamento_horas a ON a.funcionario_id = f.id
GROUP BY f.id, f.nome, d.nome;

CREATE OR REPLACE VIEW vw_projetos_clientes AS
SELECT p.id, p.nome AS projeto, p.status, c.nome AS cliente,
       COUNT(os.id) AS quantidade_os
FROM projetos p
INNER JOIN clientes c ON c.id = p.cliente_id
LEFT JOIN ordens_servico os ON os.projeto_id = p.id
GROUP BY p.id, p.nome, p.status, c.nome;

-- 4. FUNCTIONS (6)
DELIMITER $$

CREATE FUNCTION fn_total_horas_os(p_os_id INT)
RETURNS DECIMAL(10,2) NOT DETERMINISTIC READS SQL DATA
BEGIN
  DECLARE v_minutos INT DEFAULT 0;
  SELECT COALESCE(SUM(duracao_minutos),0) INTO v_minutos
  FROM apontamento_horas WHERE os_id = p_os_id;
  RETURN v_minutos / 60.0;
END$$

CREATE FUNCTION fn_quantidade_os_funcionario(p_funcionario_id INT)
RETURNS INT NOT DETERMINISTIC READS SQL DATA
BEGIN
  DECLARE v_total INT DEFAULT 0;
  SELECT COUNT(*) INTO v_total FROM equipes WHERE funcionario_id = p_funcionario_id;
  RETURN v_total;
END$$

-- retorna 'NAO ENCONTRADO' quando o cliente não existe (antes retornava 'INATIVO')
CREATE FUNCTION fn_status_cliente(p_cliente_id INT)
RETURNS VARCHAR(20) NOT DETERMINISTIC READS SQL DATA
BEGIN
  RETURN COALESCE(
    (SELECT IF(ativo, 'ATIVO', 'INATIVO') FROM clientes WHERE id = p_cliente_id),
    'NAO ENCONTRADO');
END$$

CREATE FUNCTION fn_media_horas_departamento(p_departamento_id INT)
RETURNS DECIMAL(10,2) NOT DETERMINISTIC READS SQL DATA
BEGIN
  DECLARE v_media DECIMAL(10,2) DEFAULT 0;
  SELECT COALESCE(AVG(a.duracao_minutos),0) INTO v_media
  FROM apontamento_horas a
  INNER JOIN funcionarios f ON f.id = a.funcionario_id
  WHERE f.departamento_id = p_departamento_id;
  RETURN v_media / 60.0;
END$$

CREATE FUNCTION fn_os_atrasadas_cliente(p_cliente_id INT)
RETURNS INT NOT DETERMINISTIC READS SQL DATA
BEGIN
  DECLARE v_total INT DEFAULT 0;
  SELECT COUNT(*) INTO v_total FROM ordens_servico
  WHERE cliente_id = p_cliente_id AND status <> 'concluido'
    AND data_limite_sla < CURRENT_TIMESTAMP;
  RETURN v_total;
END$$

CREATE FUNCTION fn_percentual_conclusao_projeto(p_projeto_id INT)
RETURNS DECIMAL(5,2) NOT DETERMINISTIC READS SQL DATA
BEGIN
  DECLARE v_total INT DEFAULT 0;
  DECLARE v_concluidas INT DEFAULT 0;
  SELECT COUNT(*), COALESCE(SUM(status = 'concluido'),0)
    INTO v_total, v_concluidas
  FROM ordens_servico WHERE projeto_id = p_projeto_id;
  RETURN IF(v_total = 0, 0, (v_concluidas * 100.0) / v_total);
END$$

-- 5. STORED PROCEDURES (6)
CREATE PROCEDURE sp_listar_os_cliente(IN p_cliente_id INT)
BEGIN
  SELECT os.id, os.titulo, os.status, os.criticidade, f.nome AS responsavel
  FROM ordens_servico os
  LEFT JOIN funcionarios f ON f.id = os.responsavel_id
  WHERE os.cliente_id = p_cliente_id
  ORDER BY os.data_criacao DESC;
END$$

CREATE PROCEDURE sp_resumo_departamentos()
BEGIN
  SELECT d.id, d.nome, COUNT(os.id) AS total_os,
         COALESCE(SUM(os.status = 'concluido'), 0) AS os_concluidas
  FROM departamentos d
  LEFT JOIN ordens_servico os ON os.departamento_id = d.id
  GROUP BY d.id, d.nome ORDER BY total_os DESC;
END$$

CREATE PROCEDURE sp_registrar_apontamento(
  IN p_funcionario_id INT, IN p_os_id INT, IN p_data DATE,
  IN p_minutos INT, IN p_descricao TEXT
)
BEGIN
  IF p_minutos <= 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'A duração deve ser maior que zero';
  END IF;
  INSERT INTO apontamento_horas(funcionario_id, os_id, data_trabalho, duracao_minutos, descricao)
  VALUES(p_funcionario_id, p_os_id, p_data, p_minutos, p_descricao);
  SELECT LAST_INSERT_ID() AS apontamento_criado;
END$$

-- A auditoria da mudança de status é gravada pelo trigger trg_os_auditoria_update.
-- A procedure só informa ao trigger quem fez a mudança e o motivo (variáveis de sessão),
-- evitando o registro duplicado que existia antes.
CREATE PROCEDURE sp_atualizar_status_os(
  IN p_os_id INT, IN p_novo_status VARCHAR(30), IN p_funcionario_id INT,
  IN p_justificativa TEXT
)
BEGIN
  DECLARE v_antigo VARCHAR(30);
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    SET @app_funcionario_id = NULL;
    SET @app_justificativa = NULL;
    RESIGNAL;
  END;

  IF p_novo_status NOT IN ('em_andamento','aguardando','validacao_testes','bloqueado','concluido') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Status inválido';
  END IF;

  SET v_antigo = (SELECT status FROM ordens_servico WHERE id = p_os_id);
  IF v_antigo IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Ordem de serviço não encontrada';
  END IF;

  IF v_antigo = p_novo_status THEN
    SELECT p_os_id AS os_atualizada, v_antigo AS status_anterior,
           p_novo_status AS status_atual, 'Status já era o informado; nada alterado' AS observacao;
  ELSE
    SET @app_funcionario_id = p_funcionario_id;
    SET @app_justificativa = p_justificativa;
    UPDATE ordens_servico SET status = p_novo_status WHERE id = p_os_id;
    SET @app_funcionario_id = NULL;
    SET @app_justificativa = NULL;
    SELECT p_os_id AS os_atualizada, v_antigo AS status_anterior,
           p_novo_status AS status_atual, 'Status atualizado e auditoria registrada' AS observacao;
  END IF;
END$$

CREATE PROCEDURE sp_relatorio_horas_periodo(IN p_inicio DATE, IN p_fim DATE)
BEGIN
  SELECT f.id, f.nome, d.nome AS departamento,
         SUM(a.duracao_minutos) AS minutos,
         ROUND(SUM(a.duracao_minutos)/60,2) AS horas
  FROM apontamento_horas a
  INNER JOIN funcionarios f ON f.id = a.funcionario_id
  INNER JOIN departamentos d ON d.id = f.departamento_id
  WHERE a.data_trabalho BETWEEN p_inicio AND p_fim
  GROUP BY f.id, f.nome, d.nome
  ORDER BY minutos DESC;
END$$

CREATE PROCEDURE sp_processar_fila_os()
BEGIN
  DECLARE v_fim INT DEFAULT 0;
  DECLARE v_os_id INT;
  DECLARE v_criticidade VARCHAR(20);
  DECLARE v_processadas INT DEFAULT 0;
  DECLARE cur_os CURSOR FOR
    SELECT id, criticidade FROM ordens_servico
    WHERE status = 'aguardando' ORDER BY FIELD(criticidade,'urgente','muito_alto','alto','medio','baixo');
  DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_fim = 1;

  SET @app_justificativa = 'Processamento automático da fila de OS';
  OPEN cur_os;
  leitura: LOOP
    FETCH cur_os INTO v_os_id, v_criticidade;
    IF v_fim = 1 THEN LEAVE leitura; END IF;
    UPDATE ordens_servico SET status = 'em_andamento'
    WHERE id = v_os_id;
    SET v_processadas = v_processadas + 1;
  END LOOP;
  CLOSE cur_os;
  SET @app_justificativa = NULL;
  SELECT v_processadas AS ordens_processadas;
END$$

-- 6. TRIGGERS (6)
-- Convenção: quem altera dados pode informar @app_funcionario_id e @app_justificativa
-- na sessão antes do UPDATE. Sem isso, a auditoria de mudança fica com funcionario_id NULL.
CREATE TRIGGER trg_os_auditoria_insert
AFTER INSERT ON ordens_servico FOR EACH ROW
BEGIN
  INSERT INTO auditoria(os_id, funcionario_id, acao, justificativa)
  VALUES(NEW.id, COALESCE(@app_funcionario_id, NEW.solicitante_id), 'insercao',
         COALESCE(@app_justificativa, 'Registro automático de criação da OS'));
END$$

CREATE TRIGGER trg_os_auditoria_update
AFTER UPDATE ON ordens_servico FOR EACH ROW
BEGIN
  IF OLD.status <> NEW.status THEN
    INSERT INTO auditoria(os_id, funcionario_id, acao, campo_alterado,
                          dado_antigo, dado_novo, justificativa)
    VALUES(NEW.id, @app_funcionario_id, 'atualizacao', 'status',
           OLD.status, NEW.status, @app_justificativa);
  END IF;
END$$

-- Preenche data_fim automaticamente ao concluir a OS (a validação de datas
-- em INSERT e UPDATE é feita pelos CHECKs da tabela)
CREATE TRIGGER trg_os_preencher_data_fim
BEFORE UPDATE ON ordens_servico FOR EACH ROW
BEGIN
  IF NEW.status = 'concluido' AND NEW.data_fim IS NULL THEN
    SET NEW.data_fim = NOW();
  END IF;
END$$

CREATE TRIGGER trg_apontamento_validar
BEFORE INSERT ON apontamento_horas FOR EACH ROW
BEGIN
  IF NEW.duracao_minutos <= 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Duração de apontamento inválida';
  END IF;
END$$

CREATE TRIGGER trg_projeto_auditoria_update
AFTER UPDATE ON projetos FOR EACH ROW
BEGIN
  IF OLD.status <> NEW.status THEN
    INSERT INTO auditoria_projetos(projeto_id, funcionario_id, acao,
      campo_alterado, dado_antigo, dado_novo, justificativa)
    VALUES(NEW.id, @app_funcionario_id, 'atualizacao', 'status', OLD.status, NEW.status,
      COALESCE(@app_justificativa, 'Alteração automática de status do projeto'));
  END IF;
END$$

CREATE TRIGGER trg_anexo_validar_tamanho
BEFORE INSERT ON anexos FOR EACH ROW
BEGIN
  IF NEW.tamanho_bytes <= 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'O tamanho do anexo deve ser positivo';
  END IF;
END$$

DELIMITER ;

-- 7. CONSULTAS PARA DEMONSTRAR OS RESULTADOS (prints da avaliação)
SELECT COUNT(*) AS total_clientes FROM clientes;
SELECT COUNT(*) AS total_funcionarios FROM funcionarios;
SELECT COUNT(*) AS total_ordens FROM ordens_servico;
SELECT * FROM vw_resumo_ordens LIMIT 10;
SELECT * FROM vw_horas_funcionario ORDER BY minutos_trabalhados DESC LIMIT 10;
SELECT * FROM vw_projetos_clientes LIMIT 10;

-- Exemplos de execução das 6 functions
SELECT fn_total_horas_os(1) AS horas_os_1;
SELECT fn_quantidade_os_funcionario(1) AS quantidade_os_funcionario;
SELECT fn_status_cliente(1) AS status_cliente_1;
SELECT fn_media_horas_departamento(1) AS media_horas_departamento_1;
SELECT fn_os_atrasadas_cliente(1) AS os_atrasadas_cliente_1;
SELECT fn_percentual_conclusao_projeto(1) AS percentual_conclusao_projeto_1;

-- Exemplos de execução das 6 procedures
CALL sp_listar_os_cliente(1);
CALL sp_resumo_departamentos();
CALL sp_registrar_apontamento(1, 1, '2026-11-01', 90, 'Teste de execução da procedure');
-- a OS 5 está 'em_andamento'; a procedure muda para 'aguardando' e o trigger grava UMA linha de auditoria
CALL sp_atualizar_status_os(5, 'aguardando', 5, 'Teste de atualização via procedure');
SELECT id, os_id, funcionario_id, acao, dado_antigo, dado_novo, justificativa
  FROM auditoria WHERE os_id = 5 ORDER BY id;
CALL sp_relatorio_horas_periodo('2026-10-01', '2026-10-31');
CALL sp_processar_fila_os();

-- Verificação da quantidade de registros por tabela
SELECT 'clientes' tabela, COUNT(*) registros FROM clientes
UNION ALL SELECT 'departamentos', COUNT(*) FROM departamentos
UNION ALL SELECT 'funcionarios', COUNT(*) FROM funcionarios
UNION ALL SELECT 'locais_operacionais', COUNT(*) FROM locais_operacionais
UNION ALL SELECT 'projetos', COUNT(*) FROM projetos
UNION ALL SELECT 'ordens_servico', COUNT(*) FROM ordens_servico
UNION ALL SELECT 'anexos', COUNT(*) FROM anexos
UNION ALL SELECT 'auditoria', COUNT(*) FROM auditoria
UNION ALL SELECT 'equipes', COUNT(*) FROM equipes
UNION ALL SELECT 'apontamento_horas', COUNT(*) FROM apontamento_horas
UNION ALL SELECT 'auditoria_projetos', COUNT(*) FROM auditoria_projetos
UNION ALL SELECT 'projetos_departamentos', COUNT(*) FROM projetos_departamentos
UNION ALL SELECT 'feriados', COUNT(*) FROM feriados
UNION ALL SELECT 'sla_config', COUNT(*) FROM sla_config;
