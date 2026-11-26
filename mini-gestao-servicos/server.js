import express from 'express'
import mysql from 'mysql2/promise'
import dotenv from 'dotenv'
import path from 'path'
import { fileURLToPath } from 'url'

dotenv.config()
const app = express()
const __dirname = path.dirname(fileURLToPath(import.meta.url))
app.use(express.json())
app.use(express.static(path.join(__dirname, 'public')))

const banco = mysql.createPool({
  host: process.env.DB_HOST || 'localhost',
  port: Number(process.env.DB_PORT || 3306),
  user: process.env.DB_USER || 'root',
  password: process.env.DB_PASSWORD || '',
  database: process.env.DB_NAME || 'gestao_servicos',
  connectionLimit: 10
})

app.get('/api/clientes', async (req, res) => {
  try {
    const [rows] = await banco.query('SELECT id, nome, ativo FROM clientes ORDER BY nome')
    res.json(rows)
  } catch (e) { res.status(500).json({ erro: e.message }) }
})

app.get('/api/ordens', async (req, res) => {
  try {
    const [rows] = await banco.query(`SELECT id, titulo, status, criticidade, cliente_id, responsavel_id, projeto_id
      FROM ordens_servico ORDER BY data_criacao DESC LIMIT 100`)
    res.json(rows)
  } catch (e) { res.status(500).json({ erro: e.message }) }
})

app.get('/api/indicadores/:clienteId', async (req, res) => {
  try {
    const id = Number(req.params.clienteId)
    const [cliente] = await banco.query('SELECT fn_status_cliente(?) AS status_cliente, fn_os_atrasadas_cliente(?) AS atrasadas', [id, id])
    const [ordens] = await banco.query('CALL sp_listar_os_cliente(?)', [id])
    res.json({ indicadores: cliente[0], ordens: ordens[0] })
  } catch (e) { res.status(500).json({ erro: e.message }) }
})

app.get('/api/os/:id/horas', async (req, res) => {
  try {
    const [rows] = await banco.query('SELECT fn_total_horas_os(?) AS horas', [Number(req.params.id)])
    res.json(rows[0])
  } catch (e) { res.status(500).json({ erro: e.message }) }
})

app.get('/api/projetos/:id/progresso', async (req, res) => {
  try {
    const [rows] = await banco.query('SELECT fn_percentual_conclusao_projeto(?) AS percentual', [Number(req.params.id)])
    res.json(rows[0])
  } catch (e) { res.status(500).json({ erro: e.message }) }
})

app.get('/api/departamentos/resumo', async (req, res) => {
  try {
    const [rows] = await banco.query('CALL sp_resumo_departamentos()')
    res.json(rows[0])
  } catch (e) { res.status(500).json({ erro: e.message }) }
})

app.post('/api/apontamentos', async (req, res) => {
  try {
    const { funcionario_id, os_id, data, minutos, descricao } = req.body
    if (![funcionario_id, os_id, minutos].every(Number.isInteger) || minutos <= 0)
      return res.status(400).json({ erro: 'Informe funcionário, OS e duração positiva em minutos.' })
    const [resultado] = await banco.query('CALL sp_registrar_apontamento(?,?,?,?,?)',
      [funcionario_id, os_id, data || new Date().toISOString().slice(0,10), minutos, descricao || null])
    res.status(201).json({ mensagem: 'Apontamento registrado.', resultado: resultado[0] })
  } catch (e) { res.status(400).json({ erro: e.message }) }
})

app.patch('/api/ordens/:id/status', async (req, res) => {
  try {
    const { status, funcionario_id, justificativa } = req.body
    const permitidos = ['em_andamento','aguardando','validacao_testes','bloqueado','concluido']
    if (!permitidos.includes(status)) return res.status(400).json({ erro: 'Status inválido.' })
    const [resultado] = await banco.query('CALL sp_atualizar_status_os(?,?,?,?)',
      [Number(req.params.id), status, Number(funcionario_id), justificativa || 'Atualização pelo mini projeto'])
    res.json({ mensagem: 'Status atualizado usando stored procedure.', resultado: resultado[0] })
  } catch (e) { res.status(400).json({ erro: e.message }) }
})

app.get('/api/relatorio-horas', async (req, res) => {
  try {
    const inicio = req.query.inicio
    const fim = req.query.fim
    if (!inicio || !fim) return res.status(400).json({ erro: 'Informe inicio e fim.' })
    const [rows] = await banco.query('CALL sp_relatorio_horas_periodo(?,?)', [inicio, fim])
    res.json(rows[0])
  } catch (e) { res.status(500).json({ erro: e.message }) }
})

app.get('/api/funcionarios/:id/os', async (req, res) => {
  try {
    const [rows] = await banco.query('SELECT fn_quantidade_os_funcionario(?) AS quantidade', [Number(req.params.id)])
    res.json(rows[0])
  } catch (e) { res.status(500).json({ erro: e.message }) }
})

app.get('/api/departamentos/:id/media-horas', async (req, res) => {
  try {
    const [rows] = await banco.query('SELECT fn_media_horas_departamento(?) AS media_horas', [Number(req.params.id)])
    res.json(rows[0])
  } catch (e) { res.status(500).json({ erro: e.message }) }
})

app.post('/api/fila/processar', async (req, res) => {
  try {
    const [rows] = await banco.query('CALL sp_processar_fila_os()')
    res.json({ mensagem: 'Fila processada.', resultado: rows[0] })
  } catch (e) { res.status(500).json({ erro: e.message }) }
})

app.get('/api/saude', async (req, res) => {
  try { await banco.query('SELECT 1'); res.json({ banco: 'conectado' }) }
  catch (e) { res.status(500).json({ banco: 'erro', erro: e.message }) }
})

const port = Number(process.env.PORT || 3000)
app.listen(port, () => console.log(`Mini projeto em http://localhost:${port}`))
