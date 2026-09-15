import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), { status, headers: { ...cors, 'Content-Type': 'application/json' } })

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms))

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })

  try {
    const SUPABASE_URL     = Deno.env.get('SUPABASE_URL')!
    const SERVICE_ROLE_KEY = Deno.env.get('SERVICE_ROLE_KEY')!

    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
      auth: { autoRefreshToken: false, persistSession: false },
    })

    const authHeader = req.headers.get('Authorization')
    if (!authHeader) return json({ erro: 'Autenticação necessária' }, 401)

    const token = authHeader.replace('Bearer ', '')
    const { data: userData, error: authErr } = await supabase.auth.getUser(token)
    if (authErr || !userData.user) return json({ erro: 'Token inválido' }, 401)

    const user = userData.user
    const body = await req.json() as { empresaId?: string }
    const empresaId = body.empresaId
    if (!empresaId) return json({ erro: 'empresaId obrigatório' }, 400)

    // Verifica se o usuário pertence a esta empresa
    const { data: usuario, error: usuErr } = await supabase
      .from('USUARIO')
      .select('TIPO_USU, ID_EMP, ATIVO_USU')
      .eq('EMAIL_USU', user.email!)
      .eq('ID_EMP', empresaId)
      .single()

    if (usuErr || !usuario) return json({ erro: 'Usuário não encontrado nesta empresa' }, 403)
    if (!usuario.ATIVO_USU) return json({ erro: 'Usuário inativo nesta empresa' }, 403)

    // Atualiza user_metadata com a empresa selecionada
    const currentMeta = user.user_metadata || {}
    const newMeta = {
      ...currentMeta,
      ID_EMP:    empresaId,
      id_emp:    empresaId,
      tipo_usu:  usuario.TIPO_USU,
      ativo_usu: usuario.ATIVO_USU,
    }

    // O Auth do Supabase às vezes rejeita essa chamada com "unrecognized JWT kid"
    // por inconsistência interna entre os nós dele (não é erro nosso) — tenta de
    // novo algumas vezes antes de retornar erro pro usuário.
    let updateErr: { message: string } | null = null
    for (let attempt = 1; attempt <= 4; attempt++) {
      const { error } = await supabase.auth.admin.updateUserById(user.id, { user_metadata: newMeta })
      updateErr = error
      if (!error) break
      if (attempt < 4) await sleep(400 * attempt)
    }

    if (updateErr) return json({ erro: updateErr.message }, 500)

    return json({ sucesso: true })
  } catch (e: unknown) {
    return json({ erro: e instanceof Error ? e.message : String(e) }, 500)
  }
})
