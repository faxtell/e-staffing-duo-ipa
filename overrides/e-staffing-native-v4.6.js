// ==UserScript==
// @name         e-staffing Native iOS UI (Duo v2.2)
// @namespace    https://m.e-staffing.ne.jp/
// @version      4.6.1
// @description  Hybrid route identification, Apple-like UI, HHMM now buttons, Duo wide-calendar close view.
// @match        https://m.e-staffing.ne.jp/s/*
// @run-at       document-end
// @grant        none
// ==/UserScript==

(() => {
  'use strict';
  // v4.4: Return to v4.1's synchronous document-end initialization.
  // The v4.3 prepaint cloak and DOMContentLoaded wait caused regressions on iPhone Safari.
  if (window.__etcNativeV4 || !document.body) return;
  window.__etcNativeV4 = true;

  // SECURITY / FUNCTIONALITY
  // No automatic attendance submission or application. Saved-account login is managed by the native credential bridge.
  // Existing input nodes and Struts forms remain in their original form.
  // Never persist etcToken, login IDs or passwords to local/session storage.
  // Disable older e-staffing Userscripts first (v3 included).

  const $ = (s, root = document) => root.querySelector(s);
  const $$ = (s, root = document) => Array.from(root.querySelectorAll(s));
  const tidy = s => String(s ?? '').replace(/\s+/g, ' ').trim();
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const THEME = 'etc-native-v4-theme'; // carry over the v4/v4.1 appearance preference
  const icons = {
    house: '<path d="m3 10 9-7 9 7v10a1 1 0 0 1-1 1h-5v-7H9v7H4a1 1 0 0 1-1-1z"/>',
    calendar: '<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M7 3v4M17 3v4M3 10h18M8 14h2M14 14h2"/>',
    check: '<rect x="5" y="3" width="14" height="18" rx="2"/><path d="m8 12 3 3 5-6M9 7h6"/>',
    settings: '<circle cx="12" cy="12" r="3"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3M4.9 4.9 7 7m10 10 2.1 2.1m0-14.2L17 7M7 17l-2.1 2.1"/>',
    chevron: '<path d="m9 6 6 6-6 6"/>',
    back: '<path d="m15 18-6-6 6-6"/>',
    building: '<rect x="3" y="3" width="18" height="18" rx="2"/><path d="M8 7h2m4 0h2M8 11h2m4 0h2M9 21v-5h6v5"/>',
    clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l4 2"/>',
    shield: '<path d="M12 2 4 6v6c0 5 3 8 8 10 5-2 8-5 8-10V6z"/><path d="m9 12 2 2 4-4"/>',
    lock: '<rect x="5" y="10" width="14" height="11" rx="2"/><path d="M8 10V7a4 4 0 0 1 8 0v3"/>',
    mail: '<rect x="3" y="5" width="18" height="14" rx="2"/><path d="m4 7 8 6 8-6"/>',
    x: '<path d="M6 6l12 12M18 6 6 18"/>',
    info: '<circle cx="12" cy="12" r="10"/><path d="M12 11v6M12 7h.01"/>',
    arrow: '<path d="M5 12h14M13 6l6 6-6 6"/>'
  };
  function svg(k, size = 22) { return `<svg aria-hidden="true" viewBox="0 0 24 24" width="${size}" height="${size}" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round">${icons[k] || icons.info}</svg>`; }
  function theme() { try { return localStorage.getItem(THEME) || 'system'; } catch { return 'system'; } }
  function applyTheme(mode) { document.body.dataset.etcNativeTheme = mode; try { localStorage.setItem(THEME, mode); } catch {} }
  function token() {
    return $('form input[name="etcToken"]')?.value || $('input[name="etcToken"]')?.value || new URL(location.href).searchParams.get('etcToken') || '';
  }
  function officialLink(path) {
    const link = $$('a[href]').find(a => { try { const u = new URL(a.href); return u.origin === location.origin && u.pathname.replace(/\/$/, '') === path.replace(/\/$/, '') && !u.hash; } catch { return false; } });
    if (link) return link.href;
    const u = new URL(path, location.origin);
    if (token()) u.searchParams.set('etcToken', token());
    return u.href;
  }
  const routes = {
    home: '/s/TMSMNU01/',
    daily: '/s/TMSMNU01/daily',
    close: '/s/TMSMNU01/close',
    password: '/s/TMSPRF02/',
    email: '/s/TMSPRF01/'
  };
  function page() {
    // Most server pages have a reliable URL. Check them first to avoid any DOM wait.
    // Exception: POST /s/TMSLGN01/ also returns the staff menu after a successful login.
    const path = location.pathname;
    if (/\/TMSMNU01\/?$/.test(path)) return 'home';
    if (/\/TMSMNU01\/daily\/?$/.test(path)) return 'daily';
    if (/\/TMSMNU01\/close\/?$/.test(path)) return 'close';
    if (/\/TMSPRF0[12]\//.test(path)) return 'settings';

    // The SAME login URL is used before and after sign-in. Never infer page
    // identity from this address alone; use the returned Struts form name.
    if (/\/TMSLGN01\/?$/.test(path)) {
      if ($('form[name="TMSMNU01ActionForm"]')) return 'home';
      if ($('form[name="TMSLGN01ActionForm"]')) return 'login';
      return 'login';
    }

    // Form-based fallbacks for postbacks whose endpoints aren't menu links.
    if ($('form[name="TMSINP01ActionForm"]')) return 'daily';
    if ($('form[name="TMSINP02ActionForm"]')) return 'close';
    if ($('form[name="TMSMNU01ActionForm"]')) return 'home';
    if ($('form[name="TMSLGN01ActionForm"]')) return 'login';
    return 'other';
  }
  function viewport() {
    let m = $('meta[name="viewport"]');
    if (!m) { m = document.createElement('meta'); m.name = 'viewport'; document.head.appendChild(m); }
    m.content = 'width=device-width, initial-scale=1, viewport-fit=cover';
  }
  function addCSS() {
    const style = document.createElement('style');
    style.id = 'etc-native-v4-css';
    style.textContent = `
      body.etc-native-v4 {
        --e-bg:#f2f2f7;--e-card:#ffffff;--e-ink:#1c1c1e;--e-muted:#6e6e73;--e-line:rgba(60,60,67,.13);
        --e-blue:#007aff;--e-blue-wash:rgba(0,122,255,.1);--e-soft:#f2f2f7;
        --e-green:#34c759;--e-red:#ff3b30;--e-neutral:#8e8e93;
        margin:0!important;padding:0 0 calc(82px + env(safe-area-inset-bottom,0px))!important;
        min-height:100dvh;background:var(--e-bg)!important;color:var(--e-ink)!important;
        font-family:-apple-system,BlinkMacSystemFont,'SF Pro Text','Hiragino Kaku Gothic ProN',sans-serif!important;
        font-size:15px!important;line-height:1.45!important;-webkit-font-smoothing:antialiased;
      }
      body.etc-native-v4[data-etc-native-theme=dark]{--e-bg:#000;--e-card:#1c1c1e;--e-ink:#f5f5f7;--e-muted:#a1a1aa;--e-line:rgba(255,255,255,.16);--e-blue:#0a84ff;--e-blue-wash:rgba(10,132,255,.18);--e-soft:#2c2c2e;color-scheme:dark;}
      @media(prefers-color-scheme:dark){body.etc-native-v4[data-etc-native-theme=system]{--e-bg:#000;--e-card:#1c1c1e;--e-ink:#f5f5f7;--e-muted:#a1a1aa;--e-line:rgba(255,255,255,.16);--e-blue:#0a84ff;--e-blue-wash:rgba(10,132,255,.18);--e-soft:#2c2c2e;color-scheme:dark;}}
      body.etc-native-v4 *,body.etc-native-v4 *::before,body.etc-native-v4 *::after{box-sizing:border-box;}
      body.etc-native-v4 a{color:var(--e-blue);text-decoration:none;-webkit-tap-highlight-color:transparent;}
      body.etc-native-v4 input,body.etc-native-v4 select,body.etc-native-v4 textarea,body.etc-native-v4 button{font-family:inherit!important;}
      body.etc-native-v4 input[type=text],body.etc-native-v4 input[type=password],body.etc-native-v4 input[type=email],body.etc-native-v4 input[type=number],body.etc-native-v4 select,body.etc-native-v4 textarea{
        min-height:44px;border-radius:12px;border:1px solid var(--e-line);background:var(--e-soft);
        color:var(--e-ink);padding:9px 12px;font-size:16px!important;max-width:100%;outline-offset:2px;
      }
      body.etc-native-v4 input[type=checkbox],body.etc-native-v4 input[type=radio]{accent-color:var(--e-blue);width:20px;height:20px;vertical-align:middle;}
      body.etc-native-v4 input[type=submit],body.etc-native-v4 button.etc-action{
        min-height:43px;border-radius:12px;border:0;padding:9px 15px;max-width:100%;font-size:15px!important;
        font-weight:650;color:var(--e-blue);background:var(--e-blue-wash);-webkit-appearance:none;appearance:none;
      }
      body.etc-native-v4 input[type=submit]:active,body.etc-native-v4 a:active{opacity:.73;}
      body.etc-native-v4 .etc-primary,input.etc-primary{background:var(--e-blue)!important;color:white!important;min-height:50px!important;padding:11px 24px!important;font-weight:680!important;}
      body.etc-native-v4 .etc-secondary{background:var(--e-soft)!important;color:var(--e-blue)!important;min-height:50px!important;}
      body.etc-native-v4 .btnLink{background:none!important;border:0!important;box-shadow:none!important;color:var(--e-blue)!important;min-height:34px!important;padding:4px 1px!important;font-size:14px!important;font-weight:500!important;}
      body.etc-native-v4 .etc-legacy-logo,body.etc-native-v4 .etc-legacy-banner{display:none!important;}
      body.etc-native-v4 hr[style*="FF6600"],body.etc-native-v4 hr[style*="ff6600"]{display:none!important;}
      body.etc-native-v4 .subHeader{background:transparent!important;color:var(--e-muted)!important;border:0!important;}
      body.etc-native-v4 .subTh{background:var(--e-soft)!important;color:var(--e-muted)!important;border:0!important;}
      body.etc-native-v4 .subTd{background:var(--e-card)!important;color:var(--e-ink)!important;}
      body.etc-native-v4 tr[style*="background-color:#efefef"],body.etc-native-v4 tr[style*="background-color:#FFFFFF"]{background:transparent!important;}
      .etc-native-header{margin:0 auto;max-width:690px;padding:20px 20px 14px;display:flex;gap:14px;align-items:center;}
      .etc-native-header .etc-nav-back{display:flex;align-items:center;color:var(--e-blue);justify-content:center;width:23px;height:34px;flex:none;}
      .etc-header-group{min-width:0;}
      .etc-header-eyebrow{font-size:12px;color:var(--e-muted);font-weight:600;letter-spacing:.04em;}
      .etc-header-title{font-size:33px;margin:0!important;font-weight:760;letter-spacing:-.065em;line-height:1.12;color:var(--e-ink);}
      .etc-content{max-width:690px;margin:0 auto;padding:0 16px 30px;}
      .etc-caption{font-size:12px;font-weight:650;color:var(--e-muted);padding:0 10px;margin:19px 0 8px;}
      .etc-card{background:var(--e-card);border:1px solid var(--e-line);border-radius:17px;overflow:hidden;margin-bottom:13px;}
      .etc-card-pad{padding:16px;}
      .etc-card-title{font-size:15px;font-weight:720;letter-spacing:-.02em;margin:0 0 8px;color:var(--e-ink);}
      .etc-card-hint{font-size:12px;color:var(--e-muted);margin:5px 0 13px;}
      .etc-row-link{display:flex;gap:12px;align-items:center;padding:14px 16px!important;color:var(--e-ink)!important;min-height:65px;border-bottom:1px solid var(--e-line);}
      .etc-row-link:last-child{border-bottom:0;}
      .etc-row-link .etc-row-symbol{display:grid;place-items:center;color:white;background:var(--e-blue);width:37px;height:37px;border-radius:11px;flex:none;}
      .etc-row-link .etc-row-info{flex:1;line-height:1.25;}
      .etc-row-link .etc-row-info strong{display:block;font-size:16px;font-weight:650;}
      .etc-row-link .etc-row-info small{display:block;color:var(--e-muted);margin-top:4px;font-size:12px;}
      .etc-row-link .etc-row-chevron{color:var(--e-muted);display:flex;}
      .etc-person-name{font-size:29px;font-weight:760;letter-spacing:-.05em;margin:3px 0;}
      .etc-org-name{font-weight:650;font-size:16px;}
      .etc-org-detail{font-size:13px;color:var(--e-muted);margin-top:5px;}
      .etc-period{font-weight:650;font-size:14px;color:var(--e-ink);padding:10px 13px;background:var(--e-card);border:1px solid var(--e-line);border-radius:12px;margin:0 0 12px!important;}
      .etc-today-status{background:var(--e-card);border:1px solid var(--e-line);border-radius:16px;padding:15px;margin-bottom:14px;display:flex;justify-content:space-between;gap:10px;align-items:center;font-size:16px;font-weight:680;}
      .etc-today-status .etc-chip{border-radius:999px;font-size:12px;font-weight:700;color:var(--e-red);background:rgba(255,59,48,.09);padding:5px 10px;white-space:nowrap;}
      .etc-form-card{background:var(--e-card);border:1px solid var(--e-line);border-radius:17px;padding:15px;margin:0 0 14px;overflow:hidden;}
      .etc-form-card .etc-card-title{margin-bottom:12px;}
      form.etc-enhanced-form{width:100%;max-width:690px;margin:0 auto;padding:0 16px 28px;font-size:15px!important;}
      .etc-form-card table{width:100%!important;margin:0!important;border:0!important;border-collapse:collapse!important;background:transparent!important;}
      .etc-form-card table td,.etc-form-card table th{border:0!important;background:transparent!important;color:var(--e-ink)!important;}
      .etc-form-card table.etc-fields td{word-break:normal;}
      .etc-form-card table.etc-fields>tbody>tr{display:grid;grid-template-columns:minmax(0,1fr);border-bottom:1px solid var(--e-line);padding:12px 0;gap:8px;align-items:center;}
      .etc-form-card table.etc-fields>tbody>tr:first-child{padding-top:2px;}
      .etc-form-card table.etc-fields>tbody>tr:last-child{border:0;padding-bottom:0;}
      .etc-form-card table.etc-fields>tbody>tr>td{padding:0!important;text-align:left!important;width:auto!important;min-width:0;}
      .etc-form-card table.etc-fields>tbody>tr>td:first-child{font-size:13px!important;color:var(--e-muted)!important;font-weight:650;}
      .etc-form-card table.etc-fields>tbody>tr>td:last-child:has(input[type=text]){font-size:0!important;}
      .etc-form-card table.etc-fields>tbody>tr>td:last-child input[type=text]{font-size:18px!important;letter-spacing:.025em;text-align:center;font-variant-numeric:tabular-nums;width:122px!important;max-width:100%;}
      .etc-form-card table.etc-fields>tbody>tr:has(input[name=startTime]){grid-template-columns:1fr 125px;}
      .etc-form-card table.etc-fields>tbody>tr:has(input[name=startTime])>td:first-child{grid-column:1/-1;}
      .etc-form-card table.etc-fields>tbody>tr:has(input[name=endTime])>td:last-child{text-align:right!important;}
      .etc-form-card table.etc-fields>tbody>tr:has(input[name=startTime])>td:nth-child(2){display:flex;gap:6px;}
      .etc-form-card table.etc-fields>tbody>tr:has(input[name=startTime])>td:nth-child(2) input{flex:1;min-width:0;padding:7px 3px;font-size:13px!important;}
      .etc-form-card table.etc-fields>tbody>tr:has(input[name=startTime])>td:last-child{text-align:right!important;}
      .etc-form-card table.etc-details>tbody>tr{display:grid;grid-template-columns:minmax(0,1fr) auto;align-items:center;gap:12px;border-bottom:1px solid var(--e-line);min-height:60px;padding:8px 0;}
      .etc-form-card table.etc-details>tbody>tr:last-child{border:0;}
      .etc-form-card table.etc-details td{font-size:14px!important;width:auto!important;padding:0!important;}
      .etc-form-card table.etc-details td:last-child{text-align:right!important;font-size:0!important;}
      .etc-form-card table.etc-details td:last-child input[type=text]{font-size:17px!important;width:102px!important;text-align:center;font-variant-numeric:tabular-nums;}
      .etc-form-card table.etc-details td:last-child input[name=remark]{width:178px!important;text-align:left;font-size:15px!important;}
      .etc-form-card table.etc-details td:last-child input.btnLink{font-size:14px!important;}
      .etc-form-card table.etc-fields table.tableRight{width:100%!important;margin:0!important;border:0!important;}
      .etc-form-card table.etc-fields table.tableRight td{padding:4px 0!important;font-size:15px!important;}
      .etc-form-card table.etc-fields table.tableRight tr{background:none!important;}
      .etc-apply-controls{display:flex!important;justify-content:center;gap:10px;margin:8px 0 0!important;padding:0!important;}
      .etc-apply-controls input{min-width:110px;}
      .etc-action-extras{display:flex;flex-wrap:wrap;gap:12px;margin:12px 3px;}
      .etc-day-pager{display:grid;grid-template-columns:1fr 1fr;gap:10px;width:100%;}
      .etc-day-pager a{display:flex;align-items:center;justify-content:center;background:var(--e-card);border:1px solid var(--e-line);border-radius:13px;min-height:48px;color:var(--e-blue)!important;font-size:15px;font-weight:650;}
      details.etc-collapsible{border:1px solid var(--e-line);border-radius:15px;background:var(--e-card);padding:0 14px;margin:12px 0;overflow:hidden;}
      details.etc-collapsible>summary{list-style:none;padding:14px 2px;font-size:14px;font-weight:680;cursor:pointer;display:flex;justify-content:space-between;}
      details.etc-collapsible>summary::-webkit-details-marker{display:none;}
      details.etc-collapsible>summary::after{content:'⌄';color:var(--e-muted);}
      details.etc-collapsible[open]>summary::after{content:'⌃';}
      .etc-detail-body{padding:0 2px 12px;font-size:13px;line-height:1.55;}
      .etc-detail-body table{width:100%;border-collapse:collapse;}
      .etc-detail-body td{padding:7px 1px;border-bottom:1px solid var(--e-line);}
      .etc-detail-body .subHeader{display:none;}
      .etc-close-stats>tbody{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px;}
      @media (min-width:700px){.etc-close-stats>tbody{grid-template-columns:repeat(var(--etc-stats-cols-wide,4),minmax(0,1fr));}}
      .etc-close-stats>tbody>tr{display:contents;}
      .etc-close-stats>tbody>tr:first-child{display:none;}
      .etc-close-stats>tbody>tr>td{background:var(--e-soft)!important;border:0!important;border-radius:12px;min-height:78px;padding:11px!important;display:flex;flex-direction:column;gap:6px;justify-content:center;text-align:left!important;font-size:19px!important;font-weight:710;color:var(--e-ink)!important;width:auto!important;min-width:0!important;max-width:none!important;white-space:nowrap!important;word-break:keep-all!important;line-break:strict!important;writing-mode:horizontal-tb!important;text-orientation:mixed!important;overflow-wrap:normal!important;}
      .etc-close-stats>tbody>tr>td::before{content:attr(data-label);font-size:12px;color:var(--e-muted);font-weight:600;writing-mode:horizontal-tb!important;}
      .etc-close-stats>tbody>tr>td *{writing-mode:horizontal-tb!important;text-orientation:mixed!important;white-space:nowrap!important;}
      .etc-close-stats>tbody>tr>td:has(input[type=submit]){font-size:14px!important;}
      .etc-close-stats>tbody>tr>td:empty{display:none!important;}
      .etc-close-stats>tbody>tr>td input.btnLink{font-size:14px!important;text-align:left!important;min-height:20px!important;white-space:normal!important;}
      .etc-close-stats>tbody>tr>td:nth-child(4) span{color:var(--e-red)!important;font-size:16px;}
      .etc-notification-box{font-size:14px;line-height:2;}
      .etc-notification-box span{display:inline-block;vertical-align:middle;}
      .etc-notification-box input[type=submit]{vertical-align:middle;}
      .etc-date-list{width:100%!important;border:0!important;border-collapse:separate!important;border-spacing:0 7px!important;}
      .etc-date-list>tbody>tr:first-child{display:none!important;}
      .etc-date-list>tbody>tr:not(:first-child){display:grid!important;grid-template-columns:68px minmax(0,1fr);gap:10px;background:var(--e-soft)!important;padding:12px!important;border-radius:13px;min-height:70px;align-items:center;cursor:pointer;}
      .etc-date-list>tbody>tr>td{border:0!important;background:transparent!important;color:var(--e-ink)!important;padding:0!important;font-size:13px!important;width:auto!important;text-align:left!important;}
      .etc-date-list>tbody>tr>td:first-child{grid-column:1;grid-row:1;align-self:stretch;display:flex;align-items:center;justify-content:center;}
      .etc-date-list>tbody>tr>td:first-child a{display:flex;align-items:center;justify-content:center;width:100%;min-height:44px;border-radius:10px;background:var(--e-card);font-size:15px;font-weight:720;color:var(--e-blue)!important;}
      .etc-date-list>tbody>tr>td:nth-child(5){grid-column:2;grid-row:1;display:flex;flex-direction:column;gap:5px;font-size:17px!important;font-variant-numeric:tabular-nums;font-weight:680;}
      .etc-date-list>tbody>tr>td:nth-child(2),.etc-date-list>tbody>tr>td:nth-child(3),.etc-date-list>tbody>tr>td:nth-child(4),.etc-date-list>tbody>tr>td:nth-child(6),.etc-date-list>tbody>tr>td:nth-child(7){display:none!important;}
      .etc-date-list .etc-record-meta{display:flex;gap:5px;flex-wrap:wrap;font-size:11px;color:var(--e-muted);font-weight:600;font-variant-numeric:normal;}
      .etc-date-list .etc-record-meta span{display:inline-flex;align-items:center;border-radius:5px;padding:2px 6px;background:var(--e-card);}
      .etc-date-list>tbody>tr.etc-holiday{background:color-mix(in srgb,var(--e-blue) 7%,var(--e-card))!important;}
      .etc-date-list .etc-record-empty{font-size:14px;font-weight:540;color:var(--e-muted);}
      .etc-list-hint{font-size:12px;color:var(--e-muted);margin:-2px 0 12px;}
      .etc-date-calendar{display:none;}
      .etc-date-calendar-head{display:flex;align-items:center;justify-content:space-between;margin:0 0 12px;}
      .etc-date-calendar-title{font-size:16px;font-weight:730;}
      .etc-date-calendar-sub{font-size:12px;color:var(--e-muted);}
      .etc-calendar-weekdays,.etc-calendar-grid{display:grid;grid-template-columns:repeat(7,minmax(0,1fr));gap:8px;}
      .etc-calendar-weekdays{margin-bottom:8px;}
      .etc-calendar-weekdays span{font-size:12px;font-weight:700;color:var(--e-muted);text-align:center;padding:0 0 4px;}
      .etc-calendar-weekdays span:first-child{color:var(--e-red);}
      .etc-calendar-day{min-height:108px;border-radius:16px;background:var(--e-soft);border:1px solid transparent;padding:10px;display:flex;flex-direction:column;gap:8px;position:relative;overflow:hidden;}
      .etc-calendar-day.is-outside{opacity:.34;background:transparent;border-color:var(--e-line);}
      .etc-calendar-day.is-disabled{opacity:.55;}
      .etc-calendar-day.is-holiday{background:color-mix(in srgb,var(--e-blue) 10%,var(--e-card));}
      .etc-calendar-day.is-clickable{cursor:pointer;}
      .etc-calendar-day.is-clickable:active{opacity:.8;}
      .etc-calendar-day-number{font-size:19px;font-weight:760;line-height:1;color:var(--e-ink);}
      .etc-calendar-day-week{font-size:11px;color:var(--e-muted);margin-left:4px;}
      .etc-calendar-day-top{display:flex;align-items:baseline;justify-content:space-between;}
      .etc-calendar-time{font-size:15px;font-weight:700;font-variant-numeric:tabular-nums;color:var(--e-ink);}
      .etc-calendar-empty{font-size:13px;color:var(--e-muted);margin-top:auto;}
      .etc-calendar-badges{display:flex;gap:5px;flex-wrap:wrap;margin-top:auto;}
      .etc-calendar-badges span{display:inline-flex;align-items:center;min-height:22px;padding:0 7px;border-radius:8px;background:var(--e-card);font-size:11px;font-weight:650;color:var(--e-muted);}
      @media (min-width:700px){
        .etc-date-list.etc-has-calendar{display:none!important;}
        .etc-date-calendar{display:block;margin-top:8px;}
      }
      /* Duo v2.2: readable summary, no vertical character wrapping at narrow widths */
      .etc-close-stats {table-layout:auto!important;}
      .etc-close-stats>tbody>tr>td {overflow:visible!important;line-height:1.25!important;min-width:0!important;}
      .etc-close-stats>tbody>tr>td::before {white-space:nowrap!important;}
      .etc-close-stats>tbody>tr>td span {display:inline-block;white-space:nowrap!important;}
      .etc-close-stats>tbody>tr>td input.btnLink {white-space:nowrap!important;}
      .etc-close-stats>tbody>tr>td:has(input[name=cloHistory]) {align-items:flex-start;}
      /* Responsive monthly calendar. The original source table stays in the DOM. */
      .etc-date-calendar {display:none;}
      .etc-calendar-panel {margin:8px 0 20px;}
      .etc-calendar-toolbar {display:flex;align-items:center;justify-content:space-between;gap:10px;margin:6px 0 14px;flex-wrap:wrap;}
      .etc-calendar-legend {display:flex;gap:8px 15px;flex-wrap:wrap;color:var(--e-muted);font-size:11px;font-weight:640;}
      .etc-calendar-legend span {display:inline-flex;align-items:center;gap:5px;white-space:nowrap;}
      .etc-calendar-legend i {display:inline-block;width:9px;height:9px;border-radius:4px;flex:none;}
      body.etc-native-v4 button.etc-calendar-jump {display:inline-flex;align-items:center;min-height:32px;background:var(--e-blue-wash);color:var(--e-blue);border:0;border-radius:10px;padding:6px 12px;font-size:12px!important;font-weight:730;white-space:nowrap;}
      .etc-legend-work {background:var(--e-green);}
      .etc-legend-leave {background:#8b78ff;}
      .etc-legend-blank {background:var(--e-neutral);}
      .etc-legend-today {background:var(--e-blue);}
      .etc-calendar-month + .etc-calendar-month {margin-top:24px;padding-top:16px;border-top:1px solid var(--e-line);}
      .etc-calendar-month-title {font-size:16px;font-weight:760;margin:0 0 11px;letter-spacing:-.02em;}
      .etc-calendar-weekdays,.etc-calendar-grid {display:grid;grid-template-columns:repeat(7,minmax(0,1fr));gap:7px;}
      .etc-calendar-weekdays span {text-align:center;font-size:12px;font-weight:760;color:var(--e-muted);padding:0 0 6px;}
      .etc-calendar-weekdays span:first-child {color:#ff6b61;}
      .etc-calendar-weekdays span:last-child {color:var(--e-blue);}
      .etc-calendar-day {min-width:0;min-height:105px;padding:10px 7px 8px;border-radius:13px;display:flex;flex-direction:column;gap:6px;background:var(--e-soft);border:1.5px solid transparent;color:var(--e-ink)!important;text-decoration:none!important;box-shadow:none;}
      .etc-calendar-day.is-other {background:transparent!important;border:1px dashed var(--e-line);opacity:.34;pointer-events:none;}
      .etc-calendar-day.is-disabled {opacity:.5;}
      .etc-calendar-day.is-weekend:not(.is-work):not(.is-leave) {background:color-mix(in srgb,var(--e-soft) 70%,var(--e-bg));}
      .etc-calendar-day.is-work {background:color-mix(in srgb,var(--e-green) 10%,var(--e-card));}
      .etc-calendar-day.is-leave {background:color-mix(in srgb,#8b78ff 14%,var(--e-card));}
      .etc-calendar-day.is-today {border-color:var(--e-blue)!important;box-shadow:0 0 0 1px color-mix(in srgb,var(--e-blue) 35%,transparent);}
      .etc-calendar-day:focus-visible {outline:2px solid var(--e-blue);outline-offset:2px;}
      .etc-calendar-day.is-clickable:active {filter:brightness(.92);}
      .etc-calendar-day-number {font-size:18px;font-weight:770;line-height:1;}
      .etc-calendar-day.is-today .etc-calendar-day-number {color:var(--e-blue);}
      .etc-calendar-day-top {display:flex;justify-content:space-between;align-items:center;}
      .etc-calendar-reference-hint{font-size:12px;color:var(--e-muted);line-height:1.55;margin:10px 0;}
      .etc-calendar-today-indicator {font-size:9px;font-weight:700;color:var(--e-blue);background:var(--e-blue-wash);padding:3px 4px;border-radius:5px;white-space:nowrap;}
      .etc-calendar-time {font-size:13px;font-weight:760;color:var(--e-ink);font-variant-numeric:tabular-nums;letter-spacing:-.01em;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;}
      .etc-calendar-subline {font-size:10px;color:var(--e-muted);font-weight:560;line-height:1.35;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;}
      .etc-calendar-tag {margin-top:auto;display:block;align-self:flex-start;max-width:100%;border-radius:6px;padding:3px 5px;font-size:10px;font-weight:690;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;color:var(--e-muted);background:var(--e-card);}
      .etc-calendar-tag.is-work {color:var(--e-green);}
      .etc-calendar-tag.is-leave {color:#9b8bff;}
      .etc-calendar-tag.is-empty {color:var(--e-muted);}
      .etc-calendar-toggle {display:none;align-items:center;background:var(--e-soft);padding:3px;border-radius:11px;gap:3px;}
      body.etc-native-v4 button.etc-calendar-toggle-btn {appearance:none;border:0;border-radius:9px;padding:7px 12px;min-height:33px;font-size:12px!important;font-weight:680;background:transparent;color:var(--e-muted);}
      body.etc-native-v4 button.etc-calendar-toggle-btn.is-selected {color:var(--e-ink);background:var(--e-card);box-shadow:0 1px 5px rgba(0,0,0,.11);}
      @media(min-width:700px) {
        .etc-calendar-toggle {display:flex;}
        .etc-date-list.etc-has-calendar {display:none!important;}
        .etc-close-calendar-section.etc-calendar-force-list .etc-date-list.etc-has-calendar {display:table!important;}
        .etc-close-calendar-section.etc-calendar-force-list .etc-date-calendar {display:none!important;}
        .etc-close-calendar-section:not(.etc-calendar-force-list) .etc-date-calendar {display:block!important;}
      }
      @media(max-width:699px){
        .etc-close-calendar-section .etc-date-calendar{display:none!important;}
        .etc-close-calendar-section .etc-date-list.etc-has-calendar{display:table!important;}
      }
      @media(min-width:700px) and (max-width:850px) {
        .etc-calendar-day {min-height:100px;padding:8px 5px;}
        .etc-calendar-time {font-size:12px;}
        .etc-calendar-weekdays,.etc-calendar-grid {gap:5px;}
      }
      /* Open Duo can be only ~450 CSS px wide, so use aspect ratio too. */
      @media (min-aspect-ratio:3/5) and (min-width:420px) and (max-width:699px) {
        .etc-close-calendar-section .etc-date-list.etc-has-calendar {display:none!important;}
        .etc-close-calendar-section .etc-date-calendar {display:block!important;}
        .etc-calendar-weekdays,.etc-calendar-grid{gap:3px;}
        .etc-calendar-day {padding:7px 3px 6px;min-height:86px;border-radius:9px;gap:4px;}
        .etc-calendar-day-number {font-size:15px;}
        .etc-calendar-reference-hint{font-size:12px;color:var(--e-muted);line-height:1.55;margin:10px 0;}
      .etc-calendar-today-indicator {display:none;}
        .etc-calendar-time {font-size:10.5px;white-space:normal!important;line-height:1.22;overflow:visible;}
        .etc-calendar-time-start,.etc-calendar-time-end {display:block;white-space:nowrap;}
        .etc-calendar-time-sep {display:none;}
        .etc-calendar-subline {display:none;}
        .etc-calendar-tag {font-size:8px;padding:2px 3px;border-radius:4px;}
        .etc-calendar-month-title {font-size:15px;}
        .etc-calendar-weekdays span {font-size:11px;}
        .etc-calendar-legend {font-size:10px;gap:5px 10px;}
        .etc-calendar-toggle {display:none!important;}
      }
      .etc-form-card table.etc-details tr:has(input[name=advanceRegistered]) td:last-child{font-size:14px!important;}
      form.etc-enhanced-form>hr,form.etc-enhanced-form>br{display:none!important;}
      form.etc-enhanced-form>div:not(.etc-today-status):not(.etc-period):not(.etc-form-card):not(.etc-day-pager):not(.etc-action-extras):not(.etc-collapsible){margin-bottom:9px;}
      .etc-action-extras{padding:12px 15px!important;background:var(--e-card);border:1px solid var(--e-line);border-radius:15px;}
      .etc-action-extras>div,.etc-action-extras>span{display:inline-flex;align-items:center;gap:7px;}
      .etc-list-notice{display:none!important;}
      .etc-skip-original-footer{display:none!important;}
      .etc-nav-bar{z-index:2147482000;position:fixed;bottom:0;left:0;right:0;background:color-mix(in srgb,var(--e-card) 94%,transparent);border-top:1px solid var(--e-line);-webkit-backdrop-filter:blur(23px);backdrop-filter:blur(23px);padding:5px max(6px,env(safe-area-inset-right,0px)) calc(4px + env(safe-area-inset-bottom,0px)) max(6px,env(safe-area-inset-left,0px));}
      .etc-nav-inner{display:grid;grid-template-columns:repeat(4,1fr);max-width:690px;margin:0 auto;}
      .etc-nav-bar a,.etc-nav-bar button{border:0;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:3px;color:var(--e-muted)!important;min-height:52px;text-decoration:none!important;background:transparent!important;padding:5px!important;line-height:1.2;}
      .etc-nav-bar .active{color:var(--e-blue)!important;}
      .etc-nav-label{font-size:10px;font-weight:650;}
      #etc-native-modal{display:none;position:fixed;inset:0;z-index:2147482100;background:rgba(0,0,0,.38);align-items:flex-end;justify-content:center;}
      #etc-native-modal.open{display:flex;}
      .etc-sheet{width:100%;max-width:690px;max-height:85dvh;overflow:auto;background:var(--e-bg);border-radius:23px 23px 0 0;padding:18px 17px calc(26px + env(safe-area-inset-bottom,0px));color:var(--e-ink);}
      .etc-sheet-top{display:flex;align-items:center;justify-content:space-between;margin-bottom:20px;font-size:20px;font-weight:740;}
      .etc-sheet-close{border:0;background:var(--e-soft);color:var(--e-muted);width:33px;height:33px;border-radius:50%;display:grid;place-items:center;}
      .etc-segmented{display:grid;grid-template-columns:repeat(3,1fr);gap:4px;padding:4px;background:var(--e-soft);border-radius:10px;}
      .etc-segmented button{border:0;border-radius:8px;background:transparent;min-height:37px;color:var(--e-ink);font-size:13px;font-weight:630;}
      .etc-segmented button.selected{background:var(--e-card);box-shadow:0 1px 3px rgba(0,0,0,.15);}
      .etc-sheet-link{min-height:51px;padding:13px 14px;display:flex;gap:10px;align-items:center;border-bottom:1px solid var(--e-line);color:var(--e-ink)!important;font-size:15px;}
      .etc-sheet-link:last-child{border:0;}
      .etc-sheet-link>span{flex:1;}
      .etc-logout-note{font-size:12px;color:var(--e-muted);text-align:center;margin:16px;}
      body.etc-native-v4.etc-login form{max-width:550px;margin:20px auto;background:var(--e-card);border:1px solid var(--e-line);border-radius:18px;padding:20px;}
      .etc-login-head{max-width:550px;margin:0 auto;padding:42px 22px 0;}
      .etc-login-sub{font-size:13px;color:var(--e-muted);margin:6px 0 0;}
      .etc-company-help{font-size:12px;color:var(--e-muted);padding:4px 0;}
      body.etc-native-v4.etc-login input[type=submit]{background:var(--e-blue)!important;color:white!important;min-height:48px!important;}

      /* v4.1 — clean iOS sign-in, isolated from the work-time pages */
      body.etc-native-v4.etc-login {padding:0!important; min-height:100dvh;}
      body.etc-native-v4.etc-login .etc-login-original-logo {display:none!important;}
      body.etc-native-v4.etc-login form[name="TMSLGN01ActionForm"],
      body.etc-native-v4.etc-login form.etc-login-form {
        max-width:none!important; margin:0!important; padding:0!important; background:none!important;
        border:0!important; border-radius:0!important; box-shadow:none!important;
      }
      .etc-login-original {display:none!important;}
      .etc-login-shell {max-width:530px;margin:0 auto;padding:calc(38px + env(safe-area-inset-top, 0px)) 18px calc(32px + env(safe-area-inset-bottom, 0px));}
      .etc-login-brand {display:flex;gap:14px;align-items:center;margin:0 4px 25px;}
      .etc-login-appicon {flex:none;width:57px;height:57px;display:grid;place-items:center;border-radius:18px;background:linear-gradient(155deg,#54a0ff,#0874ef);color:white;box-shadow:0 7px 17px rgba(0,122,255,.19);}
      .etc-login-brandname {font-size:15px;font-weight:700;letter-spacing:-.015em;line-height:1.25;}
      .etc-login-brandnote {font-size:12px;color:var(--e-muted);margin-top:2px;}
      .etc-login-hero {margin:0 4px 23px;}
      .etc-login-kicker {font-size:12px;letter-spacing:.055em;font-weight:650;color:var(--e-muted);}
      .etc-login-h1 {font-size:35px!important;line-height:1.1;letter-spacing:-.055em;font-weight:760;margin:5px 0 9px!important;color:var(--e-ink)!important;}
      .etc-login-caption {font-size:14px;color:var(--e-muted);margin:0;line-height:1.55;}
      .etc-login-form-card {background:var(--e-card);border:1px solid var(--e-line);border-radius:20px;padding:6px 17px 17px;overflow:hidden;}
      .etc-login-field-row {padding:16px 0 17px;}
      .etc-login-field-row + .etc-login-field-row {border-top:1px solid var(--e-line);}
      .etc-login-field-label {display:flex;gap:8px;justify-content:space-between;align-items:center;color:var(--e-ink);font-size:14px;font-weight:650;margin:0 0 9px;}
      .etc-login-prefilled {font-size:11px;font-weight:650;padding:3px 8px;border-radius:999px;color:var(--e-blue);background:var(--e-blue-wash);}
      body.etc-native-v4.etc-login .etc-login-field {
        width:100%!important;min-height:51px!important;display:block!important;margin:0!important;
        border-radius:12px!important;border:1px solid var(--e-line)!important;background:var(--e-soft)!important;
        color:var(--e-ink)!important;font-size:17px!important;padding:10px 14px!important;
        box-shadow:none!important;-webkit-appearance:none!important;appearance:none!important;
      }
      body.etc-native-v4.etc-login .etc-login-field:focus {outline:2px solid var(--e-blue)!important;outline-offset:1px;}
      .etc-login-password-box {display:flex;align-items:center;position:relative;}
      body.etc-native-v4.etc-login .etc-login-password-box .etc-login-field {padding-right:70px!important;}
      body.etc-native-v4.etc-login .etc-login-toggle {position:absolute;right:8px;top:5px;min-height:41px;border:0;background:transparent;color:var(--e-blue);font-weight:650;font-size:13px;padding:0 10px;border-radius:9px;}
      body.etc-native-v4.etc-login input[type=submit].etc-login-submit {
        display:block!important;width:100%!important;max-width:none!important;min-height:53px!important;
        border-radius:13px!important;margin:6px 0 0!important;font-size:17px!important;font-weight:700!important;
        color:white!important;background:var(--e-blue)!important;box-shadow:none!important;
      }
      .etc-login-reset {display:flex;align-items:center;justify-content:center;min-height:49px;font-size:14px;font-weight:600;margin:7px 2px 0;color:var(--e-blue)!important;gap:4px;text-align:center;}
      .etc-login-notes {margin-top:25px;}
      .etc-login-section-heading {font-size:12px;font-weight:700;color:var(--e-muted);padding:0 13px;margin:0 0 9px;letter-spacing:.025em;}
      .etc-login-service {background:var(--e-card);border:1px solid var(--e-line);border-radius:16px;padding:14px 16px;margin-bottom:12px;display:flex;align-items:center;gap:12px;}
      .etc-login-service-icon {height:34px;width:34px;flex:none;background:var(--e-blue-wash);border-radius:10px;display:grid;place-items:center;color:var(--e-blue);}
      .etc-login-service-strong {font-weight:650;font-size:14px;}
      .etc-login-service-detail {font-size:12px;color:var(--e-muted);margin-top:2px;}
      .etc-login-notice-wrap {border:1px solid var(--e-line);border-radius:16px;background:var(--e-card);overflow:hidden;}
      details.etc-login-notice {padding:0;margin:0;border-bottom:1px solid var(--e-line);}
      details.etc-login-notice:last-child {border-bottom:0;}
      .etc-login-notice>summary {list-style:none;display:flex;gap:10px;align-items:center;min-height:55px;padding:13px 15px;cursor:pointer;font-size:14px;font-weight:600;color:var(--e-ink);}
      .etc-login-notice>summary::-webkit-details-marker {display:none;}
      .etc-login-notice>summary .etc-login-notice-title {flex:1;}
      .etc-login-notice>summary .etc-login-note-chevron {color:var(--e-muted);transition:transform .2s ease;}
      .etc-login-notice[open]>summary .etc-login-note-chevron {transform:rotate(90deg);}
      .etc-login-news-body {padding:0 15px 17px;font-size:13px;line-height:1.75;color:var(--e-ink);overflow-wrap:anywhere;}
      body.etc-native-v4.etc-login .etc-login-news-body span[style*="color"],body.etc-native-v4.etc-login .etc-login-news-body div[style*="color"] {color:var(--e-ink)!important;}
      .etc-login-news-body a {color:var(--e-blue)!important;text-decoration:underline;}
      .etc-login-quick-links {margin-top:14px;display:flex;flex-wrap:wrap;align-items:center;justify-content:center;gap:10px 16px;}
      .etc-login-quick-links a {font-size:13px;color:var(--e-blue)!important;}
      .etc-login-disclaimer {text-align:center;color:var(--e-muted);font-size:11px;line-height:1.6;padding:20px 9px 0;}
/* v2.4: iPhone Duo inner-display responsive sign-in.
   The original 530px shell caused a narrow central column even on a large viewport. */
.etc-login-main {display:block;}
.etc-login-intro,.etc-login-fields {min-width:0;}
@media (min-width:680px) {
  body.etc-native-v4.etc-login .etc-login-shell {
    box-sizing:border-box; width:100%;max-width:1180px;
    padding:clamp(24px,4dvw,44px) max(26px,env(safe-area-inset-right,0px)) 42px max(26px,env(safe-area-inset-left,0px));
  }
  .etc-login-main {
    display:grid;grid-template-columns:minmax(0,.8fr) minmax(365px,1fr);
    gap:clamp(24px,4vw,62px);align-items:center;
  }
  .etc-login-intro {align-self:center;padding:12px 0 40px;}
  .etc-login-intro .etc-login-brand {margin-bottom:32px;}
  .etc-login-intro .etc-login-h1 {font-size:clamp(40px,5vw,56px)!important;}
  .etc-login-fields {width:100%;max-width:520px;justify-self:center;}
  .etc-login-notes {margin:28px auto 0;max-width:820px;}
  .etc-login-form-card {border-radius:22px;}
}
@media (min-width:680px) and (max-width:820px){
  .etc-login-main {grid-template-columns:minmax(0,.65fr) minmax(345px,1fr);gap:22px;}
  .etc-login-intro .etc-login-h1 {font-size:40px!important;}
}
@media (max-width:679px){
  .etc-login-shell {width:100%!important;max-width:560px!important;}
}
      .etc-login-message {font-size:13px;line-height:1.55;background:rgba(255,59,48,.09);color:var(--e-red);border:1px solid rgba(255,59,48,.18);border-radius:13px;margin:0 0 14px;padding:12px 14px;}
      @media (max-width:360px){.etc-login-shell{padding-left:14px;padding-right:14px}.etc-login-h1{font-size:31px!important;}}
      @media(max-width:360px){.etc-form-card table.etc-fields>tbody>tr:has(input[name=startTime]){grid-template-columns:minmax(0,1fr) 106px;}.etc-form-card table.etc-fields>tbody>tr:has(input[name=startTime])>td:nth-child(2) input{font-size:12px!important;padding:6px 1px!important;}}

      /* v4.2: compact, accessible 'current time' buttons, placed LEFT of each HHMM field */
      .etc-form-card .etc-now-inline { display:flex;align-items:center;justify-content:flex-end;gap:9px;min-width:0;font-size:16px; }
      .etc-form-card .etc-now-inline input[name=startTime],
      .etc-form-card .etc-now-inline input[name=endTime]{
        width:112px!important;min-width:0!important;max-width:112px!important;flex:0 0 112px;
        font-size:18px!important;font-variant-numeric:tabular-nums;text-align:center;
      }
      body.etc-native-v4 button.etc-now-button{
        display:inline-flex;align-items:center;justify-content:center;gap:4px;
        background:var(--e-blue-wash)!important;color:var(--e-blue)!important;
        border:1px solid transparent!important;border-radius:12px!important;
        min-width:61px;min-height:44px;padding:7px 9px!important;
        font-size:14px!important;font-weight:700!important;line-height:1.1;
        white-space:nowrap;flex:0 0 auto;cursor:pointer;
      }
      .etc-now-button svg{width:16px;height:16px;flex-shrink:0;}
      body.etc-native-v4 button.etc-now-button:focus-visible{outline:2px solid var(--e-blue);outline-offset:2px;}
      .etc-form-card table.etc-fields>tbody>tr:has(input[name=startTime]){grid-template-columns:minmax(0,1fr) 187px;}
      .etc-form-card table.etc-fields>tbody>tr:has(input[name=startTime])>td:last-child,
      .etc-form-card table.etc-fields>tbody>tr:has(input[name=endTime])>td:last-child{display:block;text-align:right!important;}
      /* At narrow iPhone widths, preset controls and current-time action get separate lines. */
      @media (max-width:390px){
        .etc-form-card table.etc-fields>tbody>tr:has(input[name=startTime]){grid-template-columns:minmax(0,1fr)!important;}
        .etc-form-card table.etc-fields>tbody>tr:has(input[name=startTime])>td:nth-child(2){grid-column:1;}
        .etc-form-card table.etc-fields>tbody>tr:has(input[name=startTime])>td:last-child{grid-column:1;}
      }

    `;
    document.head.appendChild(style);
  }

  function removeBrandDecorations() {
    // Only the old visual banner/logo/footer are hidden, never forms or input controls.
    $$('img[src*="/s/images/logo.gif"]').forEach(img => { const h = img.closest('h3') || img; h.classList.add('etc-legacy-logo'); });
    $$('div[style*="background-color:#FF6600"],div[style*="background-color: #FF6600"],div[style*="background-color:#ff6600"]').forEach(el => {
      const label = tidy(el.textContent);
      if (/^(日々申請|締め申請|スタッフメニュー)$/.test(label) || /\(c\)\s*2012/i.test(label)) el.classList.add('etc-legacy-banner');
    });
    // The old header/logo is wrapped outside the form: leave it in the DOM but hide it.
    $$('a[href="#TOP"],a[href="#menu"]').forEach(a => { if (a.parentElement?.tagName === 'DIV') a.parentElement.classList.add('etc-skip-original-footer'); });
    $$('div[style*="font-size:small"]', document).forEach(el => {
      if (el.querySelector('form')) return;
      const t=tidy(el.textContent);
      if (/^(日々申請|締め申請|スタッフメニュー)$/.test(t)) el.classList.add('etc-skip-original-footer');
    });
  }

  function header(label, eyebrow) {
    const h = document.createElement('header');
    h.className = 'etc-native-header';
    h.innerHTML = `<a class="etc-nav-back" aria-label="ホームへ戻る" href="${esc(officialLink(routes.home))}">${svg('back',24)}</a><div class="etc-header-group"><div class="etc-header-eyebrow">${esc(eyebrow)}</div><h1 class="etc-header-title">${esc(label)}</h1></div>`;
    document.body.prepend(h);
  }
  function makeCard(title, cls = '') {
    const el = document.createElement('section');
    el.className = `etc-form-card ${cls}`.trim();
    if (title) el.innerHTML = `<h2 class="etc-card-title">${esc(title)}</h2>`;
    return el;
  }
  function wrap(el, section) {
    if (!el || !el.parentNode) return null;
    el.parentNode.insertBefore(section, el);
    section.appendChild(el);
    return section;
  }
  function moveInto(node, parent) { if (node && parent) parent.appendChild(node); }
  function topLevelTable(el, form) { return el && el.parentElement === form; }
  function directTables(form) { return $$(':scope > table', form); }
  function addPeriod(form) {
    const div = $$(':scope > .divCenter', form).find(el => /\d{4}年\d+月\d+日/.test(tidy(el.textContent)));
    if (div) div.classList.add('etc-period');
  }
  function decorateInputs(form) {
    $$('input[name=startTime],input[name=endTime],input[name=rstTime],input[name=nightRstTime]', form).forEach(el => el.setAttribute('inputmode','numeric'));
    $$('input[type=submit]', form).forEach(el => {
      if (el.name === 'apply' || el.name === 'cloApply') el.classList.add('etc-primary');
      if (el.name === 'temStorage') el.classList.add('etc-secondary');
    });
  }
  function prepareForm(form) { form.classList.add('etc-enhanced-form'); addPeriod(form); decorateInputs(form); }
  function moveButtonBox(form, names, section, cssClass) {
    const buttons = names.map(n => $(`input[name="${n}"]`, form)).filter(Boolean);
    if (!buttons.length) return;
    const target = buttons[0].parentElement;
    if (target && target !== form && buttons.every(b => b.parentElement === target)) {
      if (cssClass) target.classList.add(cssClass);
      section.appendChild(target);
    }
  }
  function pager(form, selector) {
    const table = directTables(form).find(t => t.querySelector(selector));
    if (!table) return;
    const box = document.createElement('div');
    box.className = 'etc-day-pager';
    table.parentNode.insertBefore(box, table);
    $$('a', table).forEach(a => { const btn = document.createElement('a'); btn.href = a.href; btn.textContent = tidy(a.textContent); box.appendChild(btn); });
    // Original pagination is preserved but visually hidden; it has navigation links, no form inputs.
    table.classList.add('etc-skip-original-footer');
  }
  function collapseReference(form, title, anchorId) {
    const anchor = form.querySelector(`#${anchorId}`);
    if (!anchor) return;
    const section = document.createElement('details');
    section.className = 'etc-collapsible';
    section.innerHTML = `<summary>${esc(title)}</summary><div class="etc-detail-body"></div>`;
    anchor.parentNode.insertBefore(section, anchor);
    const slot = $('.etc-detail-body', section);
    // Move only anchor, the next section label, and its next data table / explanatory span.
    moveInto(anchor, slot);
    let next = section.nextSibling;
    let moved = 0;
    while (next && moved < 4) {
      const candidate = next;
      next = next.nextSibling;
      if (candidate.nodeType === 1 && (candidate.tagName === 'HR' || candidate.classList.contains('divleft'))) break;
      if (candidate.nodeType === 1 && (candidate.matches('.subHeader, table, span') || candidate.tagName === 'BR')) {
        moveInto(candidate, slot); moved++;
        if (candidate.matches('table, span')) break;
      } else if (candidate.nodeType === 3 && !tidy(candidate.textContent)) {
        candidate.remove();
      } else if (candidate.nodeType === 1 && candidate.tagName === 'A' && candidate.id) {
        break;
      }
    }
    section.addEventListener('toggle', () => {});
    // An in-page anchor should open the details section when targeted.
    $$(`a[href="#${anchorId}"]`, form).forEach(link => link.addEventListener('click', () => { section.open = true; }));
  }

  function addCurrentTimeButtons(form) {
    // Keep original input nodes and names. No form submission, no network call;
    // calculate the value only when a user taps the button.
    for (const [name, label] of [['startTime', '開始'], ['endTime', '終了']]) {
      const input = $(`input[name="${name}"]`, form);
      if (!input || input.closest('.etc-now-inline')) continue;
      const originalParent = input.parentElement;
      if (!originalParent) continue;
      const wrap = document.createElement('span');
      wrap.className = 'etc-now-inline';
      const button = document.createElement('button');
      button.type = 'button'; // critical: never submit a Struts attendance form
      button.className = 'etc-now-button';
      button.setAttribute('aria-label', `${label}時刻に現在の時刻を入力`);
      button.title = '現在の時刻を入力（HHMM）';
      button.innerHTML = `${svg('clock',16)}<span>今</span>`;
      button.addEventListener('click', () => {
        const now = new Date(); // local time on the iPhone, evaluated at TAP time
        const hhmm = String(now.getHours()).padStart(2,'0') + String(now.getMinutes()).padStart(2,'0');
        // Native setter lets sites that observe value changes receive the update.
        const desc = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value');
        if (desc && desc.set) desc.set.call(input,hhmm);
        else input.value = hhmm;
        input.dispatchEvent(new Event('input', { bubbles:true }));
        input.dispatchEvent(new Event('change', { bubbles:true }));
      });
      originalParent.insertBefore(wrap,input);
      wrap.append(button,input);
      input.setAttribute('inputmode','numeric');
    }
  }

  function makeDaily(form) {
    header('日々勤怠', '勤務時間を入力');
    prepareForm(form);
    addCurrentTimeButtons(form);
    const divs = $$(':scope > div', form);
    const status = divs.find(d => /\d+月\d+日\s*\(.+?\)/.test(tidy(d.textContent)) && /作成中|申請済|承認|差戻/.test(tidy(d.textContent)) && tidy(d.textContent).length < 90);
    if (status) {
      const text = tidy(status.textContent);
      const match = text.match(/(\d+月\d+日\s*\(.+?\))\s*[:：]?\s*(.*)/);
      if (match) {
        const day = document.createElement('span'); day.textContent = match[1];
        const badge = document.createElement('span'); badge.className = 'etc-chip'; badge.textContent = match[2] || '入力中';
        status.replaceChildren(day, badge);
      }
      status.classList.add('etc-today-status');
    }
    const tables = directTables(form);
    if (tables[0]) {
      const section = makeCard('勤務内容'); wrap(tables[0], section);
      tables[0].classList.add('etc-fields');
    }
    if (tables[1]) {
      const section = makeCard('休憩時間'); wrap(tables[1], section);
      tables[1].classList.add('etc-details');
    }
    if (tables[2] || tables[3]) {
      const t = tables[2] || tables[3];
      const section = makeCard('備考・立替金'); wrap(t, section);
      t.classList.add('etc-details');
      if (tables[3] && tables[3] !== t) { moveInto(tables[3], section); tables[3].classList.add('etc-details'); }
    }
    const apply = $('input[name="apply"]', form);
    if (apply) {
      const section = makeCard('保存・申請');
      section.insertAdjacentHTML('beforeend','<p class="etc-card-hint">内容を確認して、申請または一時保存を選んでください。</p>');
      const box = apply.closest('div');
      if (box && box.parentElement) { box.parentNode.insertBefore(section, box); box.classList.add('etc-apply-controls'); section.appendChild(box); }
      const notify = $('input[name="dailyChk"]', form)?.closest('div');
      if (notify && notify !== box) section.insertBefore(notify, box);
    }
    // Hide the visual-only footer (not the official form or its submit controls).
    pager(form,'a[href*="/TMSINP01/prev"],a[href*="/TMSINP01/next"]');
    collapseReference(form, '時間外労働時間を確認', 'overTimeWorkPlace');
    collapseReference(form, '備考・立替金に関する注意', 'StaffInputWkplace');
    const extras = ['dayHistory', 'close'].map(n=>$(`input[name="${n}"]`,form)?.closest('div')).filter(Boolean);
    const linkSpan = $('input[name="labormngagreement"]',form)?.closest('span');
    if(extras.length || linkSpan){
      const details=document.createElement('details');details.className='etc-collapsible';
      details.innerHTML='<summary>履歴・その他の操作</summary><div class="etc-detail-body"></div>';
      const point=extras[0] || linkSpan;
      point.parentNode.insertBefore(details,point);
      const slot=$('.etc-detail-body',details);
      if(linkSpan)slot.appendChild(linkSpan);
      extras.forEach(el=>slot.appendChild(el));
    }
    footer(form);
  }

function decorateStats(table) {
  const rows = $$('tr', table);
  if (rows.length < 2) return;
  const th = $$('th', rows[0]).map(el => tidy(el.textContent));
  const valueCells = $$('td', rows[1]);
  valueCells.forEach((td,i) => td.dataset.label = th[i] || '項目');
  const visibleCount = valueCells.filter(td => tidy(td.textContent) || td.querySelector('input,button,a')).length || valueCells.length || 2;
  table.style.setProperty('--etc-stats-cols-wide', String(Math.max(2, Math.min(visibleCount, 5))));
  table.classList.add('etc-close-stats');
}
function parseClosePeriod(form) {
  // Use the official period shown by the server, never the device's current month
  // unless no usable date is available. Handles same-month and month-crossing ranges.
  const original = [...form.querySelectorAll('.divCenter, .etc-period')]
      .map(el => tidy(el.textContent)).find(t => /\d{4}年.*\d+月.*\d+日.*[～〜]/.test(t)) || '';
  const text = original || tidy(form.textContent).slice(0,700);
  let m = text.match(/(\d{4})年\s*(\d{1,2})月\s*(\d{1,2})日\s*[～〜]\s*(?:(\d{4})年\s*)?(?:(\d{1,2})月\s*)?(\d{1,2})日/);
  if (!m) return null;
  const sy = Number(m[1]), sm = Number(m[2]), sd = Number(m[3]);
  const ey = m[4] ? Number(m[4]) : sy;
  const em = m[5] ? Number(m[5]) : sm;
  const ed = Number(m[6]);
  if (![sy,sm,sd,ey,em,ed].every(Number.isInteger) || sm < 1 || sm > 12 || em < 1 || em > 12) return null;
  const start = new Date(sy,sm-1,sd);
  let end = new Date(ey,em-1,ed);
  if (end < start && !m[4] && !m[5]) end = new Date(sy,sm,ed); // day-number rollover
  if (start.getFullYear() !== sy || start.getMonth() !== sm-1 || start.getDate() !== sd) return null;
  const days = Math.round((end - start)/86400000);
  if (days < 0 || days > 62) return null;
  return {start,end};
}
function dateKey(date) {
  return `${date.getFullYear()}-${String(date.getMonth()+1).padStart(2,'0')}-${String(date.getDate()).padStart(2,'0')}`;
}
function formatHHMM(raw) {
  const m = String(raw || '').match(/^(\d{2})(\d{2})\s*[-－〜～]\s*(\d{2})(\d{2})$/);
  return m ? `${m[1]}:${m[2]}–${m[3]}:${m[4]}` : String(raw || '');
}
function buildCloseCalendar(table, form) {
  const period = parseClosePeriod(form);
  if (!period) return null;  // If the official dates cannot be parsed, keep the original list.
  const records = new Map();
  const rows = $$('tbody > tr',table).slice(1);
  // Source day numbers are from the original official table, before list enhancement.
  let cursor = new Date(period.start);
  rows.forEach(tr => {
    const tds = $$(':scope > td',tr);
    if (tds.length < 7) return;
    const m = tidy(tds[0].textContent).match(/(\d{1,2})/);
    if (!m) return;
    const dayNumber = Number(m[1]);
    const firstValid = new Date(cursor);
    let found = null;
    for (let i=0;i<34 && firstValid<=period.end;i++) {
      if (firstValid.getDate()===dayNumber) {found=new Date(firstValid);break;}
      firstValid.setDate(firstValid.getDate()+1);
    }
    if (!found) return;
    const href = $('a[href]',tds[0]);
    // Only use URLs supplied by the official page; never fabricate date-specific endpoints.
    const isOfficial = href && href.origin===location.origin && href.pathname.startsWith('/s/');
    const record = {
      href:isOfficial ? href.href : '',
      kind:tidy(tds[2].textContent),
      place:tidy(tds[3].textContent),
      status:tidy(tds[1].textContent),
      hours:tidy(tds[4].textContent),
      rest:tidy(tds[5].textContent),
      deep:tidy(tds[6].textContent)
    };
    records.set(dateKey(found),record);
    cursor.setTime(found.getTime());cursor.setDate(cursor.getDate()+1);
  });
  if (!records.size) return null;
  // Session-memory only; date-specific URLs and statuses are never persisted.
  // Data feeds the optional home dashboard; no date URLs are replayed in Swift.
  window.__etcOfficialRecords = {
    start: dateKey(period.start), end: dateKey(period.end),
    days: Array.from(records, ([date, record]) => ({date,
      href: record.href, status: record.status, kind: record.kind,
      hours: record.hours, rest: record.rest, place: record.place, leave: record.kind === '年',
      work: Boolean(record.hours)
    }))
  };
  const panel=document.createElement('div');panel.className='etc-date-calendar';
  const now=new Date();const today=dateKey(now);
  const legend=document.createElement('div');legend.className='etc-calendar-legend';
  [['work','勤務入力あり'],['leave','年休'],['blank','記録なし'],['today','今日']].forEach(([kind,label])=>{
    const sp=document.createElement('span');const swatch=document.createElement('i');swatch.className=`etc-legend-${kind}`;
    sp.append(swatch,document.createTextNode(label));legend.appendChild(sp);
  });
  const toolbar=document.createElement('div');toolbar.className='etc-calendar-toolbar';toolbar.appendChild(legend);
  if (today >= dateKey(period.start) && today <= dateKey(period.end)) {
    const jump=document.createElement('button');jump.type='button';jump.className='etc-calendar-jump';jump.textContent='今日へ';
    jump.addEventListener('click',()=>panel.querySelector('.etc-calendar-day.is-today')?.scrollIntoView({behavior:'smooth',block:'center'}));
    toolbar.appendChild(jump);
  }
  panel.appendChild(toolbar);
  const help=document.createElement('p');
  help.className='etc-calendar-reference-hint';
  help.textContent='月カレンダーは閲覧専用です。日付を編集する場合は「一覧表示」に切り替えて公式リンクから開いてください。';
  panel.appendChild(help);
  const firstMonth = new Date(period.start.getFullYear(),period.start.getMonth(),1);
  const sameMonth = period.start.getFullYear()===period.end.getFullYear() && period.start.getMonth()===period.end.getMonth();
  const lastMonth = sameMonth ? new Date(firstMonth) : new Date(period.end.getFullYear(),period.end.getMonth(),1);
  const weeks=['日','月','火','水','木','金','土'];
  for(let month=new Date(firstMonth);month<=lastMonth;month.setMonth(month.getMonth()+1)){
    const wrap=document.createElement('section');wrap.className='etc-calendar-month';
    const title=document.createElement('h3');title.className='etc-calendar-month-title';
    title.textContent=`${month.getFullYear()}年${month.getMonth()+1}月`;
    const weekhead=document.createElement('div');weekhead.className='etc-calendar-weekdays';
    for(const w of weeks){const el=document.createElement('span');el.textContent=w;weekhead.appendChild(el);}
    const grid=document.createElement('div');grid.className='etc-calendar-grid';
    for(let i=0;i<month.getDay();i++){
      const empty=document.createElement('div');empty.className='etc-calendar-day is-other';empty.setAttribute('aria-hidden','true');grid.appendChild(empty);
    }
    const monthLength=new Date(month.getFullYear(),month.getMonth()+1,0).getDate();
    for(let day=1;day<=monthLength;day++){
      const date=new Date(month.getFullYear(),month.getMonth(),day);
      const key=dateKey(date);
      const record=records.get(key);
      const within=date>=period.start && date<=period.end;
      const worked=within && record && !!record.hours;
      const leave=within && record && record.kind==='年';
      const weekend=(date.getDay()===0 || date.getDay()===6);
      // Reference-only: navigate to dates from the ORIGINAL official list,
      // never from duplicated calendar links (stateful server workflow).
      const cell=document.createElement('div');
      cell.className='etc-calendar-day';
      if(!within && !sameMonth)cell.classList.add('is-other');
      if(!within && sameMonth)cell.classList.add('etc-v295-unfetched');
      cell.dataset.date = key;
      const publicHoliday=window.__etcJapanHolidayName?.(key)||'';
      if(publicHoliday) { cell.classList.add('etc-v295-holiday'); cell.title=publicHoliday; }
      if(within && !record?.href)cell.classList.add('is-disabled');
      if(worked)cell.classList.add('is-work');
      else if(leave)cell.classList.add('is-leave');
      if(weekend)cell.classList.add('is-weekend');
      if(key===today)cell.classList.add('is-today');
      // Original official anchors remain untouched in the switchable list.
      const number=document.createElement('div');number.className='etc-calendar-day-top';
      const digit=document.createElement('span');digit.className='etc-calendar-day-number';digit.textContent=String(day);number.appendChild(digit);
      if(key===today){const badge=document.createElement('span');badge.className='etc-calendar-today-indicator';badge.textContent='今日';number.appendChild(badge);}
      cell.appendChild(number);
      if(within || sameMonth) {
        const time=document.createElement('div');time.className='etc-calendar-time';
        if (worked) {
          const parts = formatHHMM(record.hours).split('–');
          if (parts.length === 2) {
            const a = document.createElement('span');a.className='etc-calendar-time-start';a.textContent=parts[0];
            const dash = document.createElement('span');dash.className='etc-calendar-time-sep';dash.textContent='–';
            const b = document.createElement('span');b.className='etc-calendar-time-end';b.textContent=parts[1];
            time.append(a,dash,b);
          } else time.textContent=formatHHMM(record.hours);
        } else time.textContent=!within ? '未取得' : leave ? '年次有給休暇' : (publicHoliday||'入力なし');
        cell.appendChild(time);
        if(worked){
          const info=document.createElement('div');info.className='etc-calendar-subline';
          info.textContent=(record.place==='オ'?'オフィス':record.place==='自'?'自宅':'勤務')+(record.rest ? ` · 休${record.rest}分` : '');
          cell.appendChild(info);
        }
        const pill=document.createElement('span');pill.className='etc-calendar-tag';
        if(worked){pill.textContent=record.status||'入力あり';pill.classList.add('is-work');}
        else if(leave){pill.textContent=record.status||'年休';pill.classList.add('is-leave');}
        else {pill.textContent=!within?'取得待ち':(record?.status||(publicHoliday?'祝日・記録なし':weekend?'休日・記録なし':'記録なし'));pill.classList.add('is-empty');}
        cell.appendChild(pill);
      }
      const desc=`${month.getFullYear()}年${month.getMonth()+1}月${day}日${weeks[date.getDay()]}曜日`;
      cell.setAttribute('aria-label',`${desc}、${within ? (worked ? formatHHMM(record.hours) : leave ? '年次有給休暇' : publicHoliday||'入力なし') : sameMonth?'未取得':'対象期間外'}。日付の編集は一覧表示から`);
      grid.appendChild(cell);
    }
    wrap.append(title,weekhead,grid);panel.appendChild(wrap);
  }
  return panel;
}
function decorateDateTable(table) {

    table.classList.add('etc-date-list');
    const rows = $$('tbody > tr', table);
    rows.slice(1).forEach(tr => {
      const tds = $$(':scope > td', tr);
      if (tds.length < 7) return;
      const day = tidy(tds[0].textContent);
      const state = tidy(tds[1].textContent);
      const kind = tidy(tds[2].textContent);
      const place = tidy(tds[3].textContent);
      const hrs = tidy(tds[4].textContent);
      const rest = tidy(tds[5].textContent);
      const night = tidy(tds[6].textContent);
      const summary = [];
      if (state) summary.push(state);
      if (kind === '年') { summary.push('年次有給休暇'); tr.classList.add('etc-holiday'); }
      else if (kind === '通') summary.push('通常勤務');
      else if (kind) summary.push(`区分 ${kind}`);
      if (place === 'オ') summary.push('オフィス');
      else if (place === '自') summary.push('自宅');
      else if (place) summary.push(`就業場所 ${place}`);
      if (rest) summary.push(`休憩 ${rest}分`);
      if (night && night !== '0') summary.push(`深夜休憩 ${night}分`);
      if (!hrs) {
        const label = document.createElement('span');
        label.className = 'etc-record-empty';
        label.textContent = kind === '年' ? '年次有給休暇' : '入力なし';
        tds[4].append(label);
      }
      if (summary.length) {
        const meta = document.createElement('div'); meta.className = 'etc-record-meta';
        summary.forEach(s => { const badge = document.createElement('span'); badge.textContent = s; meta.appendChild(badge); });
        tds[4].appendChild(meta);
      }
      const a = $('a[href]',tds[0]);
      if (a && a.origin === location.origin) {
        tr.tabIndex = 0;
        tr.setAttribute('aria-label', `${day}、${hrs || (kind === '年' ? '年次有給休暇' : '入力なし')}、勤怠入力を開く`);
        tr.addEventListener('click', e => { if (!e.target.closest('a,button,input,select')) location.assign(a.href); });
        tr.addEventListener('keydown', e => { if (e.key === 'Enter' && e.target === tr) location.assign(a.href); });
      }
    });
  }
  function makeClose(form) {
    header('締め申請', '期間の勤怠を確認');
    prepareForm(form);
    const tables = directTables(form);
    if (tables[0]) { const section = makeCard('勤務状況'); wrap(tables[0],section); decorateStats(tables[0]); }
    if (tables[1]) { const section = makeCard('就業時間の集計'); wrap(tables[1],section); decorateStats(tables[1]); }
    const submit = $('input[name="cloApply"]', form);
    if (submit) {
      const box = submit.closest('div');
      if (box) {
        const section = makeCard('締め申請を行う');
        section.insertAdjacentHTML('beforeend','<p class="etc-card-hint">勤務日・勤務時間と承認者を確認したうえで申請してください。</p>');
        box.parentNode.insertBefore(section,box);
        const notify = $('input[name="cloChk"]',form)?.closest('div');
        if (notify && notify !== box) { notify.classList.add('etc-notification-box'); moveInto(notify,section); }
        box.classList.add('etc-apply-controls'); moveInto(box,section);
      }
    }
    if (tables[2]) {
      const section = makeCard('日別の勤怠一覧');
      section.insertAdjacentHTML('beforeend','<div class="etc-list-hint">日付をタップすると、その日の勤怠入力に移動できます。</div>');
      wrap(tables[2],section);
      const calendar = buildCloseCalendar(tables[2], form);
      decorateDateTable(tables[2]);
      if (calendar) {
        tables[2].classList.add('etc-has-calendar');
        section.classList.add('etc-close-calendar-section');
        section.appendChild(calendar);
        const bar = document.createElement('div');bar.className='etc-calendar-toggle';
        const storageKey='etc-native-v22-close-view';
        let preference='calendar';
        try { preference=localStorage.getItem(storageKey)==='list'?'list':'calendar'; } catch {};
        const modes=[['calendar','月表示'],['list','一覧表示']];
        modes.forEach(([mode,label])=>{
          const button=document.createElement('button');button.type='button';button.textContent=label;
          button.className='etc-calendar-toggle-btn';button.setAttribute('aria-pressed',String(preference===mode));
          button.addEventListener('click',()=>{
            preference=mode;
            section.classList.toggle('etc-calendar-force-list',mode==='list');
            bar.querySelectorAll('button').forEach(b=>{const selected=(b===button);b.classList.toggle('is-selected',selected);b.setAttribute('aria-pressed',String(selected));});
            try{localStorage.setItem(storageKey,mode);}catch{}
          });
          bar.appendChild(button);
        });
        section.classList.toggle('etc-calendar-force-list',preference==='list');
        bar.querySelectorAll('button').forEach((b,i)=>b.classList.toggle('is-selected',modes[i][0]===preference));
        section.querySelector('.etc-list-hint')?.after(bar);
      }
    }
    pager(form,'a[href*="/TMSINP02/prev"],a[href*="/TMSINP02/next"]');
    collapseReference(form, '時間集計の注意事項', 'time');
    $$('a[href="#time"]',form).forEach(a=>{if(a.parentElement?.tagName==='SPAN')a.parentElement.classList.add('etc-skip-original-footer');});
    $$('div',form).filter(el=>!el.querySelector('table,form') && /日付リンクから日々申請できます/.test(tidy(el.textContent))).forEach(el=>el.classList.add('etc-list-notice'));
    footer(form);
  }
  function footer(form) {
    // Footer support/FAQ/copyright and old repeated page-top shortcuts only.
    $$('div.divleft', form).forEach(d => {
      const tx = tidy(d.textContent);
      if (/メニューへ|ページトップへ/.test(tx) || (tx.includes('FAQ') && tx.includes('LOGOUT'))) d.classList.add('etc-skip-original-footer');
    });
    $$('span',form).filter(el => tidy(el.textContent) === 'サポートセンター').forEach(el => el.classList.add('etc-skip-original-footer'));
    $$('div[style*="background-color:#FF6600"]',form).filter(el => /\(c\)/i.test(el.textContent)).forEach(el => el.classList.add('etc-skip-original-footer'));
    // Hide only empty standalone HR dividers in the bottom footer.
  }
  function menu() {
    const form = $('form[name="TMSMNU01ActionForm"]');
    if (!form) return;
    // On login POST responses the legacy heading still exists above the form.
    // Hide only its decorative siblings, after preserving their text below.
    const nameSpan = $$('span',document).find(s => /さん\s*$/.test(tidy(s.textContent)) && tidy(s.textContent).length < 55);
    const name = nameSpan ? tidy(nameSpan.textContent).replace(/\s*さん\s*$/,'') : '';
    const orgText = $$('span',form).map(el => tidy(el.textContent)).filter(t => t.length > 1 && t.length < 60);
    const company = orgText.find(t => /株式会社|合同会社|有限会社/.test(t)) || '';
    const dept = orgText.find(t => /(?:部|課|本部|センター|グループ|チーム)$/.test(t) && !/サポート/.test(t) && t !== company) || '';
    const host = document.createElement('div'); host.className = 'etc-content'; host.id = 'etc-native-home';
    const today = new Intl.DateTimeFormat('ja-JP',{month:'long',day:'numeric',weekday:'short'}).format(new Date());
    host.innerHTML = `
      <div class="etc-caption">${esc(today)} ・ WEB TIME CARD</div>
      <div class="etc-person-name">${esc(name || 'WebTimeCard')}</div>
      <section class="etc-v29-summary" id="etc-v29-summary" aria-label="勤務ダッシュボード">
        <div class="etc-v29-summary-head"><strong>勤務ダッシュボード</strong><small id="etc-v29-period">今月の前半・後半を確認中</small></div>
        <div class="etc-v29-summary-grid">
          <div><small>今日の勤務</small><strong id="etc-v29-today">未確認</strong></div>
          <div><small>入力済み勤務日</small><strong id="etc-v29-worked">—</strong></div>
          <div><small>勤務時間</small><strong id="etc-v29-total">—</strong></div>
          <div><small>残業時間</small><strong id="etc-v29-overtime">—</strong></div>
          <div><small>記録なし</small><strong id="etc-v29-empty">—</strong></div>
          <div><small>未申請</small><strong id="etc-v29-unsent">—</strong></div>
        </div>
      </section>
      <div class="etc-caption">勤務先</div>
      <section class="etc-card etc-card-pad"><div class="etc-org-name">${esc(company || '契約中の勤務先')}</div>${dept ? `<div class="etc-org-detail">${esc(dept)}</div>` : ''}</section>
      <div class="etc-caption">勤怠管理</div>
      <section class="etc-card">
        <a class="etc-row-link" href="${esc(officialLink(routes.daily))}"><span class="etc-row-symbol">${svg('calendar')}</span><span class="etc-row-info"><strong>日々勤怠</strong><small>出退勤・休憩時間を入力</small></span><span class="etc-row-chevron">${svg('chevron',18)}</span></a>
        <a class="etc-row-link" href="${esc(officialLink(routes.close))}"><span class="etc-row-symbol">${svg('check')}</span><span class="etc-row-info"><strong>締め申請</strong><small>勤務実績の確認と申請</small></span><span class="etc-row-chevron">${svg('chevron',18)}</span></a>
      </section><div class="etc-caption">契約期間</div><section class="etc-card etc-card-pad" id="etc-contract"><p class="etc-card-hint">期間を変えたら「切替」を押してください。</p><div class="etc-contract-fields" style="display:flex;gap:10px;align-items:center"></div></section>
      <p class="etc-logout-note">e-staffing公式WebTimeCardの表示をカスタマイズしています。</p>`;
    // Keep the actual form and all hidden tokens. Move only select + original submit controls.
    const select = $('select[name="selectedContractPeriod"]',form);
    const switchButton = $('input[name="changeKeiyaku"]',form);
    const slot = $('.etc-contract-fields',host);
    if (select && slot) { select.style.flex = '1'; select.style.minWidth = '0'; slot.appendChild(select); }
    if (switchButton && slot) slot.appendChild(switchButton);
    else if (!select) $('#etc-contract',host)?.remove();
    const original = document.createElement('div'); original.className = 'etc-skip-original-footer'; original.id = 'etc-native-menu-original';
    while (form.firstChild) original.appendChild(form.firstChild);
    form.appendChild(original); form.appendChild(host);
    form.classList.add('etc-home-form');
    // Remove legacy pre-form logo, grey horizontal rules, and menu banner.
    // Do not hide any surfaced server error/warning message.
    for (let node=form.previousElementSibling; node; node=node.previousElementSibling) {
      if (node.matches('script,style') || /エラー|失敗|警告|ログインできません/.test(tidy(node.textContent))) continue;
      node.classList.add('etc-skip-original-footer');
    }
    // The original form remains functional; contract selection and submit stay inside it.
  }
  function decorateSettingsAndOther(p) {
    header(p === 'settings' ? 'アカウント設定' : 'WebTimeCard','e-staffing');
  }
  function navbar(p) {
    const nav = document.createElement('nav');nav.className = 'etc-nav-bar';nav.id = 'etc-native-nav';nav.setAttribute('aria-label','ページ切り替え');
    const tabs = [
      ['home','ホーム','house',routes.home], ['daily','日々勤怠','calendar',routes.daily], ['close','締め申請','check',routes.close]
    ];
    nav.innerHTML = `<div class="etc-nav-inner">${tabs.map(([key,label,ic,path])=> `<a href="${esc(officialLink(path))}" class="${p === key ? 'active' : ''}" ${p === key ? 'aria-current="page"' : ''}>${svg(ic,23)}<span class="etc-nav-label">${label}</span></a>`).join('')}<button type="button" id="etc-settings-show" aria-label="設定">${svg('settings',23)}<span class="etc-nav-label">設定</span></button></div>`;
    document.body.appendChild(nav);
    const overlay = document.createElement('div');overlay.id='etc-native-modal';
    overlay.innerHTML = `<section class="etc-sheet" role="dialog" aria-modal="true" aria-label="設定"><div class="etc-sheet-top">設定<button type="button" class="etc-sheet-close" id="etc-sheet-x" aria-label="閉じる">${svg('x',18)}</button></div><div class="etc-caption">外観</div><div class="etc-segmented"><button type="button" data-choice="system">自動</button><button type="button" data-choice="light">ライト</button><button type="button" data-choice="dark">ダーク</button></div><div class="etc-caption">アカウント</div><div class="etc-card"><a class="etc-sheet-link" href="${esc(officialLink(routes.password))}">${svg('lock',20)}<span>パスワード変更</span>${svg('chevron',16)}</a><a class="etc-sheet-link" href="${esc(officialLink(routes.email))}">${svg('mail',20)}<span>メールアドレス変更</span>${svg('chevron',16)}</a></div></section>`;
    document.body.appendChild(overlay);
    const update = () => $$('[data-choice]',overlay).forEach(b=>b.classList.toggle('selected',b.dataset.choice===theme()));
    $('#etc-settings-show',nav).addEventListener('click',()=>{update();overlay.classList.add('open');});
    $('#etc-sheet-x',overlay).addEventListener('click',()=>overlay.classList.remove('open'));
    overlay.addEventListener('click',e=>{if(e.target===overlay)overlay.classList.remove('open');});
    $$('[data-choice]',overlay).forEach(b=>b.addEventListener('click',()=>{applyTheme(b.dataset.choice);update();}));
  }
  function findCompanyField() {
    const forms = $$('form');
    const inputs = forms.flatMap(f => $$('input:not([type=hidden]):not([type=password]):not([type=submit]):not([type=checkbox]):not([type=radio])',f)).filter(input=> !input.disabled && input.offsetParent !== null);
    const candidates = inputs.map(input => {
      const attr = [input.name,input.id,input.getAttribute('aria-label'),input.placeholder].filter(Boolean).join(' ');
      const labels = [input.labels ? [...input.labels].map(x=>x.textContent).join(' ') : '',input.closest('tr')?.textContent?.slice(0,120),input.parentElement?.textContent?.slice(0,60)].join(' ');
      const sign = `${attr} ${labels}`;
      let score = 0;
      if (/企業\s*(ID|ＩＤ|コード)|会社\s*(ID|ＩＤ|コード)/i.test(labels)) score += 12;
      if (/(company|corp|enterprise|business|client|kigyo|kaisha|companycd|companycode)/i.test(attr)) score += 6;
      if (/(company.?id|corp.?id|company.?code|kigyo.?id)/i.test(attr)) score += 6;
      if (/企業|会社/.test(sign)) score += 3;
      if (/個人|スタッフ|担当者|ユーザー|user.?id|password|login.?id|社員|staff/i.test(sign)) score -= 9;
      return {input,score};
    });
    candidates.sort((a,b)=>b.score-a.score);
    return candidates[0]?.score >= 9 ? candidates[0].input : null;
  }
  function fillCompanyId() {
    const field = findCompanyField();
    if (!field || field.value.trim()) return false;
    field.value = 'pasona';
    field.dispatchEvent(new Event('input',{bubbles:true}));
    field.dispatchEvent(new Event('change',{bubbles:true}));
    field.dataset.etcDefaultCompany = 'true';
    return true;
  }
  function login() {
    const body = document.body;
    body.classList.add('etc-login');
    const form = $('form[name="TMSLGN01ActionForm"]') || $$('form').find(f => f.querySelector('input[type="password"]'));
    if (!form) return;
    const company = $('input[name="comid"]',form) || findCompanyField();
    const userid = $('input[name="userid"]',form) || $('input[name="userId"]',form);
    const password = $('input[name="password"][type="password"]',form) || $('input[type="password"]',form);
    const submit = $('input[type="submit"][name="login"]',form) || $('input[type="submit"]',form);
    // Avoid modifying unexpected login forms; preserves server validation and a manual fallback.
    if (!company || !userid || !password || !submit) { fillCompanyId(); return; }

    // Capture news before moving legacy DOM. The actual notices and their source links
    // are moved as nodes, rather than copied or replaced with old/fabricated information.
    const noticeSources = ['news1','news1022','news0623','news13','news'];
    const notices = noticeSources.map(id => {
      const anchor = document.getElementById(id);
      const content = anchor?.nextElementSibling;
      if (!anchor || !content || content.tagName !== 'DIV') return null;
      const label = tidy(content.querySelector('span[style*="font-weight:bold"],b,strong')?.textContent || content.textContent).slice(0,95);
      return {anchor,content,label};
    }).filter(Boolean);
    const reset = $('a[href*="/s/TMSPWI01/"]',form);
    const faq = $('a[href*="/wtc_mobile/FAQ.html"]',form);
    const inquiry = $('a[href*="/wtc_mobile/Inquiry.html"]',form);
    const uptime = (tidy(form.textContent).match(/システムご利用時間\s*([0-9:～〜\- ]+)/) || [])[1]?.trim();

    // If the server shows validation errors, surface them instead of burying them.
    const errors = [];
    for (const child of Array.from(form.children)) {
      if (child.matches('table.table02')) break;
      const txt = tidy(child.textContent);
      if (!txt || txt.length > 180 || child.querySelector('a[href*="TMSPWI01"]')) continue;
      if (/(?:エラー|認証失敗|入力してください|正しくありません|一致しません|誤っています|ログインできません|無効な)/.test(txt)) errors.push(txt);
    }

    const logo = $('img[src*="/s/images/logo.gif"]');
    if (logo) { (logo.closest('h3')?.parentElement || logo).classList.add('etc-login-original-logo'); }

    const filled = !company.value.trim();
    if (filled) {
      company.value = 'pasona';
      company.dispatchEvent(new Event('input',{bubbles:true}));
      company.dispatchEvent(new Event('change',{bubbles:true}));
    }

    const original = document.createElement('div'); original.className = 'etc-login-original';
    while (form.firstChild) original.appendChild(form.firstChild);
    form.appendChild(original); // Hidden Struts anti-CSRF and session fields are still submitted.
    form.classList.add('etc-login-form');

    // Prevent reordering of the actual input elements: only transplant their nodes.
    const shell = document.createElement('div'); shell.className = 'etc-login-shell';
    shell.innerHTML = `
      <div class="etc-login-brand">
        <div class="etc-login-appicon">${svg('shield',28)}</div>
        <div><div class="etc-login-brandname">WebTimeCard</div><div class="etc-login-brandnote">e-staffing · Mobile</div></div>
      </div>
      <header class="etc-login-hero">
        <div class="etc-login-kicker">WELCOME BACK</div>
        <h1 class="etc-login-h1">ログイン</h1>
        <p class="etc-login-caption">アカウント情報を入力してください。</p>
      </header>
      <div id="etc-login-errors"></div>
      <section class="etc-login-form-card" aria-label="ログインフォーム">
        <div class="etc-login-field-row"><label class="etc-login-field-label" for="etc-comid">企業ID <span class="etc-login-prefilled" id="etc-login-prefilled" ${filled?'':'hidden'}>自動入力</span></label><div id="etc-comid-slot"></div></div>
        <div class="etc-login-field-row"><label class="etc-login-field-label" for="etc-userid">ユーザID</label><div id="etc-userid-slot"></div></div>
        <div class="etc-login-field-row"><label class="etc-login-field-label" for="etc-password">パスワード</label><div class="etc-login-password-box"><div id="etc-password-slot" style="width:100%"></div><button class="etc-login-toggle" type="button" id="etc-login-toggle" aria-label="パスワードを表示" aria-pressed="false">表示</button></div></div>
        <div id="etc-login-submit-slot"></div>
      </section>
      <div id="etc-login-reset-slot"></div>
      <section class="etc-login-notes">
        <div class="etc-login-section-heading">ご利用案内</div>
        <div class="etc-login-service"><span class="etc-login-service-icon">${svg('clock',21)}</span><div><div class="etc-login-service-strong">システム利用時間</div><div class="etc-login-service-detail">${esc(uptime || '公式サイトのお知らせをご確認ください')}</div></div></div>
        <div id="etc-login-notice-container"></div>
        <div class="etc-login-quick-links" id="etc-login-quick-links"></div>
        <div class="etc-login-disclaimer">非公式のデザイン変更です。ログイン・認証はe-staffingの公式フォームで処理されます。</div>
      </section>`;

    // Group ONLY the presentation containers for adaptive 1/2-column login layout.
    // Inputs remain the original Struts fields; their names, token and submit remain intact.
    const loginMain = document.createElement('div'); loginMain.className = 'etc-login-main';
    const loginIntro = document.createElement('div'); loginIntro.className = 'etc-login-intro';
    const loginFields = document.createElement('div'); loginFields.className = 'etc-login-fields';
    ['.etc-login-brand','.etc-login-hero'].forEach(selector => loginIntro.appendChild($(selector,shell)));
    ['#etc-login-errors','.etc-login-form-card','#etc-login-reset-slot'].forEach(selector => loginFields.appendChild($(selector,shell)));
    loginMain.append(loginIntro,loginFields);
    shell.prepend(loginMain);

    // Keep the original form as the single submitting form; preserve field names/maxlength.
    form.appendChild(shell);
    const fields = [
      [company,'etc-comid','#etc-comid-slot','organization'],
      [userid,'etc-userid','#etc-userid-slot','username'],
      [password,'etc-password','#etc-password-slot','current-password']
    ];
    fields.forEach(([field,id,slot,autocomplete]) => {
      field.id = id; field.classList.add('etc-login-field');
      field.setAttribute('autocomplete',autocomplete);
      field.setAttribute('autocapitalize','none');
      field.setAttribute('autocorrect','off');
      field.spellcheck = false;
      $(slot,shell).appendChild(field);
    });
    submit.classList.add('etc-login-submit'); $('#etc-login-submit-slot',shell).appendChild(submit);
    const prefilled = $('#etc-login-prefilled',shell);
    company.addEventListener('input', () => { if(prefilled)prefilled.hidden = company.value.trim() !== 'pasona'; });

    const toggle = $('#etc-login-toggle',shell);
    toggle.addEventListener('click',()=>{
      const shown = password.type === 'password';
      password.type = shown ? 'text' : 'password';
      toggle.textContent = shown ? '隠す' : '表示';
      toggle.setAttribute('aria-pressed',String(shown));
      toggle.setAttribute('aria-label',shown ? 'パスワードを隠す' : 'パスワードを表示');
    });

    if (reset) {
      reset.className = 'etc-login-reset';
      reset.textContent = 'パスワードを忘れた・ロック解除  ›';
      $('#etc-login-reset-slot',shell).appendChild(reset);
    }
    if (errors.length) {
      const el = document.createElement('div');el.className='etc-login-message';
      el.textContent = [...new Set(errors)].join(' / ');
      $('#etc-login-errors',shell).appendChild(el);
    }
    if (notices.length) {
      const wrap = document.createElement('div'); wrap.className='etc-login-notice-wrap';
      notices.forEach((n,i) => {
        const details=document.createElement('details');details.className='etc-login-notice';
        const summary=document.createElement('summary');
        const txt=document.createElement('span');txt.className='etc-login-notice-title';
        txt.textContent=n.label || '公式のお知らせ';
        summary.appendChild(txt);
        const chev=document.createElement('span');chev.className='etc-login-note-chevron';chev.innerHTML=svg('chevron',17);summary.appendChild(chev);
        const content=document.createElement('div');content.className='etc-login-news-body';
        content.appendChild(n.anchor);content.appendChild(n.content);
        details.appendChild(summary);details.appendChild(content);wrap.appendChild(details);
      });
      $('#etc-login-notice-container',shell).appendChild(wrap);
      // In-page old news links still work when users jump to their sections.
      const maybeOpen = () => {
        if (!location.hash) return;
        const target = document.getElementById(decodeURIComponent(location.hash.slice(1)));
        if (target) target.closest('details.etc-login-notice')?.setAttribute('open','');
      };
      window.addEventListener('hashchange',maybeOpen);maybeOpen();
    }
    const quick = $('#etc-login-quick-links',shell);
    [['よくある質問',faq],['お問い合わせ',inquiry]].forEach(([label,anchor])=>{
      if (!anchor) return;
      anchor.textContent=label;quick.appendChild(anchor);
    });
    // Old form content remains in DOM for compatibility but cannot visually overlay the new UI.
  }

  // The iPhone app uses a real SwiftUI Liquid Glass navigation overlay.
  // Browser userscripts keep the existing HTML bottom bar as a fallback.
  function setupNativeGlassNavigation(pageKey) {
    const bridge = window.webkit?.messageHandlers?.etcNavigationBridge;
    if (!bridge || typeof bridge.postMessage !== 'function') return;
    const style = document.createElement('style');
    style.id = 'etc-native-liquid-glass-bridge';
    style.textContent = `
      #etc-native-nav { display:none !important; }
      /* Native system bottomBar owns the appropriate bottom/trailing safe
         region (including Duo camera, status area, and vertical controls).
         Avoid the v2.7 fixed bottom padding and any handcrafted side gutter. */
      body.etc-native-v4:not(.etc-login) {
        padding-bottom:max(16px, env(safe-area-inset-bottom, 0px)) !important;
      }
    `;
    (document.head || document.documentElement).appendChild(style);
    const sheet = document.getElementById('etc-native-modal');
    const publish = () => {
      bridge.postMessage({
        page: pageKey,
        visible: pageKey !== 'login',
        sheetOpen: Boolean(sheet?.classList.contains('open')),
        theme: theme()
      });
    };
    // Reuse the same official URLs generated by the existing navbar, including
    // session/query parameters. Do not recreate navigation URLs in Swift.
    window.__etcNativeNavigate = (target) => {
      if (target !== 'settings' && target === pageKey) return true;
      if (target !== 'settings' && window.__etcNavigationPending) return false;
      const inner = document.querySelector('#etc-native-nav .etc-nav-inner');
      if (!inner) return false;
      let button = null;
      if (target === 'home') button = inner.querySelector('a:nth-of-type(1)');
      else if (target === 'daily') button = inner.querySelector('a:nth-of-type(2)');
      else if (target === 'close') button = inner.querySelector('a:nth-of-type(3)');
      else if (target === 'settings') button = document.getElementById('etc-settings-show');
      if (!button) return false;
      if (target !== 'settings') {
        window.__etcNavigationPending = true;
        window.setTimeout(() => { window.__etcNavigationPending = false; }, 2500);
      }
      button.click();
      if (target === 'settings') publish();
      return true;
    };
    if (sheet) new MutationObserver(publish).observe(sheet, { attributes:true, attributeFilter:['class'] });
    new MutationObserver(publish).observe(document.body, { attributes:true, attributeFilter:['data-etc-native-theme'] });
    publish();
  }

  // Paint guard is an independent, optional .user.css for earlier browser stylesheet injection.
  // Main UI runs synchronously at document-end as in v4.1.
  const p = page();
  if (p === 'other' && !location.pathname.startsWith('/s/TMS')) return;
  viewport();
  addCSS();
  document.body.classList.add('etc-native-v4');
  applyTheme(theme());
  if (p === 'login') { login(); setupNativeGlassNavigation(p); return; }
  removeBrandDecorations();
  if (p === 'home') menu();
  else if (p === 'daily' && $('form[name="TMSINP01ActionForm"]')) makeDaily($('form[name="TMSINP01ActionForm"]'));
  else if (p === 'close' && $('form[name="TMSINP02ActionForm"]')) makeClose($('form[name="TMSINP02ActionForm"]'));
  else decorateSettingsAndOther(p);
  navbar(p);
  setupNativeGlassNavigation(p);
})();
