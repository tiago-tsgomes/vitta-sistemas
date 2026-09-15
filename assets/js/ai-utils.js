/* VittaAI — Integração multi-provider (Claude, OpenAI, Gemini, Meta/Groq)
 * Requer que window.supabase esteja inicializado (config.js carregado antes).
 */
window.VittaAI = (() => {
  'use strict';

  /* ── Configuração dos provedores ── */
  const PROVIDERS = {
    CLAUDE: {
      name: 'Claude (Anthropic)',
      keyChave: 'CLAUDE_API_KEY',
      keyLabel: 'Chave da API Anthropic',
      keyPlaceholder: 'sk-ant-api03-…',
      keyHint: 'Obtenha sua chave em <strong class="text-violet-500">console.anthropic.com</strong> → API Keys',
      models: [
        { id: 'claude-sonnet-4-6',          label: 'Sonnet 4.6 — Alta capacidade' },
        { id: 'claude-haiku-4-5-20251001',   label: 'Haiku 4.5 — Mais rápido e econômico' }
      ]
    },
    OPENAI: {
      name: 'OpenAI (ChatGPT)',
      keyChave: 'OPENAI_API_KEY',
      keyLabel: 'Chave da API OpenAI',
      keyPlaceholder: 'sk-…',
      keyHint: 'Obtenha sua chave em <strong class="text-violet-500">platform.openai.com</strong> → API Keys',
      models: [
        { id: 'gpt-4o',      label: 'GPT-4o — Alta capacidade' },
        { id: 'gpt-4o-mini', label: 'GPT-4o mini — Mais rápido e econômico' }
      ]
    },
    GEMINI: {
      name: 'Google Gemini',
      keyChave: 'GEMINI_API_KEY',
      keyLabel: 'Chave da API Google AI',
      keyPlaceholder: 'AIzaSy…',
      keyHint: 'Obtenha sua chave em <strong class="text-violet-500">aistudio.google.com</strong> → Get API Key (gratuito)',
      models: [
        { id: 'gemini-1.5-flash',               label: 'Gemini 1.5 Flash — Gratuito (15 req/min)' },
        { id: 'gemini-1.5-pro',                 label: 'Gemini 1.5 Pro — Gratuito (2 req/min)' },
        { id: 'gemini-2.0-flash',               label: 'Gemini 2.0 Flash — Requer billing ativado' }
      ]
    },
    META: {
      name: 'Meta Llama (via Groq)',
      keyChave: 'META_API_KEY',
      keyLabel: 'Chave da API Groq',
      keyPlaceholder: 'gsk_…',
      keyHint: 'Obtenha sua chave em <strong class="text-violet-500">console.groq.com</strong> → API Keys (gratuito)',
      models: [
        { id: 'llama-3.3-70b-versatile', label: 'Llama 3.3 70B — Alta capacidade' },
        { id: 'llama-3.1-8b-instant',    label: 'Llama 3.1 8B — Mais rápido e econômico' }
      ]
    }
  };

  /* ── Gera o resumo via Edge Function (a chave de API nunca chega ao navegador) ── */
  async function complete(context) {
    const { data: { session } } = await window.supabase.auth.getSession();
    if (!session) throw new Error('Sessão expirada. Faça login novamente.');
    const { data, error } = await window.supabase.functions.invoke('ai-completion', {
      body: { context }
    });
    if (error) {
      let msg = error.message || 'Erro ao gerar resumo com IA';
      try { const body = await error.context.json(); if (body?.erro) msg = body.erro; } catch (e) {}
      throw new Error(msg);
    }
    if (!data || data.erro) throw new Error(data?.erro || 'Erro ao gerar resumo com IA');
    return { text: data.text, provider: data.provider };
  }

  /* ── Dispatcher: chama a API correta conforme provedor ── */
  async function callAI(apiKey, prompt, context, provider, model) {
    switch ((provider || 'CLAUDE').toUpperCase()) {
      case 'OPENAI': return _callOpenAI(apiKey, prompt, context, model);
      case 'GEMINI': return _callGemini(apiKey, prompt, context, model);
      case 'META':   return _callGroq(apiKey, prompt, context, model);
      default:       return _callClaude(apiKey, prompt, context, model);
    }
  }

  /* ── Claude (Anthropic) ── */
  async function _callClaude(apiKey, prompt, context, model = 'claude-haiku-4-5-20251001') {
    const resp = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        'anthropic-dangerous-direct-browser-access': 'true'
      },
      body: JSON.stringify({
        model,
        max_tokens: 1200,
        messages: [{ role: 'user', content: `${prompt}\n\n${context}` }]
      })
    });
    if (!resp.ok) {
      let msg = `Erro ${resp.status}`;
      try { const e = await resp.json(); msg = e.error?.message || msg; } catch {}
      throw new Error(msg);
    }
    const data = await resp.json();
    return data.content?.[0]?.text || '';
  }

  /* ── OpenAI ── */
  async function _callOpenAI(apiKey, prompt, context, model = 'gpt-4o-mini') {
    const resp = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${apiKey}` },
      body: JSON.stringify({
        model,
        max_tokens: 1200,
        messages: [{ role: 'user', content: `${prompt}\n\n${context}` }]
      })
    });
    if (!resp.ok) {
      let msg = `Erro ${resp.status}`;
      try { const e = await resp.json(); msg = e.error?.message || msg; } catch {}
      throw new Error(msg);
    }
    const data = await resp.json();
    return data.choices?.[0]?.message?.content || '';
  }

  /* ── Google Gemini ── */
  async function _callGemini(apiKey, prompt, context, model = 'gemini-1.5-flash') {
    // Modelos 1.x usam endpoint v1 (estável e gratuito); 2.x+ usam v1beta
    const apiVer = model.startsWith('gemini-1') ? 'v1' : 'v1beta';
    const resp = await fetch(
      `https://generativelanguage.googleapis.com/${apiVer}/models/${model}:generateContent?key=${apiKey}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          contents: [{ parts: [{ text: `${prompt}\n\n${context}` }] }],
          generationConfig: { maxOutputTokens: 1200 }
        })
      }
    );
    if (!resp.ok) {
      let msg = `Erro ${resp.status}`;
      try { const e = await resp.json(); msg = e.error?.message || msg; } catch {}
      throw new Error(msg);
    }
    const data = await resp.json();
    return data.candidates?.[0]?.content?.parts?.[0]?.text || '';
  }

  /* ── Meta Llama via Groq (API compatível com OpenAI) ── */
  async function _callGroq(apiKey, prompt, context, model = 'llama-3.3-70b-versatile') {
    const resp = await fetch('https://api.groq.com/openai/v1/chat/completions', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${apiKey}` },
      body: JSON.stringify({
        model,
        max_tokens: 1200,
        messages: [{ role: 'user', content: `${prompt}\n\n${context}` }]
      })
    });
    if (!resp.ok) {
      let msg = `Erro ${resp.status}`;
      try { const e = await resp.json(); msg = e.error?.message || msg; } catch {}
      throw new Error(msg);
    }
    const data = await resp.json();
    return data.choices?.[0]?.message?.content || '';
  }

  /* ── Monta o contexto clínico ── */
  function buildContext(pac, consultas, sv, alergias) {
    const age = d => {
      if (!d) return null;
      const b = new Date(d), n = new Date();
      let a = n.getFullYear() - b.getFullYear();
      if (n < new Date(n.getFullYear(), b.getMonth(), b.getDate())) a--;
      return a;
    };
    const fmt = d => {
      if (!d) return '—';
      try { return new Date(String(d).includes('T') ? d : d + 'T12:00').toLocaleDateString('pt-BR'); } catch { return String(d); }
    };

    let c = `PACIENTE:\nNome: ${pac?.NOME_PAC || '—'}\n`;
    c += `Idade: ${age(pac?.DTNASC_PAC) != null ? age(pac.DTNASC_PAC) + ' anos' : 'Não informada'}\n`;
    c += `Sexo: ${pac?.SEXO_PAC === 'M' ? 'Masculino' : pac?.SEXO_PAC === 'F' ? 'Feminino' : 'Não informado'}\n`;
    if (pac?.OBS_PAC) c += `Observações: ${pac.OBS_PAC}\n`;
    c += '\n';

    c += alergias?.length
      ? `ALERGIAS:\n${alergias.map(a => `- ${a.DESCR_ALERGIA} (${a.GRAVIDADE_ALERGIA})`).join('\n')}\n\n`
      : 'ALERGIAS: Nenhuma registrada\n\n';

    if (sv?.length) {
      c += `SINAIS VITAIS (${Math.min(sv.length, 5)} mais recentes):\n`;
      sv.slice(0, 5).forEach(s => {
        const imc = s.PESO_SV && s.ALTURA_SV ? +(s.PESO_SV / ((s.ALTURA_SV / 100) ** 2)).toFixed(1) : null;
        c += `- ${fmt(s.DT_SV)}: Peso ${s.PESO_SV || '—'}kg | Alt ${s.ALTURA_SV || '—'}cm | IMC ${imc || '—'} | PA ${s.PA_SIST_SV && s.PA_DIAST_SV ? `${s.PA_SIST_SV}/${s.PA_DIAST_SV}` : '—'} | FC ${s.FC_SV || '—'}bpm | SpO₂ ${s.SPO2_SV || '—'}%\n`;
      });
      c += '\n';
    } else {
      c += 'SINAIS VITAIS: Nenhum registrado\n\n';
    }

    if (consultas?.length) {
      c += `HISTÓRICO — ${consultas.length} consulta${consultas.length !== 1 ? 's' : ''} (mais recentes primeiro):\n\n`;
      consultas.slice(0, 15).forEach((q, i) => {
        c += `Consulta ${i + 1} (${fmt(q.DT_CONS)}${q.PROFISSIONAL?.NOME_PROF ? ` — ${q.PROFISSIONAL.NOME_PROF}` : ''})\n`;
        if (q.CID_CONS) c += `CID: ${q.CID_CONS}\n`;
        if (q.ANAMNESE) c += `Desc: ${q.ANAMNESE.slice(0, 600)}${q.ANAMNESE.length > 600 ? '…' : ''}\n`;
        if (q.HIPOTESE_DIAG) c += `Hipótese: ${q.HIPOTESE_DIAG}\n`;
        if (q.RECEITAS?.length) q.RECEITAS.forEach(r => { if (r.CONTEUDO) c += `Prescrição: ${r.CONTEUDO}\n`; });
        c += '\n';
      });
    } else {
      c += 'HISTÓRICO: Nenhuma consulta registrada\n\n';
    }
    return c;
  }

  /* ── Renderiza resposta da IA em HTML estilizado ── */
  function renderText(text) {
    const esc  = s => (s || '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    const bold = s => esc(s).replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>').replace(/---+/g, '');
    const clean = text.replace(/(\|[^\n]*)\n\n+(?=[ \t]*\|)/g, '$1\n');
    const SECS = [
      { s: '📋', col: 'text-violet-600',  wrap: '',   thead: 'bg-violet-50/60' },
      { s: '💊', col: 'text-blue-600',    wrap: '',   thead: 'bg-blue-50/60' },
      { s: '📊', col: 'text-emerald-600', wrap: '',   thead: 'bg-emerald-50/70' },
      { s: '⚠',  col: 'text-amber-600',   wrap: 'bg-amber-50 border border-amber-100 rounded-xl px-3.5 py-2.5', thead: 'bg-amber-50' }
    ];
    const TITLE_ICON = `<svg class="w-4 h-4 text-blue-500" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.8"><path d="M9 5H7a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V7a2 2 0 0 0-2-2h-2"/><rect x="9" y="3" width="6" height="4" rx="1.5"/><line x1="9" y1="12" x2="15" y2="12"/><line x1="9" y1="16" x2="13" y2="16"/></svg>`;

    function mdTable(raw, theadBg = 'bg-gray-50') {
      const lines = raw.split('\n').map(l => l.trim()).filter(l => l.startsWith('|'));
      if (lines.length < 2) return null;
      const isSep = l => /^\|[\s\-:|]+\|$/.test(l) || /^\|+$/.test(l);
      const parseRow = l => l.split('|').slice(1, -1).map(c => c.trim());
      const dataLines = lines.filter(l => !isSep(l));
      if (dataLines.length < 1) return null;
      const headers = parseRow(dataLines[0]);
      const rows = dataLines.slice(1).map(parseRow);
      return `<div class="mt-2 rounded-xl border border-gray-200 overflow-hidden shadow-sm"><table class="w-full"><thead><tr class="${theadBg} border-b border-gray-200">${headers.map((h,i) => `<th class="px-3 py-2.5 text-[0.65rem] font-bold text-gray-500 uppercase tracking-wide whitespace-nowrap ${i===0?'text-left':'text-center'}">${bold(h)}</th>`).join('')}</tr></thead><tbody class="divide-y divide-gray-100">${rows.map(row => `<tr class="hover:bg-gray-50/60 transition-colors">${row.map((cell,ci) => `<td class="px-3 py-2.5 text-[0.78rem] ${ci===0?'font-semibold text-gray-700 text-left':'text-gray-600 text-center'}">${bold(cell)}</td>`).join('')}</tr>`).join('')}</tbody></table></div>`;
    }

    function renderBody(bodyText, theadBg) {
      if (!bodyText.trim()) return '';
      if (!bodyText.includes('|')) return `<p class="text-[0.78rem] text-gray-700 leading-relaxed whitespace-pre-line">${bold(bodyText)}</p>`;
      const lines = bodyText.split('\n');
      const segs = []; let textBuf = [], tableBuf = [];
      for (const line of lines) {
        if (line.trim().startsWith('|')) { if (textBuf.length) { segs.push({t:'text',c:textBuf.join('\n').trim()}); textBuf=[]; } tableBuf.push(line); }
        else { if (tableBuf.length) { segs.push({t:'table',c:tableBuf.join('\n')}); tableBuf=[]; } textBuf.push(line); }
      }
      if (tableBuf.length) segs.push({t:'table',c:tableBuf.join('\n')});
      if (textBuf.length && textBuf.join('').trim()) segs.push({t:'text',c:textBuf.join('\n').trim()});
      return segs.map(seg => seg.t==='table' ? (mdTable(seg.c,theadBg)||`<p class="text-[0.78rem] text-gray-700 whitespace-pre-line">${bold(seg.c)}</p>`) : (seg.c?`<p class="text-[0.78rem] text-gray-700 leading-relaxed whitespace-pre-line">${bold(seg.c)}</p>`:'')).join('');
    }

    return clean.split(/\n{2,}/).map(para => {
      const t = para.trim();
      if (!t || /^-{3,}$/.test(t)) return '';
      const lines = t.split('\n'), firstLine = lines[0];
      const h1 = firstLine.match(/^#\s+(.+)$/);
      if (h1) return `<div class="flex items-center gap-2.5 pb-3 mb-1 border-b border-gray-100"><div class="w-7 h-7 rounded-lg bg-blue-50 border border-blue-100 flex items-center justify-center shrink-0">${TITLE_ICON}</div><p class="text-[0.88rem] font-bold text-gray-700 leading-snug">${esc(h1[1].trim())}</p></div>`;
      const rawH = firstLine.replace(/^#{1,4}\s*/, '').trim();
      const sec  = SECS.find(s => rawH.startsWith(s.s));
      if (sec) { const body = lines.slice(1).join('\n').trim(); return `<div class="${sec.wrap}"><p class="text-[0.65rem] font-bold uppercase tracking-wide mb-1.5 ${sec.col}">${esc(rawH)}</p>${renderBody(body,sec.thead)}</div>`; }
      return `<div>${renderBody(t,'bg-gray-50')}</div>`;
    }).filter(Boolean).join('');
  }

  return { PROVIDERS, complete, callAI, buildContext, renderText };
})();
