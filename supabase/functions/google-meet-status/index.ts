import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: { ...cors, 'Content-Type': 'application/json' } })
}

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE_ROLE_KEY = Deno.env.get('SERVICE_ROLE_KEY')!

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })

  try {
    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { autoRefreshToken: false, persistSession: false } })

    const authHeader = req.headers.get('Authorization')
    if (!authHeader) return json({ erro: 'Autenticação necessária' }, 401)
    const token = authHeader.replace('Bearer ', '')
    const { data: userData, error: authErr } = await supabase.auth.getUser(token)
    if (authErr || !userData.user) return json({ erro: 'Token inválido' }, 401)

    const url = new URL(req.url)
    const idEmp = url.searchParams.get('id_emp')
    if (!idEmp) return json({ erro: 'id_emp é obrigatório' }, 400)

    const { data: usuarios } = await supabase.from('USUARIO')
      .select('TIPO_USU, ID_EMP, ATIVO_USU')
      .eq('AUTH_ID', userData.user.id)

    const usuario = usuarios?.find((u) => u.ATIVO_USU !== false && (u.ID_EMP === idEmp || u.TIPO_USU === 'ADMIN_GLOBAL'))

    if (!usuario) return json({ erro: 'Usuário não encontrado ou inativo' }, 403)

    const { data: googleAuth } = await supabase.from('EMPRESA_GOOGLE_AUTH')
      .select('STATUS, GOOGLE_EMAIL')
      .eq('ID_EMP', idEmp)
      .maybeSingle()

    return json({
      sucesso: true,
      status: googleAuth?.STATUS ?? 'desconectado',
      google_email: googleAuth?.GOOGLE_EMAIL ?? null,
    })
  } catch (e: unknown) {
    return json({ erro: e instanceof Error ? e.message : String(e) }, 500)
  }
})
