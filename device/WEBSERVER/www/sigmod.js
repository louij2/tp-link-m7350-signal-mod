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
  var CGI_DEV    = '/cgi-bin/deviceinfo.sh';
  var CGI_KEYS   = '/cgi-bin/keys.sh';
  var CGI_HIST   = '/cgi-bin/signal_hist.sh';
  var CGI_TILES  = '/cgi-bin/tiles.sh';

  // Custom device name (AirPort-style). Change this to rebrand the UI.
  var MODEL = 'M7350+ Extreme';

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
    /* --- Status-page redesign: card-ify the actual stock sections, cut
       whitespace so the stock content matches the mod cards. --- */
    /* Neutralise the firmware's fixed geometry BEFORE laying anything out.
     * settings.css pins .statusPage to width:850px/height:500px/min-height:630px
     * and floats the sections at 49.5% with height:310px, with fixed-height rows
     * and floated labels. Every one of those has to be undone explicitly or the
     * container keeps its 630px whether or not anything is in it -- which is
     * what produced a tall empty band above the cards. */
    '.statusPage{width:auto!important;height:auto!important;min-height:0!important;padding:0!important;margin:0!important;background:transparent!important;display:grid!important;grid-template-columns:repeat(auto-fill,minmax(300px,1fr))!important;grid-auto-flow:row dense!important;gap:12px!important;align-items:start!important;}',
    '.statusPage .sigmod-card{margin:0 0 12px!important;width:auto!important;height:auto!important;box-sizing:border-box!important;break-inside:avoid!important;-webkit-column-break-inside:avoid!important;page-break-inside:avoid!important;background:#171b21!important;border:1px solid #2a313b!important;border-radius:10px!important;padding:14px 16px!important;}',
    '.statusPage .pinSection,.statusPage .connectionSection,.statusPage .wifiSection,.statusPage .statisticSection,.statusPage .simSection,.statusPage .dataSection{width:auto!important;height:auto!important;min-height:0!important;float:none!important;margin:0!important;height:auto!important;box-sizing:border-box!important;position:relative!important;}',
    '.statusPage .content-group{height:auto!important;min-height:0!important;margin-left:0!important;padding-top:0!important;min-width:0!important;overflow-wrap:break-word!important;}',
    '.statusPage .content-group>.content-label{float:none!important;width:auto!important;margin-right:0!important;}',
    '.statusPage .content-group>label{white-space:normal!important;min-width:0!important;overflow-wrap:break-word!important;}',
    '.statusPage .statusHeader{padding:0 0 8px!important;margin:0 0 10px!important;line-height:1.3!important;}',
    '.statusHeader{font-size:12px!important;letter-spacing:.04em;text-transform:uppercase;color:#9aa4b2!important;font-weight:600;margin:0 0 10px!important;padding:0 0 8px!important;border-bottom:1px solid #2a313b!important;}',
    /* Stock rows: label stacked above value, same visual language as the mod's
     * own .sigmod-stat tiles, so the two halves of the page read as one UI. */
    '.statusPage .content-group{margin:0!important;padding:0!important;min-height:0!important;line-height:1.35!important;}',
    '.statusPage .content-label{display:block!important;min-width:0!important;color:#9aa4b2!important;font-size:11px!important;font-weight:400!important;}',
    '.statusPage .content-group>label+label,.statusPage .content-group>label:last-child:not(.content-label),.statusPage .content-group>span:last-child,.statusPage .content-group>div:last-child:not(.content-label){display:block!important;font-size:14px!important;color:#e6edf3!important;margin-top:2px!important;overflow-wrap:break-word!important;}',
    /* the wrapper divs stay transparent; the real sections become the cards */
    '.statusPage>div{background:transparent!important;border:0!important;padding:0!important;margin:0!important;}',
    /* Each stock section becomes a dense auto-fill grid. NOTHING is hidden,
     * moved or duplicated -- every stock row stays exactly where the firmware
     * put it and merely reflows into columns, so no value can go missing and
     * the page still works if TP-LINK changes the DOM. */
    '.connectionSection:not(.hide),.wifiSection:not(.hide),.statisticSection:not(.hide),.pinSection:not(.hide),.simSection:not(.hide),.dataSection:not(.hide){background:#171b21!important;border:1px solid #2a313b!important;border-radius:10px!important;padding:14px 16px!important;box-shadow:none!important;min-height:0!important;display:grid!important;grid-template-columns:repeat(auto-fill,minmax(120px,1fr))!important;gap:10px 12px!important;align-content:start!important;}',
    /* The mod's OWN cards get the dashboard grid. The stock sections are left
     * exactly where the firmware's CSS puts them -- an earlier version dissolved
     * their wrappers with display:contents and re-flowed everything into one
     * masonry column set, which overlapped cards on the real device because the
     * stock stylesheet positions those blocks itself. Only style what we own. */
    '#sigmodAbout .sigmod-grid{grid-template-columns:repeat(auto-fill,minmax(150px,1fr))!important;}',
    '#sigmodAbout .sigmod-stat .v{font-variant-numeric:tabular-nums;letter-spacing:-0.01em;}',
    '.sigmod-col{display:flex!important;flex-direction:column!important;gap:12px!important;min-width:0!important;margin:0 0 12px!important;break-inside:avoid!important;-webkit-column-break-inside:avoid!important;page-break-inside:avoid!important;}',
    '.sigmod-col>.sigmod-card{margin:0!important;height:auto!important;background:#171b21!important;border:1px solid #2a313b!important;border-radius:10px!important;padding:14px 16px!important;box-sizing:border-box!important;}',
    '.sigmod-cards{display:block!important;column-width:300px!important;column-gap:12px!important;margin:12px 0!important;}',
    '.sigmod-cards>.sigmod-card{margin:0 0 12px!important;break-inside:avoid!important;-webkit-column-break-inside:avoid!important;page-break-inside:avoid!important;width:auto!important;}',
    /* headers and any full-width controls span every column */
    '.statusPage .statusHeader{grid-column:1/-1!important;}',
    '.statusPage .btn,.statusPage button,.statusPage input[type="button"],.statusPage input[type="submit"]{justify-self:start!important;}',
    /* two-column top row (Connection | Wi-Fi) with a real gap, Stats full width */
    '.connectionSection:not(.hide),.wifiSection:not(.hide){width:auto!important;}',
    /* Do NOT force .hide to display:none with !important. The firmware unhides
     * #statusContent -- the wrapper holding Internet Connection, Wireless and
     * Statistics -- with an INLINE style while leaving the .hide class on it, so
     * an !important rule here wins and suppresses the entire stock status block.
     * Keeping .pinSection out of the section styling below is enough to stop the
     * PIN panel appearing, without fighting the framework's own show/hide. */
    '.statusPage>#statusContent{display:none!important;}',
    'a.icon-help,.icon-help{border:0!important;background:transparent!important;padding:0!important;margin:0!important;}',
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
    /* Login status box: let it grow so the extra signal rows never spill past
     * the panel edge (the stock CSS gives it a fixed height). */
    '#loginStatus,.section-status{height:auto!important;min-height:0!important;max-height:none!important;overflow:visible!important;padding:16px 18px 18px!important;box-sizing:border-box!important;}',
    '#content,#loginContainer{height:auto!important;overflow:visible!important;}',
    '#content,#content>.container,#content .container{width:auto!important;max-width:none!important;margin-left:0!important;margin-right:0!important;}',
    '#deviceName{font-weight:600;}',
    /* Hide the Wizard tab (first-run setup) -- not needed day to day. */
    '#tabWizard{display:none!important;}',
    /* Mod panels ------------------------------------------------------- */
    '.sigmod-card{background:#171b21!important;border:1px solid #2a313b;border-radius:10px;padding:12px 14px;margin:12px 0;}',
    '.sigmod-card h3{margin:0 0 10px;font-size:13px;letter-spacing:.04em;text-transform:uppercase;color:#9aa4b2!important;display:flex;align-items:center;gap:8px;}',
    '.sigmod-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(120px,1fr));gap:10px 12px;}',
    '.sigmod-stat{min-width:0;overflow-wrap:anywhere;}',
    '.sigmod-stat .k{display:flex;align-items:center;gap:7px;font-size:11px;color:#9aa4b2!important;}',
    '.sigmod-stat .v{font-size:14px;color:#e6edf3!important;margin-top:2px;overflow-wrap:break-word;font-variant-numeric:tabular-nums;}',
    '.sigmod-ctrls{display:flex;flex-wrap:wrap;gap:10px;}',
    '.sigmod-btn{display:inline-flex;align-items:center;gap:8px;cursor:pointer;border:1px solid #2a313b;border-radius:8px;padding:9px 14px;font-size:13px;background:#1d232c!important;color:#e6edf3!important;user-select:none;}',
    '.sigmod-btn:hover{border-color:#3a4552;}',
    '.sigmod-btn.on{border-color:#34d399;color:#34d399!important;}',
    '.sigmod-btn.off{border-color:#2a313b;color:#9aa4b2!important;}',
    '.sigmod-btn.danger:hover{border-color:#f87171;color:#f87171!important;}',
    '.sigmod-pill{font-size:10px;padding:1px 7px;border-radius:999px;border:1px solid currentColor;}',
    '.sigmod-keys{margin-top:10px;display:flex;flex-direction:column;gap:8px;}',
    '.sigmod-key{display:flex;align-items:center;justify-content:space-between;gap:10px;background:#1d232c!important;border:1px solid #2a313b;border-radius:8px;padding:8px 10px;}',
    '.sigmod-key>div:first-child{min-width:0;flex:1 1 auto;}',
    '.sigmod-key .kt{font-size:13px;color:#e6edf3!important;overflow-wrap:break-word;}',
    '.sigmod-key .kf{font-size:10px;color:#9aa4b2!important;overflow-wrap:break-word;font-family:monospace;}',
    '.sigmod-key .sigmod-btn{padding:5px 10px;font-size:11px;flex:0 0 auto;}',
    '.sigmod-tile{cursor:grab;}',
    '@media(max-width:700px){.statusPage>*{grid-column:auto!important;}}',
    '.sigmod-grip{position:absolute;right:2px;bottom:2px;width:16px;height:16px;cursor:nwse-resize;opacity:0;transition:opacity .12s;z-index:6;}',
    '.sigmod-grip:before{content:"";position:absolute;right:3px;bottom:3px;width:8px;height:8px;border-right:2px solid #4b5563;border-bottom:2px solid #4b5563;}',
    '.sigmod-tile:hover .sigmod-grip{opacity:1;}',
    '.sigmod-grip:hover:before{border-color:#38bdf8;}',
    '.sigmod-resizing{outline:1px solid #38bdf8!important;user-select:none;}',

    '.sigmod-tile:active{cursor:grabbing;}',
    '.sigmod-drag{opacity:.35;}',
    '.sigmod-over{outline:2px dashed #38bdf8!important;outline-offset:2px;}',
    '.sigmod-spark{margin-top:12px;padding-top:10px;border-top:1px solid #2a313b;}',
    '.sigmod-spark .sk{font-size:10px;color:#9aa4b2!important;margin-bottom:4px;}',
    '.sigmod-spark .sk:last-child{margin:4px 0 0;}',
    '.sigmod-bars{display:inline-flex;align-items:flex-end;gap:2px;height:14px;}',
    '.sigmod-bars i{width:3px;background:#34d399!important;background-color:#34d399!important;border-radius:1px;opacity:.25;}'
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
    shield:  '<path d="M12 2 4 5v6c0 5 3.4 8.5 8 11 4.6-2.5 8-6 8-11V5zm-1 13-3-3 1.4-1.4L11 12.2l3.6-3.6L16 10z"/>',
    battery: '<path d="M4 8h14a2 2 0 0 1 2 2v4a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2v-4a2 2 0 0 1 2-2zm0 2v4h14v-4zm18 1h1v2h-1z"/>',
    bolt:    '<path d="M13 2 4 14h6l-1 8 9-12h-6z"/>'
  };

  function svg(name, size) {
    var s = size || 18;
    var body = P[name] || '';
    return '<span class="sigmod-svg" data-sigmod-svg="' + name + '">' +
           '<svg width="' + s + '" height="' + s + '" viewBox="0 0 24 24" aria-hidden="true">' +
           body + '</svg></span>';
  }

  /* Swap the stock sprite glyphs for SVG (idempotent). */
  // NOTE: icon-logo is deliberately NOT swapped -- keep the stock TP-LINK logo
  // (the sprite renders fine again now that the theme no longer wipes the icon
  // background-image). Only the monochrome nav/login glyphs are replaced.
  var ICONMAP = {
    'icon-username': 'user', 'icon-password': 'lock',
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
    // Prefer .statusPage: putting our cards in the firmware's own container lets
    // them share one masonry flow with the stock sections, so a short stock card
    // no longer strands the space beneath it. We only ever APPEND our own
    // elements -- the firmware's nodes are never moved or restructured.
    return document.querySelector('.statusPage') ||
           document.querySelector('#content .container') ||
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
        stat('battery', 'Battery', 'spBatt') +
        stat('clock', 'Uptime', 'spUp') +
        stat('globe', 'WAN IP', 'spWan') +
        stat('signal', 'Cell ID', 'spCell') +
        stat('globe', 'TAC', 'spTac') +
      '</div>' +
      '<div class="sigmod-spark"><div class="sk">Signal, last 4 hours</div>' +
        '<div id="spSpark"></div></div>';

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
        '<span class="sigmod-btn" id="btnWifi">' + svg('signal', 16) +
          'Wi-Fi <span class="sigmod-pill" id="pillWifi">--</span></span>' +
        '<span class="sigmod-btn" id="btnFtp">' + svg('globe', 16) +
          'FTP <span class="sigmod-pill" id="pillFtp">--</span></span>' +
        '<span class="sigmod-btn" id="btnTelnet">' + svg('usb', 16) +
          'Telnet <span class="sigmod-pill" id="pillTelnet">--</span></span>' +
        '<span class="sigmod-btn" id="btnSaver">' + svg('globe', 16) +
          'Data saver <span class="sigmod-pill" id="pillSaver">--</span></span>' +
        '<span class="sigmod-btn danger" id="btnReboot">' + svg('reboot', 16) + 'Reboot</span>' +
        '<span class="sigmod-btn" id="btnResetTiles">' + svg('advanced', 16) + 'Reset layout</span>' +
      '</div>' +
      '<div class="content-label" style="margin-top:8px;font-size:11px;">' +
        'Data saver stops the device generating traffic of its own: no latency ping, ' + '\n' +
        'Prometheus scraping is refused, and both the daemon and this page poll far ' +
        'less often. Worth turning on before you travel. ' +
        'TTL-fix pins outgoing TTL to 65 (helps tethering on SMARTY/Three). ' +
        'ADB = USB debug bridge. FTP/Telnet serve the whole filesystem on the ' +
        'LAN side only — handy for file access, but leave them off when not in ' +
        'use. SSH (key-only) is also available on the LAN for secure access.</div>';

    var about = document.createElement('div');
    about.className = 'sigmod-card';
    about.id = 'sigmodAbout';
    about.innerHTML =
      '<h3>' + svg('chip', 15) + 'About Device</h3>' +
      '<div class="sigmod-grid">' +
        // Grouped: what the device is, then what network it is on, then the
        // subscriber identifiers (which are the long ones, kept together).
        stat('chip', 'Model', 'abModel') +
        stat('chip', 'Hardware', 'abHw') +
        stat('advanced', 'Firmware', 'abFw') +
        stat('globe', 'Operator', 'abOper') +
        stat('advanced', 'Network Mode', 'abNet') +
        stat('signal', 'APN', 'abApn') +
        stat('signal', 'IMEI', 'abImei') +
        stat('usb', 'IMSI', 'abImsi') +
        stat('sms', 'SIM Number', 'abSim') +
        stat('globe', 'MAC', 'abMac') +
        stat('usb', 'ICCID', 'abIccid') +
        stat('signal', 'Carrier (SPN)', 'abSpn') +
      '</div>';

    var hw = document.createElement('div');
    hw.className = 'sigmod-card';
    hw.id = 'sigmodHw';
    hw.innerHTML =
      '<h3>' + svg('chip', 15) + 'Hardware</h3>' +
      '<div class="sigmod-grid">' +
        stat('advanced', 'CPU', 'hwCpu') +
        stat('chip', 'Load', 'hwLoad') +
        stat('chip', 'RAM', 'hwRam') +
        stat('usb', 'Swap', 'hwSwap') +
        stat('advanced', 'Storage /', 'hwRoot') +
        stat('advanced', 'Storage /usr', 'hwUsr') +
        stat('usb', 'SD card', 'hwSd') +
        stat('thermo', 'Temp', 'hwTemp') +
      '</div>';

    var sec = document.createElement('div');
    sec.className = 'sigmod-card';
    sec.id = 'sigmodSec';
    sec.innerHTML =
      '<h3>' + svg('shield', 15) + 'Security</h3>' +
      '<div class="sigmod-ctrls">' +
        '<span class="sigmod-btn" id="btnAddKey">' + svg('lock', 16) + 'Add SSH key</span>' +
        '<span class="sigmod-btn" id="btnChangePw">' + svg('lock', 16) + 'Change password</span>' +
      '</div>' +
      '<div id="sigmodKeys" class="sigmod-keys"></div>' +
      '<div class="content-label" style="margin-top:8px;font-size:11px;">' +
        'Keys here grant root SSH. Both actions need the control password, and ' +
        'the last remaining key cannot be revoked so you cannot lock yourself out.</div>';

    // Our cards live in a container we own, so the grid can never interfere with
    // however the firmware chooses to lay out its own sections.
    if (host.className.indexOf('statusPage') >= 0) {
      host.appendChild(sys); host.appendChild(ctl); host.appendChild(hw);
      host.appendChild(sec); host.appendChild(about);
    } else {
      var wrap = document.createElement('div');
      wrap.className = 'sigmod-cards';
      wrap.id = 'sigmodCards';
      wrap.appendChild(sys); wrap.appendChild(ctl); wrap.appendChild(hw);
      wrap.appendChild(sec); wrap.appendChild(about);
      host.appendChild(wrap);
    }
    wireControls();
    var rt = document.getElementById('btnResetTiles'); if (rt) rt.onclick = resetTileOrder;
    var ak = document.getElementById('btnAddKey');   if (ak) ak.onclick = addKey;
    var cp = document.getElementById('btnChangePw'); if (cp) cp.onclick = changePw;
    refreshCtlState();
    fetchDeviceInfo();
    loadKeys();
    fetchHist();
  }

  // IMEI / IMSI / SIM come back redacted unless we present the control password,
  // so send it when we have one and offer a one-click unlock when we do not.
  function unlockAbout() {
    var p = window.prompt('Control password (to show IMEI / IMSI / SIM):');
    if (p === null) return;
    try { sessionStorage.setItem('sigmodPw', p); } catch (e) {}
    fetchDeviceInfo(p);
  }

  function fetchDeviceInfo(pw) {
    var x = new XMLHttpRequest();
    x.onload = function () {
      try {
        var d = JSON.parse(x.responseText);
        var set = function (id, v) { var e = document.getElementById(id); if (e) e.textContent = v || '—'; };
        set('abModel', d.model); set('abFw', d.firmware); set('abHw', d.hardware);
        set('abImei', d.imei); set('abMac', d.mac); set('abImsi', d.imsi); set('abSim', d.sim);
        set('abOper', d.operator + (d.mccmnc ? ' (' + d.mccmnc + ')' : '')); set('abApn', d.apn); set('abNet', d.netmode);

        var ids = ['abImei', 'abImsi', 'abSim'];
        for (var i = 0; i < ids.length; i++) {
          var e = document.getElementById(ids[i]);
          if (!e) continue;
          if (d.locked === '1') {
            e.textContent = 'locked';
            e.style.cursor = 'pointer';
            e.style.color = '#9aa4b2';
            e.title = 'Click to unlock with the control password';
            e.onclick = unlockAbout;
          } else {
            e.style.cursor = ''; e.style.color = ''; e.title = ''; e.onclick = null;
          }
        }
      } catch (e) {}
    };
    x.open('GET', CGI_DEV + '?t=' + (new Date()).getTime(), true);
    var use = (pw != null) ? pw : storedPw();
    if (use) x.setRequestHeader('X-Auth', use);
    x.send();
  }

  function injectPanels() {
    if (!isPostLogin()) return;
    if (!document.getElementById('sigRow')) return;   // wait for status view
    var host = panelHost();
    if (!host) return;
    buildPanels(host);
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
        setPill('pillFtp', d.ftp);
        setPill('pillTelnet', d.telnet);
        setPill('pillWifi', d.wifi);
        setPill('pillSaver', d.saver);
        if (d.saver) { saverOn = (d.saver === 'on'); applySaverCadence(); }
        var w = document.getElementById('spWan'); if (w) w.textContent = d.wan || '--';
        var t = document.getElementById('spTemp'); if (t && d.temp) t.textContent = d.temp + ' °C';
        var bt = document.getElementById('spBatt');
        if (bt && d.battery) bt.textContent = d.battery + '%' + (d.charging === '1' ? ' ⚡' : '');

        var mb = function (kb) { var n = parseFloat(kb); return isNaN(n) ? null : (n / 1024); };
        var setx = function (id, v) { var e = document.getElementById(id); if (e) e.textContent = v; };
        setx('hwCpu',  d.cpu ? d.cpu + '%' : '—');
        setx('hwLoad', d.load || '—');
        var mt = mb(d.memtotal), mf = mb(d.memfree);
        setx('hwRam',  (mt && mf !== null) ? (Math.round(mt - mf) + ' / ' + Math.round(mt) + ' MB') : '—');
        var st = mb(d.swaptotal), sf = mb(d.swapfree);
        setx('hwSwap', (st && sf !== null) ? (Math.round(st - sf) + ' / ' + Math.round(st) + ' MB') : '—');
        var rf = mb(d.rootfree), uf = mb(d.usrfree);
        setx('hwRoot', rf !== null ? (rf.toFixed(1) + ' MB free' + (d.rootpct ? ' · ' + d.rootpct + '%' : '')) : '—');
        setx('hwUsr',  uf !== null ? (uf.toFixed(1) + ' MB free' + (d.usrpct ? ' · ' + d.usrpct + '%' : '')) : '—');
        setx('hwSd',   d.sd || '—');
        setx('hwTemp', d.temp ? d.temp + ' °C' : '—');
      } catch (e) {}
    };
    x.open('GET', CGI_SYS + '?t=' + (new Date()).getTime(), true);
    x.send();
  }

  // Generic authenticated request. Same 403-then-prompt-once flow as ctl(),
  // but supports POST so passwords and public keys travel in the body rather
  // than the query string, where they would be logged by the web server.
  function api(method, url, body, cb, pw) {
    var x = new XMLHttpRequest();
    x.onload = function () {
      if (x.status === 403) {
        var p = window.prompt('Control password:');
        if (p === null) { cb && cb(null, 403); return; }
        try { sessionStorage.setItem('sigmodPw', p); } catch (e) {}
        api(method, url, body, cb, p);
        return;
      }
      var d = null;
      try { d = JSON.parse(x.responseText); } catch (e) {}
      cb && cb(d, x.status);
    };
    x.onerror = function () { cb && cb(null, 0); };
    x.open(method, url + (url.indexOf('?') < 0 ? '?' : '&') + 't=' + (new Date()).getTime(), true);
    var use = (pw != null) ? pw : storedPw();
    if (use) x.setRequestHeader('X-Auth', use);
    x.send(body || null);
  }

  function esc(t) { return String(t == null ? '' : t).replace(/[&<>"]/g, function (c) {
    return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]; }); }

  function renderKeys(list) {
    var host = document.getElementById('sigmodKeys');
    if (!host) return;
    if (!list || !list.length) { host.innerHTML = '<div class="content-label">No keys installed.</div>'; return; }
    var h = '';
    for (var i = 0; i < list.length; i++) {
      var k = list[i];
      h += '<div class="sigmod-key">' +
             '<div><div class="kt">' + esc(k.comment || '(no comment)') + '</div>' +
             '<div class="kf">' + esc(k.type) + '  ' + esc(k.fp) + '</div></div>' +
             '<span class="sigmod-btn danger sigmod-revoke" data-i="' + k.i + '">Revoke</span>' +
           '</div>';
    }
    host.innerHTML = h;
    var btns = host.getElementsByClassName('sigmod-revoke');
    for (var j = 0; j < btns.length; j++) {
      btns[j].onclick = function () {
        var n = this.getAttribute('data-i');
        if (!window.confirm('Revoke this key? Anything using it loses SSH access.')) return;
        api('GET', CGI_KEYS + '?action=revoke&i=' + n, null, function (d) {
          if (d && d.error) window.alert(d.error);
          loadKeys();
        });
      };
    }
  }

  function loadKeys() {
    var host = document.getElementById('sigmodKeys');
    if (!host) return;
    api('GET', CGI_KEYS + '?action=list', null, function (d, st) {
      if (st === 403 || st === 503) {
        host.innerHTML = '<div class="content-label">' +
          (st === 503 ? 'Set a control password first (/etc/signalmod.pw).' : 'Locked.') + '</div>';
        return;
      }
      renderKeys(d);
    });
  }

  function addKey() {
    var k = window.prompt('Paste an SSH public key (ssh-ed25519 / ssh-rsa ...):');
    if (!k) return;
    api('POST', CGI_KEYS + '?action=add', k, function (d) {
      if (d && d.error) window.alert('Rejected: ' + d.error);
      loadKeys();
    });
  }

  function changePw() {
    var a = window.prompt('New control password (at least 8 characters):');
    if (!a) return;
    var b = window.prompt('Repeat it:');
    if (a !== b) { window.alert('They did not match. Nothing changed.'); return; }
    api('POST', CGI_CTL + '?action=setpw', a, function (d) {
      if (d && d.ok) {
        try { sessionStorage.setItem('sigmodPw', a); } catch (e) {}
        window.alert('Control password changed.');
      } else { window.alert((d && d.error) || 'Change failed.'); }
    });
  }

  function isMutation(a) { return /_on$|_off$/.test(a) || a === 'reboot'; }
  function storedPw() { try { return sessionStorage.getItem('sigmodPw'); } catch (e) { return null; } }

  // Sends the control password (X-Auth) on state-changing actions. If the server
  // requires auth (403) and we have no/incorrect password, prompt once and retry.
  function ctl(action, cb, pw) {
    var x = new XMLHttpRequest();
    x.onload = function () {
      if (x.status === 403) {
        var p = window.prompt('Control password:');
        if (p === null) { cb && cb({ error: 'auth' }); return; }
        try { sessionStorage.setItem('sigmodPw', p); } catch (e) {}
        ctl(action, cb, p);            // retry with the entered password
        return;
      }
      try { cb && cb(JSON.parse(x.responseText)); } catch (e) { cb && cb({}); }
    };
    x.onerror = function () { cb && cb({}); };
    x.open('GET', CGI_CTL + '?action=' + action + '&t=' + (new Date()).getTime(), true);
    var use = (pw != null) ? pw : storedPw();
    if (isMutation(action) && use) x.setRequestHeader('X-Auth', use);
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

    var svc = function (btnId, pillId, name) {
      var b = document.getElementById(btnId);
      if (!b) return;
      b.onclick = function () {
        var on = document.getElementById(pillId).textContent === 'ON';
        if (!on && !window.confirm('Start ' + name + ' with full filesystem access on the LAN (192.168.0.1)? Turn it off when done.')) return;
        setPill(pillId, '...');
        ctl(name.toLowerCase() + (on ? '_off' : '_on'), function (d) {
          setPill(pillId, d[name.toLowerCase()] || (on ? 'off' : 'on'));
        });
      };
    };
    svc('btnFtp', 'pillFtp', 'FTP');
    svc('btnTelnet', 'pillTelnet', 'Telnet');

    var wifi = document.getElementById('btnWifi');
    var sv = document.getElementById('btnSaver');
    if (sv) sv.onclick = function () {
      var on = document.getElementById('pillSaver').textContent === 'ON';
      ctl(on ? 'saver_off' : 'saver_on', function (d) {
        setPill('pillSaver', d.saver || (on ? 'off' : 'on'));
        applySaverCadence();
      });
    };

    if (wifi) wifi.onclick = function () {
      var on = document.getElementById('pillWifi').textContent === 'ON';
      if (on && !window.confirm('Turn Wi-Fi OFF? Any devices on the router\'s Wi-Fi (including this one, if you\'re on it) will disconnect. Reach it over USB to turn it back on.')) return;
      setPill('pillWifi', '...');
      ctl(on ? 'wifi_off' : 'wifi_on', function (d) { setPill('pillWifi', d.wifi || (on ? 'off' : 'on')); });
    };
  }

  // RSRP sparkline. Fixed -120..-60 dBm scale so the shape means the same thing
  // every time you look at it; an auto-scaled sparkline makes a flat-but-weak
  // signal look identical to a flat-but-strong one.
  function drawSpark(csv) {
    var host = document.getElementById('spSpark');
    if (!host) return;
    var raw = (csv || '').split(',');
    var v = [];
    for (var i = 0; i < raw.length; i++) {
      var n = parseFloat(raw[i]);
      if (!isNaN(n)) v.push(n);
    }
    if (v.length < 2) { host.innerHTML = '<span class="sk">collecting…</span>'; return; }
    var W = 260, H = 34, LO = -120, HI = -60;
    var pts = [];
    for (var j = 0; j < v.length; j++) {
      var y = (v[j] - LO) / (HI - LO);
      if (y < 0) y = 0; if (y > 1) y = 1;
      pts.push(((j / (v.length - 1)) * W).toFixed(1) + ',' + ((1 - y) * H).toFixed(1));
    }
    var last = v[v.length - 1];
    var col = last >= -85 ? '#34d399' : last >= -100 ? '#fbbf24' : '#f87171';
    host.innerHTML =
      '<svg viewBox="0 0 ' + W + ' ' + H + '" preserveAspectRatio="none" ' +
        'style="width:100%;height:' + H + 'px;display:block">' +
        '<polyline points="' + pts.join(' ') + '" fill="none" stroke="' + col +
        '" stroke-width="1.5" stroke-linejoin="round" stroke-linecap="round"/>' +
      '</svg>' +
      '<div class="sk">' + Math.min.apply(null, v).toFixed(0) + ' to ' +
        Math.max.apply(null, v).toFixed(0) + ' dBm · ' + v.length + ' samples</div>';
  }

  function fetchHist() {
    if (!document.getElementById('spSpark')) return;
    var x = new XMLHttpRequest();
    x.onload = function () { try { drawSpark(x.responseText); } catch (e) {} };
    x.open('GET', CGI_HIST + '?t=' + (new Date()).getTime(), true);
    x.send();
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
    set('spCell', (function () {
      if (!last.cellid) return '—';
      var n = parseInt(last.cellid, 16);
      if (isNaN(n)) return last.cellid;
      return last.cellid + ' (eNB ' + Math.floor(n / 256) + '.' + (n % 256) + ')';
    })());
    set('spTac', last.tac || '—');
    set('abIccid', last.iccid || '—');
    set('abSpn', last.spn || '—');
  }

  /* ==================================================================== *
   * Main loop                                                            *
   * ==================================================================== */
  // Rebrand the device name shown next to the TP-LINK logo (login header).
  function ensureBranding() {
    try {
      var dn = document.getElementById('deviceName');
      if (dn && dn.textContent !== MODEL) dn.textContent = MODEL;
    } catch (e) {}
  }


  /* ==================================================================== *
   * Drag-and-drop tile arrangement                                       *
   *                                                                      *
   * The firmware rebuilds its own DOM, and it keeps the stock sections in
   * a #statusContent wrapper while the mod's cards sit directly under
   * .statusPage. To reorder freely they all have to share one flow, so the
   * stock sections are REPARENTED next to ours. Reparenting preserves the
   * nodes and their ids, so the firmware's own updates keep landing; we
   * never recreate or copy its elements. Everything here is idempotent and
   * re-applied on each tick, because a firmware re-render undoes it.
   * ==================================================================== */
  var TILES = [
    { k: 'conn',   sel: '.connectionSection' },
    { k: 'wifi',   sel: '.wifiSection' },
    { k: 'stats',  sel: '.statisticSection' },
    { k: 'system', sel: '#sigmodPanel' },
    { k: 'ctl',    sel: '#sigmodCtl' },
    { k: 'hw',     sel: '#sigmodHw' },
    { k: 'sec',    sel: '#sigmodSec' },
    { k: 'about',  sel: '#sigmodAbout' }
  ];
  var ORDER_KEY = 'sigmodTileOrder';
  var tileW = {};   // key -> column span (integer)
  var tileH = {};   // key -> pixel min-height, or undefined for automatic

  function gridInfo(host) {
    var cs = getComputedStyle(host);
    var tracks = cs.gridTemplateColumns.split(' ').filter(function (x) { return x; });
    var gap = parseFloat(cs.columnGap) || 12;
    var tw = tracks.length ? parseFloat(tracks[0]) : 300;
    return { n: tracks.length || 1, gap: gap, tw: tw };
  }

  function applySize(el, k) {
    var w = tileW[k], h = tileH[k];
    el.style.gridColumn = (w && w > 1) ? ('span ' + w) : '';
    el.style.minHeight = h ? (h + 'px') : '';
  }

  function encodeLayout(keys) {
    return keys.map(function (k) {
      var w = tileW[k] || 1, h = tileH[k];
      if (h) return k + ':' + w + ':' + h;
      if (w > 1) return k + ':' + w;
      return k;
    }).join(',');
  }

  function decodeLayout(str) {
    var keys = [];
    (str || '').split(',').forEach(function (part) {
      if (!part) return;
      var b = part.split(':');
      keys.push(b[0]);
      if (b[1]) { var w = parseInt(b[1], 10); if (w >= 1 && w <= 9) tileW[b[0]] = w; }
      if (b[2]) { var h = parseInt(b[2], 10); if (h >= 80 && h <= 4000) tileH[b[0]] = h; }
    });
    return keys;
  }

  // A grip in the bottom-right corner. Dragging it sets how many grid columns
  // the card spans and its minimum height. Pointer events rather than HTML5
  // drag, so it also works by touch, and the card's own drag is disabled while
  // resizing so the two gestures cannot fight.
  function addGrip(el, key) {
    if (el.querySelector('.sigmod-grip')) return;
    var g = document.createElement('span');
    g.className = 'sigmod-grip';
    g.title = 'Drag to resize';
    g.setAttribute('draggable', 'false');
    el.appendChild(g);

    var host = null, info = null, startH = 0;
    function move(e) {
      if (!host) return;
      var r = el.getBoundingClientRect();
      var want = Math.round((e.clientX - r.left + info.gap) / (info.tw + info.gap));
      if (want < 1) want = 1;
      if (want > info.n) want = info.n;
      tileW[key] = want;
      var h = Math.round(e.clientY - r.top);
      tileH[key] = (h > 120) ? h : undefined;
      applySize(el, key);
      e.preventDefault();
    }
    function up() {
      if (!host) return;
      document.removeEventListener('pointermove', move, true);
      document.removeEventListener('pointerup', up, true);
      el.setAttribute('draggable', 'true');
      el.classList.remove('sigmod-resizing');
      saveOrder(currentOrder(host));
      host = null;
    }
    g.addEventListener('pointerdown', function (e) {
      host = document.querySelector('.statusPage');
      if (!host) return;
      info = gridInfo(host);
      startH = el.getBoundingClientRect().height;
      el.setAttribute('draggable', 'false');   // stop the reorder drag firing
      el.classList.add('sigmod-resizing');
      document.addEventListener('pointermove', move, true);
      document.addEventListener('pointerup', up, true);
      e.preventDefault();
      e.stopPropagation();
    }, false);
  }

  // The layout lives on the ROUTER, so it follows the device rather than
  // whichever browser last touched it. localStorage is a cache only, so the page
  // can arrange itself immediately instead of flashing the default order.
  var serverOrder = null;

  function savedOrder() {
    if (serverOrder && serverOrder.length) return serverOrder;
    try {
      var v = JSON.parse(localStorage.getItem(ORDER_KEY));
      return (v && v.length) ? v : null;
    } catch (e) { return null; }
  }

  function loadOrderFromDevice() {
    var x = new XMLHttpRequest();
    x.onload = function () {
      try {
        var d = JSON.parse(x.responseText);
        if (d && d.order) {
          var arr = decodeLayout(d.order);
          if (arr.length) {
            serverOrder = arr;
            try { localStorage.setItem(ORDER_KEY, JSON.stringify(arr)); } catch (e) {}
            arrangeTiles();
          }
        }
      } catch (e) {}
    };
    x.open('GET', CGI_TILES + '?t=' + (new Date()).getTime(), true);
    x.send();
  }

  function saveOrder(keys) {
    serverOrder = keys;
    try { localStorage.setItem(ORDER_KEY, JSON.stringify(keys)); } catch (e) {}
    api('POST', CGI_TILES, encodeLayout(keys), function (d, st) {
      if (st === 503) window.alert('Layout not saved to the router: set a control password first (/etc/signalmod.pw).');
      else if (d && d.error) window.alert('Layout not saved: ' + d.error);
    });
  }

  function tileEl(t) { try { return document.querySelector(t.sel); } catch (e) { return null; } }

  function currentOrder(host) {
    var out = [];
    for (var i = 0; i < host.children.length; i++) {
      var k = host.children[i].getAttribute && host.children[i].getAttribute('data-tile');
      if (k) out.push(k);
    }
    return out;
  }

  function arrangeTiles() {
    var host = document.querySelector('.statusPage');
    if (!host) return;
    var want = savedOrder() || TILES.map(function (t) { return t.k; });
    TILES.forEach(function (t) { if (want.indexOf(t.k) < 0) want.push(t.k); });

    // Resolve to the tiles that actually exist right now.
    var live = [];
    want.forEach(function (k) {
      for (var i = 0; i < TILES.length; i++) {
        if (TILES[i].k !== k) continue;
        var el = tileEl(TILES[i]);
        if (el) live.push({ k: k, el: el });
      }
    });
    if (!live.length) return;

    // Only touch the DOM when something is actually out of place. Rearranging
    // on every tick would fight the user mid-drag and flicker the page.
    var ok = true;
    for (var i = 0; i < live.length; i++) {
      if (live[i].el.parentNode !== host) { ok = false; break; }
    }
    if (ok && currentOrder(host).join(',') !== live.map(function (x) { return x.k; }).join(',')) ok = false;
    if (ok) {
      live.forEach(function (x) { addGrip(x.el, x.k); applySize(x.el, x.k); });
      return;
    }

    live.forEach(function (x) {
      if (!x.el.getAttribute('data-tile')) { x.el.setAttribute('data-tile', x.k); wireTile(x.el); }
      addGrip(x.el, x.k);
      applySize(x.el, x.k);
      host.appendChild(x.el);   // appendChild moves an existing node
    });
  }

  var dragKey = null;
  function wireTile(el) {
    el.setAttribute('draggable', 'true');
    el.classList.add('sigmod-tile');
    el.addEventListener('dragstart', function (e) {
      dragKey = el.getAttribute('data-tile');
      el.classList.add('sigmod-drag');
      try { e.dataTransfer.effectAllowed = 'move'; e.dataTransfer.setData('text/plain', dragKey); } catch (x) {}
    }, false);
    el.addEventListener('dragend', function () {
      dragKey = null;
      el.classList.remove('sigmod-drag');
      var host = document.querySelector('.statusPage');
      var tiles = host ? host.querySelectorAll('.sigmod-over') : [];
      for (var i = 0; i < tiles.length; i++) tiles[i].classList.remove('sigmod-over');
      if (host) saveOrder(currentOrder(host));
    }, false);
    el.addEventListener('dragover', function (e) {
      if (!dragKey || el.getAttribute('data-tile') === dragKey) return;
      e.preventDefault();
      el.classList.add('sigmod-over');
      var host = el.parentNode;
      var src = host.querySelector('[data-tile="' + dragKey + '"]');
      if (!src || src === el) return;
      // insert before or after depending on which half of the tile we are over
      var r = el.getBoundingClientRect();
      var after = (e.clientY - r.top) > r.height / 2;
      host.insertBefore(src, after ? el.nextSibling : el);
    }, false);
    el.addEventListener('dragleave', function () { el.classList.remove('sigmod-over'); }, false);
    el.addEventListener('drop', function (e) { e.preventDefault(); el.classList.remove('sigmod-over'); }, false);
  }

  function resetTileOrder() {
    serverOrder = null;
    try { localStorage.removeItem(ORDER_KEY); } catch (e) {}
    tileW = {}; tileH = {};
    TILES.forEach(function (t) { var el = tileEl(t); if (el) { el.style.gridColumn = ''; el.style.minHeight = ''; } });
    api('POST', CGI_TILES, TILES.map(function (t) { return t.k; }).join(','), function () {});
    var host = document.querySelector('.statusPage');
    if (!host) return;
    TILES.forEach(function (t) { var el = tileEl(t); if (el) host.appendChild(el); });
  }

  function tick() {
    try { ensureDarkTheme(); } catch (e) {}
    try { ensureBranding(); } catch (e) {}
    try { ensureIcons(); } catch (e) {}
    try { injectSignalRows(); } catch (e) {}
    try { injectPanels(); } catch (e) {}
    try { arrangeTiles(); } catch (e) {}
    try { fetchSignal(); } catch (e) {}
  }

  // Polling cadence. When you view this page over Tailscale from abroad, the
  // page's own polling crosses the metered link, so data saver has to slow the
  // browser down too, not just the device. Timers are rebuilt rather than
  // adjusted because setInterval has no way to change period.
  var saverOn = false;
  var tSig = null, tCtl = null, tHist = null;

  function applySaverCadence() {
    var sig  = saverOn ? 30000  : 1500;
    var ctlP = saverOn ? 120000 : 6000;
    var hist = saverOn ? 600000 : 60000;
    if (tSig)  clearInterval(tSig);
    if (tCtl)  clearInterval(tCtl);
    if (tHist) clearInterval(tHist);
    tSig  = setInterval(tick, sig);
    tCtl  = setInterval(function () { if (document.getElementById('sigmodPanel')) refreshCtlState(); }, ctlP);
    tHist = setInterval(fetchHist, hist);
  }

  ensureDarkTheme();
  loadOrderFromDevice();
  applySaverCadence();
  // Refresh control/system state a bit less often than signal.


  var quick = [50, 150, 300, 500, 800, 1200, 1800, 2500];
  for (var i = 0; i < quick.length; i++) { setTimeout(tick, quick[i]); }
  if (document.addEventListener) document.addEventListener('DOMContentLoaded', tick, false);
  if (window.addEventListener) window.addEventListener('load', tick, false);
})();
