/* Local stand-in for the claude.ai dashboard runtime, so dashboard/index.html runs unchanged as a plain file.
   It provides the part of `dash` the page uses (data, calc, draw, params, setLink, colors) and the design tokens,
   built from fleet/dashboard/look.json; filters start at fleet/dashboard/params.json. fleet/fleet.py inlines this, the data (window.FLEET) and the page into dashboard.html. */
(() => {
  const {look} = window.FLEET;
  let params = {...window.FLEET.params};
  const tokens = (t) => `--color-bg:${t.card};--color-fg:${t.text};--color-fg-muted:${t.muted};--color-border-line:${t.border};
    --color-panel:color-mix(in srgb, ${t.text} 4%, ${t.card});--color-ok:${t.good};--color-warn:${t.warning};--color-bad:${t.bad};
    --cds-chart-grid:color-mix(in srgb, ${t.text} 12%, ${t.card});--fx-ground:${t.ground};`;
  const css = document.createElement('style');
  css.textContent = `
    :root { ${tokens(look.light)} --cds-radius:${look.corners}; --cds-gap-sm:8px; --cds-gap-md:16px; --cds-font-weight-medium:500;
      --cds-font-size-caption:${look.sizes.caption}; --cds-font-size-body:${look.sizes.body}; --cds-font-size-heading:${look.sizes.heading};
      --cds-font-size-title:${look.sizes.title}; --font-anthropic-sans:${look.fonts.text}; --font-anthropic-serif:${look.fonts.display}; color-scheme: light dark; }
    @media (prefers-color-scheme: dark) { :root { ${tokens(look.dark)} } }
    body { margin: 0; background: var(--fx-ground); }
    #dash-root { max-width: 1200px; margin: 0 auto; padding: 24px 16px 48px; }
    .dash-select { font: inherit; font-size: var(--cds-font-size-caption); color: var(--color-fg); background: var(--color-bg);
      border: 1px solid var(--color-border-line); border-radius: 6px; padding: 5px 8px; }`;
  document.head.append(css);

  const datasets = {}, calcs = {}, draws = {}, widths = new WeakMap();
  /* as on claude.ai, a drawing runs again when its element's width changes, opening a hidden tab included */
  const resized = new ResizeObserver((entries) => requestAnimationFrame(() => entries.forEach(({target: e}) => {
    if (widths.get(e) !== e.clientWidth) { widths.set(e, e.clientWidth); draws[e.dataset.draw](e); }
  })));
  for (const id of ['loops', 'waiting']) {
    const d = window.FLEET[id];
    /* as on claude.ai, a cell is a string, number, boolean or null */
    d.rows.forEach((r) => Object.entries(r).forEach(([k, v]) => { if (v !== null && typeof v === 'object') throw new TypeError(`${id}.${k} is not a scalar: ${JSON.stringify(v)}`); }));
    datasets[id] = {status: 'ok', data: d.rows, meta: d.meta, columns: Object.keys(d.rows[0] || {})};
  }
  const rerun = () => { Object.values(calcs).forEach((c) => delete c.value); Object.keys(draws).forEach((n) => window.dash.draw(n)); };
  const dark = matchMedia('(prefers-color-scheme: dark)');
  window.dash = {
    get colors() { return (dark.matches ? look.dark : look.light).charts; },
    data(id) {
      if (datasets[id]) return datasets[id];
      const c = calcs[id];
      if (!c) return {status: 'missing', data: null};
      if (!('value' in c)) c.value = c.fn(...c.inputs.map((i) => this.data(i).data));
      return {status: 'ok', data: c.value};
    },
    calc(id, spec) { calcs[id] = {...spec}; },
    draw(name, fn) {
      if (fn) draws[name] = fn;
      document.querySelectorAll(`[data-draw="${name}"]`).forEach((e) => {
        if (!draws[name]) return;
        draws[name](e); widths.set(e, e.clientWidth); resized.observe(e);
      });
    },
    params() { return {...params}; },
    setParams(v) { params = {...params, ...v}; rerun(); },
    resetParams() { params = {...window.FLEET.params}; rerun(); },
    setLink(name) { history.replaceState(null, '', name ? '#' + name : location.pathname); },
  };
  dark.addEventListener('change', () => location.reload());
})();
