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

    // Autenticação
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) return json({ erro: 'Autenticação necessária' }, 401)

    const token = authHeader.replace('Bearer ', '')
    const { data: userData, error: authErr } = await supabase.auth.getUser(token)
    if (authErr || !userData.user) return json({ erro: 'Token inválido' }, 401)

    // Apenas ADMIN_GLOBAL pode cancelar assinaturas
    const tipo = userData.user.user_metadata?.tipo_usu
    if (tipo !== 'ADMIN_GLOBAL') return json({ erro: 'Acesso negado' }, 403)

    const { empresaId } = await req.json() as { empresaId: string }
    if (!empresaId) return json({ erro: 'empresaId obrigatório' }, 400)

    // Busca dados da empresa
    const { data: emp, error: empErr } = await supabase
      .from('EMPRESA')
      .select('ASAAS_SUBSCRIPTION_ID, NOME_EMP')
      .eq('ID_EMP', empresaId)
      .single()

    if (empErr || !emp) return json({ erro: 'Empresa não encontrada' }, 404)

    // Se não tem assinatura no Asaas, apenas retorna sucesso (nada a cancelar)
    if (!emp.ASAAS_SUBSCRIPTION_ID) {
      return json({ sucesso: true, aviso: 'Empresa sem assinatura no Asaas.' })
    }

    // Cancela a assinatura no Asaas
    const ctrl  = new AbortController()
    const timer = setTimeout(() => ctrl.abort(), 15000)

    let cancelRes: Response
    try {
      cancelRes = await fetch(
        `${ASAAS_BASE_URL}/subscriptions/${emp.ASAAS_SUBSCRIPTION_ID}`,
        {
          method:  'DELETE',
          headers: { 'access_token': ASAAS_API_KEY },
          signal:  ctrl.signal,
        }
      )
      clearTimeout(timer)
    } catch (fetchErr: unknown) {
      clearTimeout(timer)
      const isAbort = fetchErr instanceof Error && fetchErr.name === 'AbortError'
      return json({ erro: isAbort
        ? 'Tempo limite ao cancelar assinatura no Asaas.'
        : `Erro ao conectar com o Asaas: ${fetchErr instanceof Error ? fetchErr.message : String(fetchErr)}`
      }, 502)
    }

    // Asaas retorna 200 ou 204 no cancelamento bem-sucedido
    if (!cancelRes.ok && cancelRes.status !== 404) {
      const body = await cancelRes.json().catch(() => ({}))
      return json({ erro: `Erro ${cancelRes.status} ao cancelar no Asaas.`, detalhe: body }, 502)
    }

    // Remove o ID da assinatura do banco (assinatura cancelada não é mais válida)
    await supabase
      .from('EMPRESA')
      .update({ ASAAS_SUBSCRIPTION_ID: null })
      .eq('ID_EMP', empresaId)

    return json({ sucesso: true })

  } catch (e: unknown) {
    return json({ erro: e instanceof Error ? e.message : String(e) }, 500)
  }
})
