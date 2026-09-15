import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: { ...cors, 'Content-Type': 'application/json' } })
}

function b64urlEncode(str: string): string {
  return btoa(str).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

async function hmacHex(secret: string, data: string): Promise<string> {
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'])
  const sig = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(data))
  return Array.from(new Uint8Array(sig)).map(b => b.toString(16).padStart(2, '0')).join('')
}

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE_ROLE_KEY = Deno.env.get('SERVICE_ROLE_KEY')!
const GOOGLE_CLIENT_ID = Deno.env.get('GOOGLE_CLIENT_ID')!
const GOOGLE_STATE_SECRET = Deno.env.get('GOOGLE_STATE_SECRET')!

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

    const usuario = usuarios?.find((u) => u.ATIVO_USU !== false && (u.ID_EMP === id_emp || u.TIPO_USU === 'ADMIN_GLOBAL'))

    if (!usuario) return json({ erro: 'Usuário não encontrado ou inativo' }, 403)

    const podeConectar = usuario.TIPO_USU === 'ADMIN_GLOBAL' ||
      (usuario.ID_EMP === id_emp && ['ADMIN_EMPRESA', 'SECRETARIA'].includes(usuario.TIPO_USU))

    if (!podeConectar) return json({ erro: 'Sem permissão para conectar o Google Meet desta empresa' }, 403)

    const payload = JSON.stringify({ id_emp, ts: Date.now() })
    const payloadB64 = b64urlEncode(payload)
    const assinatura = await hmacHex(GOOGLE_STATE_SECRET, payloadB64)
    const state = `${payloadB64}.${assinatura}`

    const redirectUri = `${SUPABASE_URL}/functions/v1/google-oauth-callback`

    const params = new URLSearchParams({
      client_id: GOOGLE_CLIENT_ID,
      redirect_uri: redirectUri,
      response_type: 'code',
      scope: 'https://www.googleapis.com/auth/meetings.space.created openid email',
      access_type: 'offline',
      prompt: 'consent',
      state,
    })

    const url = `https://accounts.google.com/o/oauth2/v2/auth?${params.toString()}`

    return json({ sucesso: true, url })
  } catch (e: unknown) {
    return json({ erro: e instanceof Error ? e.message : String(e) }, 500)
  }
})
