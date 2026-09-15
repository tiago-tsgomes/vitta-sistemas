import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), { status, headers: { ...cors, 'Content-Type': 'application/json' } })

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })

  try {
    const SUPABASE_URL     = Deno.env.get('SUPABASE_URL')!
    const SERVICE_ROLE_KEY = Deno.env.get('SERVICE_ROLE_KEY')!

    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
      auth: { autoRefreshToken: false, persistSession: false },
    })

    const body = await req.json() as { email?: string }
    const email = body.email?.trim().toLowerCase()
    if (!email) return json({ erro: 'Email obrigatório' }, 400)

    // Verifica no Supabase Auth se o e-mail já possui conta (independente de vínculo em USUARIO)
    const authResp = await fetch(
      `${SUPABASE_URL}/auth/v1/admin/users?filter=${encodeURIComponent(email)}&per_page=10`,
      { headers: { 'apikey': SERVICE_ROLE_KEY, 'Authorization': `Bearer ${SERVICE_ROLE_KEY}` } }
    )
    const authRespData = await authResp.json() as { users?: Record<string, unknown>[] }
    const emailExiste = (authRespData?.users || []).some(
      (u) => (u.email as string)?.toLowerCase() === email
    )

    // Busca todas as empresas associadas ao email (inclui TIPO_USU para detectar ADMIN_GLOBAL)
    const { data: usuRows, error } = await supabase
      .from('USUARIO')
      .select('ID_EMP, TIPO_USU')
      .eq('EMAIL_USU', email)

    if (error) return json({ erro: error.message }, 500)

    // ADMIN_GLOBAL bypassa o seletor de empresa (verificação prioritária)
    const isAdminGlobalUsuario = (usuRows || []).some(
      (r: Record<string, unknown>) => r.TIPO_USU === 'ADMIN_GLOBAL'
    )
    if (isAdminGlobalUsuario) return json({ emailExiste, empresas: [] })

    const empIds = [...new Set((usuRows || []).map((r: Record<string, unknown>) => r.ID_EMP).filter(Boolean))]
    if (empIds.length === 0) return json({ emailExiste, empresas: [] })

    const { data: empRows } = await supabase
      .from('EMPRESA')
      .select('ID_EMP, NOME_EMP')
      .in('ID_EMP', empIds)

    const empresas = (empRows || []).map((e: Record<string, unknown>) => ({
      id:   e.ID_EMP,
      nome: e.NOME_EMP,
    }))

    return json({ emailExiste, empresas })
  } catch (e: unknown) {
    return json({ erro: e instanceof Error ? e.message : String(e) }, 500)
  }
})
