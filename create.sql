CREATE DATABASE IF NOT EXISTS gestao_servicos
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE gestao_servicos;

CREATE TABLE clientes (
  id INT AUTO_INCREMENT PRIMARY KEY,
  nome VARCHAR(191) NOT NULL UNIQUE,
  razao_social VARCHAR(191) NOT NULL UNIQUE,
  ramo_atuacao VARCHAR(191) NOT NULL,
  ativo BOOLEAN NOT NULL DEFAULT TRUE
) ENGINE=InnoDB;

CREATE TABLE departamentos (
  id INT AUTO_INCREMENT PRIMARY KEY,
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

CREATE TABLE locais_operacionais (
  id INT AUTO_INCREMENT PRIMARY KEY,
  cliente_id INT NOT NULL,
  titulo VARCHAR(191) NOT NULL,
  descricao VARCHAR(255) NULL,
  CONSTRAINT fk_local_cliente FOREIGN KEY (cliente_id) REFERENCES clientes(id)
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
  CONSTRAINT chk_projeto_datas CHECK (data_fim IS NULL OR data_inicio IS NULL OR data_fim >= data_inicio),
  CONSTRAINT chk_projeto_concluido CHECK (status <> 'concluido' OR data_fim IS NOT NULL)
) ENGINE=InnoDB;

-- Relação N:N "ligado" entre PROJETO e DEPARTAMENTO
CREATE TABLE projetos_departamentos (
  projeto_id INT NOT NULL,
  departamento_id INT NOT NULL,
  PRIMARY KEY (projeto_id, departamento_id),
  CONSTRAINT fk_projdep_projeto FOREIGN KEY (projeto_id) REFERENCES projetos(id),
  CONSTRAINT fk_projdep_departamento FOREIGN KEY (departamento_id) REFERENCES departamentos(id)
) ENGINE=InnoDB;

CREATE TABLE ordens_servico (
  id INT AUTO_INCREMENT PRIMARY KEY,
  departamento_id INT NOT NULL,
  projeto_id INT NOT NULL,
  responsavel_id INT NULL,
  titulo VARCHAR(191) NOT NULL,
  descricao TEXT NOT NULL,
  tipo ENUM('instalacao','manutencao') NOT NULL DEFAULT 'instalacao',
  criticidade ENUM('baixo','medio','alto','muito_alto','urgente') NOT NULL DEFAULT 'medio',
  status ENUM('em_andamento','aguardando','validacao_testes','bloqueado','concluido')
    NOT NULL DEFAULT 'em_andamento',
  data_criacao DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  data_inicio DATETIME NULL,
  data_fim DATETIME NULL,
  data_limite_sla DATETIME NULL,
  prazo_dias_uteis INT NOT NULL,
  sla_manual BOOLEAN NOT NULL DEFAULT FALSE,
  parecer_tecnico TEXT NULL,
  justificativa TEXT NULL,
  CONSTRAINT fk_os_departamento FOREIGN KEY (departamento_id) REFERENCES departamentos(id),
  CONSTRAINT fk_os_projeto FOREIGN KEY (projeto_id) REFERENCES projetos(id),
  CONSTRAINT fk_os_responsavel FOREIGN KEY (responsavel_id) REFERENCES funcionarios(id),
  CONSTRAINT chk_os_datas CHECK (data_fim IS NULL OR data_inicio IS NULL OR data_fim >= data_inicio),
  CONSTRAINT chk_os_concluida_com_data_fim CHECK (status <> 'concluido' OR data_fim IS NOT NULL),
  CONSTRAINT chk_os_prazo_positivo CHECK (prazo_dias_uteis > 0),
  CONSTRAINT chk_os_sla_manual CHECK (
    (sla_manual = 0 AND justificativa IS NULL) OR
    (sla_manual = 1 AND justificativa IS NOT NULL)),
  INDEX idx_os_criticidade_limite (criticidade, data_limite_sla),
  INDEX idx_os_departamento_status (departamento_id, status),
  INDEX idx_os_responsavel_status (responsavel_id, status),
  INDEX idx_os_projeto (projeto_id)
);

CREATE TABLE anexos (
  id INT AUTO_INCREMENT PRIMARY KEY,
  os_id INT NOT NULL,
  enviado_por_id INT NOT NULL,
  nome VARCHAR(255) NOT NULL,
  tipo VARCHAR(100) NOT NULL,
  tamanho_bytes BIGINT NOT NULL,
  caminho VARCHAR(191) NOT NULL UNIQUE,
  data_upload DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  relato TEXT NULL,
  CONSTRAINT fk_anexo_enviado_por FOREIGN KEY (enviado_por_id) REFERENCES funcionarios(id),
  CONSTRAINT fk_anexo_os FOREIGN KEY (os_id) REFERENCES ordens_servico(id),
  INDEX idx_anexos_os_data (os_id, data_upload)
);

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
);

CREATE TABLE auditoria (
  id INT AUTO_INCREMENT PRIMARY KEY,
  os_id INT NOT NULL,
  funcionario_id INT NULL,
  entidade VARCHAR(50) NOT NULL DEFAULT 'ordem_servico',
  data_modificacao DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  acao ENUM('insercao','atualizacao','exclusao') NOT NULL,
  campo_alterado VARCHAR(191) NULL,
  dado_antigo TEXT NULL,
  dado_novo TEXT NULL,
  justificativa TEXT NULL,
  CONSTRAINT fk_auditoria_funcionario FOREIGN KEY (funcionario_id) REFERENCES funcionarios(id),
  CONSTRAINT fk_auditoria_os FOREIGN KEY (os_id) REFERENCES ordens_servico(id),
  INDEX idx_auditoria_os_data (os_id, data_modificacao)
);

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
);
