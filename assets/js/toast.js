// Toast padronizado do sistema — substitui as implementações locais de showToast()
// que existiam duplicadas em cada página.
(function () {
  const ICONS = {
    success: '<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5 shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"/></svg>',
    error: '<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5 shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="9"/><line x1="15" y1="9" x2="9" y2="15"/><line x1="9" y1="9" x2="15" y2="15"/></svg>',
    warning: '<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5 shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M12 9v4m0 4h.01M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z"/></svg>',
    info: '<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5 shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="9"/><line x1="12" y1="16" x2="12" y2="11"/><line x1="12" y1="8" x2="12.01" y2="8"/></svg>',
  };
  const COLORS = {
    success: 'bg-emerald-500',
    error: 'bg-red-500',
    warning: 'bg-amber-500',
    info: 'bg-vitta-600',
  };

  let hideTimer = null;

  function ensureEl() {
    let el = document.getElementById('vt-toast');
    if (el) return el;
    el = document.createElement('div');
    el.id = 'vt-toast';
    el.className = 'fixed bottom-6 right-6 z-[999] hidden';
    el.innerHTML =
      '<div id="vt-toast-inner" class="flex items-center gap-3 px-4 py-3 rounded-xl shadow-lg text-sm font-semibold text-white min-w-[260px] max-w-[360px] opacity-0 translate-y-2 transition-all duration-200">' +
        '<span id="vt-toast-icon" class="shrink-0 inline-flex"></span>' +
        '<span id="vt-toast-msg" class="leading-snug"></span>' +
      '</div>';
    document.body.appendChild(el);
    return el;
  }

  window.showToast = function (msg, type) {
    if (!ICONS[type]) type = 'success';
    const el = ensureEl();
    const inner = document.getElementById('vt-toast-inner');
    inner.className = `flex items-center gap-3 px-4 py-3 rounded-xl shadow-lg text-sm font-semibold text-white min-w-[260px] max-w-[360px] transition-all duration-200 ${COLORS[type]}`;
    document.getElementById('vt-toast-icon').innerHTML = ICONS[type];
    document.getElementById('vt-toast-msg').textContent = msg;

    el.classList.remove('hidden');
    requestAnimationFrame(() => inner.classList.remove('opacity-0', 'translate-y-2'));

    clearTimeout(hideTimer);
    hideTimer = setTimeout(() => {
      inner.classList.add('opacity-0', 'translate-y-2');
      setTimeout(() => el.classList.add('hidden'), 200);
    }, 3500);
  };
})();
