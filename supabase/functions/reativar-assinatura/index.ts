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

    const tipo = userData.user.user_metadata?.tipo_usu
    if (tipo !== 'ADMIN_GLOBAL') return json({ erro: 'Acesso negado' }, 403)

    const { empresaId } = await req.json() as { empresaId: string }
    if (!empresaId) return json({ erro: 'empresaId obrigatório' }, 400)

    const { data: emp, error: empErr } = await supabase
      .from('EMPRESA')
      .select('NOME_EMP, CNPJ_EMP, EMAIL_EMP, ASAAS_CUSTOMER_ID, ASAAS_SUBSCRIPTION_ID, ISENTO_COBRANCA, PLANO:ID_PLANO(NOME_PLANO, PRECO_PLANO)')
      .eq('ID_EMP', empresaId)
      .single()

    if (empErr || !emp) return json({ erro: 'Empresa não encontrada' }, 404)

    // Empresa isenta de cobrança: apenas libera o acesso, sem criar assinatura no Asaas
    if (emp.ISENTO_COBRANCA) {
      const { error: updateErr } = await supabase
        .from('EMPRESA')
        .update({ STATUS_EMP: 'ativo', ACESSO_ATE: null })
        .eq('ID_EMP', empresaId)
      if (updateErr) return json({ erro: updateErr.message }, 500)
      return json({ sucesso: true, aviso: 'Empresa isenta de cobrança — acesso liberado sem assinatura no Asaas.' })
    }

    // Se já tem assinatura ativa no Asaas, não cria outra
    if (emp.ASAAS_SUBSCRIPTION_ID) {
      return json({ sucesso: true, aviso: 'Empresa já possui assinatura ativa no Asaas.' })
    }

    const plano = emp.PLANO as Record<string, unknown>
    const valor = Number(plano?.PRECO_PLANO ?? 0)
    if (!valor) return json({ erro: 'Plano sem preço definido.' }, 400)

    let customerId = emp.ASAAS_CUSTOMER_ID as string | null

    // Verifica se o cliente existe no Asaas (pode estar inválido ou ser de outro ambiente)
    if (customerId) {
      const checkRes = await fetch(`${ASAAS_BASE_URL}/customers/${customerId}`, {
        headers: { 'access_token': ASAAS_API_KEY },
      })
      if (!checkRes.ok) customerId = null // cliente não existe — vai criar um novo
    }

    // Cria o cliente no Asaas se não existe ou era inválido
    if (!customerId) {
      const clienteBody: Record<string, unknown> = { name: emp.NOME_EMP }
      if (emp.CNPJ_EMP)  clienteBody.cpfCnpj = emp.CNPJ_EMP
      if (emp.EMAIL_EMP) clienteBody.email   = emp.EMAIL_EMP

      const clienteRes = await fetch(`${ASAAS_BASE_URL}/customers`, {
        method:  'POST',
        headers: { 'Content-Type': 'application/json', 'access_token': ASAAS_API_KEY },
        body:    JSON.stringify(clienteBody),
      })
      const cliente = await clienteRes.json() as Record<string, unknown>

      if (!clienteRes.ok || !cliente.id) {
        const erros = (cliente.errors as Array<Record<string, string>>)
        const detalhe = erros?.map(e => e.description || e.code).join('; ') || JSON.stringify(cliente)
        return json({ erro: `Erro ao criar cliente no Asaas: ${detalhe}` }, 502)
      }

      customerId = cliente.id as string
      await supabase.from('EMPRESA').update({ ASAAS_CUSTOMER_ID: customerId }).eq('ID_EMP', empresaId)
    }

    // Próximo vencimento: 30 dias a partir de hoje
    const nextDue = new Date()
    nextDue.setDate(nextDue.getDate() + 30)
    const nextDueDate = nextDue.toISOString().split('T')[0]

    const ctrl  = new AbortController()
    const timer = setTimeout(() => ctrl.abort(), 15000)

    let assinaturaRes: Response
    try {
      assinaturaRes = await fetch(`${ASAAS_BASE_URL}/subscriptions`, {
        method:  'POST',
        headers: { 'Content-Type': 'application/json', 'access_token': ASAAS_API_KEY },
        body: JSON.stringify({
          customer:    customerId,
          billingType: 'UNDEFINED',
          nextDueDate,
          value:       valor,
          cycle:       'MONTHLY',
          description: `Vitta Sistemas — ${plano?.NOME_PLANO ?? 'Plano'}`,
        }),
        signal: ctrl.signal,
      })
      clearTimeout(timer)
    } catch (fetchErr: unknown) {
      clearTimeout(timer)
      const isAbort = fetchErr instanceof Error && fetchErr.name === 'AbortError'
      return json({ erro: isAbort
        ? 'Tempo limite ao criar assinatura no Asaas.'
        : `Erro ao conectar com o Asaas: ${fetchErr instanceof Error ? fetchErr.message : String(fetchErr)}`
      }, 502)
    }

    const assinatura = await assinaturaRes.json() as Record<string, unknown>

    if (!assinaturaRes.ok || !assinatura.id) {
      // Extrai mensagem de erro do Asaas para exibir ao admin
      const erros = (assinatura.errors as Array<Record<string, string>>)
      const detalheAsaas = erros?.map(e => e.description || e.code).join('; ')
        || (assinatura.error as string)
        || JSON.stringify(assinatura)
      return json({ erro: `Erro ao criar assinatura no Asaas: ${detalheAsaas}` }, 502)
    }

    // Atualiza a empresa com a nova assinatura e status ativo (sem expiração)
    const { error: updateErr } = await supabase
      .from('EMPRESA')
      .update({
        ASAAS_SUBSCRIPTION_ID: assinatura.id,
        STATUS_EMP: 'ativo',
        ACESSO_ATE: null,
      })
      .eq('ID_EMP', empresaId)

    if (updateErr) return json({ erro: updateErr.message }, 500)

    return json({ sucesso: true, subscriptionId: assinatura.id, proximoVencimento: nextDueDate })

  } catch (e: unknown) {
    return json({ erro: e instanceof Error ? e.message : String(e) }, 500)
  }
})
