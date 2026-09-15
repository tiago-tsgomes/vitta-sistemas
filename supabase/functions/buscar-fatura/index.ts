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

    // Deriva empresa_id do JWT — cada usuário só busca a própria cobrança,
    // exceto ADMIN_GLOBAL, que pode passar a empresa selecionada no header
    // via query param (mesmo padrão de buscar-faturas / faturas.html).
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) return json({ erro: 'Autenticação necessária' }, 401)

    const token = authHeader.replace('Bearer ', '')
    const { data: userData, error: authErr } = await supabase.auth.getUser(token)
    if (authErr || !userData.user) return json({ erro: 'Token inválido' }, 401)

    const meta    = userData.user.user_metadata || {}
    const tipoUsu = meta.tipo_usu || meta.TIPO_USU

    const url = new URL(req.url)
    const paramEmpresaId = url.searchParams.get('empresa_id')

    const empresaId = (tipoUsu === 'ADMIN_GLOBAL' && paramEmpresaId)
      ? paramEmpresaId
      : (meta.ID_EMP || meta.id_emp)
    if (!empresaId) return json({ erro: 'Usuário sem empresa vinculada' }, 400)

    // Fetch empresa + plano
    const { data: emp, error: empErr } = await supabase
      .from('EMPRESA')
      .select('ASAAS_SUBSCRIPTION_ID, ASAAS_CUSTOMER_ID, STATUS_EMP, PLANO:ID_PLANO(NOME_PLANO, PRECO_PLANO)')
      .eq('ID_EMP', empresaId)
      .single()

    if (empErr || !emp) return json({ erro: 'Empresa não encontrada' }, 404)
    if (!emp.ASAAS_SUBSCRIPTION_ID && !emp.ASAAS_CUSTOMER_ID) {
      return json({ erro: 'Empresa sem cadastro no sistema de cobrança. Entre em contato com o suporte.' }, 404)
    }

    const asaasHeaders = { 'access_token': ASAAS_API_KEY }

    // Junta PENDING + OVERDUE, tanto da assinatura quanto do cliente
    // (cobranças avulsas — ex.: geradas fora do ciclo da assinatura, ou
    // antes dela existir — não aparecem no endpoint de subscription e
    // ficavam invisíveis para este aviso, mesmo vencidas. buscar-faturas,
    // usada na tela "Minhas Faturas", já buscava por ambos; este endpoint
    // buscava só por assinatura, deixando o popup de aviso do dashboard
    // cego para essas cobranças) e escolhe o de vencimento mais próximo
    // (a API do Asaas não garante ordenação por data — pegar data.data[0]
    // pode retornar uma cobrança futura distante em vez da mais urgente).
    const seenIds = new Set<string>()
    let allPayments: Array<{ id: string; dueDate: string; [k: string]: unknown }> = []
    const urls: string[] = []
    if (emp.ASAAS_SUBSCRIPTION_ID) urls.push(`${ASAAS_BASE_URL}/subscriptions/${emp.ASAAS_SUBSCRIPTION_ID}/payments`)
    if (emp.ASAAS_CUSTOMER_ID)     urls.push(`${ASAAS_BASE_URL}/payments?customer=${emp.ASAAS_CUSTOMER_ID}`)

    for (const baseUrl of urls) {
      for (const status of ['PENDING', 'OVERDUE']) {
        const sep = baseUrl.includes('?') ? '&' : '?'
        const res = await fetch(`${baseUrl}${sep}status=${status}`, { headers: asaasHeaders })
        const data = await res.json()
        for (const p of (data.data ?? [])) {
          if (!seenIds.has(p.id)) { seenIds.add(p.id); allPayments.push(p) }
        }
      }
    }
    allPayments.sort((a, b) => new Date(a.dueDate).getTime() - new Date(b.dueDate).getTime())
    const payment = allPayments[0] ?? null

    if (!payment) {
      return json({
        erro: 'Nenhuma cobrança pendente encontrada. Seu pagamento pode já ter sido processado. Se o problema persistir, entre em contato com o suporte.',
      }, 404)
    }

    // Fetch PIX QR Code
    let pix: { payload: string; qrCode: string } | null = null
    try {
      const pixRes = await fetch(
        `${ASAAS_BASE_URL}/payments/${payment.id}/pixQrCode`,
        { headers: asaasHeaders }
      )
      const pixData = await pixRes.json()
      if (pixData.payload) {
        pix = { payload: pixData.payload, qrCode: pixData.encodedImage ?? '' }
      }
    } catch (_) { /* PIX not available */ }

    return json({
      sucesso: true,
      payment: {
        id:                 payment.id,
        valor:              payment.value,
        vencimento:         payment.dueDate,
        status:             payment.status,
        invoiceUrl:         payment.invoiceUrl         ?? null,
        bankSlipUrl:        payment.bankSlipUrl        ?? null,
        identificationField: payment.identificationField ?? null,
      },
      pix,
      plano: {
        nome:  (emp.PLANO as Record<string, unknown>)?.NOME_PLANO  ?? null,
        preco: (emp.PLANO as Record<string, unknown>)?.PRECO_PLANO ?? null,
      },
    })

  } catch (e: unknown) {
    return json({ erro: e instanceof Error ? e.message : String(e) }, 500)
  }
})
