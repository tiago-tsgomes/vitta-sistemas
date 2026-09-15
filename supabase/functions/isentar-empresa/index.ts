import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), { status, headers: { ...cors, 'Content-Type': 'application/json' } })

async function fetchOpenPaymentIds(
  baseUrl: string,
  customerId: string,
  headers: Record<string, string>,
  signal: AbortSignal
): Promise<string[]> {
  const ids: string[] = []
  for (const status of ['PENDING', 'OVERDUE']) {
    const pageSize = 100
    let offset = 0
    while (true) {
      const res = await fetch(
        `${baseUrl}/payments?customer=${customerId}&status=${status}&limit=${pageSize}&offset=${offset}`,
        { headers, signal }
      )
      if (!res.ok) break
      const body = await res.json() as Record<string, unknown>
      const data = (body.data as Record<string, unknown>[]) || []
      ids.push(...data.map(p => String(p.id)))
      if (ids.length >= Number(body.totalCount ?? 0) || data.length < pageSize) break
      offset += pageSize
    }
  }
  return ids
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

    // Apenas ADMIN_GLOBAL pode isentar uma empresa de cobrança
    const tipo = userData.user.user_metadata?.tipo_usu
    if (tipo !== 'ADMIN_GLOBAL') return json({ erro: 'Acesso negado' }, 403)

    const { empresaId } = await req.json() as { empresaId: string }
    if (!empresaId) return json({ erro: 'empresaId obrigatório' }, 400)

    const { data: emp, error: empErr } = await supabase
      .from('EMPRESA')
      .select('ASAAS_CUSTOMER_ID, ASAAS_SUBSCRIPTION_ID')
      .eq('ID_EMP', empresaId)
      .single()

    if (empErr || !emp) return json({ erro: 'Empresa não encontrada' }, 404)

    const asaasHeaders = { 'access_token': ASAAS_API_KEY }
    const ctrl  = new AbortController()
    const timer = setTimeout(() => ctrl.abort(), 20000)

    let cobrancasExcluidas = 0

    try {
      // Cancela a assinatura no Asaas (impede geração de novas cobranças)
      if (emp.ASAAS_SUBSCRIPTION_ID) {
        const cancelRes = await fetch(
          `${ASAAS_BASE_URL}/subscriptions/${emp.ASAAS_SUBSCRIPTION_ID}`,
          { method: 'DELETE', headers: asaasHeaders, signal: ctrl.signal }
        )
        if (!cancelRes.ok && cancelRes.status !== 404) {
          const body = await cancelRes.json().catch(() => ({}))
          clearTimeout(timer)
          return json({ erro: `Erro ${cancelRes.status} ao cancelar assinatura no Asaas.`, detalhe: body }, 502)
        }
      }

      // Exclui cobranças pendentes/vencidas já geradas para essa empresa
      if (emp.ASAAS_CUSTOMER_ID) {
        const openIds = await fetchOpenPaymentIds(ASAAS_BASE_URL, emp.ASAAS_CUSTOMER_ID, asaasHeaders, ctrl.signal)
        for (const paymentId of openIds) {
          const delRes = await fetch(`${ASAAS_BASE_URL}/payments/${paymentId}`, {
            method: 'DELETE', headers: asaasHeaders, signal: ctrl.signal,
          })
          if (delRes.ok) cobrancasExcluidas++
        }
      }

      clearTimeout(timer)
    } catch (fetchErr: unknown) {
      clearTimeout(timer)
      const isAbort = fetchErr instanceof Error && fetchErr.name === 'AbortError'
      return json({ erro: isAbort
        ? 'Tempo limite ao limpar cobranças no Asaas.'
        : `Erro ao conectar com o Asaas: ${fetchErr instanceof Error ? fetchErr.message : String(fetchErr)}`
      }, 502)
    }

    const { error: updateErr } = await supabase
      .from('EMPRESA')
      .update({
        ISENTO_COBRANCA: true,
        STATUS_EMP: 'ativo',
        ACESSO_ATE: null,
        ASAAS_SUBSCRIPTION_ID: null,
      })
      .eq('ID_EMP', empresaId)

    if (updateErr) return json({ erro: updateErr.message }, 500)

    return json({ sucesso: true, cobrancasExcluidas })

  } catch (e: unknown) {
    return json({ erro: e instanceof Error ? e.message : String(e) }, 500)
  }
})
