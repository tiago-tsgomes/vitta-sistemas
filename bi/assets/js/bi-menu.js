/* Vitta BI — menu lateral e header, compartilhados entre as páginas do módulo.
   Evita duplicar o HTML da sidebar/header em cada página (mesmo padrão de
   centralização já usado em assets/js/config.js no app principal). */
(function () {
  const APP_BASE_URL = 'https://app.vittasistemas.com.br';

  const ICON_PATHS = {
    dashboard: '<rect x="3" y="3" width="7" height="9" rx="1.5"/><rect x="14" y="3" width="7" height="5" rx="1.5"/><rect x="14" y="12" width="7" height="9" rx="1.5"/><rect x="3" y="16" width="7" height="5" rx="1.5"/>',
    financeiro: '<circle cx="12" cy="12" r="9"/><path d="M12 7v10M9.5 9.5c0-1.4 1.2-2.2 2.5-2.2s2.5.8 2.5 2c0 2.4-5 1.6-5 4 0 1.2 1.2 2.2 2.5 2.2s2.5-.8 2.5-2.2"/>',
    despesas: '<path d="M6 2h12v20l-3-2-3 2-3-2-3 2z"/><path d="M9 8h6"/><path d="M9 12h6"/>',
    agenda: '<rect x="3" y="4" width="18" height="17" rx="2"/><path d="M3 9h18M8 2v4M16 2v4"/>',
    pacientes: '<circle cx="9" cy="8" r="3.2"/><path d="M3 20c0-3.3 2.7-6 6-6s6 2.7 6 6"/><circle cx="17.5" cy="9.5" r="2.4"/><path d="M15.5 14.2c2.6.3 4.7 2.6 4.7 5.3"/>',
    leads: '<path d="M3 4h18l-6.5 8.5V19l-5 2v-8.5z"/>',
    equipe: '<rect x="4" y="12" width="4" height="8" rx="1"/><rect x="10" y="7" width="4" height="13" rx="1"/><rect x="16" y="3" width="4" height="17" rx="1"/>',
    relatorios: '<path d="M6 2h9l5 5v14a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1V3a1 1 0 0 1 1-1z"/><path d="M15 2v6h6"/><path d="M8 13h8M8 17h5"/>',
  };

  const NAV_ITEMS = [
    { key: 'dashboard', label: 'Dashboard', href: 'dashboard.html', ready: true },
    { key: 'financeiro', label: 'Financeiro', href: 'financeiro.html', ready: true },
    { key: 'despesas', label: 'Despesas', href: 'despesas.html', ready: true },
    { key: 'agenda', label: 'Agenda & Ocupação', href: 'agenda.html', ready: false },
    { key: 'pacientes', label: 'Pacientes', href: 'pacientes.html', ready: false },
    { key: 'leads', label: 'Leads', href: 'leads.html', ready: true },
    { key: 'equipe', label: 'Equipe & Produtividade', href: 'equipe.html', ready: false },
    { key: 'relatorios', label: 'Relatórios personalizados', href: 'relatorios.html', ready: false },
  ];

  function renderBISidebar(mountSelector, { active, empresaNome }) {
    const mount = document.querySelector(mountSelector);
    if (!mount) return;

    const navHtml = NAV_ITEMS.map((item) => {
      const on = item.key === active;
      const iconColor = on ? '#6D5DF6' : '#9CA3AF';
      const textColor = on ? '#4F3DD1' : '#6B7280';
      const wrapStyle = `display:flex;align-items:center;gap:11px;margin:1px 10px;padding:8px 12px;border-radius:10px;font-size:13.5px;font-weight:${on ? 500 : 500};background:${on ? '#F3F1FE' : 'transparent'};text-decoration:none;${item.ready ? 'cursor:pointer;' : 'cursor:default;opacity:.45;'}`;
      const badge = item.ready ? '' : '<span style="margin-left:auto;font-size:10px;font-weight:600;color:#C4C1D6;background:#F5F4FA;padding:2px 6px;border-radius:999px;">EM BREVE</span>';
      const inner = `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="${iconColor}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${ICON_PATHS[item.key]}</svg><span style="color:${textColor};">${item.label}</span>${badge}`;
      const tag = item.ready ? 'a' : 'div';
      const hrefAttr = item.ready ? ` href="${item.href}"` : ' title="Em breve"';
      return `<${tag}${hrefAttr} style="${wrapStyle}">${inner}</${tag}>`;
    }).join('');

    mount.innerHTML = `
      <div style="width:220px;height:100%;background:#FFFFFF;border-right:1px solid #EFEDF9;display:flex;flex-direction:column;flex-shrink:0;overflow-y:auto;">
        <div style="display:flex;flex-direction:column;align-items:center;justify-content:center;gap:4px;padding:26px 20px 22px 20px;">
          <img src="../img/logo_bi.png" alt="Vitta BI" style="height:35px;width:auto;">
          <p style="font-size:.6rem;color:#9CA3AF;letter-spacing:.03em;margin:0;">v1.0.1</p>
        </div>
        <div style="height:1px;background:#F1F0F7;margin:2px 20px 14px 20px;"></div>
        <nav style="flex:1;display:flex;flex-direction:column;gap:2px;">${navHtml}</nav>
        <a href="${APP_BASE_URL}/pages/dashboard.html" style="display:flex;align-items:center;gap:9px;padding:14px 20px;border-top:1px solid #F1F0F7;cursor:pointer;text-decoration:none;">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#9CA3AF" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <path d="M19 12H5M12 19l-7-7 7-7"/>
          </svg>
          <span style="font-size:13px;font-weight:500;color:#9CA3AF;">Voltar ao sistema</span>
        </a>
      </div>
    `;
  }

  function renderBIHeader(mountSelector, { title, subtitle, userName, userRole, avatarLetter }) {
    const mount = document.querySelector(mountSelector);
    if (!mount) return;

    mount.innerHTML = `
      <div style="width:100%;flex-shrink:0;">
        <div style="height:64px;background:#FFFFFF;border-bottom:1px solid #F1F0F5;display:flex;align-items:center;justify-content:space-between;padding:0 28px;">
          <div style="display:flex;align-items:center;gap:12px;">
            <div style="font-size:20px;font-weight:600;color:#111827;">${title}</div>
            <div style="font-size:11.5px;font-weight:600;letter-spacing:.04em;color:#6D5DF6;background:#F3F1FE;padding:3px 8px;border-radius:6px;">BI</div>
            <div style="width:1px;height:16px;background:#EFEDF9;"></div>
            <div style="font-size:14.5px;color:#9CA3AF;">${subtitle}</div>
          </div>
          <div style="display:flex;align-items:center;gap:16px;">
            <div style="display:flex;align-items:center;gap:6px;font-size:13px;color:#C4C1D6;">
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#C4C1D6" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <circle cx="12" cy="12" r="9"/>
                <path d="M3 12h18M12 3c2.5 2.5 3.8 5.7 3.8 9s-1.3 6.5-3.8 9c-2.5-2.5-3.8-5.7-3.8-9s1.3-6.5 3.8-9z"/>
              </svg>
              bi.vittasistemas.com.br
            </div>
            <div style="width:1px;height:24px;background:#F1F0F5;"></div>
            <div style="display:flex;align-items:center;gap:10px;">
              <div style="width:34px;height:34px;border-radius:50%;background:#EEECFE;display:flex;align-items:center;justify-content:center;color:#6D5DF6;font-size:14.5px;font-weight:500;">${avatarLetter}</div>
              <div>
                <div style="font-size:14.5px;font-weight:500;color:#111827;line-height:1.2;">${userName}</div>
                <div style="font-size:12px;color:#9CA3AF;line-height:1.2;">${userRole}</div>
              </div>
            </div>
          </div>
        </div>
      </div>
    `;
  }

  window.BIMenu = { renderBISidebar, renderBIHeader };
})();
