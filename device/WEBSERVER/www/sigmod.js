/* M7350 LTE signal-stats web-UI mod ---------------------------------------
 *
 * Adds two live rows -- "RSRP / RSRQ" and "Band (EARFCN)" -- to the router's
 * status view, on BOTH the pre-login status block (login.html) and the
 * post-login Status tab (settings.html).
 *
 * WHY THIS FILE IS LOADED FROM <head>, NOT THE END OF <body>:
 *   The TP-Link JS framework (libs.min.js / tpweb.min.js / login.min.js)
 *   synchronously rebuilds the status DOM from its own templates while those
 *   scripts run. A <script> placed later in <body> is discarded before the
 *   parser reaches it (it never executes), and any static rows added to the
 *   HTML are wiped on every re-render. Loading from <head> runs this code
 *   first; the setInterval() closure below is not tied to any DOM node, so it
 *   survives every rebuild and simply re-creates the rows whenever they are
 *   missing.
 *
 * DATA SOURCE:
 *   GET /cgi-bin/signal_stats.sh -> JSON written by the signal_poll.sh daemon
 *   (which polls AT commands on /dev/smd7 every 5s). The CGI only cats a cache
 *   file; never read /dev/smd7 directly from a CGI context -- it blocks and
 *   kills lighttpd.
 */
(function () {
  'use strict';

  // Apply the modern dark theme WITHOUT needing a <link> in every page's HTML.
  // We inject the rules as an inline <style> in <head>. sigmod.js is loaded
  // from <head>, so this runs before the body is painted -> no light flash and
  // no async external-stylesheet repaint problem (which left the post-login
  // cards light-on-light when the theme was a JS-injected <link>).
  var DARK_CSS = [
    ':root{--dk-bg:#0f1216;--dk-panel:#171b21;--dk-panel2:#1d232c;--dk-border:#2a313b;--dk-text:#e6edf3;--dk-muted:#9aa4b2;--dk-accent:#38bdf8;--dk-green:#34d399;}',
    'html,body{background:#0f1216!important;color:#e6edf3!important;}',
    '#content,#loginPage,#loginContainer,#login,#noteDiv,.tabCover,.clearfix{background:transparent!important;}',
    '.container,.statusPage,.section,.section-status,.popup,.help-popup,.panel,.box,[class*="section"],[class*="Section"],[class*="panel"],[class*="-box"],[class*="card"]{background:#171b21!important;color:#e6edf3!important;border-color:#2a313b!important;box-shadow:none!important;background-image:none!important;}',
    '.connectionSection,.wifiSection,.statisticsSection,.dataSection,#statusContent,#statusContent>div{background:#171b21!important;border-color:#2a313b!important;}',
    '.statusPage>div,.statusPage .container,#content .container>div{background:#171b21!important;border-color:#2a313b!important;}',
    '#header,#top_layout,#top_layout .container{background:#1d232c!important;color:#e6edf3!important;border-bottom:1px solid #2a313b!important;}',
    '.tabs,.tabs li,ul.tabs{background:transparent!important;}',
    '.tabs li.active,li.active,#tabStatus.active{background:#38bdf8!important;color:#04121a!important;}',
    'label,span,td,th,li,p,h1,h2,h3,h4,h5,dt,dd,div,strong,b{color:#e6edf3;}',
    '.content-label,.muted,small,.note,#noteDiv{color:#9aa4b2!important;}',
    'a,a:visited{color:#38bdf8!important;}a:hover{color:#7dd3fc!important;}',
    'i,em,.icon,[class^="icon-"],[class*=" icon-"],img{background:transparent!important;}',
    'input,select,textarea,.loginInput{background:#0f1216!important;color:#e6edf3!important;border:1px solid #2a313b!important;}',
    '.btn,button{background:#1d232c!important;color:#e6edf3!important;border:1px solid #2a313b!important;}',
    '.btn-success{background:#34d399!important;border-color:transparent!important;color:#04120a!important;}',
    '.btn-info,.btn-primary{background:#38bdf8!important;border-color:transparent!important;color:#04121a!important;}',
    '#connectionStatus,#connection{color:#34d399!important;}',
    '#sigRsrp,#sigBand{color:#e6edf3!important;}'
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
  ensureDarkTheme();

  function fetchAndUpdate() {
    if (!document.getElementById('sigRsrp')) return;   // rows not present yet
    var x = new XMLHttpRequest();
    x.onload = function () {
      try {
        var d = JSON.parse(x.responseText);
        var r = document.getElementById('sigRsrp');
        var b = document.getElementById('sigBand');
        if (r) r.textContent = (d.rsrp || '--') + ' dBm / ' + (d.rsrq || '--') +
                               ' dB  (RSSI ' + (d.rssi || '--') + ' dBm)';
        if (b) b.textContent = (d.mode || '--') +
                               (d.band ? '  Band ' + d.band : '') +
                               '  (EARFCN ' + (d.earfcn || '--') + ')';
      } catch (e) {}
    };
    x.open('GET', '/cgi-bin/signal_stats.sh?t=' + (new Date()).getTime(), true);
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

  /* Locate where to insert the rows. Works on both pages:
   *   login.html    : #networkType label inside #netTypeDiv (.content-group)
   *   settings.html : #networkType / #connectionStatus label in a .content-group
   * The value labels sit directly inside a .content-group, so the label's
   * parentNode IS that row and its grandparent is the status container. */
  function locate() {
    var el = document.getElementById('networkType') ||
             document.getElementById('connectionStatus') ||
             document.getElementById('connection');
    if (el && el.parentNode && el.parentNode.parentNode) {
      var group = el.parentNode;                       // the .content-group row
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
    if (document.getElementById('sigRow')) return;     // already present
    var pos = locate();
    if (!pos) return;                                  // status view not rendered yet
    pos.container.insertBefore(makeRow('sigRow', 'RSRP / RSRQ', 'sigRsrp'), pos.before);
    pos.container.insertBefore(makeRow('sigBandRow', 'Band (EARFCN)', 'sigBand'), pos.before);
    fetchAndUpdate();
  }

  function tick() { ensureDarkTheme(); injectSignalRows(); fetchAndUpdate(); }

  // Steady-state watchdog: the framework rebuilds the status DOM periodically
  // (and on every page refresh); this re-creates the rows within ~1.2s of any
  // wipe. The closure is not tied to a DOM node, so it survives the rebuilds.
  setInterval(tick, 1200);

  // Fast catch-up right after load so a refresh shows the rows almost
  // immediately instead of waiting for the first interval, and so we win the
  // race against the framework's initial async render.
  var quick = [50, 150, 300, 500, 800, 1200, 1800, 2500];
  for (var i = 0; i < quick.length; i++) { setTimeout(tick, quick[i]); }

  if (document.addEventListener) {
    document.addEventListener('DOMContentLoaded', tick, false);
  }
  if (window.addEventListener) {
    window.addEventListener('load', tick, false);
  }
})();
