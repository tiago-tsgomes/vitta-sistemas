import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}
const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), { status, headers: { ...cors, 'Content-Type': 'application/json' } })

function calcNextDueDate(acessoAte: string | null): string {
  const today = new Date(); today.setHours(0, 0, 0, 0)

  if (acessoAte) {
    const ref = new Date(acessoAte); ref.setHours(0, 0, 0, 0)
    if (ref >= today) return acessoAte.split('T')[0] // ainda no período pago

    // período expirado: próxima ocorrência do mesmo dia do mês
    const day  = ref.getDate()
    const next = new Date(today)
    next.setDate(day)
    if (next <= today) next.setMonth(next.getMonth() + 1)
    return next.toISOString().split('T')[0]
  }

  // fallback: 30 dias a partir de hoje
  const d = new Date(today)
  d.setDate(d.getDate() + 30)
  return d.toISOString().split('T')[0]
}

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

    const meta = userData.user.user_metadata || {}
    if (meta.tipo_usu !== 'ADMIN_EMPRESA') return json({ erro: 'Acesso negado' }, 403)

    const empresaId = meta.ID_EMP || meta.id_emp
    if (!empresaId) return json({ erro: 'Usuário sem empresa vinculada' }, 400)

    const { planoId } = await req.json() as { planoId?: string }

    // Busca empresa
    const { data: emp, error: empErr } = await supabase
      .from('EMPRESA')
      .select('ASAAS_CUSTOMER_ID, ACESSO_ATE, ID_PLANO, STATUS_EMP, NOME_EMP')
      .eq('ID_EMP', empresaId)
      .single()

    if (empErr || !emp) return json({ erro: 'Empresa não encontrada' }, 404)
    if (emp.STATUS_EMP !== 'cancelamento_agendado')
      return json({ erro: 'A empresa não possui cancelamento agendado.' }, 400)
    if (!emp.ASAAS_CUSTOMER_ID)
      return json({ erro: 'Empresa sem cadastro no Asaas. Contate o suporte.' }, 400)

    // Plano a usar (novo ou atual)
    const targetPlanoId = planoId || emp.ID_PLANO
    const { data: plano, error: planoErr } = await supabase
      .from('PLANO')
      .select('ID_PLANO, NOME_PLANO, PRECO_PLANO')
      .eq('ID_PLANO', targetPlanoId)
      .single()

    if (planoErr || !plano) return json({ erro: 'Plano não encontrado.' }, 404)

    const nextDueDate = calcNextDueDate(emp.ACESSO_ATE)

    // Cria nova assinatura no Asaas
    const ctrl  = new AbortController()
    const timer = setTimeout(() => ctrl.abort(), 15000)

    let assinaturaRes: Response
    try {
      assinaturaRes = await fetch(`${ASAAS_BASE_URL}/subscriptions`, {
        method:  'POST',
        headers: { 'Content-Type': 'application/json', 'access_token': ASAAS_API_KEY },
        body: JSON.stringify({
          customer:    emp.ASAAS_CUSTOMER_ID,
          billingType: 'BOLETO',
          nextDueDate,
          value:       Number(plano.PRECO_PLANO),
          cycle:       'MONTHLY',
          description: `Vitta Sistemas — ${plano.NOME_PLANO}`,
        }),
        signal: ctrl.signal,
      })
      clearTimeout(timer)
    } catch (fetchErr: unknown) {
      clearTimeout(timer)
      const isAbort = fetchErr instanceof Error && fetchErr.name === 'AbortError'
      return json({ erro: isAbort ? 'Tempo limite ao criar assinatura.' : `Erro Asaas: ${String(fetchErr)}` }, 502)
    }

    const assinatura = await assinaturaRes.json() as Record<string, unknown>
    if (!assinaturaRes.ok || !assinatura.id)
      return json({ erro: 'Erro ao criar assinatura no Asaas.', detalhe: assinatura }, 502)

    // Atualiza empresa
    await supabase.from('EMPRESA').update({
      STATUS_EMP:            'ativo',
      ASAAS_SUBSCRIPTION_ID: String(assinatura.id),
      ID_PLANO:              targetPlanoId,
      MOTIVO_CANCELAMENTO:   null,
    }).eq('ID_EMP', empresaId)

    return json({
      sucesso:           true,
      plano:             plano.NOME_PLANO,
      preco:             plano.PRECO_PLANO,
      proximoVencimento: nextDueDate,
    })

  } catch (e: unknown) {
    return json({ erro: e instanceof Error ? e.message : String(e) }, 500)
  }
})
