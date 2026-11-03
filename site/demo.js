/* Interactive demo of the Vital panel. Every figure is simulated: a web page cannot read your Mac. */
(function () {
  function mount(root, startTab, resetButton) {

  var TOTAL_GB = 16, SYSTEM_MEM = 2.6, SYSTEM_CPU = 4, CORES = 8;
  var SEED = [
    { id: 'dia',    name: 'Dia',               n: 30, cpu: 6.0,  mem: 3.9, w: 0.9, hue: '#f2c24c', kinds: [['Dia Helper (Renderer)', 22, .7], ['Dia', 1, .15], ['Dia Helper (GPU)', 1, .1], ['Other helpers', 6, .05]] },
    { id: 'chrome', name: 'Google Chrome',     n: 96, cpu: 4.0,  mem: 2.2, w: 1.4, hue: '#7aa7ff', kinds: [['Google Chrome Helper (Renderer)', 71, .72], ['Google Chrome', 1, .12], ['Google Chrome Helper (GPU)', 1, .1], ['Other helpers', 23, .06]] },
    { id: 'xcode',  name: 'Xcode',             n: 7,  cpu: 21.0, mem: 1.2, w: 2.6, hue: '#4aa3ff', kinds: [['SourceKitService', 1, .45], ['Xcode', 1, .3], ['swift-frontend', 3, .2], ['Other', 2, .05]] },
    { id: 'slack',  name: 'Slack',             n: 13, cpu: 1.2,  mem: 0.8, w: 0.4, hue: '#c07bff', kinds: [['Slack Helper (Renderer)', 6, .6], ['Slack', 1, .25], ['Other helpers', 6, .15]] },
    { id: 'zoom',   name: 'Zoom',              n: 8,  cpu: 7.0,  mem: 0.6, w: 1.8, hue: '#5b8dff', kinds: [['zoom.us', 1, .6], ['CptHost', 1, .25], ['Other', 6, .15]] },
    { id: 'figma',  name: 'Figma',             n: 14, cpu: 2.0,  mem: 0.7, w: 0.7, hue: '#ff7262', kinds: [['Figma Helper (Renderer)', 8, .65], ['Figma', 1, .25], ['Other helpers', 5, .1]] },
    { id: 'terminal',   name: 'Terminal',          n: 12, cpu: 0.8,  mem: 0.3, w: 0.1, hue: '#9aa0a6', kinds: [['zsh', 6, .3], ['node', 4, .55], ['Terminal', 1, .15]] },
    { id: 'finder', name: 'Finder',            n: 2,  cpu: 0.5,  mem: 0.28, w: 0.1, hue: '#4aa3ff', protectedApp: true, kinds: [['Finder', 1, .9], ['Finder Extension', 1, .1]] }
  ];
  var FOLDERS = [['Applications', 38.2], ['Developer', 61.5], ['Library caches', 31.4], ['Documents and Desktop', 27.9], ['Photos', 22.6]];
  var TABS = ['CPU', 'Memory', 'Storage', 'Heat'];

  var state, timer;
  var OVERVIEW = [['CPU', 'In use'], ['Memory', null], ['Disk', null], ['Heat', null]];
  function seedHist() {
    var h = { CPU: [], Memory: [], Disk: [], Heat: [] }, v = { CPU: 40, Memory: 78, Disk: 25, Heat: 48 };
    for (var i = 0; i < 60; i++) Object.keys(h).forEach(function (k) {
      v[k] = Math.max(2, Math.min(98, v[k] + (Math.random() - .5) * (k === 'Memory' ? 1.2 : 9))); h[k].push(v[k]);
    });
    return h;
  }
  function fresh() {
    state = { tab: 'Memory', open: null, apps: JSON.parse(JSON.stringify(SEED)).map(function (a) { a.base = { cpu: a.cpu, mem: a.mem, w: a.w }; return a; }), pending: null, toast: '', fan: { manual: false, rpm: 3600 }, showAll: false, hist: seedHist() };
  }
  fresh();
  if (startTab) state.tab = startTab;

  /* ---------- derived figures ---------- */
  function sum(key) { return state.apps.reduce(function (t, a) { return t + a[key]; }, 0); }
  function cpuTotal() { return Math.min(99, sum('cpu') + SYSTEM_CPU); }
  function memUsed() { return Math.min(TOTAL_GB, sum('mem') + SYSTEM_MEM); }
  function memPct() { return memUsed() / TOTAL_GB * 100; }
  function temp() { return 36 + cpuTotal() * 0.32 - (state.fan.manual ? (state.fan.rpm - 2300) / 4500 * 9 : 0); }
  var STORAGE_USED = 94.0;
  function heatWord() { var t = temp(); return t >= 62 ? 'Hot' : (t >= 50 ? 'Warm' : 'Normal'); }

  function level(kind) {
    if (kind === 'CPU') { var c = cpuTotal(); return c >= 75 ? 2 : (c >= 45 ? 1 : 0); }
    if (kind === 'Memory') { var m = memPct(); return m >= 92 ? 2 : (m >= 75 ? 1 : 0); }
    if (kind === 'Storage') return STORAGE_USED >= 95 ? 2 : (STORAGE_USED >= 90 ? 1 : 0);
    var t = temp(); return t >= 62 ? 2 : (t >= 50 ? 1 : 0);
  }
  function value(kind) {
    if (kind === 'CPU') return Math.round(cpuTotal()) + '%';
    if (kind === 'Memory') return Math.round(memPct()) + '%';
    if (kind === 'Storage') return Math.round(STORAGE_USED) + '%';
    return Math.round(temp()) + '°';
  }
  function fraction(kind) {
    if (kind === 'CPU') return cpuTotal() / 100;
    if (kind === 'Memory') return memPct() / 100;
    if (kind === 'Storage') return STORAGE_USED / 100;
    return Math.min(1, (temp() - 30) / 60);
  }
  function metric(a) { return state.tab === 'CPU' ? a.cpu : (state.tab === 'Memory' ? a.mem : a.w); }
  function ranked() { return state.apps.slice().sort(function (x, y) { return metric(y) - metric(x); }); }
  function top() { return ranked().filter(function (a) { return !a.protectedApp; })[0]; }
  function fmtMetric(a) {
    if (state.tab === 'CPU') return Math.round(a.cpu / CORES * 100 * 10) / 10 < 0.5 ? '<1%' : Math.round(a.cpu) + '%';
    if (state.tab === 'Memory') return a.mem >= 1 ? a.mem.toFixed(1) + ' GB' : Math.round(a.mem * 1024) + ' MB';
    return a.w.toFixed(1) + ' W';
  }
  function fmtKind(a, k) {
    var share = k[2];
    if (state.tab === 'CPU') return Math.max(0, Math.round(a.cpu * share)) + '%';
    if (state.tab === 'Memory') { var g = a.mem * share; return g >= 1 ? g.toFixed(1) + ' GB' : Math.round(g * 1024) + ' MB'; }
    return (a.w * share).toFixed(1) + ' W';
  }
  function banner() {
    var kind = state.tab, lv = kind === 'Overview' ? 0 : level(kind), t = top();
    if (lv === 0) return null;
    if (kind === 'Storage') return { lv: lv, title: 'Storage is almost full', detail: 'Free up space in the folders below.', quit: null };
    var titles = { CPU: 'CPU is busy', Memory: 'Memory is getting full', Heat: 'Your Mac is running warm' };
    var who = t ? t.name + (kind === 'Heat' ? ' is drawing the most power.' : ' is using the most.') : '';
    return { lv: lv, title: titles[kind], detail: who, quit: t && state.tab !== 'Heat' ? t : (t || null) };
  }

  /* ---------- overview page ---------- */
  function spark(k) {
    var a = state.hist[k], lo = Math.min.apply(null, a), hi = Math.max.apply(null, a), span = Math.max(k === 'Memory' ? 6 : 20, hi - lo);
    return a.map(function (v, i) { return (i ? 'L' : 'M') + (i / (a.length - 1) * 100).toFixed(1) + ' ' + (30 - (v - lo) / span * 26 - 2).toFixed(1); }).join('');
  }
  function ovValue(k) { return k === 'Disk' ? (state.apps.reduce(function (t, a) { return t + a.w; }, 0) * 3.1).toFixed(1) + ' MB/s' : value(k); }
  function ovCaption(k) {
    if (k === 'CPU') return 'In use';
    if (k === 'Memory') return memUsed().toFixed(1) + ' GB of ' + TOTAL_GB + ' GB';
    if (k === 'Disk') return '<span style="color:#4aa3ff">●</span> read &nbsp;<span style="color:#ff9f0a">●</span> write';
    return heatWord();
  }
  function overview() {
    return '<div class="d-grid">' + OVERVIEW.map(function (o) {
      var k = o[0], lv = k === 'Disk' ? 0 : level(k);
      return '<button type="button" class="d-oc" data-act="tab" data-k="' + (k === 'Disk' ? 'Storage' : k) + '" data-f="oc-' + k + '"><span class="d-ot">' + k + '</span><span class="d-ov l' + lv + '" data-ov="' + k + '">' + ovValue(k) + '</span><small data-oc="' + k + '">' + ovCaption(k) + '</small>' +
        '<svg class="d-spark l' + lv + '" data-sp="' + k + '" viewBox="0 0 100 30" preserveAspectRatio="none" aria-hidden="true"><path d="' + spark(k) + '"/></svg></button>';
    }).join('') + '</div><div class="d-card">' +
      '<button type="button" class="d-thin" data-act="tab" data-k="Storage" data-f="thin-s"><span>Storage</span><span>' + Math.round(STORAGE_USED) + '% · ' + (494 * (1 - STORAGE_USED / 100)).toFixed(1) + ' GB free</span></button>' +
      '<div class="d-thin"><span>Network</span><span>↓ 1.4 MB/s &nbsp;↑ 82 KB/s</span></div>' +
      '<div class="d-thin"><span>Battery</span><span>87% · On battery</span></div></div>';
  }
  function foot() {
    var on = state.tab === 'Overview';
    return '<div class="d-foot"><button type="button" class="d-ovbtn" data-act="overview" data-f="overview" aria-pressed="' + on + '"><svg width="13" height="13" viewBox="0 0 14 14" fill="' + (on ? 'currentColor' : 'none') + '" stroke="currentColor" stroke-width="1.4"><rect x="1.5" y="1.5" width="4.5" height="4.5" rx="1.2"/><rect x="8" y="1.5" width="4.5" height="4.5" rx="1.2"/><rect x="1.5" y="8" width="4.5" height="4.5" rx="1.2"/><rect x="8" y="8" width="4.5" height="4.5" rx="1.2"/></svg>' + (on ? 'Back to apps' : 'Overview') + '</button></div>';
  }

  /* ---------- rendering ---------- */
  function esc(s) { return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;'); }
  function tile(a) { return '<svg class="d-ic" viewBox="0 0 64 64" aria-hidden="true"><use href="icons.svg#' + a.id + '"/></svg>'; }

  function tabs() {
    return '<div class="d-tabs" role="tablist" aria-label="Vitals">' + TABS.map(function (k) {
      var sel = k === state.tab, lv = level(k);
      return '<button type="button" role="tab" aria-selected="' + sel + '" class="d-tab' + (sel ? ' on' : '') + '" data-act="tab" data-k="' + k + '" data-f="tab-' + k + '">' +
        '<span class="d-tl">' + k + '</span><span class="d-tv l' + lv + '" data-k="' + k + '">' + value(k) + '</span>' +
        '<span class="d-m"><i class="l' + lv + '" data-k="' + k + '" style="width:' + Math.max(4, Math.round(fraction(k) * 100)) + '%"></i></span></button>';
    }).join('') + '</div>';
  }

  function bannerHtml() {
    var b = banner();
    if (!b) return '';
    var btn = (b.quit && state.tab !== 'Heat') ? '<button type="button" class="d-pill red" data-act="ask" data-id="' + b.quit.id + '" data-kind="quit" data-f="banner-quit">Quit ' + esc(b.quit.name) + '</button>' : '';
    return '<div class="d-banner l' + b.lv + '"><span class="d-dot"></span><div><b>' + esc(b.title) + '</b><span>' + esc(b.detail) + '</span></div>' + btn + '</div>';
  }

  function row(a) {
    var open = state.open === a.id;
    var h = '<div class="d-row"><button type="button" class="d-head" data-act="open" data-id="' + a.id + '" data-f="row-' + a.id + '" aria-expanded="' + open + '">' + tile(a) +
      '<span class="d-name">' + esc(a.name) + (a.n > 1 ? '<em>' + a.n + ' processes</em>' : '') + '</span>' +
      '<span class="d-val" data-id="' + a.id + '">' + fmtMetric(a) + '</span><span class="d-chev' + (open ? ' on' : '') + '" aria-hidden="true"></span></button>';
    if (open) {
      h += '<div class="d-more">' + a.kinds.map(function (k, i) {
        return '<div><span>' + esc(k[0]) + (k[1] > 1 ? ' <em>×' + k[1] + '</em>' : '') + '</span><span class="d-kv" data-id="' + a.id + '" data-i="' + i + '">' + fmtKind(a, k) + '</span></div>';
      }).join('');
      h += a.protectedApp ? '<p class="d-lock">Protected: Vital will not quit this</p>' :
        '<div class="d-actions"><button type="button" class="d-pill" data-act="ask" data-id="' + a.id + '" data-kind="quit" data-f="ask-' + a.id + '-quit">Quit</button>' +
        '<button type="button" class="d-pill red" data-act="ask" data-id="' + a.id + '" data-kind="force" data-f="ask-' + a.id + '-force">Force Quit</button></div>';
      h += '</div>';
    }
    return h + '</div>';
  }

  function appList() {
    var list = ranked(), shown = state.showAll ? list : list.slice(0, 5);
    return '<div class="d-card">' + shown.map(row).join('') +
      (list.length > 5 ? '<button type="button" class="d-less" data-act="all" data-f="all">' + (state.showAll ? 'Show fewer' : 'Show more') + '</button>' : '') + '</div>';
  }

  function fanCard() {
    var f = state.fan;
    return '<div class="d-card d-fan"><div class="d-fanrow"><svg width="24" height="24" viewBox="0 0 24 24" aria-hidden="true"><g fill="currentColor"><ellipse cx="12" cy="6.6" rx="2.7" ry="4.4"/><ellipse cx="12" cy="6.6" rx="2.7" ry="4.4" transform="rotate(120 12 12)"/><ellipse cx="12" cy="6.6" rx="2.7" ry="4.4" transform="rotate(240 12 12)"/></g><circle cx="12" cy="12" r="2" fill="#1a1a1c"/></svg>' +
      '<div class="d-fn"><b>Fan</b><span>' + (f.manual ? 'Manual · ' + f.rpm.toLocaleString('en-US') + ' rpm' : 'Idle · Automatic') + '</span></div>' +
      '<button type="button" class="d-switch' + (f.manual ? ' on' : '') + '" role="switch" aria-checked="' + f.manual + '" aria-label="Manual fan speed" data-act="fan" data-f="fan"><i></i></button></div>' +
      (f.manual ? '<div class="d-slide"><span>2,300</span><input type="range" min="2300" max="6800" step="100" value="' + f.rpm + '" aria-label="Fan speed in rpm" data-act="rpm" data-f="rpm"><span>6,800</span></div>' : '') + '</div>';
  }

  function storage() {
    var used = 494 * STORAGE_USED / 100;
    return '<div class="d-card d-store"><div class="d-sh"><b>Mac storage</b><span>494 GB total</span></div><div class="d-big">' + (494 - used).toFixed(1) + ' GB <small>available</small></div>' +
      '<div class="d-m wide"><i class="l' + level('Storage') + '" style="width:' + STORAGE_USED + '%"></i></div></div>' +
      '<p class="d-cap">Folders on this Mac</p><div class="d-card">' + FOLDERS.map(function (f) {
        return '<div class="d-flat"><span>' + f[0] + '</span><span>' + f[1].toFixed(1) + ' GB</span></div>';
      }).join('') + '</div>';
  }

  function sheet() {
    var p = state.pending;
    if (!p) return '';
    var a = state.apps.filter(function (x) { return x.id === p.id; })[0];
    if (!a) return '';
    var force = p.kind === 'force';
    return '<div class="d-sheet" role="dialog" aria-modal="true" aria-label="' + (force ? 'Force Quit ' : 'Quit ') + esc(a.name) + '"><div class="d-box"><h4>' + (force ? 'Force Quit ' : 'Quit ') + esc(a.name) + '?</h4>' +
      '<p>' + (a.n > 1 ? a.n + ' processes will close. ' : '') + (force ? 'Unsaved work will be lost.' : 'The app can ask you to save first.') + '</p>' +
      '<div class="d-actions"><button type="button" class="d-pill" data-act="cancel">Cancel</button><button type="button" class="d-pill ' + (force ? 'red solid' : 'solid') + '" data-act="confirm">' + (force ? 'Force Quit' : 'Quit') + '</button></div></div></div>';
  }

  var lastSig = '';
  function signature() {
    var b = banner();
    return state.tab + '|' + state.open + '|' + ranked().map(function (a) { return a.id; }).join() + '|' + (b ? b.lv + b.title + b.detail : '');
  }
  function render() {
    var a = document.activeElement, key = a && root.contains(a) ? a.getAttribute('data-f') : null;
    var body = state.tab === 'Overview' ? overview() : state.tab === 'Storage' ? storage() : (state.tab === 'Heat' ? fanCard() : '') + appList();
    root.innerHTML = tabs() + '<div class="d-body">' + (state.tab === 'Overview' ? '' : bannerHtml()) + body + '</div>' + foot() + sheet() + '<div class="d-toast" role="status" aria-live="polite">' + esc(state.toast) + '</div>';
    if (state.pending) { var b = root.querySelector('.d-sheet .solid'); if (b) b.focus(); }
    else if (key) { var again = root.querySelector('[data-f="' + key + '"]'); if (again) again.focus({ preventScroll: true }); }
    lastSig = signature();
  }

  /* Updates the numbers without touching the elements around them, so a click or a drag is never interrupted. */
  function patch() {
    TABS.forEach(function (k) {
      var v = root.querySelector('.d-tv[data-k="' + k + '"]'), m = root.querySelector('.d-m i[data-k="' + k + '"]');
      if (v) { v.textContent = value(k); v.className = 'd-tv l' + level(k); }
      if (m) { m.className = 'l' + level(k); m.style.width = Math.max(4, Math.round(fraction(k) * 100)) + '%'; }
    });
    if (state.tab === 'Overview') OVERVIEW.forEach(function (o) {
      var k = o[0], v = root.querySelector('[data-ov="' + k + '"]'), p = root.querySelector('[data-sp="' + k + '"] path'), c = root.querySelector('[data-oc="' + k + '"]');
      if (v) v.textContent = ovValue(k);
      if (p) p.setAttribute('d', spark(k));
      if (c && k === 'Memory') c.innerHTML = ovCaption(k);
    });
    state.apps.forEach(function (a) {
      var v = root.querySelector('.d-val[data-id="' + a.id + '"]');
      if (v) v.textContent = fmtMetric(a);
      a.kinds.forEach(function (k, i) {
        var kv = root.querySelector('.d-kv[data-id="' + a.id + '"][data-i="' + i + '"]');
        if (kv) kv.textContent = fmtKind(a, k);
      });
    });
  }

  /* ---------- actions ---------- */
  var toastTimer;
  function toast(text) { state.toast = text; clearTimeout(toastTimer); toastTimer = setTimeout(function () { state.toast = ''; render(); }, 3200); }

  root.addEventListener('click', function (e) {
    var el = e.target.closest('[data-act]');
    if (!el) return;
    var act = el.getAttribute('data-act'), id = el.getAttribute('data-id');
    if (act === 'overview') { state.tab = state.tab === 'Overview' ? (state.last || 'Memory') : 'Overview'; state.open = null; state.showAll = false; }
    else if (act === 'tab') { state.tab = el.getAttribute('data-k'); state.last = state.tab; state.open = null; state.showAll = false; }
    else if (act === 'open') { state.open = state.open === id ? null : id; }
    else if (act === 'all') { state.showAll = !state.showAll; }
    else if (act === 'ask') { state.pending = { id: id, kind: el.getAttribute('data-kind') }; }
    else if (act === 'cancel') { state.pending = null; }
    else if (act === 'confirm') {
      var p = state.pending, name = '';
      state.apps = state.apps.filter(function (a) { if (a.id === p.id) name = a.name; return a.id !== p.id; });
      state.pending = null; state.open = null;
      toast(name + (p.kind === 'force' ? ' was force quit.' : ' quit.'));
    }
    else if (act === 'fan') { state.fan.manual = !state.fan.manual; toast(state.fan.manual ? 'Manual fan speed on. Automatic returns when you turn it off.' : 'Fan back on Automatic.'); }
    else return;
    render();
  });
  root.addEventListener('input', function (e) {
    if (e.target.getAttribute('data-act') !== 'rpm') return;
    state.fan.rpm = +e.target.value;
    var s = root.querySelector('.d-fn span'); if (s) s.textContent = 'Manual · ' + state.fan.rpm.toLocaleString('en-US') + ' rpm';
    var tv = root.querySelectorAll('.d-tv'); if (tv[3]) tv[3].textContent = value('Heat');
  });
  root.addEventListener('keydown', function (e) { if (e.key === 'Escape' && state.pending) { state.pending = null; render(); } });
  if (resetButton) resetButton.addEventListener('click', function () { var t = state.tab; fresh(); state.tab = t; render(); });

  /* ---------- gentle drift while visible ---------- */
  function drift() {
    var now = { CPU: cpuTotal(), Memory: memPct(), Heat: (temp() - 30) / 60 * 100, Disk: state.hist.Disk[59] };
    now.Disk = Math.max(2, Math.min(98, now.Disk + (Math.random() - .5) * 14));
    Object.keys(now).forEach(function (k) { state.hist[k].push(now[k]); state.hist[k].shift(); });
    state.apps.forEach(function (a) {
      ['cpu', 'w'].forEach(function (k) { a[k] = Math.max(.05, a[k] + (a.base[k] - a[k]) * .25 + a.base[k] * (Math.random() - .5) * .16); });
      a.mem = a.mem + (a.base.mem - a.mem) * .1 + a.base.mem * (Math.random() - .5) * .02;
    });
  }
  var pointerDown = false;
  root.addEventListener('pointerdown', function () { pointerDown = true; });
  document.addEventListener('pointerup', function () { pointerDown = false; });
  document.addEventListener('pointercancel', function () { pointerDown = false; });
  function tick() {
    if (state.pending || pointerDown || (document.activeElement && document.activeElement.type === 'range')) return;
    drift();
    if (signature() !== lastSig) render(); else patch();
  }
  var seen = false;
  if ('IntersectionObserver' in window) {
    new IntersectionObserver(function (es) {
      seen = es[0].isIntersecting;
      clearInterval(timer);
      if (seen) timer = setInterval(tick, 2000);
    }, { threshold: .2 }).observe(root);
  }
  render();
  }

  var main = document.getElementById('demo');
  if (main) {
    var wanted = (location.hash.match(/^#try-(cpu|memory|storage|heat)$/i) || [])[1];
    mount(main, wanted && wanted[0].toUpperCase() + wanted.slice(1).toLowerCase(), document.getElementById('demo-reset'));
  }
  document.querySelectorAll('.demo[data-tab]').forEach(function (el) { mount(el, el.getAttribute('data-tab')); });
})();
