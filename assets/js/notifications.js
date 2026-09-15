/* Vitta Sistemas — Central de Notificações In-app
 * Inclua após config.js em qualquer página com header padrão.
 * O módulo injeta automaticamente o sino, carrega notificações e expõe window.vittaNotif.
 */
(function () {
  'use strict';

  const TIPO_CFG = {
    INFO:        { cls: 'bg-blue-100 text-blue-600',    svg: '<svg xmlns="http://www.w3.org/2000/svg" class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/></svg>' },
    ALERTA:      { cls: 'bg-amber-100 text-amber-600',  svg: '<svg xmlns="http://www.w3.org/2000/svg" class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/></svg>' },
    SUCESSO:     { cls: 'bg-emerald-100 text-emerald-600', svg: '<svg xmlns="http://www.w3.org/2000/svg" class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><polyline points="20 6 9 17 4 12"/></svg>' },
    PAGAMENTO:   { cls: 'bg-cyan-100 text-cyan-700',    svg: '<svg xmlns="http://www.w3.org/2000/svg" class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><line x1="12" y1="1" x2="12" y2="23"/><path d="M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6"/></svg>' },
    AGENDAMENTO: { cls: 'bg-violet-100 text-violet-600', svg: '<svg xmlns="http://www.w3.org/2000/svg" class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><rect x="3" y="4" width="18" height="18" rx="2"/><line x1="16" y1="2" x2="16" y2="6"/><line x1="8" y1="2" x2="8" y2="6"/><line x1="3" y1="10" x2="21" y2="10"/></svg>' },
  };

  const AV_COLORS = ['bg-blue-500','bg-emerald-500','bg-violet-500','bg-amber-500','bg-rose-500','bg-cyan-500','bg-indigo-500','bg-pink-500'];

  let _data = [], _agenda = [], _open = false;

  function _esc(s) { return String(s||'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); }

  function _avColor(n) { let h=0; for (const c of (n||'')) h=(h<<5)-h+c.charCodeAt(0); return AV_COLORS[Math.abs(h)%AV_COLORS.length]; }

  function _initials(n) { return (n||'').split(' ').filter(Boolean).slice(0,2).map(function(w){return w[0];}).join('').toUpperCase(); }

  function _fmtTime(dt) { if (!dt) return ''; return new Date(dt).toLocaleTimeString('pt-BR',{hour:'2-digit',minute:'2-digit'}); }

  function _ago(dt) {
    const m = Math.floor((Date.now() - new Date(dt)) / 60000);
    if (m < 1) return 'agora';
    if (m < 60) return m + 'min';
    const h = Math.floor(m / 60);
    if (h < 24) return h + 'h';
    return Math.floor(h / 24) + 'd';
  }

  function _badge(n) {
    const el = document.getElementById('notif-badge');
    if (!el) return;
    if (n > 0) { el.textContent = n > 99 ? '99+' : n; el.classList.remove('hidden'); }
    else { el.classList.add('hidden'); }
  }

  function _renderList() {
    const el = document.getElementById('notif-list');
    if (!el) return;
    if (!_data.length) {
      el.innerHTML = '<div class="py-10 text-center"><svg xmlns="http://www.w3.org/2000/svg" class="w-8 h-8 text-gray-200 mx-auto mb-2" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.5"><path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.73 21a2 2 0 0 1-3.46 0"/></svg><p class="text-[0.8rem] text-gray-400">Sem notificações</p></div>';
      return;
    }
    el.innerHTML = _data.map(function(n) {
      var cfg = TIPO_CFG[n.TIPO_NOT] || TIPO_CFG.INFO;
      var safeUrl = (n.URL_NOT||'').replace(/'/g,"\\'");
      return '<div onclick="window.vittaNotif.open(\'' + n.ID_NOT + '\',\'' + safeUrl + '\',' + n.LIDA_NOT + ')" class="flex gap-3 px-4 py-3 cursor-pointer border-b border-gray-50 hover:bg-gray-50 transition-colors' + (!n.LIDA_NOT?' bg-vitta-50/40':'') + '">'
        + '<div class="w-8 h-8 rounded-xl ' + cfg.cls + ' flex items-center justify-center shrink-0 mt-0.5">' + cfg.svg + '</div>'
        + '<div class="flex-1 min-w-0">'
        + '<p class="text-[0.8rem] font-semibold text-gray-800 leading-snug">' + _esc(n.TITULO_NOT) + '</p>'
        + (n.CORPO_NOT ? '<p class="text-[0.72rem] text-gray-500 mt-0.5 leading-snug" style="display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden">' + _esc(n.CORPO_NOT) + '</p>' : '')
        + '<p class="text-[0.67rem] text-gray-400 mt-1">' + _ago(n.DTCRI_NOT) + '</p>'
        + '</div>'
        + (!n.LIDA_NOT ? '<div class="w-2 h-2 rounded-full bg-vitta-500 shrink-0 mt-2.5"></div>' : '')
        + '</div>';
    }).join('');
  }

  function _agendaItemHTML(a) {
    var pac = a.PACIENTE || {};
    var nome = pac.NOME_PAC || '—';
    var idPac = pac.ID_PAC || a.PAC_AGD;
    return '<a href="prontuario.html?pac=' + idPac + '" class="flex items-center gap-2.5 px-4 py-2.5 hover:bg-gray-50 transition-colors border-b border-gray-50">'
      + '<div class="w-8 h-8 rounded-xl ' + _avColor(nome) + ' flex items-center justify-center text-white text-[0.65rem] font-bold shrink-0">' + _esc(_initials(nome)) + '</div>'
      + '<div class="flex-1 min-w-0">'
      + '<p class="text-[0.78rem] font-semibold text-gray-800 truncate">' + _esc(nome) + '</p>'
      + '<p class="text-[0.68rem] text-gray-400 mt-0.5">' + _fmtTime(a.DT_AGD) + '</p>'
      + '</div>'
      + '<svg xmlns="http://www.w3.org/2000/svg" class="w-3.5 h-3.5 text-gray-300 shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M9 5l7 7-7 7"/></svg>'
      + '</a>';
  }

  function _renderAgenda() {
    var section = document.getElementById('notif-agenda-section');
    var listEl = document.getElementById('notif-agenda-list');
    if (!section || !listEl) return;
    if (!_agenda.length) { section.classList.add('hidden'); listEl.innerHTML = ''; return; }
    section.classList.remove('hidden');
    var groups = {}, order = [];
    _agenda.forEach(function(a) {
      var dk = new Date(a.DT_AGD).toDateString();
      if (!groups[dk]) { groups[dk] = []; order.push(dk); }
      groups[dk].push(a);
    });
    listEl.innerHTML = order.map(function(dk) {
      var items = groups[dk];
      var header = new Date(items[0].DT_AGD).toLocaleDateString('pt-BR',{weekday:'short',day:'numeric',month:'short'}).replace(/\./g,'');
      return '<p class="px-4 pt-2 pb-1 text-[0.65rem] font-bold text-gray-400 uppercase tracking-wider">' + _esc(header) + '</p>' + items.map(_agendaItemHTML).join('');
    }).join('');
  }

  // O tipo_usu do JWT (user_metadata) pode ficar desatualizado em relação
  // ao banco (troca de cargo, vínculo multi-empresa, etc). Por isso o tipo
  // real é sempre reconfirmado via USUARIO no banco, nunca só pelo JWT.
  async function _resolveTipo(meta, sess) {
    try {
      if (typeof getUsuarioAtual === 'undefined') return { tipo: meta.tipo_usu, profId: null };
      var u = await getUsuarioAtual('TIPO_USU,PROF_USU', sess);
      return { tipo: (u && u.TIPO_USU) || meta.tipo_usu, profId: u && u.PROF_USU };
    } catch (e) { return { tipo: meta.tipo_usu, profId: null }; }
  }

  async function _loadAgenda(tipo, profId) {
    try {
      if (tipo !== 'PROFISSIONAL' && tipo !== 'ADMIN_EMPRESA') { _agenda = []; return; }
      if (!profId) { _agenda = []; return; }
      var hoje = new Date(); hoje.setHours(0,0,0,0);
      var res = await supabase.from('AGENDAMENTO')
        .select('ID_AGD,DT_AGD,PAC_AGD,PACIENTE!PAC_AGD(NOME_PAC,ID_PAC)')
        .eq('PROF_AGD', profId).eq('STATUS_AGD','CONFIRMADA')
        .gte('DT_AGD', hoje.toISOString())
        .order('DT_AGD').limit(20);
      _agenda = res.data || [];
    } catch(e) { _agenda = []; }
  }

  async function _load() {
    try {
      var sess = (await supabase.auth.getSession()).data.session;
      if (!sess) return;
      var meta = sess.user.user_metadata;
      var real = await _resolveTipo(meta, sess);
      var tipo = real.tipo;
      var idEmp = (typeof AdminEmpresaCtx !== 'undefined')
        ? AdminEmpresaCtx.resolveIdEmp(tipo, meta.ID_EMP || meta.id_emp)
        : (tipo !== 'ADMIN_GLOBAL' ? (meta.ID_EMP || meta.id_emp) : null);
      await _loadAgenda(tipo, real.profId);
      _renderAgenda();
      if (tipo === 'PROFISSIONAL') { _data = []; _badge(_agenda.length); _renderList(); return; }
      if (tipo === 'ADMIN_GLOBAL' && !idEmp) { _data = []; _badge(_agenda.length); _renderList(); return; }
      var q = supabase.from('NOTIFICACAO').select('*').order('DTCRI_NOT',{ascending:false}).limit(25);
      if (idEmp) q = q.eq('ID_EMP', idEmp);
      var res = await q;
      _data = res.data || [];
      _badge(_data.filter(function(n){return !n.LIDA_NOT;}).length + _agenda.length);
      _renderList();
    } catch(e) {}
  }

  function _inject() {
    var header = document.querySelector('header');
    if (!header || document.getElementById('notif-wrap')) return;
    // Remove static decorative bell buttons (no onclick)
    header.querySelectorAll('button:not([onclick]):not([title])').forEach(function(btn){
      if (btn.innerHTML.indexOf('M18 8A6') !== -1 || btn.innerHTML.indexOf('M13.73 21') !== -1) btn.remove();
    });
    var bellHTML = '<div id="notif-wrap" style="position:relative;flex-shrink:0">'
      + '<button id="notif-bell" onclick="window.vittaNotif.toggle(event)" title="Notificações"'
      + ' class="relative p-2.5 rounded-xl hover:bg-gray-100 text-gray-500 transition-colors">'
      + '<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">'
      + '<path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.73 21a2 2 0 0 1-3.46 0"/></svg>'
      + '<span id="notif-badge" class="hidden absolute top-1.5 right-1.5 min-w-[16px] h-4 bg-red-500 rounded-full border border-white text-white text-[0.55rem] font-bold flex items-center justify-center px-0.5"></span>'
      + '</button>'
      + '<div id="notif-drop" class="hidden absolute right-0 mt-2 w-80 bg-white rounded-2xl shadow-2xl border border-gray-100 overflow-hidden" style="top:100%;z-index:9999;max-height:560px">'
      + '<div class="flex items-center justify-between px-4 py-3 border-b border-gray-100">'
      + '<p class="text-sm font-bold text-gray-800">Notificações</p>'
      + '<button onclick="window.vittaNotif.markAllRead()" class="text-[0.72rem] font-semibold text-cyan-500 hover:text-cyan-600 transition-colors">Todas lidas</button>'
      + '</div>'
      + '<div class="overflow-y-auto" style="max-height:470px">'
      + '<div id="notif-agenda-section" class="hidden border-b border-gray-100 pb-1">'
      + '<p class="px-4 pt-3 pb-0.5 text-[0.68rem] font-bold text-gray-400 uppercase tracking-wider">Agenda confirmada</p>'
      + '<div id="notif-agenda-list"></div>'
      + '</div>'
      + '<div id="notif-list"></div>'
      + '</div>'
      + '<div class="border-t border-gray-50 py-2.5 text-center">'
      + '<a href="notificacoes.html" class="text-[0.75rem] font-semibold text-cyan-500 hover:text-cyan-600">Ver todas as notificações →</a>'
      + '</div></div></div>';
    var tmp = document.createElement('div');
    tmp.innerHTML = bellHTML;
    var node = tmp.firstChild;
    var logoutBtn = header.querySelector('button[title="Sair"]') || header.querySelector('button[onclick*="handleLogout"]');
    if (logoutBtn) header.insertBefore(node, logoutBtn);
    else header.appendChild(node);
  }

  window.vittaNotif = {
    toggle: function(e) {
      if (e) e.stopPropagation();
      _open = !_open;
      var drop = document.getElementById('notif-drop');
      if (drop) drop.classList.toggle('hidden', !_open);
      if (_open) _load();
    },
    markAllRead: async function() {
      try {
        var sess = (await supabase.auth.getSession()).data.session;
        if (!sess) return;
        var meta = sess.user.user_metadata;
        var real = await _resolveTipo(meta, sess);
        var tipo = real.tipo;
        if (tipo === 'PROFISSIONAL') return;
        var idEmp = (typeof AdminEmpresaCtx !== 'undefined')
          ? AdminEmpresaCtx.resolveIdEmp(tipo, meta.ID_EMP || meta.id_emp)
          : (tipo !== 'ADMIN_GLOBAL' ? (meta.ID_EMP || meta.id_emp) : null);
        if (tipo === 'ADMIN_GLOBAL' && !idEmp) return;
        var q = supabase.from('NOTIFICACAO').update({LIDA_NOT:true}).eq('LIDA_NOT',false);
        if (idEmp) q = q.eq('ID_EMP', idEmp);
        await q;
        await _load();
      } catch(e) {}
    },
    open: async function(id, url, isRead) {
      if (!isRead) {
        try { await supabase.from('NOTIFICACAO').update({LIDA_NOT:true}).eq('ID_NOT',id); } catch(e) {}
      }
      if (url) window.location.href = url;
      else await _load();
    },
    create: async function(empId, titulo, corpo, tipo, url) {
      try {
        await supabase.from('NOTIFICACAO').insert({
          ID_EMP: empId, TITULO_NOT: titulo,
          CORPO_NOT: corpo || null, TIPO_NOT: tipo || 'INFO', URL_NOT: url || null
        });
        await _load();
      } catch(e) {}
    },
    reload: _load
  };

  document.addEventListener('click', function(e) {
    var wrap = document.getElementById('notif-wrap');
    if (wrap && !wrap.contains(e.target) && _open) {
      _open = false;
      var drop = document.getElementById('notif-drop');
      if (drop) drop.classList.add('hidden');
    }
  });

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function() { _inject(); setTimeout(_load, 1200); });
  } else {
    _inject(); setTimeout(_load, 400);
  }
  setInterval(_load, 60000);
})();
