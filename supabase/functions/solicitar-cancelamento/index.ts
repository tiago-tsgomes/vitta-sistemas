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
    const ASAAS_API_KEY    = Deno.env.get('ASAAS_API_KEY')!
    const ASAAS_BASE_URL   = Deno.env.get('ASAAS_BASE_URL')!
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

    // Apenas ADMIN_EMPRESA pode cancelar a própria assinatura
    const meta = userData.user.user_metadata || {}
    const tipo = meta.tipo_usu
    if (tipo !== 'ADMIN_EMPRESA') return json({ erro: 'Acesso negado' }, 403)

    const empresaId = meta.ID_EMP || meta.id_emp
    if (!empresaId) return json({ erro: 'Usuário sem empresa vinculada' }, 400)

    const { motivo } = await req.json() as { motivo: string }

    const { data: emp, error: empErr } = await supabase
      .from('EMPRESA')
      .select('ASAAS_SUBSCRIPTION_ID, ACESSO_ATE, NOME_EMP, STATUS_EMP')
      .eq('ID_EMP', empresaId)
      .single()

    if (empErr || !emp) return json({ erro: 'Empresa não encontrada' }, 404)

    if (emp.STATUS_EMP === 'cancelamento_agendado') {
      return json({ erro: 'A assinatura já está com cancelamento agendado.' }, 400)
    }

    // Cancela a assinatura no Asaas (para não gerar novas cobranças)
    if (emp.ASAAS_SUBSCRIPTION_ID) {
      const ctrl  = new AbortController()
      const timer = setTimeout(() => ctrl.abort(), 15000)
      try {
        await fetch(`${ASAAS_BASE_URL}/subscriptions/${emp.ASAAS_SUBSCRIPTION_ID}`, {
          method:  'DELETE',
          headers: { 'access_token': ASAAS_API_KEY },
          signal:  ctrl.signal,
        })
      } finally {
        clearTimeout(timer)
      }
    }

    // Atualiza status para cancelamento_agendado e salva motivo
    await supabase.from('EMPRESA').update({
      STATUS_EMP:            'cancelamento_agendado',
      ASAAS_SUBSCRIPTION_ID: null,
      MOTIVO_CANCELAMENTO:   motivo || null,
    }).eq('ID_EMP', empresaId)

    return json({ sucesso: true, acessoAte: emp.ACESSO_ATE })

  } catch (e: unknown) {
    return json({ erro: e instanceof Error ? e.message : String(e) }, 500)
  }
})
