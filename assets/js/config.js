/* ═══════════════════════════════════════════════
   PERMISSÕES POR PLANO — inicialização síncrona
   Lê do sessionStorage para evitar flash de UI antes
   do DOM renderizar. Verificação async atualiza depois.
═══════════════════════════════════════════════ */
;(function() {
  // Injeta CSS de controle de features antes de qualquer render
  const s = document.createElement('style');
  s.id = '_vitta-plan-style';
  s.textContent =
    'html.vitta-no-ia .vitta-ai-feature{display:none!important}' +
    'html:not(.vitta-no-ia) .vitta-ai-noplan-msg{display:none!important}';
  document.head.appendChild(s);

  // Lê cache do sessionStorage (síncrono — sem flash)
  try {
    const raw = sessionStorage.getItem('vitta_plan');
    if (raw) {
      const plan = JSON.parse(raw);
      window.VittaPlano = plan;
      if (plan.temIA === false) document.documentElement.classList.add('vitta-no-ia');
    }
  } catch(_) {}

  if (!window.VittaPlano) window.VittaPlano = { temApp: true, temIA: true };
})();

const SUPABASE_URL = 'https://ccdeuabmjwgntwssjfgo.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNjZGV1YWJtandnbnR3c3NqZmdvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg2NzM1MjcsImV4cCI6MjA5NDI0OTUyN30.6I2TjAzyIuoKxA1Q-lbM6ibMLVo1_CtEmEjfbjBvlUs';

// URL base do sistema (usada para links de email).
// Em desenvolvimento: http://127.0.0.1:8080 (servidor Python)
// Em produção: https://seudominio.com.br
const APP_BASE_URL = 'https://app.vittasistemas.com.br';

window.supabase = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// Busca a linha do USUARIO para o login atual. Um mesmo AUTH_ID pode ter uma
// linha por empresa (multi-empresa), então sempre filtra também pela empresa
// ativa (ID_EMP do user_metadata) para não pegar a linha errada nem quebrar
// o .single() com "múltiplas linhas encontradas".
async function getUsuarioAtual(cols, session) {
  try {
    if (!session) {
      const { data: { session: s } } = await supabase.auth.getSession();
      session = s;
    }
    if (!session) return null;

    const meta  = session.user.user_metadata || {};
    const idEmp = meta.ID_EMP || meta.id_emp || null;

    let query = supabase.from('USUARIO').select(cols).eq('AUTH_ID', session.user.id);
    if (idEmp) query = query.eq('ID_EMP', idEmp);

    const { data } = await query.maybeSingle();
    return data;
  } catch (_) { return null; }
}

async function setUsuarioAvatarPhoto(authId, idEmp) {
  if (!authId) return;
  try {
    let query = supabase.from('USUARIO').select('FOTO_USU').eq('AUTH_ID', authId);
    if (idEmp) query = query.eq('ID_EMP', idEmp);
    const { data } = await query.limit(1).maybeSingle();
    if (!data?.FOTO_USU) return;
    ['user-avatar', 'header-avatar'].forEach(id => {
      const el = document.getElementById(id);
      if (!el) return;
      el.innerHTML = `<img src="${data.FOTO_USU}" class="w-full h-full object-cover rounded-full" alt="" />`;
      el.classList.add('overflow-hidden');
      el.style.background = 'transparent';
    });
  } catch (_) { }
}

async function setUserAvatarPhoto(profId) {
  if (!profId) return;
  try {
    const { data } = await supabase.from('PROFISSIONAL')
      .select('FOTO_PROF').eq('ID_PROF', profId).single();
    if (!data?.FOTO_PROF) return;
    ['user-avatar', 'header-avatar'].forEach(id => {
      const el = document.getElementById(id);
      if (!el) return;
      el.innerHTML = `<img src="${data.FOTO_PROF}" class="w-full h-full object-cover rounded-full" alt="" />`;
      el.classList.add('overflow-hidden');
      el.style.background = 'transparent';
    });
  } catch (_) { /* mantém iniciais se falhar */ }
}

/* ───────────────────────────────────────────────
   Badge de plano no cabeçalho
   Injeta automaticamente em qualquer página que
   tenha o elemento #empresa-nome no header.
─────────────────────────────────────────────── */
;(function() {
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initPlanBadge);
  } else {
    initPlanBadge();
  }

async function initPlanBadge() {
  const empresaNomeEl = document.getElementById('empresa-nome');
  if (!empresaNomeEl) return;

  // Garante que a animação de pulso funcione sem depender do Tailwind
  if (!document.getElementById('_plan-badge-style')) {
    const s = document.createElement('style');
    s.id = '_plan-badge-style';
    s.textContent = '@keyframes _pulse{0%,100%{opacity:1}50%{opacity:.4}}@keyframes _fadeIn{from{opacity:0;transform:scale(.96)}to{opacity:1;transform:scale(1)}}';
    document.head.appendChild(s);
  }

  // Cria o badge (oculto por padrão)
  const badge = document.createElement('div');
  badge.id = 'plano-badge';
  badge.style.cssText = 'display:none';
  empresaNomeEl.parentElement.insertAdjacentElement('afterend', badge);

  try {
    const { data: { session } } = await supabase.auth.getSession();
    if (!session) return;

    const meta  = session.user.user_metadata || {};
    const tipo  = meta.tipo_usu;
    if (tipo === 'ADMIN_GLOBAL') return;

    const idEmp = meta.ID_EMP || meta.id_emp;
    if (!idEmp) return;

    const { data: emp } = await supabase
      .from('EMPRESA')
      .select('STATUS_EMP, TRIAL_EXPIRA_EM, ISENTO_COBRANCA, PLANO:ID_PLANO(NOME_PLANO)')
      .eq('ID_EMP', idEmp)
      .single();

    if (!emp) return;

    const nomePlano = emp.PLANO?.NOME_PLANO || '';
    const status    = emp.STATUS_EMP || '';

    if (emp.ISENTO_COBRANCA) {
      badge.style.cssText = 'display:flex;align-items:center;gap:5px;padding:5px 10px;background:#f0fdf4;border:1.5px solid #86efac;border-radius:10px;cursor:default;user-select:none';
      badge.innerHTML = `
        <svg style="width:13px;height:13px;flex-shrink:0;color:#16a34a" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2.5">
          <path stroke-linecap="round" stroke-linejoin="round" d="M9 12.75L11.25 15 15 9.75M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/>
        </svg>
        <span style="font-size:0.72rem;font-weight:700;color:#15803d">${nomePlano || 'Isento de cobrança'}</span>`;
      badge.title = 'Empresa isenta de cobrança';
      return;
    }

    if (status === 'trial') {
      const expira = new Date(emp.TRIAL_EXPIRA_EM);
      const dias   = Math.max(0, Math.ceil((expira - new Date()) / 86400000));
      const diasTxt = dias === 1 ? '1 dia restante' : `${dias} dias restantes`;

      badge.style.cssText = 'display:flex;align-items:center;gap:6px;padding:5px 10px;background:#fffbeb;border:1.5px solid #fcd34d;border-radius:10px;cursor:default;user-select:none';
      badge.innerHTML = `
        <span style="width:7px;height:7px;border-radius:50%;background:#f59e0b;flex-shrink:0;animation:_pulse 1.8s ease-in-out infinite"></span>
        <span style="display:flex;flex-direction:column;line-height:1.1">
          <span style="font-size:0.7rem;font-weight:700;color:#92400e">${nomePlano || 'Trial'}</span>
          <span style="font-size:0.62rem;color:#b45309">${diasTxt}</span>
        </span>`;
      badge.title = `Período de teste — expira em ${expira.toLocaleDateString('pt-BR')}`;

    } else if (nomePlano) {
      badge.style.cssText = 'display:flex;align-items:center;gap:5px;padding:5px 10px;background:#f0fbfd;border:1.5px solid #80deea;border-radius:10px;cursor:default;user-select:none';
      badge.innerHTML = `
        <svg style="width:13px;height:13px;flex-shrink:0;color:#1a96ac" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2.5">
          <path d="M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2z"/>
        </svg>
        <span style="font-size:0.72rem;font-weight:700;color:#127a8c">${nomePlano}</span>`;
    }
  } catch (_) { badge.style.display = 'none'; }
}
})();

/* ───────────────────────────────────────────────
   Controle de inadimplência
   • Bloqueio agendado só quando existe um 2º boleto em
     aberto além do 1º já vencido e não pago — ACESSO_ATE
     guarda o vencimento desse 2º boleto (calculado no
     backend, ver _shared/billing.ts). O bloqueio total
     ocorre no dia seguinte a essa data.
     Ex.: boletos vencendo 20/08 e 20/09 → se 20/09 vencer
     sem o 20/08 ter sido pago, bloqueia em 21/09.
   • Nos 5 dias antes do bloqueio → popup de aviso no
     dashboard (Administrador/Secretaria — não-Profissional)
   • Roda em qualquer página desktop com #empresa-nome
     no header, e em qualquer página mobile (exceto
     access-denied, que já é a tela de bloqueio de
     acesso ao app). Em apps multi-página como este,
     cada navegação recarrega config.js do zero — então
     rodar em toda página mobile já revalida a cada troca
     de tela, sem precisar de listener de resume nativo.
─────────────────────────────────────────────── */
;(function() {
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initInadimplenciaCheck);
  } else {
    initInadimplenciaCheck();
  }

async function initInadimplenciaCheck() {
  const isMobilePage   = location.pathname.includes('/mobile/');
  const isAccessDenied = /\/mobile\/access-denied\.html$/.test(location.pathname);
  if (isAccessDenied) return;
  if (!isMobilePage && !document.getElementById('empresa-nome')) return;

  try {
    const { data: { session } } = await supabase.auth.getSession();
    if (!session) return;

    const meta = session.user.user_metadata || {};
    const tipo = meta.tipo_usu;
    if (tipo === 'ADMIN_GLOBAL') return;

    const idEmp = meta.ID_EMP || meta.id_emp;
    if (!idEmp) return;

    const { data: emp } = await supabase
      .from('EMPRESA')
      .select('STATUS_EMP, ACESSO_ATE, ISENTO_COBRANCA')
      .eq('ID_EMP', idEmp)
      .single();

    if (!emp) return;
    if (emp.ISENTO_COBRANCA) return;

    const hoje = new Date(); hoje.setHours(0, 0, 0, 0);
    const isProfissional = tipo === 'PROFISSIONAL';
    const faturasUrl     = isMobilePage ? '../pages/faturas.html' : 'faturas.html';
    // faturas.html é o destino do bloqueio — nunca cobrir essa própria página
    // com o overlay, senão o usuário fica impedido de ver/pagar o boleto.
    const isFaturasPage   = (location.pathname.split('/').pop() || '') === 'faturas.html';
    // popup de aviso (até 5 dias antes) só no dashboard — o bloqueio total
    // continua valendo em qualquer página, propositalmente.
    const isDashboardPage = (location.pathname.split('/').pop() || '') === 'dashboard.html';

    // ACESSO_ATE vem do banco como timestamptz (ISO, meia-noite UTC). Extrair
    // só a parte "AAAA-MM-DD" e reconstruir como meia-noite local evita
    // perder um dia em fusos negativos (Brasil = UTC-3) ao truncar a hora —
    // new Date(isoCompleto).setHours(0,0,0,0) joga a data para o dia anterior.
    const soData = (iso) => iso ? new Date(iso.slice(0, 10) + 'T00:00:00') : null;

    if (emp.STATUS_EMP === 'cancelamento_agendado') {
      const ate = soData(emp.ACESSO_ATE);
      if (ate && hoje > ate && !isFaturasPage) _showSistemaBloqueado(isProfissional, faturasUrl, 'cancelado');
      return; // dentro do período pago, acesso normal
    }

    if (emp.STATUS_EMP !== 'inadimplente') return;

    // ACESSO_ATE só existe quando há um 2º boleto em aberto (bloqueio
    // agendado). Com só 1 boleto vencido, ACESSO_ATE vem nulo — empresa já
    // é inadimplente, mas ainda sem bloqueio previsto.
    const ref = soData(emp.ACESSO_ATE);
    if (!ref) return;

    if (isFaturasPage) return; // já está no lugar certo para regularizar

    const diasParaVencimento = Math.round((ref - hoje) / 86400000);

    if (diasParaVencimento < 0) {
      // 2º boleto já venceu sem pagamento: bloqueio total, no dia seguinte
      _showSistemaBloqueado(isProfissional, faturasUrl);
    } else if (diasParaVencimento <= 4) {
      // faltam até 5 dias para o bloqueio (que ocorre no dia seguinte ao
      // vencimento do 2º boleto)
      if (isProfissional || !isDashboardPage) return;
      const diasParaBloqueio = diasParaVencimento + 1;
      _showInadimplenciaPopup(diasParaBloqueio, faturasUrl);
    }
  } catch (_) {}
}
})();

function _showInadimplenciaPopup(diasParaBloqueio, faturasUrl) {
  const diasTxt = diasParaBloqueio === 1 ? '1 dia' : `${diasParaBloqueio} dias`;
  const overlay = document.createElement('div');
  overlay.id = '_inadimplencia-popup';
  overlay.style.cssText = [
    'position:fixed;inset:0;z-index:99990',
    'background:rgba(0,0,0,0.45)',
    'display:flex;align-items:center;justify-content:center',
    'padding:1rem',
    'animation:_fadeIn .2s ease',
  ].join(';');

  overlay.innerHTML = `
    <div style="background:#fff;border-radius:16px;padding:2rem;max-width:420px;width:100%;box-shadow:0 20px 60px rgba(0,0,0,0.25);text-align:center">
      <div style="width:56px;height:56px;border-radius:50%;background:#fff7ed;border:2px solid #fed7aa;display:flex;align-items:center;justify-content:center;margin:0 auto 1rem">
        <svg style="width:28px;height:28px;color:#f97316" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
          <path stroke-linecap="round" stroke-linejoin="round" d="M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126zM12 15.75h.007v.008H12v-.008z"/>
        </svg>
      </div>
      <h3 style="font-size:1.1rem;font-weight:700;color:#111827;margin-bottom:.5rem">Pagamento em atraso</h3>
      <p style="font-size:.875rem;color:#6b7280;margin-bottom:1.5rem;line-height:1.5">
        Há boletos em aberto na sua conta. Se não forem regularizados, o
        sistema será <strong style="color:#f97316">bloqueado em ${diasTxt}</strong>.
      </p>
      <div style="display:flex;gap:.75rem;justify-content:center;flex-wrap:wrap">
        <button onclick="document.getElementById('_inadimplencia-popup').remove()"
          style="padding:.6rem 1.25rem;border-radius:8px;border:1.5px solid #e5e7eb;background:#fff;color:#6b7280;font-size:.875rem;font-weight:600;cursor:pointer">
          Lembrar mais tarde
        </button>
        <a href="${faturasUrl}"
          style="padding:.6rem 1.25rem;border-radius:8px;background:#1a96ac;color:#fff;font-size:.875rem;font-weight:700;text-decoration:none;display:inline-flex;align-items:center;gap:.4rem">
          <svg style="width:15px;height:15px" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2.5">
            <path stroke-linecap="round" stroke-linejoin="round" d="M2.25 8.25h19.5M2.25 9h19.5m-16.5 5.25h6m-6 2.25h3m-3.75 3h15a2.25 2.25 0 002.25-2.25V6.75A2.25 2.25 0 0019.5 4.5h-15a2.25 2.25 0 00-2.25 2.25v10.5A2.25 2.25 0 004.5 19.5z"/>
          </svg>
          Pagar Agora
        </a>
      </div>
    </div>`;

  document.body.appendChild(overlay);
}

function _showSistemaBloqueado(isProfissional, faturasUrl, motivo) {
  const overlay = document.createElement('div');
  overlay.id = '_sistema-bloqueado';
  overlay.style.cssText = [
    'position:fixed;inset:0;z-index:99999',
    'background:#f9fafb',
    'display:flex;align-items:center;justify-content:center',
    'padding:1.5rem',
  ].join(';');

  const acaoHtml = (isProfissional || motivo === 'cancelado')
    ? `<p style="font-size:.875rem;color:#6b7280;margin-top:.5rem">${isProfissional ? 'Entre em contato com o administrador para regularizar.' : 'Para contratar novamente entre em contato com o suporte.'}</p>`
    : `<a href="${faturasUrl}"
        style="margin-top:1.5rem;display:inline-flex;align-items:center;gap:.5rem;padding:.75rem 1.75rem;border-radius:10px;background:#1a96ac;color:#fff;font-size:.9rem;font-weight:700;text-decoration:none;box-shadow:0 4px 14px rgba(26,150,172,.35)">
        <svg style="width:18px;height:18px" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2.5">
          <path stroke-linecap="round" stroke-linejoin="round" d="M2.25 8.25h19.5M2.25 9h19.5m-16.5 5.25h6m-6 2.25h3m-3.75 3h15a2.25 2.25 0 002.25-2.25V6.75A2.25 2.25 0 0019.5 4.5h-15a2.25 2.25 0 00-2.25 2.25v10.5A2.25 2.25 0 004.5 19.5z"/>
        </svg>
        Pagar Agora
      </a>`;

  const voltarLoginHtml = isProfissional
    ? `<div>
        <button type="button" onclick="_voltarLogin()"
          style="margin-top:1rem;display:inline-flex;align-items:center;gap:.4rem;padding:.6rem 1.25rem;border-radius:10px;background:transparent;color:#6b7280;font-size:.85rem;font-weight:600;border:1px solid #d1d5db;cursor:pointer">
          Voltar para o Login
        </button>
      </div>`
    : '';

  overlay.innerHTML = `
    <div style="text-align:center;max-width:460px;width:100%">
      <div style="width:72px;height:72px;border-radius:50%;background:#fee2e2;border:2px solid #fca5a5;display:flex;align-items:center;justify-content:center;margin:0 auto 1.5rem">
        <svg style="width:36px;height:36px;color:#ef4444" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
          <path stroke-linecap="round" stroke-linejoin="round" d="M16.5 10.5V6.75a4.5 4.5 0 10-9 0v3.75m-.75 11.25h10.5a2.25 2.25 0 002.25-2.25v-6.75a2.25 2.25 0 00-2.25-2.25H6.75a2.25 2.25 0 00-2.25 2.25v6.75a2.25 2.25 0 002.25 2.25z"/>
        </svg>
      </div>
      <h2 style="font-size:1.5rem;font-weight:800;color:#111827;margin-bottom:.75rem">Sistema Bloqueado</h2>
      <p style="font-size:.95rem;color:#6b7280;line-height:1.6;margin-bottom:.25rem">
        ${motivo === 'cancelado'
          ? (isProfissional ? 'A assinatura foi encerrada. Contate o administrador.' : 'A assinatura foi encerrada e o período de acesso expirou.')
          : (isProfissional ? 'O acesso ao sistema está temporariamente suspenso.' : 'O pagamento está em atraso. Realize o pagamento do boleto para restaurar o acesso imediatamente.')}
      </p>
      ${acaoHtml}
      ${voltarLoginHtml}
    </div>`;

  document.body.appendChild(overlay);
}

window._voltarLogin = async function() {
  try {
    if (window.Capacitor?.Plugins?.Preferences) {
      await Capacitor.Plugins.Preferences.remove({ key: 'vitta_session' });
    }
  } catch (_) {}
  try { await supabase.auth.signOut(); } catch (_) {}
  window.location.href = '../index.html';
};

/* ───────────────────────────────────────────────
   Heartbeat de "último acesso"
   set_ultimo_acesso_empresa/plataforma antes só eram
   chamadas no momento do login (index.html). Quem loga
   uma vez e mantém a sessão viva por dias (o supabase-js
   renova o token sozinho, sem passar pelo login de novo)
   ficava com ULTIMO_ACESSO_EMP congelado — aparecendo como
   "Nunca acessou" em logs.html mesmo usando o sistema todo
   dia. Roda 1x por sessão de navegador/app (sessionStorage
   evita bater no banco a cada troca de página).
─────────────────────────────────────────────── */
;(async function initAcessoHeartbeat() {
  const FLAG = 'vitta_acesso_heartbeat_done';
  try {
    if (sessionStorage.getItem(FLAG)) return;
    const { data: { session } } = await supabase.auth.getSession();
    if (!session) return;
    sessionStorage.setItem(FLAG, '1');

    const meta = session.user.user_metadata || {};
    const { error: ePlat } = await supabase.rpc('set_ultimo_acesso_plataforma', { p_plataforma: (window.Capacitor?.getPlatform?.() || 'web') });
    if (ePlat) console.warn('[heartbeat] set_ultimo_acesso_plataforma falhou:', ePlat.message);
    const { error: eEmp } = await supabase.rpc('set_ultimo_acesso_empresa', { p_id_emp: meta.ID_EMP || meta.id_emp || null });
    if (eEmp) console.warn('[heartbeat] set_ultimo_acesso_empresa falhou:', eEmp.message);
  } catch (e) { console.warn('[heartbeat] erro inesperado:', e?.message || e); }
})();

/* ───────────────────────────────────────────────
   Menu Vitta BI
   Visível só para o Administrador (ADMIN_EMPRESA) de
   empresas com BI_ACESSO_EMP=true. O item de menu
   (#sectionVittaBI) já vem oculto no HTML de cada
   página; aqui só decide se revela. O link (#linkVittaBI)
   aponta pro domínio de produção só quando o app está
   rodando nele; em qualquer outro host (localhost, IP
   da rede local, etc.) aponta pro bi/ local, pra testes.

   Em produção, bi.vittasistemas.com.br é uma origem
   separada do app — sessão do localStorage não atravessa
   sozinha. O clique intercepta a navegação, troca o
   access_token atual por um token_hash de uso único (Edge
   Function bi-handoff, que já revalida ADMIN_EMPRESA +
   BI_ACESSO_EMP no servidor) e abre o BI já com esse token,
   que ../bi/index.html troca por sessão via verifyOtp().
   window.open síncrono (antes do fetch) evita bloqueio de
   pop-up, já que o gesto do usuário não cobre a parte async.
─────────────────────────────────────────────── */
;(function() {
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initVittaBIMenu);
  } else {
    initVittaBIMenu();
  }

async function initVittaBIMenu() {
  const el = document.getElementById('sectionVittaBI');
  if (!el) return;
  try {
    const link = document.getElementById('linkVittaBI');
    if (link) {
      const isProd = location.hostname.endsWith('vittasistemas.com.br');
      link.href = isProd ? 'https://bi.vittasistemas.com.br' : '/bi/pages/dashboard.html';

      if (isProd) {
        link.addEventListener('click', async (e) => {
          e.preventDefault();
          const win = window.open('', '_blank');
          try {
            const { data: { session } } = await supabase.auth.getSession();
            if (!session) { if (win) win.close(); window.location.href = '../index.html'; return; }

            const res = await fetch(`${SUPABASE_URL}/functions/v1/bi-handoff`, {
              headers: { Authorization: `Bearer ${session.access_token}`, apikey: SUPABASE_ANON_KEY },
            });
            const body = await res.json();
            if (!res.ok || !body.token_hash) throw new Error(body.erro || 'Falha ao abrir o Vitta BI');

            const dest = `https://bi.vittasistemas.com.br/?token_hash=${encodeURIComponent(body.token_hash)}`;
            if (win) win.location.href = dest; else window.location.href = dest;
          } catch (err) {
            if (win) win.close();
            alert('Não foi possível abrir o Vitta BI agora. Tente novamente.');
          }
        });
      }
    }

    const { data: { session } } = await supabase.auth.getSession();
    if (!session) return;

    const meta = session.user.user_metadata || {};
    if (meta.tipo_usu !== 'ADMIN_EMPRESA') return;

    const idEmp = meta.ID_EMP || meta.id_emp;
    if (!idEmp) return;

    const { data: emp } = await supabase
      .from('EMPRESA')
      .select('BI_ACESSO_EMP')
      .eq('ID_EMP', idEmp)
      .single();

    if (emp?.BI_ACESSO_EMP) el.classList.remove('hidden');
  } catch (_) {}
}
})();

/* ───────────────────────────────────────────────
   Verificação async de permissões do plano
   Confirma / corrige o cache do sessionStorage.
─────────────────────────────────────────────── */
;(async function initPlanPermissions() {
  try {
    const { data: { session } } = await supabase.auth.getSession();
    if (!session) { sessionStorage.removeItem('vitta_plan'); return; }

    const meta = session.user.user_metadata || {};
    if (meta.tipo_usu === 'ADMIN_GLOBAL') {
      sessionStorage.removeItem('vitta_plan');
      document.documentElement.classList.remove('vitta-no-ia');
      window.VittaPlano = { temApp: true, temIA: true };
      return;
    }

    const idEmp = meta.ID_EMP || meta.id_emp;
    if (!idEmp) return;

    const { data: emp } = await supabase
      .from('EMPRESA')
      .select('PLANO:ID_PLANO(TEM_APP_PLANO, TEM_IA_PLANO)')
      .eq('ID_EMP', idEmp)
      .single();

    if (!emp?.PLANO) return;

    const plan = {
      temApp: emp.PLANO.TEM_APP_PLANO === true,
      temIA:  emp.PLANO.TEM_IA_PLANO  === true,
    };
    window.VittaPlano = plan;
    sessionStorage.setItem('vitta_plan', JSON.stringify(plan));

    if (!plan.temIA) {
      document.documentElement.classList.add('vitta-no-ia');
    } else {
      document.documentElement.classList.remove('vitta-no-ia');
    }
  } catch(_) {}
})();

/* ───────────────────────────────────────────────
   Menu lateral: seções sempre fechadas ao abrir uma tela

   As páginas trazem a seção da tela atual com class="submenu open"
   (e o chevron com "open") no HTML. Ao navegar para outra tela, a
   seção clicada ficava aberta. Aqui todas começam recolhidas; o
   usuário abre a que quiser pelo toggleMenu de cada página.
   A transição é desligada durante o recolhimento para não animar
   o fechamento a cada carregamento de página.
─────────────────────────────────────────────── */
;(function() {
  function collapseSidebarSections() {
    const opened = document.querySelectorAll('#sidebar .submenu.open, #sidebar .chevron.open');
    if (!opened.length) return;
    const all = document.querySelectorAll('#sidebar .submenu, #sidebar .chevron');
    all.forEach(el => { el.style.transition = 'none'; });
    opened.forEach(el => el.classList.remove('open'));
    void document.body.offsetHeight; // aplica o estado sem transição
    all.forEach(el => { el.style.transition = ''; });
  }

  collapseSidebarSections();
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', collapseSidebarSections);
  }
})();

/* ───────────────────────────────────────────────
   Menu lateral: esconder Leads e Despesas para o Profissional

   O TIPO_USU real vem sempre do banco (getUsuarioAtual), nunca do
   JWT/user_metadata, para não repetir a regressão de privilégio já
   vista neste projeto. Some para PROFISSIONAL; ADMIN_GLOBAL,
   ADMIN_EMPRESA e SECRETARIA continuam vendo normalmente.
─────────────────────────────────────────────── */
;(function() {
  async function hideLeadsEDespesasParaProfissional() {
    const link = document.getElementById('menuLeads');
    const secao = document.getElementById('sectionDespesas');
    if (!link && !secao) return;
    try {
      const u = await getUsuarioAtual('TIPO_USU');
      if (u?.TIPO_USU === 'PROFISSIONAL') {
        link?.classList.add('hidden');
        secao?.classList.add('hidden');
      }
    } catch (_) {}
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', hideLeadsEDespesasParaProfissional);
  } else {
    hideLeadsEDespesasParaProfissional();
  }
})();
