import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { computeBillingState } from '../_shared/billing.ts'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), { status, headers: { ...cors, 'Content-Type': 'application/json' } })

type AsaasPayment = {
  id: string
  status: string
  value: number
  netValue: number
  dueDate: string
  paymentDate: string | null
  clientPaymentDate: string | null
  description: string
  invoiceUrl: string | null
  bankSlipUrl: string | null
  identificationField: string | null
}

function mapPayment(p: Record<string, unknown>): AsaasPayment {
  return {
    id:                  String(p.id),
    status:              String(p.status),
    value:               Number(p.value),
    netValue:            Number(p.netValue ?? p.value),
    dueDate:             String(p.dueDate),
    paymentDate:         (p.paymentDate        as string) ?? null,
    clientPaymentDate:   (p.clientPaymentDate  as string) ?? null,
    description:         String(p.description ?? ''),
    invoiceUrl:          (p.invoiceUrl         as string) ?? null,
    bankSlipUrl:         (p.bankSlipUrl        as string) ?? null,
    identificationField: (p.identificationField as string) ?? null,
  }
}

async function fetchAllPages(
  baseUrl: string,
  headers: Record<string, string>,
  signal: AbortSignal
): Promise<AsaasPayment[]> {
  const pageSize = 100
  let offset = 0
  const all: AsaasPayment[] = []

  while (true) {
    const url = `${baseUrl}&limit=${pageSize}&offset=${offset}`
    const res = await fetch(url, { headers, signal })
    if (!res.ok) break
    const body = await res.json() as Record<string, unknown>
    const data = (body.data as Record<string, unknown>[]) || []
    all.push(...data.map(mapPayment))
    if (all.length >= Number(body.totalCount ?? 0) || data.length < pageSize) break
    offset += pageSize
  }

  return all
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

    const meta    = userData.user.user_metadata || {}
    const tipoUsu = meta.tipo_usu || meta.TIPO_USU

    // ADMIN_GLOBAL pode passar empresa_id por query param ou body
    let empresaId: string | null = null
    const url = new URL(req.url)
    const paramEmpresaId = url.searchParams.get('empresa_id')

    if (tipoUsu === 'ADMIN_GLOBAL' && paramEmpresaId) {
      empresaId = paramEmpresaId
    } else {
      empresaId = meta.ID_EMP || meta.id_emp || null
    }

    if (!empresaId) return json({ erro: 'Usuário sem empresa vinculada' }, 400)

    const { data: emp, error: empErr } = await supabase
      .from('EMPRESA')
      .select('ASAAS_SUBSCRIPTION_ID, ASAAS_CUSTOMER_ID, STATUS_EMP, ACESSO_ATE, PLANO:ID_PLANO(NOME_PLANO, PRECO_PLANO)')
      .eq('ID_EMP', empresaId)
      .single()

    if (empErr || !emp) return json({ erro: 'Empresa não encontrada' }, 404)

    if (!emp.ASAAS_CUSTOMER_ID && !emp.ASAAS_SUBSCRIPTION_ID) {
      return json({ erro: 'Empresa sem cadastro no sistema de cobrança.' }, 404)
    }

    const asaasHeaders = { 'access_token': ASAAS_API_KEY }
    const ctrl  = new AbortController()
    const timer = setTimeout(() => ctrl.abort(), 20000)

    let payments: AsaasPayment[] = []

    try {
      // Busca 1: todos os pagamentos do cliente (inclui avulsos + assinatura)
      if (emp.ASAAS_CUSTOMER_ID) {
        const byCustomer = await fetchAllPages(
          `${ASAAS_BASE_URL}/payments?customer=${emp.ASAAS_CUSTOMER_ID}`,
          asaasHeaders,
          ctrl.signal
        )
        payments.push(...byCustomer)
      }

      // Busca 2: pagamentos da assinatura (deduplicação — por segurança)
      if (emp.ASAAS_SUBSCRIPTION_ID) {
        const bySubscription = await fetchAllPages(
          `${ASAAS_BASE_URL}/subscriptions/${emp.ASAAS_SUBSCRIPTION_ID}/payments?`,
          asaasHeaders,
          ctrl.signal
        )
        const existingIds = new Set(payments.map(p => p.id))
        for (const p of bySubscription) {
          if (!existingIds.has(p.id)) payments.push(p)
        }
      }

      clearTimeout(timer)
    } catch (fetchErr: unknown) {
      clearTimeout(timer)
      const isAbort = fetchErr instanceof Error && fetchErr.name === 'AbortError'
      return json({ erro: isAbort
        ? 'Tempo limite ao buscar dados do sistema de cobrança.'
        : `Erro ao conectar com o sistema de cobrança: ${fetchErr instanceof Error ? fetchErr.message : String(fetchErr)}`
      }, 502)
    }

    // Ordena: mais recente primeiro (por dueDate desc)
    payments.sort((a, b) => b.dueDate.localeCompare(a.dueDate))

    // Auto-corrige o estado de cobrança usando a mesma regra do webhook
    // (computeBillingState em _shared/billing.ts) — cobre casos em que o
    // webhook do Asaas atrasou, falhou ou chegou fora de ordem. Só aplica a
    // partir de 'inadimplente': nunca mexe em 'trial' (um boleto criado mas
    // ainda não vencido faria computeBillingState devolver 'ativo' e
    // encerraria o trial antes da hora — a saída do trial é feita só por um
    // PAYMENT_CONFIRMED real, no webhook), 'cancelado', 'cancelamento_agendado'
    // ou 'erro_asaas', que têm fluxos próprios.
    if (emp.STATUS_EMP === 'inadimplente') {
      const novoEstado = computeBillingState(payments)
      // ACESSO_ATE é timestamptz no banco (ISO completo) mas representa só
      // uma data — compara pela parte "AAAA-MM-DD" para não disparar update
      // (e o trigger de auditoria) a cada visita à tela sem mudança real.
      const acessoAtualData = emp.ACESSO_ATE ? String(emp.ACESSO_ATE).slice(0, 10) : null
      if (novoEstado.STATUS_EMP !== emp.STATUS_EMP || novoEstado.ACESSO_ATE !== acessoAtualData) {
        await supabase
          .from('EMPRESA')
          .update(novoEstado)
          .eq('ID_EMP', empresaId)
      }
    }

    return json({
      sucesso: true,
      payments,
      plano: {
        nome:  (emp.PLANO as Record<string, unknown>)?.NOME_PLANO  ?? null,
        preco: (emp.PLANO as Record<string, unknown>)?.PRECO_PLANO ?? null,
      },
      total: payments.length,
    })

  } catch (e: unknown) {
    return json({ erro: e instanceof Error ? e.message : String(e) }, 500)
  }
})
