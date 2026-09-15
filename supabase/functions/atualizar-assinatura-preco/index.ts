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
    const { plano_id, novo_preco } = await req.json()

    if (!plano_id)           return json({ erro: 'plano_id obrigatório' }, 400)
    if (novo_preco == null)  return json({ erro: 'novo_preco obrigatório' }, 400)

    const ASAAS_API_KEY    = Deno.env.get('ASAAS_API_KEY')!
    const ASAAS_BASE_URL   = Deno.env.get('ASAAS_BASE_URL')!
    const SUPABASE_URL     = Deno.env.get('SUPABASE_URL')!
    const SERVICE_ROLE_KEY = Deno.env.get('SERVICE_ROLE_KEY')!

    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
      auth: { autoRefreshToken: false, persistSession: false },
    })

    // Busca todas as empresas com este plano que têm assinatura no Asaas
    const { data: empresas, error: empErr } = await supabase
      .from('EMPRESA')
      .select('ID_EMP, NOME_EMP, ASAAS_SUBSCRIPTION_ID')
      .eq('ID_PLANO', plano_id)
      .not('ASAAS_SUBSCRIPTION_ID', 'is', null)

    if (empErr) return json({ erro: 'Erro ao buscar empresas', detalhe: empErr }, 500)
    if (!empresas || empresas.length === 0) {
      return json({ sucesso: true, total: 0, atualizadas: 0, falhas: 0, msg: 'Nenhuma assinatura encontrada para este plano.' })
    }

    let atualizadas = 0
    let falhas      = 0
    const detalhes: { empresa: string; status: string; erro?: string }[] = []

    for (const emp of empresas) {
      try {
        const res = await fetch(`${ASAAS_BASE_URL}/subscriptions/${emp.ASAAS_SUBSCRIPTION_ID}`, {
          method:  'POST', // Asaas usa POST para update de assinatura
          headers: { 'Content-Type': 'application/json', 'access_token': ASAAS_API_KEY },
          body: JSON.stringify({ value: novo_preco }),
        })
        const data = await res.json()

        if (data.id) {
          atualizadas++
          detalhes.push({ empresa: emp.NOME_EMP, status: 'ok' })
        } else {
          falhas++
          detalhes.push({ empresa: emp.NOME_EMP, status: 'erro', erro: data.errors?.[0]?.description || JSON.stringify(data) })
        }
      } catch (e: unknown) {
        falhas++
        detalhes.push({ empresa: emp.NOME_EMP, status: 'erro', erro: e instanceof Error ? e.message : String(e) })
      }
    }

    return json({
      sucesso:     true,
      total:       empresas.length,
      atualizadas,
      falhas,
      detalhes,
    })

  } catch (e: unknown) {
    return json({ erro: e instanceof Error ? e.message : String(e) }, 500)
  }
})
