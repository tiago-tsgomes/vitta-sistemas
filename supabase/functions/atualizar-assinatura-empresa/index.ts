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
    const { empresa_id } = await req.json()
    if (!empresa_id) return json({ erro: 'empresa_id obrigatório' }, 400)

    const ASAAS_API_KEY    = Deno.env.get('ASAAS_API_KEY')!
    const ASAAS_BASE_URL   = Deno.env.get('ASAAS_BASE_URL')!
    const SUPABASE_URL     = Deno.env.get('SUPABASE_URL')!
    const SERVICE_ROLE_KEY = Deno.env.get('SERVICE_ROLE_KEY')!

    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
      auth: { autoRefreshToken: false, persistSession: false },
    })

    // Busca a empresa com seu plano e subscription Asaas
    const { data: emp, error: empErr } = await supabase
      .from('EMPRESA')
      .select('ID_EMP, NOME_EMP, ASAAS_SUBSCRIPTION_ID, PLANO(NOME_PLANO, PRECO_PLANO)')
      .eq('ID_EMP', empresa_id)
      .single()

    if (empErr || !emp) return json({ erro: 'Empresa não encontrada.' }, 404)
    if (!emp.ASAAS_SUBSCRIPTION_ID) return json({ erro: 'Esta empresa não possui assinatura no Asaas.' }, 400)

    const plano = emp.PLANO as { NOME_PLANO: string; PRECO_PLANO: number } | null
    if (!plano?.PRECO_PLANO) return json({ erro: 'Plano sem preço definido.' }, 400)

    const res = await fetch(`${ASAAS_BASE_URL}/subscriptions/${emp.ASAAS_SUBSCRIPTION_ID}`, {
      method:  'POST',
      headers: { 'Content-Type': 'application/json', 'access_token': ASAAS_API_KEY },
      body: JSON.stringify({
        value:       plano.PRECO_PLANO,
        description: `Assinatura Vitta Sistemas — ${plano.NOME_PLANO}`,
      }),
    })
    const data = await res.json()

    if (data.id) {
      return json({ sucesso: true, subscription_id: data.id })
    } else {
      const detalhe = data.errors?.[0]?.description || JSON.stringify(data)
      return json({ erro: 'Asaas retornou erro: ' + detalhe }, 502)
    }

  } catch (e: unknown) {
    return json({ erro: e instanceof Error ? e.message : String(e) }, 500)
  }
})
