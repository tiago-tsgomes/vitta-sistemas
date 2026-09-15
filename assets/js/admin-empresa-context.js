/* ═══════════════════════════════════════════════
   Contexto de "empresa ativa" para ADMIN_GLOBAL
   Permite que um Admin Global escolha, no header,
   uma empresa para operar como se fosse Admin
   Empresa dela. Sem seleção, páginas operacionais
   não devem buscar/mostrar nenhum dado de empresa.
   Requer que config.js já tenha rodado (window.supabase).
═══════════════════════════════════════════════ */
(function () {
  const STORAGE_KEY = 'vitta_admin_empresa_ctx';

  function _read() {
    try {
      const raw = sessionStorage.getItem(STORAGE_KEY);
      if (!raw) return null;
      const parsed = JSON.parse(raw);
      if (!parsed || !parsed.id) return null;
      return parsed;
    } catch (_) { return null; }
  }

  function _write(ctx) {
    try { sessionStorage.setItem(STORAGE_KEY, JSON.stringify(ctx)); } catch (_) {}
  }

  function clear() {
    try { sessionStorage.removeItem(STORAGE_KEY); } catch (_) {}
  }

  function get() {
    const ctx = _read();
    if (!ctx) return null;
    return { id: ctx.id, nome: ctx.nome };
  }

  function set(id, nome, authId) {
    _write({ id, nome, authId: authId || null });
    location.reload();
  }

  function resolveIdEmp(tipoUsu, metaIdEmp) {
    if (tipoUsu !== 'ADMIN_GLOBAL') return metaIdEmp || null;
    const ctx = get();
    return ctx ? ctx.id : null;
  }

  // Descarta contexto de sessão anterior se o usuário logado mudou
  // (defesa extra além do listener de SIGNED_OUT abaixo).
  function _validateOwner(authId) {
    const stored = _read();
    if (stored && stored.authId && authId && stored.authId !== authId) clear();
  }

  async function initSelector(tipoUsu, authId) {
    _validateOwner(authId);
    if (tipoUsu !== 'ADMIN_GLOBAL') return;

    const anchorSpan = document.getElementById('empresa-nome');
    if (!anchorSpan) return;
    const card = anchorSpan.parentElement;
    if (!card || card.querySelector('#admin-empresa-select')) return;

    anchorSpan.style.display = 'none';

    const select = document.createElement('select');
    select.id = 'admin-empresa-select';
    select.className = 'text-[0.78rem] font-semibold text-gray-700 bg-transparent outline-none border-none cursor-pointer max-w-[150px] sm:max-w-[220px]';
    select.innerHTML = '<option value="">Selecione a empresa…</option>';
    card.appendChild(select);

    const ctx = get();

    try {
      const { data } = await supabase.from('EMPRESA')
        .select('ID_EMP,NOME_EMP').eq('ATIVO_EMP', true).order('NOME_EMP');
      (data || []).forEach(emp => {
        const opt = document.createElement('option');
        opt.value = emp.ID_EMP;
        opt.textContent = emp.NOME_EMP;
        if (ctx && ctx.id === emp.ID_EMP) opt.selected = true;
        select.appendChild(opt);
      });
    } catch (_) {}

    select.addEventListener('change', () => {
      const id = select.value;
      if (!id) { clear(); location.reload(); return; }
      const nome = select.options[select.selectedIndex].textContent;
      set(id, nome, authId);
    });
  }

  function renderBloqueio(selectors, opts) {
    opts = opts || {};
    (selectors || []).forEach(sel => {
      document.querySelectorAll(sel).forEach(el => { el.style.display = 'none'; });
    });
    if (document.getElementById('_admin-empresa-bloqueio')) return;

    const mensagem = opts.mensagem || 'Selecione uma empresa no topo da página para visualizar os dados.';
    const box = document.createElement('div');
    box.id = '_admin-empresa-bloqueio';
    box.style.cssText = 'display:flex;flex-direction:column;align-items:center;justify-content:center;gap:.75rem;padding:4.5rem 1.5rem;text-align:center;';
    box.innerHTML = `
      <div style="width:64px;height:64px;border-radius:16px;background:#f0fbfd;display:flex;align-items:center;justify-content:center">
        <svg style="width:30px;height:30px;color:#2ABCD4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.8">
          <path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/><polyline points="9 22 9 12 15 12 15 22"/>
        </svg>
      </div>
      <p style="font-size:.88rem;font-weight:600;color:#374151;max-width:320px">${mensagem}</p>`;

    const headerEl = document.querySelector('header');
    if (headerEl) headerEl.insertAdjacentElement('afterend', box);
    else document.body.appendChild(box);
  }

  if (window.supabase && supabase.auth && supabase.auth.onAuthStateChange) {
    supabase.auth.onAuthStateChange((event) => {
      if (event === 'SIGNED_OUT') clear();
    });
  }

  window.AdminEmpresaCtx = { get, set, clear, resolveIdEmp, initSelector, renderBloqueio };
})();
