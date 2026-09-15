// Regra de inadimplência: o bloqueio do sistema só é agendado quando existe
// um 2º boleto em aberto além do 1º já vencido e não pago. ACESSO_ATE passa
// a guardar o vencimento desse 2º boleto — o bloqueio efetivo ocorre no dia
// seguinte a essa data (ver initInadimplenciaCheck em assets/js/config.js).
// Ex.: boletos vencendo 20/08 e 20/09 — se 20/09 vencer sem o 20/08 ter sido
// pago, o sistema bloqueia em 21/09.
//
// O estado é sempre recalculado do zero a partir da lista real de boletos no
// Asaas (nunca incrementado a partir do payload de um único evento de
// webhook), para não desalinhar em caso de eventos fora de ordem, perdidos
// ou reentregues.

export type AsaasPaymentMin = { id: string; status: string; dueDate: string }

const PAID_STATUSES = ['CONFIRMED', 'RECEIVED', 'RECEIVED_IN_CASH']
// Refunded/cancelled não representam mais uma dívida em aberto
const IGNORED_STATUSES = ['REFUNDED', 'CANCELLED']

export function computeBillingState(
  payments: AsaasPaymentMin[],
  hoje: Date = new Date()
): { STATUS_EMP: 'ativo' | 'inadimplente'; ACESSO_ATE: string | null } {
  const ref = new Date(hoje)
  ref.setHours(0, 0, 0, 0)

  // Mesmo critério do front-end (resolveStatus em faturas.html): o Asaas não
  // vira o status para OVERDUE exatamente à meia-noite do vencimento.
  const isVencido = (p: AsaasPaymentMin) =>
    p.status === 'OVERDUE' || (p.status === 'PENDING' && new Date(p.dueDate + 'T00:00:00') < ref)

  const emAberto = payments
    .filter(p => !PAID_STATUSES.includes(p.status) && !IGNORED_STATUSES.includes(p.status))
    .sort((a, b) => a.dueDate.localeCompare(b.dueDate))

  if (emAberto.length === 0) return { STATUS_EMP: 'ativo', ACESSO_ATE: null }

  const primeiro = emAberto[0]
  if (!isVencido(primeiro)) return { STATUS_EMP: 'ativo', ACESSO_ATE: null }

  // 1º boleto vencido e não pago: já é inadimplente, mas o bloqueio só é
  // agendado quando existe um 2º boleto em aberto.
  const segundo = emAberto[1]
  return {
    STATUS_EMP: 'inadimplente',
    ACESSO_ATE: segundo ? segundo.dueDate : null,
  }
}

export async function fetchPaymentsMin(opts: {
  apiKey: string
  baseUrl: string
  customerId?: string | null
  subscriptionId?: string | null
}): Promise<AsaasPaymentMin[]> {
  const headers = { access_token: opts.apiKey }
  const seen = new Set<string>()
  const result: AsaasPaymentMin[] = []

  // Junta pagamentos por cliente (inclui avulsos) e por assinatura, com
  // deduplicação — mesmo padrão de buscar-faturas/index.ts.
  const urls: string[] = []
  if (opts.customerId) urls.push(`${opts.baseUrl}/payments?customer=${opts.customerId}`)
  if (opts.subscriptionId) urls.push(`${opts.baseUrl}/subscriptions/${opts.subscriptionId}/payments?`)

  for (const baseUrl of urls) {
    const pageSize = 100
    let offset = 0
    let fetched = 0 // contagem desta URL — não pode ser o total deduplicado
                     // acumulado entre URLs, senão a 2ª URL para cedo demais
    while (true) {
      const sep = baseUrl.includes('?') ? '&' : '?'
      const res = await fetch(`${baseUrl}${sep}limit=${pageSize}&offset=${offset}`, { headers })
      if (!res.ok) break
      const body = (await res.json()) as Record<string, unknown>
      const data = (body.data as Record<string, unknown>[]) || []
      fetched += data.length
      for (const p of data) {
        const id = String(p.id)
        if (seen.has(id)) continue
        seen.add(id)
        result.push({ id, status: String(p.status), dueDate: String(p.dueDate) })
      }
      if (fetched >= Number(body.totalCount ?? 0) || data.length < pageSize) break
      offset += pageSize
    }
  }

  return result
}
