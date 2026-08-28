/* M7350 web-UI mod -- signal stats, modern dark theme, SVG icons, controls ---
 *
 * Loaded from <head> of login.html and settings.html (BEFORE the TP-Link
 * framework scripts). The framework synchronously rebuilds the status DOM from
 * its own templates, which (a) discards any <script> placed later in <body>
 * so it never runs, and (b) wipes static rows added to the HTML. Running from
 * <head> installs setInterval() closures that are not tied to any DOM node, so
 * they survive every rebuild and simply re-apply whatever is missing.
 *
 * Pieces:
 *   - ensureDarkTheme()  inline <style> dark theme (no external <link> needed)
 *   - ensureIcons()      swap the stock CSS-sprite <i class="icon-*"> glyphs
 *                        for inline SVG (sprite glyphs are invisible on dark;
 *                        SVG uses currentColor and looks modern)
 *   - injectSignalRows() live RSRP/RSRQ + Band(EARFCN) rows in the status view
 *   - injectPanels()     post-login only: a "System" card (temp / throughput /
 *                        latency / WAN) and a "Controls" card (Reboot, ADB
 *                        on/off, TTL-fix on/off)
 *
 * Data sources (all cached; a CGI must NEVER read /dev/smd7 directly -- it
 * blocks and kills lighttpd):
 *   /cgi-bin/signal_stats.sh  modem metrics (signal_poll.sh daemon cache)
 *   /cgi-bin/sysinfo.sh       temp / mem / wan / ttl+adb state
 *   /cgi-bin/control.sh       reboot / adb_on|off / ttl_on|off (+ *_status)
 */
(function () {
  'use strict';

  var CGI_SIGNAL = '/cgi-bin/signal_stats.sh';
  var CGI_SYS    = '/cgi-bin/sysinfo.sh';
  var CGI_CTL    = '/cgi-bin/control.sh';

  /* ==================================================================== *
   * Dark theme                                                           *
   * ==================================================================== */
  var DARK_CSS = [
    ':root{--dk-bg:#0f1216;--dk-panel:#171b21;--dk-panel2:#1d232c;--dk-border:#2a313b;--dk-text:#e6edf3;--dk-muted:#9aa4b2;--dk-accent:#38bdf8;--dk-green:#34d399;--dk-red:#f87171;--dk-amber:#fbbf24;}',
    'html,body{background:#0f1216!important;color:#e6edf3!important;}',
    '#content,#loginPage,#loginContainer,#login,#noteDiv,.tabCover,.clearfix{background:transparent!important;}',
    '.container,.statusPage,.section,.section-status,.popup,.help-popup,.panel,.box,[class*="section"],[class*="Section"],[class*="panel"],[class*="-box"],[class*="card"]{background:#171b21!important;color:#e6edf3!important;border-color:#2a313b!important;box-shadow:none!important;background-image:none!important;}',
    '.connectionSection,.wifiSection,.statisticsSection,.dataSection,#statusContent,#statusContent>div{background:#171b21!important;border-color:#2a313b!important;}',
    '.statusPage>div,.statusPage .container,#content .container>div{background:#171b21!important;border-color:#2a313b!important;}',
    /* Bootstrap components used across Advanced/Wizard/SMS -- force dark so no
     * light-on-light text remains anywhere ("consider all objects"). */
    '.nav,.nav-list,.accordion,.accordion-group,.accordion-inner,.accordion-heading,.well,.hero-unit,.thumbnail,.input-append,.input-prepend,.btn-group,.breadcrumb,.pagination,.pager,.list-group,.list-group-item,.tab-content,.tab-pane,.modal,.modal-body,.modal-header,.modal-footer,.popover,.popover-content,.popover-title,.dropdown-menu,.dropdown-toggle,.submenu,.sub-menu,.menu,.leftMenu,.left-menu,fieldset{background:#171b21!important;color:#e6edf3!important;border-color:#2a313b!important;background-image:none!important;box-shadow:none!important;}',
    '.nav-list>li>a,.nav>li>a,.nav a,.accordion-heading a,.accordion-toggle,.dropdown-menu>li>a,.dropdown-menu a,.list-group-item,.menu a,.submenu a{background:transparent!important;color:#e6edf3!important;}',
    '.nav-list>li>a:hover,.nav>li>a:hover,.dropdown-menu>li>a:hover,.accordion-toggle:hover{background:#1d232c!important;color:#7dd3fc!important;}',
    '.nav-list>li.active>a,.nav>li.active>a,.nav-list>.active>a,li.active>a,.dropdown-menu>li>a.active{background:#38bdf8!important;color:#04121a!important;}',
    'table,thead,tbody,tfoot,tr,td,th,.table,.table td,.table th{background-color:#171b21!important;color:#e6edf3!important;border-color:#2a313b!important;}',
    'table thead th,.table thead th,tr:nth-child(even) td{background-color:#1d232c!important;}',
    '.dropdown-toggle,.select-box,.selectBox,.tp-select{color:#e6edf3!important;}',
    '.caret{border-top-color:#9aa4b2!important;}',
    'hr{border-color:#2a313b!important;}',
    '#header,#top_layout,#top_layout .container{background:#1d232c!important;color:#e6edf3!important;border-bottom:1px solid #2a313b!important;}',
    '.tabs,.tabs li,ul.tabs{background:transparent!important;}',
    '.tabs li.active,li.active,#tabStatus.active{background:#38bdf8!important;color:#04121a!important;}',
    'label,span,td,th,li,p,h1,h2,h3,h4,h5,dt,dd,div,strong,b{color:#e6edf3;}',
    '.content-label,.muted,small,.note,#noteDiv{color:#9aa4b2!important;}',
    'a,a:visited{color:#38bdf8!important;}a:hover{color:#7dd3fc!important;}',
    /* Only reset background-COLOR on glyphs so we never repaint them as dark
     * panels -- but KEEP background-image so any surviving sprite still shows. */
    'i,em,.icon,[class^="icon-"],[class*=" icon-"]{background-color:transparent!important;}',
    'img{background-color:transparent!important;}',
    /* SVG glyphs we inject inherit text colour and align nicely. */
    '.sigmod-svg{display:inline-block;vertical-align:middle;line-height:0;color:#cbd5e1;}',
    '.sigmod-svg svg{display:block;fill:currentColor;}',
    'input,select,textarea,.loginInput{background:#0f1216!important;color:#e6edf3!important;border:1px solid #2a313b!important;}',
    '.btn,button{background:#1d232c!important;color:#e6edf3!important;border:1px solid #2a313b!important;}',
    '.btn-success{background:#34d399!important;border-color:transparent!important;color:#04120a!important;}',
    '.btn-info,.btn-primary{background:#38bdf8!important;border-color:transparent!important;color:#04121a!important;}',
    '#connectionStatus,#connection{color:#34d399!important;}',
    '#sigRsrp,#sigBand{color:#e6edf3!important;}',
    /* Mod panels ------------------------------------------------------- */
    '.sigmod-card{background:#171b21!important;border:1px solid #2a313b;border-radius:10px;padding:12px 14px;margin:12px 0;}',
    '.sigmod-card h3{margin:0 0 10px;font-size:13px;letter-spacing:.04em;text-transform:uppercase;color:#9aa4b2!important;display:flex;align-items:center;gap:8px;}',
    '.sigmod-grid{display:flex;flex-wrap:wrap;gap:10px 22px;}',
    '.sigmod-stat{min-width:120px;}',
    '.sigmod-stat .k{display:flex;align-items:center;gap:7px;font-size:11px;color:#9aa4b2!important;}',
    '.sigmod-stat .v{font-size:16px;color:#e6edf3!important;margin-top:2px;}',
    '.sigmod-ctrls{display:flex;flex-wrap:wrap;gap:10px;}',
    '.sigmod-btn{display:inline-flex;align-items:center;gap:8px;cursor:pointer;border:1px solid #2a313b;border-radius:8px;padding:9px 14px;font-size:13px;background:#1d232c!important;color:#e6edf3!important;user-select:none;}',
    '.sigmod-btn:hover{border-color:#3a4552;}',
    '.sigmod-btn.on{border-color:#34d399;color:#34d399!important;}',
    '.sigmod-btn.off{border-color:#2a313b;color:#9aa4b2!important;}',
    '.sigmod-btn.danger:hover{border-color:#f87171;color:#f87171!important;}',
    '.sigmod-pill{font-size:10px;padding:1px 7px;border-radius:999px;border:1px solid currentColor;}',
    '.sigmod-bars{display:inline-flex;align-items:flex-end;gap:2px;height:14px;}',
    '.sigmod-bars i{width:3px;background:#34d399;border-radius:1px;opacity:.25;}'
  ].join('');

  function ensureDarkTheme() {
    try {
      if (document.getElementById('m7350DarkCss')) return;
      var head = document.head || document.getElementsByTagName('head')[0];
      if (!head) return;
      var st = document.createElement('style');
      st.id = 'm7350DarkCss';
      st.type = 'text/css';
      st.appendChild(document.createTextNode(DARK_CSS));
      head.appendChild(st);
    } catch (e) {}
  }

  /* ==================================================================== *
   * Inline SVG icons (24x24, fill=currentColor)                          *
   * ==================================================================== */
  var P = {
    logo:    '<path d="M12 2a1 1 0 0 1 .7.29l9 9-1.4 1.42L19 11.4V21a1 1 0 0 1-1 1h-4v-6h-4v6H6a1 1 0 0 1-1-1v-9.6l-1.3 1.3-1.4-1.42 9-9A1 1 0 0 1 12 2z"/>',
    user:    '<path d="M12 12a5 5 0 1 0-5-5 5 5 0 0 0 5 5zm0 2c-4 0-8 2-8 5v3h16v-3c0-3-4-5-8-5z"/>',
    lock:    '<path d="M17 9V7a5 5 0 0 0-10 0v2H5v13h14V9zM9 7a3 3 0 0 1 6 0v2H9z"/>',
    status:  '<path d="M3 13h4l2 6 4-16 2 8 2-2h4v2h-3l-3 3-2-8-3 12-3-9H3z"/>',
    sms:     '<path d="M4 3h16a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H8l-5 4V5a2 2 0 0 1 2-2zm3 6h10V7H7zm0 4h7v-2H7z"/>',
    advanced:'<path d="M10 3h4l.5 3 2.2.9 2.6-1.6 2.8 2.8-1.6 2.6.9 2.2 3 .5v4l-3 .5-.9 2.2 1.6 2.6-2.8 2.8-2.6-1.6-2.2.9L14 21h-4l-.5-3-2.2-.9-2.6 1.6-2.8-2.8 1.6-2.6L3 11 0 10.5v-4M12 9a3 3 0 1 0 0 6 3 3 0 0 0 0-6z" transform="translate(2 0)"/>',
    wizard:  '<path d="M6 21 3 18 15 6l3 3zM17 3l1 2 2 1-2 1-1 2-1-2-2-1 2-1zM5 5l.7 1.5L7 7l-1.3.6L5 9l-.6-1.4L3 7l1.4-.5z"/>',
    logout:  '<path d="M10 3H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h5v-2H5V5h5zm7.6 5.6-1.4 1.4 1 1H9v2h8.2l-1 1 1.4 1.4L21 12z"/>',
    signal:  '<path d="M2 20h3v-6H2zm5 0h3V9H7zm5 0h3V4h-3zm5 0h3v-9h-3z"/>',
    chip:    '<path d="M9 2v2H7a3 3 0 0 0-3 3v2H2v2h2v2H2v2h2v2a3 3 0 0 0 3 3h2v2h2v-2h2v2h2v-2h2a3 3 0 0 0 3-3v-2h2v-2h-2v-2h2V9h-2V7a3 3 0 0 0-3-3h-2V2h-2v2h-2V2zm0 6h6v6H9z"/>',
    thermo:  '<path d="M12 3a3 3 0 0 0-3 3v7.6a5 5 0 1 0 6 0V6a3 3 0 0 0-3-3zm0 15a2 2 0 0 1-1-3.7V6a1 1 0 0 1 2 0v8.3A2 2 0 0 1 12 18z"/>',
    globe:   '<path d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm6.9 9h-3a15 15 0 0 0-1.2-5.2A8 8 0 0 1 18.9 11zM12 4c.9 1.2 1.6 3.1 1.8 5h-3.6C10.4 7.1 11.1 5.2 12 4zM4.3 13h3a15 15 0 0 0 1.2 5.2A8 8 0 0 1 4.3 13zm3-2h-3a8 8 0 0 1 4.2-5.2A15 15 0 0 0 7.3 11zM12 20c-.9-1.2-1.6-3.1-1.8-5h3.6c-.2 1.9-.9 3.8-1.8 5zm2.7-1.8a15 15 0 0 0 1.2-5.2h3a8 8 0 0 1-4.2 5.2z"/>',
    clock:   '<path d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm1 10V6h-2v7h6v-2z"/>',
    down:    '<path d="M11 3h2v10l4-4 1.4 1.4L12 17.8 5.6 10.4 7 9l4 4zM5 19h14v2H5z"/>',
    up:      '<path d="M13 21h-2V11l-4 4-1.4-1.4L12 6.2l6.4 7.4L17 15l-4-4zM5 3h14v2H5z"/>',
    power:   '<path d="M13 3h-2v9h2zM7.1 6.3 5.7 4.9A9 9 0 1 0 18.3 4.9l-1.4 1.4a7 7 0 1 1-9.8 0z"/>',
    reboot:  '<path d="M12 5V2L7 6l5 4V7a5 5 0 1 1-5 5H5a7 7 0 1 0 7-7z"/>',
    usb:     '<path d="M15 7V3h-2v4h-1l2 3v6.2a2 2 0 1 0 2 0V13l3-2v-2h1V6h-3v3h1l-2 1V7zm-6 4H7V9L4 12l3 3v-2h2l2 3v3.2a2 2 0 1 0 2 0V15z"/>',
    shield:  '<path d="M12 2 4 5v6c0 5 3.4 8.5 8 11 4.6-2.5 8-6 8-11V5zm-1 13-3-3 1.4-1.4L11 12.2l3.6-3.6L16 10z"/>'
  };

  function svg(name, size) {
    var s = size || 18;
    var body = P[name] || '';
    return '<span class="sigmod-svg" data-sigmod-svg="' + name + '">' +
           '<svg width="' + s + '" height="' + s + '" viewBox="0 0 24 24" aria-hidden="true">' +
           body + '</svg></span>';
  }

  /* Swap the stock sprite glyphs for SVG (idempotent). */
  var ICONMAP = {
    'icon-logo': 'logo', 'icon-username': 'user', 'icon-password': 'lock',
    'icon-wizard': 'wizard', 'icon-status': 'status', 'icon-sms': 'sms',
    'icon-advanced': 'advanced', 'icon-logout': 'logout'
  };
  function ensureIcons() {
    try {
      for (var cls in ICONMAP) {
        if (!ICONMAP.hasOwnProperty(cls)) continue;
        var list = document.getElementsByClassName(cls);
        for (var i = 0; i < list.length; i++) {
          var el = list[i];
          if (el.getAttribute('data-sigmod-ico')) continue;
          el.setAttribute('data-sigmod-ico', '1');
          el.innerHTML = svg(ICONMAP[cls], cls === 'icon-logo' ? 30 : 24);
          el.style.background = 'none';
        }
      }
    } catch (e) {}
  }

  /* ==================================================================== *
   * Signal rows                                                          *
   * ==================================================================== */
  var last = {};   // last signal.json, shared with the System panel

  function bars(rssi) {
    var n = 0, v = parseInt(rssi, 10);
    if (!isNaN(v)) { n = v >= -65 ? 4 : v >= -75 ? 3 : v >= -85 ? 2 : v >= -95 ? 1 : 0; }
    var h = [5, 8, 11, 14], out = '<span class="sigmod-bars">';
    for (var i = 0; i < 4; i++) {
      out += '<i style="height:' + h[i] + 'px;opacity:' + (i < n ? 1 : 0.22) + '"></i>';
    }
    return out + '</span>';
  }

  function fetchSignal() {
    var x = new XMLHttpRequest();
    x.onload = function () {
      try {
        last = JSON.parse(x.responseText) || {};
        var r = document.getElementById('sigRsrp');
        var b = document.getElementById('sigBand');
        if (r) r.textContent = (last.rsrp || '--') + ' dBm / ' + (last.rsrq || '--') +
                               ' dB  (RSSI ' + (last.rssi || '--') + ' dBm)';
        if (b) b.textContent = (last.mode || '--') +
                               (last.band ? '  Band ' + last.band : '') +
                               '  (EARFCN ' + (last.earfcn || '--') + ')';
        updatePanels();
      } catch (e) {}
    };
    x.open('GET', CGI_SIGNAL + '?t=' + (new Date()).getTime(), true);
    x.send();
  }

  function makeRow(rowId, labelText, valueId) {
    var g = document.createElement('div');
    g.className = 'content-group';
    g.id = rowId;
    var l = document.createElement('label');
    l.className = 'content-label';
    l.textContent = labelText;
    var v = document.createElement('label');
    v.id = valueId;
    v.textContent = '--';
    g.appendChild(l);
    g.appendChild(v);
    return g;
  }

  function locate() {
    var el = document.getElementById('networkType') ||
             document.getElementById('connectionStatus') ||
             document.getElementById('connection');
    if (el && el.parentNode && el.parentNode.parentNode) {
      var group = el.parentNode;
      return { container: group.parentNode, before: group.nextSibling };
    }
    var c = document.querySelector('.section-status') ||
            document.getElementById('loginStatus') ||
            document.getElementById('statusContent');
    if (c) return { container: c, before: null };
    return null;
  }

  function injectSignalRows() {
    if (!document.body) return;
    if (document.getElementById('sigRow')) return;
    var pos = locate();
    if (!pos) return;
    pos.container.insertBefore(makeRow('sigRow', 'RSRP / RSRQ', 'sigRsrp'), pos.before);
    pos.container.insertBefore(makeRow('sigBandRow', 'Band (EARFCN)', 'sigBand'), pos.before);
    fetchSignal();
  }

  /* ==================================================================== *
   * System + Controls panels (post-login Status tab only)                *
   * ==================================================================== */
  function isPostLogin() {
    return !!(document.getElementById('top_menu') || document.getElementById('tabStatus'));
  }
  function panelHost() {
    // Prefer the active status content; fall back to the main container.
    return document.querySelector('#content .container') ||
           document.getElementById('container') ||
           document.getElementById('content');
  }

  function fmtDur(s) {
    s = parseInt(s, 10); if (isNaN(s)) return '--';
    var d = Math.floor(s / 86400); s %= 86400;
    var h = Math.floor(s / 3600); s %= 3600;
    var m = Math.floor(s / 60);
    return (d ? d + 'd ' : '') + h + 'h ' + m + 'm';
  }
  function fmtRate(k) {
    var v = parseFloat(k); if (isNaN(v)) return '--';
    return v >= 1000 ? (v / 1000).toFixed(1) + ' Mbps' : v.toFixed(0) + ' kbps';
  }

  function stat(iconName, key, valueId) {
    return '<div class="sigmod-stat"><div class="k">' + svg(iconName, 16) + key + '</div>' +
           '<div class="v" id="' + valueId + '">--</div></div>';
  }

  function buildPanels(host) {
    if (document.getElementById('sigmodPanel')) return;

    var sys = document.createElement('div');
    sys.className = 'sigmod-card';
    sys.id = 'sigmodPanel';
    sys.innerHTML =
      '<h3>' + svg('chip', 15) + 'System</h3>' +
      '<div class="sigmod-grid">' +
        stat('signal', 'Signal', 'spSig') +
        stat('down', 'Download', 'spDl') +
        stat('up', 'Upload', 'spUl') +
        stat('clock', 'Latency', 'spLat') +
        stat('thermo', 'Temp', 'spTemp') +
        stat('clock', 'Uptime', 'spUp') +
        stat('globe', 'WAN IP', 'spWan') +
      '</div>';

    var ctl = document.createElement('div');
    ctl.className = 'sigmod-card';
    ctl.id = 'sigmodCtl';
    ctl.innerHTML =
      '<h3>' + svg('advanced', 15) + 'Controls</h3>' +
      '<div class="sigmod-ctrls">' +
        '<span class="sigmod-btn" id="btnTtl">' + svg('shield', 16) +
          'TTL-fix <span class="sigmod-pill" id="pillTtl">--</span></span>' +
        '<span class="sigmod-btn" id="btnAdb">' + svg('usb', 16) +
          'ADB <span class="sigmod-pill" id="pillAdb">--</span></span>' +
        '<span class="sigmod-btn danger" id="btnReboot">' + svg('reboot', 16) + 'Reboot</span>' +
      '</div>' +
      '<div class="content-label" style="margin-top:8px;font-size:11px;">' +
        'TTL-fix pins outgoing TTL to 65 (helps tethering on SMARTY/Three). ' +
        'ADB toggles the USB debug bridge.</div>';

    host.appendChild(sys);
    host.appendChild(ctl);
    wireControls();
    refreshCtlState();
  }

  function injectPanels() {
    if (!isPostLogin()) return;
    if (!document.getElementById('sigRow')) return;   // wait for status view
    var host = panelHost();
    if (host) buildPanels(host);
  }

  function setPill(id, state) {
    var p = document.getElementById(id);
    var btn = p && p.parentNode;
    if (!p) return;
    p.textContent = state === 'on' ? 'ON' : state === 'off' ? 'OFF' : '--';
    if (btn) { btn.classList.remove('on', 'off'); if (state === 'on' || state === 'off') btn.classList.add(state); }
  }

  function refreshCtlState() {
    var x = new XMLHttpRequest();
    x.onload = function () {
      try {
        var d = JSON.parse(x.responseText);
        setPill('pillTtl', d.ttl);
        setPill('pillAdb', d.adb);
        var w = document.getElementById('spWan'); if (w) w.textContent = d.wan || '--';
        var t = document.getElementById('spTemp'); if (t && d.temp) t.textContent = d.temp + ' °C';
      } catch (e) {}
    };
    x.open('GET', CGI_SYS + '?t=' + (new Date()).getTime(), true);
    x.send();
  }

  function ctl(action, cb) {
    var x = new XMLHttpRequest();
    x.onload = function () { try { cb && cb(JSON.parse(x.responseText)); } catch (e) { cb && cb({}); } };
    x.onerror = function () { cb && cb({}); };
    x.open('GET', CGI_CTL + '?action=' + action + '&t=' + (new Date()).getTime(), true);
    x.send();
  }

  function wireControls() {
    var ttl = document.getElementById('btnTtl');
    var adb = document.getElementById('btnAdb');
    var rb  = document.getElementById('btnReboot');

    if (ttl) ttl.onclick = function () {
      var on = document.getElementById('pillTtl').textContent === 'ON';
      setPill('pillTtl', '...');
      ctl(on ? 'ttl_off' : 'ttl_on', function (d) { setPill('pillTtl', d.ttl || (on ? 'off' : 'on')); });
    };

    if (adb) adb.onclick = function () {
      var on = document.getElementById('pillAdb').textContent === 'ON';
      if (on && !window.confirm('Turn OFF the ADB debug bridge? You will lose adb access until it is turned back on from here or the device reboots.')) return;
      setPill('pillAdb', '...');
      ctl(on ? 'adb_off' : 'adb_on', function (d) {
        // adb_off replies then stops a second later; re-poll shortly.
        setTimeout(refreshCtlState, 1500);
        if (d.adb) setPill('pillAdb', d.adb);
      });
    };

    if (rb) rb.onclick = function () {
      if (!window.confirm('Reboot the router now? The connection will drop for ~30-60s.')) return;
      rb.innerHTML = svg('reboot', 16) + 'Rebooting...';
      ctl('reboot');
    };
  }

  function updatePanels() {
    var set = function (id, txt) { var e = document.getElementById(id); if (e) e.textContent = txt; };
    set('spSig', (last.rsrp ? last.rsrp + ' dBm' : '--'));
    var sEl = document.getElementById('spSig');
    if (sEl && last.rssi) sEl.innerHTML = bars(last.rssi) + ' <span style="vertical-align:middle">' + (last.rsrp || '--') + ' dBm</span>';
    set('spDl', fmtRate(last.dl_kbps));
    set('spUl', fmtRate(last.ul_kbps));
    set('spLat', last.latency_ms ? Math.round(parseFloat(last.latency_ms)) + ' ms' : '--');
    set('spUp', fmtDur(last.uptime));
  }

  /* ==================================================================== *
   * Main loop                                                            *
   * ==================================================================== */
  function tick() {
    try { ensureDarkTheme(); } catch (e) {}
    try { ensureIcons(); } catch (e) {}
    try { injectSignalRows(); } catch (e) {}
    try { injectPanels(); } catch (e) {}
    try { fetchSignal(); } catch (e) {}
  }

  ensureDarkTheme();
  setInterval(tick, 1500);
  // Refresh control/system state a bit less often than signal.
  setInterval(function () { if (document.getElementById('sigmodPanel')) refreshCtlState(); }, 6000);

  var quick = [50, 150, 300, 500, 800, 1200, 1800, 2500];
  for (var i = 0; i < quick.length; i++) { setTimeout(tick, quick[i]); }
  if (document.addEventListener) document.addEventListener('DOMContentLoaded', tick, false);
  if (window.addEventListener) window.addEventListener('load', tick, false);
})();
