-- ============================================================
-- ARQUIVO 1 DE 3: CRIAÇÃO DO BANCO E DAS TABELAS
-- Gestão de Serviços, Projetos e Ordens de Serviço
-- MySQL 8.0.16+ (necessário para o CHECK ser realmente aplicado)
--
-- Ordem de execução:
--   1) 01_criacao.sql   (este arquivo: recria o banco do zero)
--   2) 02_insercao.sql  (dados fictícios)
--   3) 03_views_funcoes_procedures_triggers.sql
--
-- Atenção: este arquivo APAGA e recria todas as tabelas.
-- ============================================================

CREATE DATABASE IF NOT EXISTS gestao_servicos
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE gestao_servicos;

SET FOREIGN_KEY_CHECKS = 0;
DROP VIEW IF EXISTS vw_resumo_ordens;
DROP VIEW IF EXISTS vw_horas_funcionario;
DROP VIEW IF EXISTS vw_projetos_clientes;
DROP TABLE IF EXISTS auditoria_projetos, auditoria, anexos, apontamento_horas,
  equipes, projetos_departamentos, ordens_servico, sla_config, feriados,
  projetos, locais_operacionais, funcionarios, departamentos, clientes;
SET FOREIGN_KEY_CHECKS = 1;

-- 1. TABELAS
CREATE TABLE clientes (
  id INT AUTO_INCREMENT PRIMARY KEY,
  nome VARCHAR(191) NOT NULL UNIQUE,
  razao_social VARCHAR(191) NOT NULL UNIQUE,
  ramo_atuacao VARCHAR(191) NOT NULL,
  ativo BOOLEAN NOT NULL DEFAULT TRUE
) ENGINE=InnoDB;

CREATE TABLE departamentos (
  id INT AUTO_INCREMENT PRIMARY KEY,
  responsavel_id INT NULL,
  nome VARCHAR(191) NOT NULL UNIQUE
) ENGINE=InnoDB;

CREATE TABLE funcionarios (
  id INT AUTO_INCREMENT PRIMARY KEY,
  departamento_id INT NOT NULL,
  usuario VARCHAR(191) NOT NULL UNIQUE,
  senha_hash VARCHAR(255) NOT NULL,
  nome VARCHAR(191) NOT NULL,
  tipo ENUM('gestor','tecnico') NOT NULL DEFAULT 'tecnico',
  ativo BOOLEAN NOT NULL DEFAULT TRUE,
  CONSTRAINT fk_funcionario_departamento FOREIGN KEY (departamento_id)
    REFERENCES departamentos(id)
) ENGINE=InnoDB;

ALTER TABLE departamentos
  ADD CONSTRAINT fk_departamento_responsavel_funcionario
  FOREIGN KEY (responsavel_id) REFERENCES funcionarios(id);

CREATE TABLE locais_operacionais (
  id INT AUTO_INCREMENT PRIMARY KEY,
  cliente_id INT NOT NULL,
  descricao VARCHAR(191) NOT NULL,
  tipo ENUM('offshore','onshore') NOT NULL,
  CONSTRAINT fk_local_cliente FOREIGN KEY (cliente_id) REFERENCES clientes(id),
  -- permite que ordens_servico referencie (local, cliente) e garanta coerência
  CONSTRAINT uk_local_id_cliente UNIQUE (id, cliente_id)
) ENGINE=InnoDB;

CREATE TABLE projetos (
  id INT AUTO_INCREMENT PRIMARY KEY,
  cliente_id INT NOT NULL,
  data_fim DATETIME NULL,
  data_inicio DATETIME NULL,
  status ENUM('em_planejamento','em_andamento','pausado','concluido')
    NOT NULL DEFAULT 'em_planejamento',
  nome VARCHAR(191) NOT NULL,
  ativo BOOLEAN NOT NULL DEFAULT TRUE,
  CONSTRAINT fk_projeto_cliente FOREIGN KEY (cliente_id) REFERENCES clientes(id),
  -- permite que ordens_servico referencie (projeto, cliente) e garanta coerência
  CONSTRAINT uk_projeto_id_cliente UNIQUE (id, cliente_id),
  CONSTRAINT chk_projeto_datas CHECK (data_fim IS NULL OR data_inicio IS NULL OR data_fim >= data_inicio),
  CONSTRAINT chk_projeto_concluido CHECK (status <> 'concluido' OR data_fim IS NOT NULL)
) ENGINE=InnoDB;

CREATE TABLE feriados (
  id INT AUTO_INCREMENT PRIMARY KEY,
  data DATE NOT NULL,
  descricao VARCHAR(191) NOT NULL,
  abrangencia ENUM('nacional','estadual','municipal') NOT NULL DEFAULT 'nacional',
  uf CHAR(2) NULL,
  municipio VARCHAR(191) NULL,
  CONSTRAINT uk_feriado UNIQUE (data, descricao),
  CONSTRAINT chk_feriado_abrangencia CHECK (
    (abrangencia = 'nacional'  AND uf IS NULL     AND municipio IS NULL) OR
    (abrangencia = 'estadual'  AND uf IS NOT NULL AND municipio IS NULL) OR
    (abrangencia = 'municipal' AND uf IS NOT NULL AND municipio IS NOT NULL))
) ENGINE=InnoDB;

CREATE TABLE sla_config (
  id INT AUTO_INCREMENT PRIMARY KEY,
  tipo ENUM('instalacao','manutencao') NOT NULL,
  criticidade ENUM('baixo','medio','alto','muito_alto','urgente') NOT NULL,
  prazo_dias_uteis INT NOT NULL,
  CONSTRAINT config_unica UNIQUE (tipo, criticidade),
  CONSTRAINT chk_sla_prazo_positivo CHECK (prazo_dias_uteis > 0)
) ENGINE=InnoDB;

CREATE TABLE ordens_servico (
  id INT AUTO_INCREMENT PRIMARY KEY,
  departamento_id INT NOT NULL,
  cliente_id INT NOT NULL,
  solicitante_id INT NOT NULL,
  responsavel_id INT NULL,
  projeto_id INT NULL,
  local_id INT NULL,
  anterior_id INT NULL,
  parecer_tecnico TEXT NULL,
  tipo ENUM('instalacao','manutencao') NOT NULL DEFAULT 'instalacao',
  criticidade ENUM('baixo','medio','alto','muito_alto','urgente') NOT NULL DEFAULT 'medio',
  titulo VARCHAR(191) NOT NULL,
  descricao TEXT NOT NULL,
  status ENUM('em_andamento','aguardando','validacao_testes','bloqueado','concluido')
    NOT NULL DEFAULT 'em_andamento',
  data_criacao DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  data_inicio DATETIME NULL,
  data_fim DATETIME NULL,
  data_limite_sla DATETIME NULL,
  -- SLA padrão: vem de sla_config (tipo + criticidade).
  -- SLA manual: prazo e justificativa ficam na própria OS.
  sla_manual BOOLEAN NOT NULL DEFAULT FALSE,
  prazo_dias_uteis INT NULL,
  justificativa_sla_manual TEXT NULL,
  ativo BOOLEAN NOT NULL DEFAULT TRUE,
  CONSTRAINT fk_os_departamento FOREIGN KEY (departamento_id) REFERENCES departamentos(id),
  CONSTRAINT fk_os_cliente FOREIGN KEY (cliente_id) REFERENCES clientes(id),
  CONSTRAINT fk_os_solicitante FOREIGN KEY (solicitante_id) REFERENCES funcionarios(id),
  CONSTRAINT fk_os_responsavel FOREIGN KEY (responsavel_id) REFERENCES funcionarios(id),
  -- FKs compostas: o projeto e o local precisam ser do mesmo cliente da OS
  -- (se projeto_id / local_id forem NULL, a verificação é ignorada)
  CONSTRAINT fk_os_projeto FOREIGN KEY (projeto_id, cliente_id) REFERENCES projetos(id, cliente_id),
  CONSTRAINT fk_os_local FOREIGN KEY (local_id, cliente_id) REFERENCES locais_operacionais(id, cliente_id),
  CONSTRAINT fk_os_anterior FOREIGN KEY (anterior_id) REFERENCES ordens_servico(id),
  CONSTRAINT chk_os_datas CHECK (data_fim IS NULL OR data_inicio IS NULL OR data_fim >= data_inicio),
  CONSTRAINT chk_os_concluida_com_data_fim CHECK (status <> 'concluido' OR data_fim IS NOT NULL),
  CONSTRAINT chk_os_sla_manual CHECK (
    (sla_manual = 0 AND prazo_dias_uteis IS NULL AND justificativa_sla_manual IS NULL) OR
    (sla_manual = 1 AND prazo_dias_uteis > 0 AND justificativa_sla_manual IS NOT NULL)),
  INDEX idx_os_criticidade_limite (criticidade, data_limite_sla),
  INDEX idx_os_departamento_status (departamento_id, status),
  INDEX idx_os_responsavel_status (responsavel_id, status)
) ENGINE=InnoDB;

CREATE TABLE anexos (
  id INT AUTO_INCREMENT PRIMARY KEY,
  os_id INT NOT NULL,
  enviado_por_id INT NOT NULL,
  nome VARCHAR(255) NOT NULL,
  tipo_mime VARCHAR(100) NOT NULL,
  tamanho_bytes BIGINT NOT NULL,
  caminho VARCHAR(191) NOT NULL UNIQUE,
  data_upload DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  descricao TEXT NULL,
  CONSTRAINT fk_anexo_enviado_por FOREIGN KEY (enviado_por_id) REFERENCES funcionarios(id),
  CONSTRAINT fk_anexo_os FOREIGN KEY (os_id) REFERENCES ordens_servico(id),
  INDEX idx_anexos_os_data (os_id, data_upload)
) ENGINE=InnoDB;

-- funcionario_id NULL = alteração automática (sistema / sem usuário identificado)
CREATE TABLE auditoria (
  id INT AUTO_INCREMENT PRIMARY KEY,
  os_id INT NOT NULL,
  funcionario_id INT NULL,
  data_modificacao DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  acao ENUM('insercao','atualizacao','exclusao') NOT NULL,
  campo_alterado VARCHAR(191) NULL,
  dado_antigo TEXT NULL,
  dado_novo TEXT NULL,
  justificativa TEXT NULL,
  CONSTRAINT fk_auditoria_funcionario FOREIGN KEY (funcionario_id) REFERENCES funcionarios(id),
  CONSTRAINT fk_auditoria_os FOREIGN KEY (os_id) REFERENCES ordens_servico(id),
  INDEX idx_auditoria_os_data (os_id, data_modificacao)
) ENGINE=InnoDB;

CREATE TABLE equipes (
  funcionario_id INT NOT NULL,
  os_id INT NOT NULL,
  PRIMARY KEY (funcionario_id, os_id),
  CONSTRAINT fk_equipe_funcionario FOREIGN KEY (funcionario_id) REFERENCES funcionarios(id),
  CONSTRAINT fk_equipe_os FOREIGN KEY (os_id) REFERENCES ordens_servico(id)
) ENGINE=InnoDB;

CREATE TABLE apontamento_horas (
  id INT AUTO_INCREMENT PRIMARY KEY,
  funcionario_id INT NOT NULL,
  os_id INT NOT NULL,
  data_trabalho DATE NOT NULL,
  duracao_minutos INT NOT NULL,
  descricao TEXT NULL,
  data_criacao DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  CONSTRAINT fk_apontamento_funcionario FOREIGN KEY (funcionario_id) REFERENCES funcionarios(id),
  CONSTRAINT fk_apontamento_os FOREIGN KEY (os_id) REFERENCES ordens_servico(id),
  CONSTRAINT chk_duracao_positiva CHECK (duracao_minutos > 0),
  INDEX idx_apontamentos_funcionario_data (funcionario_id, data_trabalho)
) ENGINE=InnoDB;

-- funcionario_id NULL = alteração automática (sistema / sem usuário identificado)
CREATE TABLE auditoria_projetos (
  id INT AUTO_INCREMENT PRIMARY KEY,
  projeto_id INT NOT NULL,
  funcionario_id INT NULL,
  data_modificacao DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  acao ENUM('insercao','atualizacao','exclusao') NOT NULL,
  campo_alterado VARCHAR(191) NULL,
  dado_antigo TEXT NULL,
  dado_novo TEXT NULL,
  justificativa TEXT NULL,
  CONSTRAINT fk_audproj_funcionario FOREIGN KEY (funcionario_id) REFERENCES funcionarios(id),
  CONSTRAINT fk_audproj_projeto FOREIGN KEY (projeto_id) REFERENCES projetos(id),
  INDEX idx_auditoria_projetos_data (projeto_id, data_modificacao)
) ENGINE=InnoDB;

CREATE TABLE projetos_departamentos (
  projeto_id INT NOT NULL,
  departamento_id INT NOT NULL,
  PRIMARY KEY (projeto_id, departamento_id),
  CONSTRAINT fk_projdep_projeto FOREIGN KEY (projeto_id) REFERENCES projetos(id),
  CONSTRAINT fk_projdep_departamento FOREIGN KEY (departamento_id) REFERENCES departamentos(id)
) ENGINE=InnoDB;
