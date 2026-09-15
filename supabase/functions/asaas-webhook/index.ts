import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { computeBillingState, fetchPaymentsMin } from '../_shared/billing.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

type AsaasPayload = {
  event: string
  payment?: { customer: string; subscription?: string; dueDate?: string }
  subscription?: { id: string; customer: string }
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  const tokenEsperado = Deno.env.get('ASAAS_WEBHOOK_TOKEN')
  const tokenRecebido = req.headers.get('asaas-access-token')
  if (tokenEsperado && tokenRecebido && tokenRecebido !== tokenEsperado) {
    return new Response('Unauthorized', { status: 401 })
  }

  try {
    const payload = (await req.json()) as AsaasPayload
    const { event } = payload

    const customerId = payload.payment?.customer ?? payload.subscription?.customer

    if (!customerId) {
      return new Response(JSON.stringify({ ok: true }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SERVICE_ROLE_KEY') ?? '',
    )

    // Empresa isenta de cobrança: ignora eventos de cobrança do Asaas por completo
    // (defesa extra — a assinatura já é cancelada quando a isenção é ativada)
    const { data: empIsenta } = await supabase
      .from('EMPRESA')
      .select('ISENTO_COBRANCA, ASAAS_SUBSCRIPTION_ID, STATUS_EMP')
      .eq('ASAAS_CUSTOMER_ID', customerId)
      .maybeSingle()

    if (empIsenta?.ISENTO_COBRANCA) {
      return new Response(JSON.stringify({ ok: true, ignorado: 'empresa isenta de cobrança' }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    let update: Record<string, unknown>

    switch (event) {
      case 'PAYMENT_CONFIRMED':
      case 'PAYMENT_RECEIVED':
      case 'PAYMENT_RECEIVED_IN_CASH':
        // Pagamento confirmado sempre ativa a empresa (sai do trial ou da
        // inadimplência) e limpa qualquer bloqueio agendado.
        update = { STATUS_EMP: 'ativo', ACESSO_ATE: null }
        break
      case 'PAYMENT_OVERDUE':
      case 'PAYMENT_CREATED':
      case 'PAYMENT_UPDATED':
      case 'PAYMENT_REFUNDED': {
        // A regra de inadimplência (2º boleto em aberto agenda o bloqueio)
        // só faz sentido quando a empresa já está em cobrança normal. Durante
        // o trial (controlado por TRIAL_EXPIRA_EM em access-guard.js), um
        // boleto apenas criado/atualizado não pode encerrar o trial —
        // computeBillingState marcaria 'ativo' mesmo sem nenhum pagamento
        // ter sido feito, terminando o trial cedo demais.
        if (empIsenta?.STATUS_EMP === 'trial') {
          return new Response(JSON.stringify({ ok: true, ignorado: 'empresa em trial' }), {
            status: 200,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          })
        }

        // Recalcula o estado de cobrança do zero a partir da lista real de
        // boletos no Asaas (nunca a partir só do payload deste evento) — o
        // bloqueio só é agendado quando existe um 2º boleto em aberto além
        // do 1º já vencido e não pago. Ver computeBillingState em
        // _shared/billing.ts.
        const ASAAS_API_KEY  = Deno.env.get('ASAAS_API_KEY')
        const ASAAS_BASE_URL = Deno.env.get('ASAAS_BASE_URL')
        if (!ASAAS_API_KEY || !ASAAS_BASE_URL) {
          throw new Error('ASAAS_API_KEY/ASAAS_BASE_URL não configurados')
        }

        const payments = await fetchPaymentsMin({
          apiKey: ASAAS_API_KEY,
          baseUrl: ASAAS_BASE_URL,
          customerId,
          subscriptionId: empIsenta?.ASAAS_SUBSCRIPTION_ID ?? null,
        })

        update = computeBillingState(payments)
        break
      }
      case 'PAYMENT_DELETED':
      case 'SUBSCRIPTION_DELETED':
        update = { STATUS_EMP: 'cancelado' }
        break
      default:
        return new Response(JSON.stringify({ ok: true }), {
          status: 200,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
    }

    const { error } = await supabase
      .from('EMPRESA')
      .update(update)
      .eq('ASAAS_CUSTOMER_ID', customerId)

    if (error) throw error

    return new Response(JSON.stringify({ ok: true }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'unknown error'
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
