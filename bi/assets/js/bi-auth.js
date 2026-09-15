/* Vitta BI — sessão do usuário logado.
   Em produção, bi.vittasistemas.com.br é origem separada do app principal —
   a sessão chega via handoff token (ver bi/index.html e initVittaBIMenu em
   assets/js/config.js) e fica persistida no localStorage desta própria
   origem depois disso. Sem sessão aqui, só resta mandar de volta pro login
   do app (não existe app/index.html relativo neste domínio). Em dev/local,
   roda no mesmo host do app principal, daí o fallback relativo. Client
   próprio (não reusa assets/js/config.js do app principal, que dispara
   vários side effects específicos das páginas dele). */
(function () {
  const SUPABASE_URL = 'https://ccdeuabmjwgntwssjfgo.supabase.co';
  const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNjZGV1YWJtandnbnR3c3NqZmdvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg2NzM1MjcsImV4cCI6MjA5NDI0OTUyN30.6I2TjAzyIuoKxA1Q-lbM6ibMLVo1_CtEmEjfbjBvlUs';
  const LOGIN_URL = location.hostname.endsWith('vittasistemas.com.br')
    ? 'https://app.vittasistemas.com.br/index.html'
    : '../../index.html';

  const TIPO_LABELS = {
    ADMIN_GLOBAL: 'Admin Global',
    ADMIN_EMPRESA: 'Administrador',
    SECRETARIA: 'Secretaria',
    PROFISSIONAL: 'Profissional',
    USUARIO: 'Usuário',
  };

  const client = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

  function iniciais(nome) {
    return nome.trim().split(/\s+/).slice(0, 2).map((w) => w[0]).join('').toUpperCase() || '?';
  }

  async function getCurrentUser() {
    const { data: { session } } = await client.auth.getSession();
    if (!session) {
      window.location.href = LOGIN_URL;
      return null;
    }

    const meta = session.user.user_metadata || {};
    const idEmp = meta.ID_EMP || meta.id_emp || null;

    let usuario = null;
    try {
      let query = client.from('USUARIO').select('NOME_USU,TIPO_USU,EMPRESA(NOME_EMP)').eq('AUTH_ID', session.user.id);
      if (idEmp) query = query.eq('ID_EMP', idEmp);
      const { data } = await query.maybeSingle();
      usuario = data;
    } catch (_) { /* mantém fallback abaixo */ }

    const nome = (usuario && usuario.NOME_USU) || meta.nome_usu || session.user.email;
    const tipo = (usuario && usuario.TIPO_USU) || meta.tipo_usu || 'USUARIO';
    const empresaNome = (usuario && usuario.EMPRESA && usuario.EMPRESA.NOME_EMP) || '';

    return {
      userName: nome,
      userRole: TIPO_LABELS[tipo] || 'Usuário',
      avatarLetter: iniciais(nome),
      empresaNome,
      idEmp,
    };
  }

  window.BIAuth = { getCurrentUser, client };
})();
