(async function vitaAccessGuard() {
  const EXEMPT = [
    'index.html',
    'cadastro.html',
    'redefinir-senha.html',
    'esqueci-senha.html',
    'planos.html',
    'minha-empresa.html',
  ]

  const page = window.location.pathname.split('/').pop() || 'index.html'
  if (EXEMPT.includes(page)) return

  if (typeof supabase === 'undefined') return

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) {
    window.location.replace('../index.html')
    return
  }

  const metaIdEmp = user.user_metadata?.ID_EMP || user.user_metadata?.id_emp || null

  let usuQuery = supabase.from('USUARIO').select('TIPO_USU, ID_EMP').eq('AUTH_ID', user.id)
  if (metaIdEmp) usuQuery = usuQuery.eq('ID_EMP', metaIdEmp)
  const { data: usu } = await usuQuery.maybeSingle()

  // ADMIN_GLOBAL e usuários sem empresa vinculada não passam pela checagem
  if (!usu || usu.TIPO_USU === 'ADMIN_GLOBAL' || !usu.ID_EMP) return

  const { data: emp } = await supabase
    .from('EMPRESA')
    .select('STATUS_EMP, TRIAL_EXPIRA_EM, ACESSO_ATE, ISENTO_COBRANCA')
    .eq('ID_EMP', usu.ID_EMP)
    .single()

  if (!emp) return
  if (emp.ISENTO_COBRANCA) return

  const now = Date.now()
  const { STATUS_EMP, TRIAL_EXPIRA_EM, ACESSO_ATE } = emp

  if (STATUS_EMP === 'cancelado') {
    window.location.replace('planos.html?motivo=cancelado')
    return
  }

  // Inadimplência: NÃO bloqueia aqui. O aviso (5 dias antes) e o bloqueio
  // total (a partir do dia seguinte ao vencimento do 2º boleto em aberto)
  // já são tratados por initInadimplenciaCheck em config.js. Um redirect
  // imediato aqui pularia essa regra.

  if (STATUS_EMP === 'trial' && TRIAL_EXPIRA_EM && new Date(TRIAL_EXPIRA_EM).getTime() < now) {
    window.location.replace('planos.html?motivo=trial_expirado')
    return
  }

  if (STATUS_EMP === 'ativo' && ACESSO_ATE && new Date(ACESSO_ATE).getTime() < now) {
    window.location.replace('planos.html?motivo=acesso_expirado')
    return
  }
})()
