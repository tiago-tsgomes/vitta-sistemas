// ===== DARK MODE =====
const DARK_KEY = 'vitta_dark_mode';

function initDarkMode() {
  if (localStorage.getItem(DARK_KEY) === '1') document.documentElement.classList.add('dark');
}

function toggleDarkMode() {
  const isDark = document.documentElement.classList.toggle('dark');
  localStorage.setItem(DARK_KEY, isDark ? '1' : '0');
  _updateDarkIcon(isDark);
  return isDark;
}

function _updateDarkIcon(isDark) {
  const btn = document.getElementById('btn-dark-toggle');
  if (!btn) return;
  btn.innerHTML = isDark
    ? `<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="5"/><line x1="12" y1="1" x2="12" y2="3"/><line x1="12" y1="21" x2="12" y2="23"/><line x1="4.22" y1="4.22" x2="5.64" y2="5.64"/><line x1="18.36" y1="18.36" x2="19.78" y2="19.78"/><line x1="1" y1="12" x2="3" y2="12"/><line x1="21" y1="12" x2="23" y2="12"/><line x1="4.22" y1="19.78" x2="5.64" y2="18.36"/><line x1="18.36" y1="5.64" x2="19.78" y2="4.22"/></svg>`
    : `<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/></svg>`;
}

function setupDarkToggle() {
  const btn = document.getElementById('btn-dark-toggle');
  if (!btn) return;
  const isDark = document.documentElement.classList.contains('dark');
  _updateDarkIcon(isDark);
  btn.addEventListener('click', toggleDarkMode);
}

initDarkMode();

// ===== PULL TO REFRESH =====
function initPullToRefresh(onRefresh) {
  let startY = 0, dragging = false, refreshing = false;

  const ind = document.createElement('div');
  ind.id = 'ptr-bar';
  ind.style.cssText = 'position:fixed;top:0;left:0;right:0;z-index:200;display:flex;align-items:center;justify-content:center;gap:8px;padding:14px;transform:translateY(-100%);transition:transform .25s ease,opacity .25s ease;opacity:0;pointer-events:none;';
  ind.innerHTML = `<svg id="ptr-icon" class="w-5 h-5 text-vitta-500" style="color:#2ABCD4;transition:transform .2s" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2.5"><polyline points="1 4 1 10 7 10"/><path d="M3.51 15a9 9 0 1 0 .49-3.5"/></svg><span id="ptr-txt" style="font-size:.82rem;font-weight:600;color:#2ABCD4">Puxe para atualizar</span>`;
  document.body.appendChild(ind);

  document.addEventListener('touchstart', e => {
    if (window.scrollY > 2 || refreshing) return;
    startY = e.touches[0].clientY; dragging = true;
  }, { passive: true });

  document.addEventListener('touchmove', e => {
    if (!dragging || refreshing) return;
    const dy = e.touches[0].clientY - startY;
    if (dy <= 0) { ind.style.opacity = '0'; return; }
    const p = Math.min(dy / 70, 1);
    ind.style.transform = `translateY(${Math.min(dy * 0.5, 56) - 60}px)`;
    ind.style.opacity = String(p);
    document.getElementById('ptr-icon').style.transform = `rotate(${p * 180}deg)`;
    document.getElementById('ptr-txt').textContent = p >= 1 ? 'Solte para atualizar' : 'Puxe para atualizar';
  }, { passive: true });

  document.addEventListener('touchend', async e => {
    if (!dragging || refreshing) return;
    dragging = false;
    const dy = e.changedTouches[0].clientY - startY;
    if (dy >= 70) {
      refreshing = true;
      ind.style.transform = 'translateY(0)';
      ind.style.opacity = '1';
      document.getElementById('ptr-txt').textContent = 'Atualizando…';
      const icon = document.getElementById('ptr-icon');
      icon.style.animation = 'spin 1s linear infinite';
      icon.style.cssText += ';animation:spin 1s linear infinite;';
      const styleEl = document.getElementById('ptr-spin-style') || document.createElement('style');
      styleEl.id = 'ptr-spin-style';
      styleEl.textContent = '@keyframes spin{to{transform:rotate(360deg)}}';
      document.head.appendChild(styleEl);
      try { await onRefresh(); } catch(e) {}
      refreshing = false;
      icon.style.animation = '';
    }
    ind.style.transform = 'translateY(-100%)';
    ind.style.opacity = '0';
  }, { passive: true });
}

// ===== SKELETON =====
function skeletonCards(n = 4, rounded = '2xl') {
  return Array.from({ length: n }, (_, i) => `
    <div class="flex items-center gap-3 bg-white rounded-${rounded} border border-gray-100 shadow-sm p-4 mb-2" style="animation-delay:${i*0.06}s">
      <div class="w-11 h-11 rounded-2xl bg-gray-200 shrink-0" style="animation:pulse 1.5s ease-in-out infinite alternate;background:linear-gradient(90deg,#e5e7eb 25%,#f3f4f6 50%,#e5e7eb 75%);background-size:200% 100%"></div>
      <div class="flex-1 space-y-2">
        <div class="h-3.5 rounded-full w-3/4" style="animation:pulse 1.5s ease-in-out infinite alternate;background:linear-gradient(90deg,#e5e7eb 25%,#f3f4f6 50%,#e5e7eb 75%);background-size:200% 100%"></div>
        <div class="h-3 rounded-full w-1/2" style="animation:pulse 1.5s ease-in-out ${i*0.1}s infinite alternate;background:linear-gradient(90deg,#e5e7eb 25%,#f3f4f6 50%,#e5e7eb 75%);background-size:200% 100%"></div>
      </div>
    </div>`).join('');
}

// ===== ABRIR LINK EXTERNO (Google Meet, etc.) =====
async function abrirLinkExterno(url) {
  if (!url) return;
  try {
    const Browser = typeof Capacitor !== 'undefined' && Capacitor.Plugins.Browser;
    if (Browser) { await Browser.open({ url }); return; }
  } catch (e) {}
  window.open(url, '_blank');
}

// ===== LOCAL NOTIFICATIONS =====
async function scheduleAppointmentNotifications(agendamentos) {
  if (typeof Capacitor === 'undefined') return;
  const LN = Capacitor.Plugins.LocalNotifications;
  if (!LN) return;
  try {
    const perm = await LN.requestPermissions();
    if (perm.display !== 'granted') return;
    await LN.cancel({ notifications: Array.from({ length: 50 }, (_, i) => ({ id: i + 1 })) });
    const now = Date.now();
    const notifs = agendamentos
      .filter(a => a.STATUS_AGD === 'CONFIRMADA' || a.STATUS_AGD === 'AGENDADO')
      .map((a, i) => {
        const dt = new Date(a.DT_AGD).getTime() - 15 * 60 * 1000;
        if (dt <= now) return null;
        const pac = a.PACIENTE || {};
        return {
          id: i + 1,
          title: '📅 Consulta em 15 minutos',
          body: pac.NOME_PAC || 'Paciente',
          schedule: { at: new Date(dt) },
          sound: 'default',
          smallIcon: 'ic_launcher',
        };
      })
      .filter(Boolean);
    if (notifs.length) await LN.schedule({ notifications: notifs });
  } catch(e) {}
}
