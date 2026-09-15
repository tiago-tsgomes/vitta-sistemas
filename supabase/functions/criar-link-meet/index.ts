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
const GOOGLE_CLIENT_ID = Deno.env.get('GOOGLE_CLIENT_ID')!
const GOOGLE_CLIENT_SECRET = Deno.env.get('GOOGLE_CLIENT_SECRET')!

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })

  try {
    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { autoRefreshToken: false, persistSession: false } })

    const authHeader = req.headers.get('Authorization')
    if (!authHeader) return json({ erro: 'Autenticação necessária' }, 401)
    const token = authHeader.replace('Bearer ', '')
    const { data: userData, error: authErr } = await supabase.auth.getUser(token)
    if (authErr || !userData.user) return json({ erro: 'Token inválido' }, 401)

    const { id_emp } = await req.json()
    if (!id_emp) return json({ erro: 'id_emp é obrigatório' }, 400)

    const { data: usuarios } = await supabase.from('USUARIO')
      .select('TIPO_USU, ID_EMP, ATIVO_USU')
      .eq('AUTH_ID', userData.user.id)

    const usuario = usuarios?.find(u => u.ATIVO_USU !== false && (u.ID_EMP === id_emp || u.TIPO_USU === 'ADMIN_GLOBAL'))

    if (!usuario) return json({ erro: 'Usuário não encontrado ou inativo' }, 403)

    const podeCriar = usuario.TIPO_USU === 'ADMIN_GLOBAL' || usuario.ID_EMP === id_emp
    if (!podeCriar) return json({ erro: 'Sem permissão para esta empresa' }, 403)

    const { data: googleAuth } = await supabase.from('EMPRESA_GOOGLE_AUTH')
      .select('STATUS, REFRESH_TOKEN')
      .eq('ID_EMP', id_emp)
      .maybeSingle()

    if (!googleAuth || googleAuth.STATUS !== 'conectado' || !googleAuth.REFRESH_TOKEN) {
      return json({ erro: 'reconexao_necessaria', mensagem: 'A conexão com o Google Meet desta empresa não está ativa. Reconecte para continuar.' }, 409)
    }

    const tokenResp = await fetch('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        client_id: GOOGLE_CLIENT_ID,
        client_secret: GOOGLE_CLIENT_SECRET,
        refresh_token: googleAuth.REFRESH_TOKEN,
        grant_type: 'refresh_token',
      }),
    })
    const tokenData = await tokenResp.json()

    if (!tokenResp.ok || !tokenData.access_token) {
      await supabase.from('EMPRESA_GOOGLE_AUTH').update({
        STATUS: 'desconectado',
        ATUALIZADO_EM: new Date().toISOString(),
      }).eq('ID_EMP', id_emp)
      return json({ erro: 'reconexao_necessaria', mensagem: 'A conexão com o Google Meet expirou. Reconecte para continuar.' }, 409)
    }

    const spaceResp = await fetch('https://meet.googleapis.com/v2/spaces', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${tokenData.access_token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        config: {
          accessType: 'OPEN',
          entryPointAccess: 'ALL',
        },
      }),
    })

    const spaceData = await spaceResp.json()

    if (spaceResp.status === 401 || spaceResp.status === 403) {
      await supabase.from('EMPRESA_GOOGLE_AUTH').update({
        STATUS: 'desconectado',
        ATUALIZADO_EM: new Date().toISOString(),
      }).eq('ID_EMP', id_emp)
      return json({ erro: 'reconexao_necessaria', mensagem: 'A conexão com o Google Meet expirou. Reconecte para continuar.' }, 409)
    }

    if (!spaceResp.ok) {
      return json({ erro: spaceData?.error?.message || 'Falha ao criar a sala no Google Meet' }, 500)
    }

    const link = spaceData.meetingUri

    if (!link) return json({ erro: 'O Google não retornou um link de videochamada' }, 500)

    return json({ sucesso: true, link, space_name: spaceData.name })
  } catch (e: unknown) {
    return json({ erro: e instanceof Error ? e.message : String(e) }, 500)
  }
})
