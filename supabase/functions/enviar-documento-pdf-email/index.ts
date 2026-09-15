import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { enviarEmail } from '../_shared/smtp.ts'
import { emailDocumentoPdf } from '../_shared/email-templates.ts'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: { ...cors, 'Content-Type': 'application/json' } })
}

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE_ROLE_KEY = Deno.env.get('SERVICE_ROLE_KEY')!
const MAX_PDF_BASE64_LENGTH = 15_000_000 // ~11MB decodificado

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })

  try {
    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { autoRefreshToken: false, persistSession: false } })

    const authHeader = req.headers.get('Authorization')
    if (!authHeader) return json({ erro: 'Autenticação necessária' }, 401)
    const token = authHeader.replace('Bearer ', '')
    const { data: userData, error: authErr } = await supabase.auth.getUser(token)
    if (authErr || !userData.user) return json({ erro: 'Token inválido' }, 401)

    const { id_emp, paciente_email, paciente_nome, tipo_documento, profissional_nome, nome_arquivo, pdf_base64 } = await req.json()

    if (!id_emp) return json({ erro: 'id_emp é obrigatório' }, 400)
    if (!paciente_email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(paciente_email)) return json({ erro: 'Email do paciente inválido' }, 400)
    if (!pdf_base64) return json({ erro: 'pdf_base64 é obrigatório' }, 400)
    if (pdf_base64.length > MAX_PDF_BASE64_LENGTH) return json({ erro: 'PDF excede o tamanho máximo permitido para envio por email' }, 400)

    const { data: usuarios } = await supabase.from('USUARIO')
      .select('TIPO_USU, ID_EMP, ATIVO_USU')
      .eq('AUTH_ID', userData.user.id)

    const usuario = usuarios?.find(u => u.ATIVO_USU !== false && (u.ID_EMP === id_emp || u.TIPO_USU === 'ADMIN_GLOBAL'))

    if (!usuario) return json({ erro: 'Usuário não encontrado ou inativo' }, 403)

    const podeEnviar = usuario.TIPO_USU === 'ADMIN_GLOBAL' || usuario.ID_EMP === id_emp
    if (!podeEnviar) return json({ erro: 'Sem permissão para esta empresa' }, 403)

    const { data: empresa } = await supabase.from('EMPRESA').select('NOME_EMP').eq('ID_EMP', id_emp).maybeSingle()
    const empresaNome = empresa?.NOME_EMP || 'Clínica'

    const { subject, html } = emailDocumentoPdf({
      pacienteNome: paciente_nome || '',
      tipoDocumento: tipo_documento || 'Documento',
      profissionalNome: profissional_nome || '',
      empresaNome,
    })

    try {
      await enviarEmail({
        to: paciente_email,
        toName: paciente_nome || undefined,
        subject,
        html,
        conta: 'noreply',
        attachments: [{ filename: nome_arquivo || 'documento.pdf', content: pdf_base64 }],
      })
    } catch (smtpErr: unknown) {
      const msgOriginal = smtpErr instanceof Error ? smtpErr.message : String(smtpErr)
      const kb = Math.round((pdf_base64.length * 0.75) / 1024)
      throw new Error(`${msgOriginal} [pdf~${kb}KB, tipo=${tipo_documento}]`)
    }

    return json({ sucesso: true })
  } catch (e: unknown) {
    return json({ erro: e instanceof Error ? e.message : String(e) }, 500)
  }
})
