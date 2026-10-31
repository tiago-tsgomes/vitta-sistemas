import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), { status, headers: { ...cors, 'Content-Type': 'application/json' } })

// Perfil e empresa vêm da tabela USUARIO — o user_metadata do login pode ser
// editado pelo próprio usuário e não serve para decidir permissões.
// deno-lint-ignore no-explicit-any
async function vinculosAtivos(supabase: any, authId: string): Promise<{ TIPO_USU: string; ID_EMP: string | null }[]> {
  const { data } = await supabase
    .from('USUARIO')
    .select('TIPO_USU, ID_EMP, ATIVO_USU')
    .eq('AUTH_ID', authId)
  // deno-lint-ignore no-explicit-any
  return (data || []).filter((u: any) => u.ATIVO_USU !== false)
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })

  try {
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

    const meta  = userData.user.user_metadata || {}
    const idEmp = meta.ID_EMP || meta.id_emp
    const vinculos = await vinculosAtivos(supabase, userData.user.id)

    // Só Administrador da empresa acessa o BI, e só se o plano incluir o BI
    // (TEM_BI_PLANO) ou a empresa tiver liberação manual (BI_ACESSO_EMP) —
    // mesma regra usada para exibir o menu Vitta BI
    // em assets/js/config.js (initVittaBIMenu). Revalidar aqui evita que
    // alguém chame a função direto e gere um link de acesso sem ter o
    // módulo liberado para a empresa.
    if (!idEmp || !vinculos.some((u) => u.TIPO_USU === 'ADMIN_EMPRESA' && u.ID_EMP === idEmp)) {
      return json({ erro: 'Sem acesso ao Vitta BI' }, 403)
    }

    const { data: emp } = await supabase
      .from('EMPRESA')
      .select('BI_ACESSO_EMP, PLANO:ID_PLANO(TEM_BI_PLANO)')
      .eq('ID_EMP', idEmp)
      .single()

    const plano = emp?.PLANO as { TEM_BI_PLANO?: boolean } | null
    if (!emp?.BI_ACESSO_EMP && !plano?.TEM_BI_PLANO) return json({ erro: 'Empresa sem acesso ao Vitta BI' }, 403)
    if (!userData.user.email) return json({ erro: 'Usuário sem email cadastrado' }, 400)

    // generateLink não envia e-mail nenhum, só emite o token_hash — que o
    // bi.vittasistemas.com.br troca por uma sessão própria via verifyOtp().
    // Expira em minutos e é de uso único, diferente de repassar o
    // access_token/refresh_token da sessão atual direto pela URL.
    const { data: linkData, error: linkErr } = await supabase.auth.admin.generateLink({
      type: 'magiclink',
      email: userData.user.email,
    })

    if (linkErr || !linkData) return json({ erro: linkErr?.message || 'Falha ao gerar link de acesso' }, 500)

    const tokenHash = linkData.properties?.hashed_token
    if (!tokenHash) return json({ erro: 'Falha ao gerar token de acesso' }, 500)

    return json({ token_hash: tokenHash })

  } catch (e: unknown) {
    return json({ erro: e instanceof Error ? e.message : String(e) }, 500)
  }
})
