const LOGO_URL   = 'https://www.vittasistemas.com.br/img/logo_branca.png'
const SITE_URL    = 'https://www.vittasistemas.com.br'
const LOGIN_URL   = 'https://app.vittasistemas.com.br/'
const SUPORTE_URL = `${SITE_URL}/suporte.html`
const WHATSAPP    = '5548984096109'
const EMAIL_CONTATO = 'contato@vittasistemas.com.br'

function layout(conteudo: string, opts?: { header?: boolean; contato?: boolean }): string {
  const showHeader = opts?.header !== false
  const showContato = opts?.contato !== false
  return `
<!DOCTYPE html>
<html lang="pt-BR">
<head><meta charset="UTF-8" /><meta name="viewport" content="width=device-width, initial-scale=1.0" /></head>
<body style="margin:0;padding:0;background-color:#f0fbfd;font-family:Arial,Helvetica,sans-serif;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background-color:#f0fbfd;padding:32px 16px;">
    <tr>
      <td align="center">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px;background-color:#ffffff;border-radius:20px;overflow:hidden;box-shadow:0 4px 20px rgba(42,188,212,0.12);">

          ${showHeader ? `<tr>
            <td align="center" style="background:linear-gradient(135deg,#1a96ac,#2ABCD4);padding:32px 24px;">
              <img src="${LOGO_URL}" alt="Vitta Sistemas" height="40" style="height:40px;" />
            </td>
          </tr>` : ''}

          <tr>
            <td style="padding:${showHeader ? '36px' : '40px'} 32px 36px;color:#374151;">
              ${conteudo}
            </td>
          </tr>

          ${showContato ? `<tr>
            <td style="padding:0 32px 32px;">
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background-color:#f0fbfd;border-radius:16px;">
                <tr>
                  <td style="padding:22px 24px;">
                    <p style="margin:0 0 12px;font-size:13px;font-weight:bold;color:#0d5f6e;text-transform:uppercase;letter-spacing:0.06em;">Fale com a gente</p>
                    <p style="margin:0 0 6px;font-size:14px;color:#374151;">
                      💬 WhatsApp: <a href="https://wa.me/${WHATSAPP}" style="color:#1a96ac;font-weight:bold;text-decoration:none;">(48) 98409-6109</a>
                    </p>
                    <p style="margin:0 0 6px;font-size:14px;color:#374151;">
                      ✉️ E-mail: <a href="mailto:${EMAIL_CONTATO}" style="color:#1a96ac;font-weight:bold;text-decoration:none;">${EMAIL_CONTATO}</a>
                    </p>
                    <p style="margin:0;font-size:14px;color:#374151;">
                      🌐 Central de suporte: <a href="${SUPORTE_URL}" style="color:#1a96ac;font-weight:bold;text-decoration:none;">vittasistemas.com.br/suporte</a>
                    </p>
                  </td>
                </tr>
              </table>
            </td>
          </tr>` : ''}

          <tr>
            <td align="center" style="padding:20px 24px 28px;border-top:1px solid #f0f0f0;">
              <p style="margin:0;font-size:12px;color:#9ca3af;">© ${new Date().getFullYear()} Vitta Sistemas. Todos os direitos reservados.</p>
            </td>
          </tr>

        </table>
      </td>
    </tr>
  </table>
</body>
</html>`
}

export function emailBoasVindas(opts: { nomeAdmin: string; nomeEmpresa: string }): { subject: string; html: string } {
  const primeiroNome = opts.nomeAdmin.trim().split(' ')[0]

  const conteudo = `
    <h1 style="margin:0 0 18px;font-size:22px;color:#0d5f6e;">Bem-vindo(a), ${primeiroNome}! 🎉</h1>
    <p style="margin:0 0 16px;font-size:15px;line-height:1.6;">
      É um prazer ter a <strong>${opts.nomeEmpresa}</strong> com a gente! Sua conta no Vitta Sistemas foi criada com sucesso
      e você já pode aproveitar <strong>14 dias grátis</strong> para conhecer todas as funcionalidades da plataforma.
    </p>
    <p style="margin:0 0 24px;font-size:15px;line-height:1.6;">
      Com o Vitta Sistemas você organiza agendamentos, prontuários, pacientes, profissionais e financeiro
      da sua clínica em um só lugar, com muito mais praticidade no dia a dia.
    </p>
    <table role="presentation" cellpadding="0" cellspacing="0" style="margin:0 0 28px;">
      <tr>
        <td style="border-radius:12px;background:linear-gradient(135deg,#2ABCD4,#1a96ac);">
          <a href="${LOGIN_URL}" style="display:inline-block;padding:14px 28px;font-size:14px;font-weight:bold;color:#ffffff;text-decoration:none;">
            Acessar o Vitta Sistemas →
          </a>
        </td>
      </tr>
    </table>
    <p style="margin:0;font-size:14px;line-height:1.6;color:#6b7280;">
      Qualquer dúvida durante a configuração inicial, é só chamar a gente por um dos canais abaixo.
      Estamos aqui para te ajudar a começar com o pé direito!
    </p>
  `

  return {
    subject: `Bem-vindo(a) ao Vitta Sistemas, ${primeiroNome}!`,
    html: layout(conteudo),
  }
}

export function emailDocumentoPdf(opts: { pacienteNome: string; tipoDocumento: string; profissionalNome?: string; empresaNome: string }): { subject: string; html: string } {
  const primeiroNome = (opts.pacienteNome || '').trim().split(' ')[0] || 'Olá'
  const doc = opts.tipoDocumento || 'Documento'

  const conteudo = `
    <table role="presentation" cellpadding="0" cellspacing="0" style="margin:0 auto 22px;">
      <tr>
        <td width="64" height="64" align="center" valign="middle" style="background-color:#e6f8fb;border-radius:50%;">
          <table role="presentation" cellpadding="0" cellspacing="0"><tr><td style="font-size:26px;line-height:1;">📄</td></tr></table>
        </td>
      </tr>
    </table>
    <h1 style="margin:0 0 18px;font-size:22px;color:#0d5f6e;text-align:center;">Olá, ${primeiroNome}!</h1>
    <p style="margin:0 0 24px;font-size:15px;line-height:1.6;text-align:center;">
      Segue em anexo a sua <strong>${doc}</strong>${opts.profissionalNome ? `, emitida por <strong>${opts.profissionalNome}</strong>` : ''}
      na <strong>${opts.empresaNome}</strong>.
    </p>
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background-color:#f0fbfd;border-radius:14px;margin:0 0 24px;">
      <tr>
        <td style="padding:16px 18px;">
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
            <tr>
              <td width="36" valign="middle" style="font-size:22px;line-height:1;">📎</td>
              <td valign="middle">
                <p style="margin:0;font-size:14px;font-weight:bold;color:#0d5f6e;">${doc}</p>
                <p style="margin:2px 0 0;font-size:12px;color:#6b7280;">Arquivo PDF anexado a este email</p>
              </td>
            </tr>
          </table>
        </td>
      </tr>
    </table>
    <p style="margin:0;font-size:14px;line-height:1.6;color:#6b7280;text-align:center;">
      Em caso de dúvida sobre o documento, entre em contato com o profissional responsável ou diretamente com a clínica.
    </p>
  `

  return {
    subject: `Sua ${doc} — ${opts.empresaNome}`,
    html: layout(conteudo, { header: false, contato: false }),
  }
}
