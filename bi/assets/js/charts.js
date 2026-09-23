/* Vitta BI — helpers de gráfico (SVG puro, sem lib externa).
   Cobrem só os 3 tipos usados no dashboard hoje: linha (pacientes),
   barra agrupada (agendamentos) e barra empilhada (faturamento). */
(function () {
  const NS = 'http://www.w3.org/2000/svg';
  const VIEW_W = 1100;
  const PAD_L = 34, PAD_R = 24, PAD_T = 20, PAD_B = 26;

  function svgEl(tag, attrs, text) {
    const e = document.createElementNS(NS, tag);
    for (const k in attrs) e.setAttribute(k, attrs[k]);
    if (text != null) e.textContent = text;
    return e;
  }

  function clear(svg) {
    while (svg.firstChild) svg.removeChild(svg.firstChild);
  }

  let tooltipEl = null;
  function getTooltip() {
    if (!tooltipEl) {
      tooltipEl = document.createElement('div');
      tooltipEl.style.cssText = 'position:fixed;z-index:9999;pointer-events:none;background:#1F2937;color:#fff;font-family:Montserrat,sans-serif;font-size:14px;font-weight:500;padding:10px 12px;border-radius:8px;box-shadow:0 6px 20px rgba(0,0,0,.22);white-space:nowrap;opacity:0;left:0;top:0;';
      document.body.appendChild(tooltipEl);
    }
    return tooltipEl;
  }

  function positionTooltip(tip, ev) {
    const margin = 14;
    const rect = tip.getBoundingClientRect();
    let left = ev.clientX + margin;
    if (left + rect.width + 8 > window.innerWidth) {
      left = ev.clientX - rect.width - margin;
    }
    tip.style.left = Math.max(4, left) + 'px';
    tip.style.top = (ev.clientY - 12) + 'px';
  }

  function attachTooltip(el, text) {
    function move(ev) {
      positionTooltip(getTooltip(), ev);
    }
    el.addEventListener('mouseenter', (ev) => {
      const tip = getTooltip();
      tip.textContent = text;
      tip.style.whiteSpace = 'nowrap';
      tip.style.maxWidth = 'none';
      tip.style.opacity = '1';
      move(ev);
    });
    el.addEventListener('mousemove', move);
    el.addEventListener('mouseleave', () => { getTooltip().style.opacity = '0'; });
  }

  function attachTooltipHTML(el, html, onEnter, onLeave) {
    function move(ev) {
      positionTooltip(getTooltip(), ev);
    }
    el.addEventListener('mouseenter', (ev) => {
      const tip = getTooltip();
      tip.innerHTML = html;
      tip.style.whiteSpace = 'normal';
      tip.style.maxWidth = '220px';
      tip.style.opacity = '1';
      move(ev);
      if (onEnter) onEnter();
    });
    el.addEventListener('mousemove', move);
    el.addEventListener('mouseleave', () => {
      getTooltip().style.opacity = '0';
      if (onLeave) onLeave();
    });
  }

  let gradCounter = 0;

  // curva suave (Catmull-Rom convertida para Bezier cúbica) passando por todos os pontos
  function smoothLinePath(points) {
    if (points.length < 3) {
      return points.map((p, i) => (i === 0 ? 'M' : 'L') + p[0] + ',' + p[1]).join(' ');
    }
    let d = `M${points[0][0]},${points[0][1]}`;
    for (let i = 0; i < points.length - 1; i++) {
      const p0 = points[i === 0 ? i : i - 1];
      const p1 = points[i];
      const p2 = points[i + 1];
      const p3 = points[i + 2 < points.length ? i + 2 : i + 1];
      const cp1x = p1[0] + (p2[0] - p0[0]) / 6;
      const cp1y = p1[1] + (p2[1] - p0[1]) / 6;
      const cp2x = p2[0] - (p3[0] - p1[0]) / 6;
      const cp2y = p2[1] - (p3[1] - p1[1]) / 6;
      d += ` C${cp1x},${cp1y} ${cp2x},${cp2y} ${p2[0]},${p2[1]}`;
    }
    return d;
  }

  function niceMax(v) {
    if (v <= 0) return 10;
    const mag = Math.pow(10, Math.floor(Math.log10(v)));
    const norm = v / mag;
    let step;
    if (norm <= 1) step = 1;
    else if (norm <= 2) step = 2;
    else if (norm <= 5) step = 5;
    else step = 10;
    return step * mag;
  }

  function fmtInt(v) {
    return Math.round(v).toLocaleString('pt-BR');
  }

  function fmtBRLk(v) {
    if (Math.abs(v) >= 1000) {
      const k = v / 1000;
      const s = (Math.round(k * 10) / 10).toString().replace('.', ',');
      return 'R$ ' + s + 'K';
    }
    return 'R$ ' + Math.round(v);
  }

  function drawGrid(svg, height, maxVal, yFmt) {
    const innerH = height - PAD_T - PAD_B;
    [0, 0.5, 1].forEach((f) => {
      const y = PAD_T + innerH * (1 - f);
      svg.appendChild(svgEl('line', { x1: 0, y1: y, x2: VIEW_W, y2: y, stroke: '#EFEEF7', 'stroke-width': 1 }));
      svg.appendChild(svgEl('text', { x: 0, y: y - 5, 'font-size': 12.5, 'font-weight': 500, fill: '#8B87A0', 'font-family': 'Montserrat, sans-serif' }, yFmt(f * maxVal)));
    });
  }

  function renderLegend(container, series) {
    if (!container) return;
    container.innerHTML = series.map((s) => `
      <span style="display:inline-flex;align-items:center;gap:6px;font-size:14.5px;font-weight:500;color:#374151;margin-right:18px;">
        <span style="width:10px;height:10px;border-radius:3px;background:${s.color};display:inline-block;"></span>${s.name}
      </span>
    `).join('');
  }

  function drawLineChart(svg, { labels, series, height = 220, yFmt = fmtInt, tooltipFmt, niceGrid = true, showEndLabels = true, maxPadding = null }) {
    clear(svg);
    svg.setAttribute('viewBox', `0 0 ${VIEW_W} ${height}`);
    svg.setAttribute('preserveAspectRatio', 'none');

    const tFmt = tooltipFmt || yFmt;
    const innerW = VIEW_W - PAD_L - PAD_R;
    const innerH = height - PAD_T - PAD_B;
    const allVals = series.flatMap((s) => s.values);
    const maxVal = maxPadding != null
      ? Math.max(...allVals) * maxPadding
      : (niceGrid ? niceMax(Math.max(...allVals) * 1.15) : Math.max(...allVals) * 1.2);

    drawGrid(svg, height, maxVal, yFmt);

    labels.forEach((label, i) => {
      const x = PAD_L + (innerW * i) / Math.max(labels.length - 1, 1);
      svg.appendChild(svgEl('text', { x, y: height - 6, 'font-size': 12.5, 'font-weight': 500, fill: '#8B87A0', 'text-anchor': 'middle', 'font-family': 'Montserrat, sans-serif' }, label));
    });

    // linha vertical (crosshair) que acompanha o mês sob o mouse
    const crosshair = svgEl('line', { x1: PAD_L, y1: PAD_T, x2: PAD_L, y2: PAD_T + innerH, stroke: '#C4C1D6', 'stroke-width': 1, 'stroke-dasharray': '3,3', style: 'opacity:0;pointer-events:none;' });

    // uma coluna invisível por mês: passar o mouse nela mostra os dados de
    // todas as séries daquele mês de uma vez (a bolinha continua mostrando só
    // o dado dela — as colunas ficam atrás dos pontos no z-order do SVG)
    const colW = labels.length > 1 ? innerW / (labels.length - 1) : innerW;
    labels.forEach((label, i) => {
      const x = PAD_L + (innerW * i) / Math.max(labels.length - 1, 1);
      const rows = series.map((s) => `
        <div style="display:flex;align-items:center;justify-content:space-between;gap:16px;margin-top:5px;">
          <span style="display:flex;align-items:center;gap:6px;font-weight:500;color:#D1D5DB;">
            <span style="width:8px;height:8px;border-radius:2px;background:${s.color};display:inline-block;flex-shrink:0;"></span>
            ${s.name}
          </span>
          <span style="font-weight:600;color:#fff;">${tFmt(s.values[i])}</span>
        </div>
      `).join('');
      const html = `<div style="font-weight:600;font-size:15px;">${label}</div>${rows}`;
      // a área de hover começa perto do ponto mais alto daquele mês, não no
      // topo do gráfico — assim o tooltip só abre dentro da área com dados,
      // não no espaço em branco acima das linhas
      const ys = series.map((s) => PAD_T + innerH * (1 - s.values[i] / maxVal));
      const colTop = Math.max(PAD_T, Math.min(...ys) - 16);
      const col = svgEl('rect', { x: x - colW / 2, y: colTop, width: colW, height: (PAD_T + innerH) - colTop, fill: 'transparent', style: 'pointer-events:all;cursor:pointer;' });
      attachTooltipHTML(col, html,
        () => { crosshair.setAttribute('x1', x); crosshair.setAttribute('x2', x); crosshair.style.opacity = '1'; },
        () => { crosshair.style.opacity = '0'; });
      svg.appendChild(col);
    });
    svg.appendChild(crosshair);

    const endLabels = [];
    series.forEach((s) => {
      const points = s.values.map((v, i) => [
        PAD_L + (innerW * i) / Math.max(labels.length - 1, 1),
        PAD_T + innerH * (1 - v / maxVal),
      ]);
      const d = smoothLinePath(points);

      if (s.area) {
        const gradId = `bi-line-area-grad-${gradCounter++}`;
        let defs = svg.querySelector('defs');
        if (!defs) { defs = svgEl('defs', {}); svg.insertBefore(defs, svg.firstChild); }
        const grad = svgEl('linearGradient', { id: gradId, x1: '0', y1: '0', x2: '0', y2: '1' });
        grad.appendChild(svgEl('stop', { offset: '0%', 'stop-color': s.color, 'stop-opacity': 0.32 }));
        grad.appendChild(svgEl('stop', { offset: '100%', 'stop-color': s.color, 'stop-opacity': 0 }));
        defs.appendChild(grad);
        const areaD = `${d} L${points[points.length - 1][0]},${PAD_T + innerH} L${points[0][0]},${PAD_T + innerH} Z`;
        svg.appendChild(svgEl('path', { d: areaD, fill: `url(#${gradId})`, stroke: 'none', style: 'pointer-events:none;' }));
      }
      svg.appendChild(svgEl('path', { d, fill: 'none', stroke: s.color, 'stroke-width': 2.5, 'stroke-linecap': 'round', 'stroke-linejoin': 'round', style: 'pointer-events:none;' }));
      points.forEach(([x, y], i) => {
        const label = `${s.name} — ${labels[i]}: ${yFmt(s.values[i])}`;
        const dot = svgEl('circle', { cx: x, cy: y, r: 4, fill: s.color });
        svg.appendChild(dot);
        const hit = svgEl('circle', { cx: x, cy: y, r: 11, fill: 'transparent', style: 'cursor:pointer;pointer-events:all;' });
        attachTooltip(hit, label);
        svg.appendChild(hit);
      });

      if (showEndLabels) {
        const [lx, ly] = points[points.length - 1];
        endLabels.push({
          x: lx - 8,
          y: ly - 8,
          anchor: 'end',
          color: s.color,
          text: yFmt(s.values[s.values.length - 1]),
        });
      }
    });

    if (showEndLabels) {
      // evita labels de fim de linha sobrepostas quando as séries terminam com valores próximos
      const minGap = 14;
      endLabels.sort((a, b) => a.y - b.y);
      for (let i = 1; i < endLabels.length; i++) {
        if (endLabels[i].y - endLabels[i - 1].y < minGap) {
          endLabels[i].y = endLabels[i - 1].y + minGap;
        }
      }
      endLabels.forEach((lbl) => {
        svg.appendChild(svgEl('text', { x: lbl.x, y: lbl.y, 'font-size': 12.5, 'font-weight': 600, fill: lbl.color, 'font-family': 'Montserrat, sans-serif', 'text-anchor': lbl.anchor }, lbl.text));
      });
    }
  }

  function drawGroupedBarChart(svg, { labels, series, height = 200, yFmt = fmtInt, maxPadding = null }) {
    clear(svg);
    svg.setAttribute('viewBox', `0 0 ${VIEW_W} ${height}`);
    svg.setAttribute('preserveAspectRatio', 'none');

    const innerW = VIEW_W - PAD_L - PAD_R;
    const innerH = height - PAD_T - PAD_B;
    const allVals = series.flatMap((s) => s.values);
    const maxVal = maxPadding != null ? Math.max(...allVals) * maxPadding : niceMax(Math.max(...allVals) * 1.2);

    drawGrid(svg, height, maxVal, yFmt);

    const groupW = innerW / labels.length;
    const barGap = 6;
    const barW = Math.max((groupW * 0.62 - barGap * (series.length - 1)) / series.length, 4);

    labels.forEach((label, gi) => {
      const groupX = PAD_L + groupW * gi + groupW / 2;
      svg.appendChild(svgEl('text', { x: groupX, y: height - 6, 'font-size': 12.5, 'font-weight': 500, fill: '#8B87A0', 'text-anchor': 'middle', 'font-family': 'Montserrat, sans-serif' }, label));

      const totalW = barW * series.length + barGap * (series.length - 1);
      series.forEach((s, si) => {
        const v = s.values[gi];
        const barH = innerH * (v / maxVal);
        const x = groupX - totalW / 2 + si * (barW + barGap);
        const y = PAD_T + innerH - barH;
        const rect = svgEl('rect', { x, y, width: barW, height: Math.max(barH, 1), rx: 3, fill: s.color, style: 'cursor:pointer;' });
        attachTooltip(rect, `${s.name} — ${label}: ${yFmt(v)}`);
        svg.appendChild(rect);
        svg.appendChild(svgEl('text', { x: x + barW / 2, y: y - 5, 'font-size': 11.5, 'font-weight': 600, fill: '#111827', 'text-anchor': 'middle', 'font-family': 'Montserrat, sans-serif' }, yFmt(v)));
      });
    });
  }

  function drawStackedBarChart(svg, { labels, series, height = 200, yFmt = fmtBRLk, maxPadding = null }) {
    clear(svg);
    svg.setAttribute('viewBox', `0 0 ${VIEW_W} ${height}`);
    svg.setAttribute('preserveAspectRatio', 'none');

    const innerW = VIEW_W - PAD_L - PAD_R;
    const innerH = height - PAD_T - PAD_B;
    const totals = labels.map((_, i) => series.reduce((s, ser) => s + ser.values[i], 0));
    const maxVal = maxPadding != null ? Math.max(...totals) * maxPadding : niceMax(Math.max(...totals) * 1.2);

    drawGrid(svg, height, maxVal, yFmt);

    const groupW = innerW / labels.length;
    const barW = groupW * 0.5;

    labels.forEach((label, gi) => {
      const groupX = PAD_L + groupW * gi + groupW / 2;
      svg.appendChild(svgEl('text', { x: groupX, y: height - 6, 'font-size': 12.5, 'font-weight': 500, fill: '#8B87A0', 'text-anchor': 'middle', 'font-family': 'Montserrat, sans-serif' }, label));

      let yCursor = PAD_T + innerH;
      series.forEach((s) => {
        const v = s.values[gi];
        const segH = innerH * (v / maxVal);
        const y = yCursor - segH;
        const rect = svgEl('rect', { x: groupX - barW / 2, y, width: barW, height: Math.max(segH, 1), rx: 3, fill: s.color, style: 'cursor:pointer;' });
        attachTooltip(rect, `${s.name} — ${label}: ${yFmt(v)}`);
        svg.appendChild(rect);
        yCursor = y;
      });

      svg.appendChild(svgEl('text', { x: groupX, y: yCursor - 6, 'font-size': 12, 'font-weight': 600, fill: '#111827', 'text-anchor': 'middle', 'font-family': 'Montserrat, sans-serif' }, yFmt(totals[gi])));
    });
  }

  window.BICharts = { drawLineChart, drawGroupedBarChart, drawStackedBarChart, renderLegend, fmtInt, fmtBRLk };
})();
