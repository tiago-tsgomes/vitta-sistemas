import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

function b64urlDecode(str: string): string {
  str = str.replace(/-/g, '+').replace(/_/g, '/')
  while (str.length % 4) str += '='
  return atob(str)
}

async function hmacHex(secret: string, data: string): Promise<string> {
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'])
  const sig = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(data))
  return Array.from(new Uint8Array(sig)).map(b => b.toString(16).padStart(2, '0')).join('')
}

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE_ROLE_KEY = Deno.env.get('SERVICE_ROLE_KEY')!
const GOOGLE_CLIENT_ID = Deno.env.get('GOOGLE_CLIENT_ID')!
const GOOGLE_CLIENT_SECRET = Deno.env.get('GOOGLE_CLIENT_SECRET')!
const GOOGLE_STATE_SECRET = Deno.env.get('GOOGLE_STATE_SECRET')!
const APP_BASE_URL = Deno.env.get('APP_BASE_URL') ?? 'https://app.vittasistemas.com.br'

const REDIRECT_DESTINO = `${APP_BASE_URL}/pages/agendamentos.html`

function redirect(query: string) {
  return new Response(null, { status: 302, headers: { ...cors, Location: `${REDIRECT_DESTINO}?${query}` } })
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })

  const url = new URL(req.url)
  const erroGoogle = url.searchParams.get('error')
  if (erroGoogle) return redirect('google_meet=erro&motivo=recusado')

  const code = url.searchParams.get('code')
  const state = url.searchParams.get('state')
  if (!code || !state) return redirect('google_meet=erro&motivo=parametros_invalidos')

  try {
    const [payloadB64, assinatura] = state.split('.')
    if (!payloadB64 || !assinatura) return redirect('google_meet=erro&motivo=state_invalido')

    const assinaturaEsperada = await hmacHex(GOOGLE_STATE_SECRET, payloadB64)
    if (assinaturaEsperada !== assinatura) return redirect('google_meet=erro&motivo=state_invalido')

    const payload = JSON.parse(b64urlDecode(payloadB64)) as { id_emp: string; ts: number }
    if (!payload.id_emp || !payload.ts || Date.now() - payload.ts > 10 * 60 * 1000) {
      return redirect('google_meet=erro&motivo=state_expirado')
    }

    const redirectUri = `${SUPABASE_URL}/functions/v1/google-oauth-callback`

    const tokenResp = await fetch('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        code,
        client_id: GOOGLE_CLIENT_ID,
        client_secret: GOOGLE_CLIENT_SECRET,
        redirect_uri: redirectUri,
        grant_type: 'authorization_code',
      }),
    })
    const tokenData = await tokenResp.json()
    if (!tokenResp.ok || !tokenData.refresh_token) {
      return redirect('google_meet=erro&motivo=token_nao_obtido')
    }

    const userInfoResp = await fetch('https://openidconnect.googleapis.com/v1/userinfo', {
      headers: { Authorization: `Bearer ${tokenData.access_token}` },
    })
    const userInfo = await userInfoResp.json()
    const googleEmail = userInfo?.email ?? null

    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { autoRefreshToken: false, persistSession: false } })

    const { error: upsertErr } = await supabase.from('EMPRESA_GOOGLE_AUTH').upsert({
      ID_EMP: payload.id_emp,
      GOOGLE_EMAIL: googleEmail,
      REFRESH_TOKEN: tokenData.refresh_token,
      STATUS: 'conectado',
      CONECTADO_EM: new Date().toISOString(),
      ATUALIZADO_EM: new Date().toISOString(),
    }, { onConflict: 'ID_EMP' })

    if (upsertErr) return redirect('google_meet=erro&motivo=falha_salvar')

    return redirect('google_meet=conectado')
  } catch (_e: unknown) {
    return redirect('google_meet=erro&motivo=falha_inesperada')
  }
})
