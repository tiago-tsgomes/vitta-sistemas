interface Anexo {
  filename: string
  content: string // base64
}

interface EnviarEmailOpts {
  to: string
  toName?: string
  subject: string
  html: string
  attachments?: Anexo[]
  conta?: 'padrao' | 'noreply'
}

// Cliente SMTP mínimo, implementado diretamente sobre Deno.connectTls, sem
// depender de bibliotecas de terceiros para montar a mensagem MIME. Motivo:
// o denomailer (usado antes) monta o cabeçalho "From" e os boundaries MIME
// com uma lógica interna não documentada (boundaries previsíveis calculados
// via regex) que, em alguns envios, resultava em mensagens rejeitadas pelo
// servidor com "550 ... 'From' header does not exist" mesmo com anexos
// pequenos — indicando corrupção na montagem da mensagem, não no conteúdo.
// Aqui montamos a mensagem RFC 5322 inteira nós mesmos, com boundaries
// aleatórios (crypto.randomUUID) e o cabeçalho From sempre presente.

function chunkBase64(base64: string, lineLen = 76): string {
  const clean = base64.replace(/[\r\n]/g, '')
  const linhas: string[] = []
  for (let i = 0; i < clean.length; i += lineLen) linhas.push(clean.slice(i, i + lineLen))
  return linhas.join('\r\n')
}

function textoParaBase64(texto: string): string {
  const bytes = new TextEncoder().encode(texto)
  let binary = ''
  for (const byte of bytes) binary += String.fromCharCode(byte)
  return chunkBase64(btoa(binary))
}

function codificarHeader(valor: string): string {
  // encoded-word (RFC 2047) para nomes/assuntos com acentos
  if (/^[\x20-\x7e]*$/.test(valor)) return valor
  const bytes = new TextEncoder().encode(valor)
  let binary = ''
  for (const byte of bytes) binary += String.fromCharCode(byte)
  return `=?UTF-8?B?${btoa(binary)}?=`
}

function novoBoundary(prefixo: string): string {
  return `----=_${prefixo}_${crypto.randomUUID().replace(/-/g, '')}`
}

function aplicarDotStuffing(mensagem: string): string {
  return mensagem.split('\r\n').map(l => (l.startsWith('.') ? '.' + l : l)).join('\r\n')
}

function montarMensagem(opts: {
  fromName: string
  fromAddr: string
  toName?: string
  toAddr: string
  subject: string
  html: string
  attachments: Anexo[]
}): string {
  const mixedBoundary = novoBoundary('mixed')
  const altBoundary = novoBoundary('alt')
  const textoAlternativo = 'Este email contém conteúdo em HTML. Abra em um cliente de email compatível para visualizar corretamente.'

  const linhas: string[] = []
  linhas.push(`Date: ${new Date().toUTCString().replace('GMT', '+0000')}`)
  linhas.push(`From: ${codificarHeader(opts.fromName)} <${opts.fromAddr}>`)
  linhas.push(`To: ${opts.toName ? `${codificarHeader(opts.toName)} <${opts.toAddr}>` : `<${opts.toAddr}>`}`)
  linhas.push(`Subject: ${codificarHeader(opts.subject)}`)
  linhas.push(`MIME-Version: 1.0`)
  linhas.push(`Content-Type: multipart/mixed; boundary="${mixedBoundary}"`)
  linhas.push('')
  linhas.push(`--${mixedBoundary}`)
  linhas.push(`Content-Type: multipart/alternative; boundary="${altBoundary}"`)
  linhas.push('')
  linhas.push(`--${altBoundary}`)
  linhas.push(`Content-Type: text/plain; charset="utf-8"`)
  linhas.push(`Content-Transfer-Encoding: base64`)
  linhas.push('')
  linhas.push(textoParaBase64(textoAlternativo))
  linhas.push('')
  linhas.push(`--${altBoundary}`)
  linhas.push(`Content-Type: text/html; charset="utf-8"`)
  linhas.push(`Content-Transfer-Encoding: base64`)
  linhas.push('')
  linhas.push(textoParaBase64(opts.html))
  linhas.push('')
  linhas.push(`--${altBoundary}--`)

  for (const anexo of opts.attachments) {
    linhas.push(`--${mixedBoundary}`)
    linhas.push(`Content-Type: application/pdf; name="${anexo.filename}"`)
    linhas.push(`Content-Disposition: attachment; filename="${anexo.filename}"`)
    linhas.push(`Content-Transfer-Encoding: base64`)
    linhas.push('')
    linhas.push(chunkBase64(anexo.content))
    linhas.push('')
  }

  linhas.push(`--${mixedBoundary}--`)
  linhas.push('')

  return linhas.join('\r\n')
}

async function escreverTudo(conn: Deno.Conn, dados: Uint8Array) {
  let escrito = 0
  while (escrito < dados.length) {
    escrito += await conn.write(dados.subarray(escrito))
  }
}

async function enviarComando(conn: Deno.Conn, comando: string) {
  await escreverTudo(conn, new TextEncoder().encode(comando + '\r\n'))
}

async function lerResposta(conn: Deno.Conn): Promise<string> {
  const decoder = new TextDecoder()
  const buf = new Uint8Array(4096)
  let acumulado = ''
  while (true) {
    const n = await conn.read(buf)
    if (n === null) throw new Error('Conexão SMTP encerrada inesperadamente')
    acumulado += decoder.decode(buf.subarray(0, n), { stream: true })
    if (acumulado.endsWith('\r\n')) {
      const linhas = acumulado.trim().split('\r\n')
      const ultima = linhas[linhas.length - 1]
      if (/^\d{3} /.test(ultima)) return acumulado
      // linha com "-" no lugar do espaço = resposta multi-linha, continua lendo
    }
  }
}

function codigoDe(resposta: string): number {
  const linhas = resposta.trim().split('\r\n')
  return parseInt(linhas[linhas.length - 1].slice(0, 3), 10)
}

function assertCodigo(resposta: string, esperado: number) {
  if (codigoDe(resposta) !== esperado) {
    throw new Error(`${resposta.trim().split('\r\n').pop()}`)
  }
}

// Serializa envios para nunca haver duas conexões SMTP simultâneas
// escrevendo na mesma instância "quente" da Edge Function.
let filaEnvio: Promise<unknown> = Promise.resolve()

export function enviarEmail(opts: EnviarEmailOpts): Promise<void> {
  const proximo = filaEnvio.then(() => enviarEmailAgora(opts), () => enviarEmailAgora(opts))
  filaEnvio = proximo.catch(() => {})
  return proximo
}

async function enviarEmailAgora(opts: EnviarEmailOpts) {
  const prefixo  = opts.conta === 'noreply' ? 'SMTP_NOREPLY_' : 'SMTP_'
  const hostname = Deno.env.get(prefixo + 'HOST') ?? Deno.env.get('SMTP_HOST')!
  const port     = Number(Deno.env.get(prefixo + 'PORT') ?? Deno.env.get('SMTP_PORT') ?? '465')
  const username = Deno.env.get(prefixo + 'USER')!
  const password = Deno.env.get(prefixo + 'PASS')!
  const fromName = Deno.env.get(prefixo + 'FROM_NAME') ?? 'Vitta Sistemas'
  const ehloHost = Deno.env.get('SMTP_EHLO_HOST') ?? 'vittasistemas.com.br'

  let conn: Deno.Conn = port === 465
    ? await Deno.connectTls({ hostname, port })
    : await Deno.connect({ hostname, port })

  try {
    assertCodigo(await lerResposta(conn), 220)

    await enviarComando(conn, `EHLO ${ehloHost}`)
    assertCodigo(await lerResposta(conn), 250)

    if (port !== 465) {
      await enviarComando(conn, 'STARTTLS')
      assertCodigo(await lerResposta(conn), 220)
      conn = await Deno.startTls(conn, { hostname })
      await enviarComando(conn, `EHLO ${ehloHost}`)
      assertCodigo(await lerResposta(conn), 250)
    }

    await enviarComando(conn, 'AUTH LOGIN')
    assertCodigo(await lerResposta(conn), 334)

    await enviarComando(conn, btoa(username))
    assertCodigo(await lerResposta(conn), 334)

    await enviarComando(conn, btoa(password))
    assertCodigo(await lerResposta(conn), 235)

    await enviarComando(conn, `MAIL FROM:<${username}>`)
    assertCodigo(await lerResposta(conn), 250)

    await enviarComando(conn, `RCPT TO:<${opts.to}>`)
    assertCodigo(await lerResposta(conn), 250)

    await enviarComando(conn, 'DATA')
    assertCodigo(await lerResposta(conn), 354)

    const mensagem = montarMensagem({
      fromName,
      fromAddr: username,
      toName: opts.toName,
      toAddr: opts.to,
      subject: opts.subject,
      html: opts.html,
      attachments: opts.attachments || [],
    })

    await escreverTudo(conn, new TextEncoder().encode(aplicarDotStuffing(mensagem) + '\r\n.\r\n'))
    assertCodigo(await lerResposta(conn), 250)

    await enviarComando(conn, 'QUIT')
  } finally {
    try { conn.close() } catch (_e) { /* já fechada */ }
  }
}
