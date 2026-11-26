const $ = seletor => document.querySelector(seletor)
const formatar = valor => Number(valor || 0).toLocaleString('pt-BR', {maximumFractionDigits:2})
async function requisicao(url, opcoes={}) {
  const resposta = await fetch(url, opcoes)
  const dados = await resposta.json()
  if (!resposta.ok) throw new Error(dados.erro || 'Falha na solicitação')
  return dados
}
function tabela(dados) {
  if (!dados?.length) return '<p>Nenhum registro encontrado.</p>'
  const colunas = Object.keys(dados[0])
  return `<div class="tablewrap"><table><thead><tr>${colunas.map(c=>`<th>${c}</th>`).join('')}</tr></thead><tbody>${dados.map(row=>`<tr>${colunas.map(c=>`<td>${row[c] ?? '—'}</td>`).join('')}</tr>`).join('')}</tbody></table></div>`
}
function mensagem(elemento, texto, tipo='') { elemento.innerHTML = texto; elemento.className = `resultado ${tipo}` }
async function iniciar() {
  try {
    const status = await requisicao('/api/saude')
    $('#conexao').textContent = 'Banco conectado'
    $('#conexao').classList.add('sucesso')
    const clientes = await requisicao('/api/clientes')
    $('#cliente').innerHTML = clientes.map(c=>`<option value="${c.id}">${c.nome} ${c.ativo?'':'(inativo)'}</option>`).join('')
    if (clientes.length) consultarCliente()
  } catch(e) {
    $('#conexao').textContent = 'Erro de conexão'
    $('#conexao').classList.add('erro')
    console.error(e)
  }
}
async function consultarCliente() {
  const id = $('#cliente').value
  if (!id) return
  try {
    const dados = await requisicao(`/api/indicadores/${id}`)
    $('#statusCliente').textContent = dados.indicadores.status_cliente
    $('#atrasadas').textContent = dados.indicadores.atrasadas
    $('#ordensCliente').innerHTML = tabela(dados.ordens)
  } catch(e) { mensagem($('#ordensCliente'),e.message,'erro') }
}
$('#consultarCliente').addEventListener('click',consultarCliente)
$('#consultarHoras').addEventListener('click',async()=>{
  try { const d=await requisicao(`/api/os/${$('#osHoras').value}/horas`); $('#resultadoHoras').textContent=`${formatar(d.horas)} hora(s) contabilizada(s)` }
  catch(e){ mensagem($('#resultadoHoras'),e.message,'erro') }
})
$('#consultarProjeto').addEventListener('click',async()=>{
  try {const d=await requisicao(`/api/projetos/${$('#projetoId').value}/progresso`);const p=Number(d.percentual);$('#barraProjeto').style.width=`${Math.min(100,Math.max(0,p))}%`;$('#progressoProjeto').textContent=`${formatar(p)}% das OS do projeto concluídas`}
  catch(e){mensagem($('#progressoProjeto'),e.message,'erro')}
})
$('#formApontamento').addEventListener('submit',async e=>{
  e.preventDefault()
  const f=new FormData(e.target), payload=Object.fromEntries(f.entries())
  for(const k of ['funcionario_id','os_id','minutos'])payload[k]=Number(payload[k])
  try{const d=await requisicao('/api/apontamentos',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload)});mensagem($('#mensagemApontamento'),d.mensagem,'sucesso');e.target.reset()}
  catch(err){mensagem($('#mensagemApontamento'),err.message,'erro')}
})
$('#formStatus').addEventListener('submit',async e=>{
  e.preventDefault();const f=new FormData(e.target),p=Object.fromEntries(f.entries());p.funcionario_id=Number(p.funcionario_id)
  try{const d=await requisicao(`/api/ordens/${p.id}/status`,{method:'PATCH',headers:{'Content-Type':'application/json'},body:JSON.stringify(p)});mensagem($('#mensagemStatus'),d.mensagem,'sucesso')}
  catch(err){mensagem($('#mensagemStatus'),err.message,'erro')}
})
$('#consultarDepartamentos').addEventListener('click',async()=>{
  try{const d=await requisicao('/api/departamentos/resumo');$('#departamentos').innerHTML=tabela(d)}
  catch(e){mensagem($('#departamentos'),e.message,'erro')}
})
$('#relatorio').addEventListener('click',async()=>{
  try{const d=await requisicao(`/api/relatorio-horas?inicio=${$('#inicio').value}&fim=${$('#fim').value}`);$('#relatorioHoras').innerHTML=tabela(d)}
  catch(e){mensagem($('#relatorioHoras'),e.message,'erro')}
})
$('#processarFila').addEventListener('click',async()=>{
  try{const d=await requisicao('/api/fila/processar',{method:'POST'});mensagem($('#filaResultado'),JSON.stringify(d.resultado),'sucesso')}
  catch(e){mensagem($('#filaResultado'),e.message,'erro')}
})
iniciar()
