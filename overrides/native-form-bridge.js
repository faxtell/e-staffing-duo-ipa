/* v3.7: native submission is available only after explicit user confirmation.
   This bridge clicks the official page's own named control in the ONE session WKWebView.
   It never fabricates requests or exports cookies, tokens, form contents or URLs. */
(() => {
  'use strict';
  if (location.origin !== 'https://m.e-staffing.ne.jp' || !location.pathname.startsWith('/s/')) return;
  const loginForm=document.querySelector('form[name="TMSLGN01ActionForm"]');
  if(loginForm){
    window.__etcNativeLogin = payload => {
      if(!payload || typeof payload!=='object')return false;
      const company=loginForm.querySelector('input[name="comid"]');
      const user=loginForm.querySelector('input[name="userid"]');
      const password=loginForm.querySelector('input[name="password"]');
      const submit=loginForm.querySelector('input[type="submit"][name="login"]');
      if(!company||!user||!password||!submit||submit.disabled||
         typeof payload.company!=='string'||typeof payload.user!=='string'||
         typeof payload.password!=='string'||payload.user.length>128||
         payload.password.length>512||!payload.user||!payload.password)return false;
      const actionURL=new URL(loginForm.action,location.href);
      if(actionURL.origin!==location.origin || !actionURL.pathname.startsWith('/s/TMSLGN01/'))return false;
      company.value=payload.company.slice(0,128);user.value=payload.user;password.value=payload.password;
      for(const el of [company,user,password])el.dispatchEvent(new Event('change',{bubbles:true}));
      const optin=loginForm.querySelector('#etc-credentials-opt-in');
      if(optin)optin.checked=payload.remember===true;
      submit.click();return true;
    };
    return;
  }
  const post = payload => { try { window.webkit?.messageHandlers?.etcNativeFormBridge?.postMessage(payload); } catch(_){} };
  const form = document.querySelector('form[name="TMSINP01ActionForm"]');
  const closingForm = document.querySelector('form[name="TMSINP02ActionForm"]');
  const submissionForm = form || closingForm;
  if (!submissionForm) return;
  const submissionKind = form ? 'daily' : 'close';
  const submissionName = form ? 'apply' : 'cloApply';
  const plainText = element => String(element?.textContent || '').trim().replace(/\\s+/g,' ').slice(0,120);
  const submissionPeriod = () =>
    plainText(submissionForm.querySelector('.etc-today-status,.etc-period,.divCenter')) ||
    (submissionKind === 'daily' ? '表示中の日付' : '表示中の締め期間');
  const officialSubmit = () => {
    const el = submissionForm.querySelector('input[name="' + submissionName + '"],button[name="' + submissionName + '"]');
    if (!el || el.disabled || el.closest('form') !== submissionForm) return null;
    if (!(el instanceof HTMLInputElement || el instanceof HTMLButtonElement)) return null;
    if (!['submit','button','image'].includes(el.type)) return null;
    return el;
  };
  let submissionLocked = false;
  const nativeSubmissionReady = () => {
    const button = officialSubmit();
    return !!button && !submissionLocked && !document.querySelector('[data-etc-native-submit-busy="true"]');
  };
  const submissionSnapshot = () => post({
    action: 'submissionSnapshot', kind: submissionKind,
    period: submissionPeriod(), available: nativeSubmissionReady()
  });
  window.__etcNativeSubmission = payload => {
    if (!payload || payload.kind !== 'submit' || payload.form !== submissionKind ||
        payload.confirmed !== true || typeof payload.period !== 'string' ||
        payload.period !== submissionPeriod() || !nativeSubmissionReady()) return false;
    // Changes pending in daily autosave must be committed/verified first.
    if (form && (busy || timer || failed || lastState === 'sending' ||
                  lastState === 'pending' || lastState === 'verify' ||
                  lastState === 'local')) return false;
    const button = officialSubmit();
    if (!button) return false;
    submissionLocked = true;
    submissionForm.dataset.etcNativeSubmitBusy = 'true';
    post({action: 'submissionState', kind: submissionKind, status: 'initiated',
          message: '公式フォームの申請操作を開始しました。結果は確認中です。'});
    try {
      button.click(); // Official validation, confirmation and server session own the request.
      submissionSnapshot();
      return true;
    } catch (_) {
      submissionLocked = false;
      delete submissionForm.dataset.etcNativeSubmitBusy;
      post({action:'submissionState',kind:submissionKind,status:'error',
            message:'公式画面で申請操作を開始できませんでした。'});
      submissionSnapshot();
      return false;
    }
  };
  window.__etcNativeSubmissionCancel = () => {
    if (!submissionLocked) return false;
    submissionLocked = false;
    delete submissionForm.dataset.etcNativeSubmitBusy;
    post({action:'submissionState',kind:submissionKind,status:'cancelled',
          message:'公式確認画面で申請をキャンセルしました。送信していません。'});
    submissionSnapshot();
    return true;
  };
  if (!form) { submissionSnapshot(); return; }
  const fieldNames = ['startTime','endTime','rstTime','nightRstTime','remark'];
  let busy = false, timer = null, revision = 0, failed = false, lastState = '';
  const text = e => String(e?.textContent || e?.value || '').trim().replace(/\s+/g,' ').slice(0,90);
  const rowFor = word => [...form.querySelectorAll('tr')].find(row => {
    const label = row.querySelector('td,th');
    return label && text(label).includes(word) && row.querySelector('select,input[type=radio],input[type=checkbox]');
  });
  const category = () => rowFor('区分');
  const workplace = () => rowFor('就業場所');
  const optionsFor = row => {
    if (!row) return {kind:'none',options:[]};
    const select=row.querySelector('select');
    if(select) return {kind:'select',options:[...select.options].map((o,index)=>({index,label:text(o),selected:o.selected,disabled:o.disabled})).filter(o=>o.label)};
    const type = row.querySelector('input[type="radio"]') ? 'radio' : 'checkbox';
    const controls=[...row.querySelectorAll(`input[type="${type}"]`)];
    return {kind:type,options:controls.map((control,index)=>{
      const label=control.closest('label') || row.querySelector(`label[for="${CSS.escape(control.id||'___')}"]`);
      return {index,label:text(label)||text(control.nextElementSibling)||text(control.parentElement).slice(0,30)||`項目${index+1}`,selected:control.checked,disabled:control.disabled};
    })};
  };
  const field = name => form.elements.namedItem(name);
  const dateText = () => text(form.querySelector('.etc-today-status')) || text(form.querySelector('.etc-period'));
  let cachedDate = dateText();
  // Approved records use text cells instead of editable form inputs. Read only
  // the labels displayed by the official page; never invent a default value.
  const clean = value => String(value || '').replace(/\s+/g,' ').trim().slice(0,120);
  const statusText = () => {
    const heading = [form.querySelector('.etc-today-status'),form.querySelector('.etc-period'),
                     ...[...form.querySelectorAll('div,span')].filter(e =>
                       e.children.length === 0 && clean(e.textContent).length < 90)];
    const s = heading.map(e => clean(e?.textContent)).find(x => /承認済|申請済|差戻|申請中|作成中/.test(x));
    const found = s?.match(/承認済|申請済|差戻|申請中|作成中/);
    return found ? found[0] : '';
  };
  const editableField = name => {
    const el = field(name);
    return el && /^(INPUT|TEXTAREA|SELECT)$/.test(el.tagName || '') &&
      !el.disabled && !el.readOnly;
  };
  // Status alone is authoritative for approved records. Also protect any
  // record with no actual writable attendance controls.
  const isLocked = () => /承認済/.test(statusText()) ||
    (fieldNames.filter(n=>n!=='remark'&&n!=='nightRstTime').every(n=>!editableField(n)) &&
     !form.querySelector('input[name="temStorage"]:not([disabled]),button[name="temStorage"]:not([disabled])'));
  const labeledValue = words => {
    for (const row of form.querySelectorAll('tr')) {
      const cells = [...row.querySelectorAll(':scope > th,:scope > td')];
      if (cells.length < 2) continue;
      const label = clean(cells[0].textContent);
      if (!words.some(w => label.includes(w))) continue;
      const cell = cells.slice(1).find(e => clean(e.textContent));
      if (cell) return clean(cell.textContent);
    }
    for (const dt of form.querySelectorAll('dt')) {
      if (words.some(w => clean(dt.textContent).includes(w))) {
        const sibling=dt.nextElementSibling;
        if(sibling && sibling.tagName==='DD') return clean(sibling.textContent);
      }
    }
    return '';
  };
  const displayValue = name => {
    const fromInput = field(name);
    if (fromInput && typeof fromInput.value === 'string' && fromInput.value.trim()) return fromInput.value.slice(0,120);
    const labels = {
      startTime:['開始','出勤'], endTime:['終了','退勤'],
      rstTime:['休憩時間','休憩'],nightRstTime:['深夜休憩'],
      remark:['備考']
    };
    const raw=labeledValue(labels[name] || []);
    if (name==='startTime'||name==='endTime') {
      const match=raw.replace(/[：:]/g,'').match(/(?:^|\D)([01]\d|2[0-3])([0-5]\d)(?:\D|$)/);
      return match ? match[1]+match[2] : '';
    }
    if(name==='rstTime'||name==='nightRstTime'){
      const match=raw.match(/\b(\d{1,3})\s*(?:分)?\b/);
      return match ? match[1] : '';
    }
    return raw;
  };
  const optionsSnapshot = (row, which) => {
    const result=optionsFor(row);
    if(result.options.length) return result;
    const value=labeledValue(which==='category'?['区分']:['就業場所']);
    return {kind:'display',options:[],value};
  };
  const values = () => Object.fromEntries(fieldNames.map(name=>[name, displayValue(name)]));
  function sendSnapshot() {
    const locked=isLocked();
    const data={action:'dailySnapshot',date:dateText().slice(0,100),fields:values(),
      category:optionsSnapshot(category(),'category'),workplace:optionsSnapshot(workplace(),'workplace'),
      readOnly:locked,approvalStatus:statusText(),
      autosave:locked?'locked':status(),
      canSave:!locked&&!!form.querySelector('input[name="temStorage"]:not([disabled]),button[name="temStorage"]:not([disabled])')};
    post(data);
  }
  function status() {return busy?'sending':failed?'error':timer?'pending':lastState||'idle';}
  function updateStatus(value) {lastState=value;post({action:'saveState',status:value});}
  function isComplete() {
    // Some leave/absence categories legitimately have no start/end; do NOT infer complete.
    // Server-side temporary save may need more conditions than these, so only use
    // this conservative check before attempting the official action.
    const start=String(field('startTime')?.value||''), end=String(field('endTime')?.value||'');
    return /^\d{4}$/.test(start) && /^\d{4}$/.test(end) && !busy && !failed;
  }
  function schedule() {
    if(isLocked() || busy || failed) return;
    revision++;
    clearTimeout(timer);
    updateStatus('pending');
    timer=setTimeout(() => {timer=null;sendTemporarySave();},2400);
  }
  function sendTemporarySave() {
    if(isLocked() || busy || failed)return false;
    const temp=form.querySelector('input[name="temStorage"]:not([disabled]),button[name="temStorage"]:not([disabled])');
    if(!temp || !isComplete()) {updateStatus('local');sendSnapshot();return false;}
    if(!(temp instanceof HTMLInputElement || temp instanceof HTMLButtonElement)) return false;
    // Never activate a non-temStorage submit, and never fabricate POST or AJAX calls.
    if(temp.name!=='temStorage'){return false;}
    busy=true;clearTimeout(timer);timer=null;
    updateStatus('sending');
    try {
      try{sessionStorage.setItem('etc-v30-temp-pending',JSON.stringify({at:Date.now(),date:cachedDate}));}catch(_){}
      temp.click(); // official page's own onClick / form submission
      // If no navigation occurred and the server did not acknowledge, do not claim success.
      setTimeout(()=>{if(busy){busy=false;failed=true;updateStatus('verify');}},8500);
      return true;
    } catch(_) {busy=false;failed=true;updateStatus('error');return false;}
  }
  // Original source fields continue to be the only fields submitted to the official server.
  const nativeSetter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value')?.set;
  function setValue(name,value){
    if(isLocked())return false;
    if(!fieldNames.includes(name)||typeof value!=='string'||value.length>120)return false;
    const input=field(name);if(!input || !('value' in input))return false;
    if(name==='startTime'||name==='endTime') {
      if(!/^\d{4}$/.test(value))return false;
      const hh=+value.slice(0,2),mm=+value.slice(2);
      if(hh>23||mm>59)return false;
    }
    if(input instanceof HTMLInputElement && nativeSetter)nativeSetter.call(input,value);else input.value=value;
    input.dispatchEvent(new Event('input',{bubbles:true}));
    input.dispatchEvent(new Event('change',{bubbles:true}));
    schedule();sendSnapshot();submissionSnapshot();return true;
  }
  function selectOption(which,index){
    if(isLocked())return false;
    if(!['category','workplace'].includes(which)||!Number.isInteger(index)||index<0||index>30)return false;
    const row=which==='category'?category():workplace();if(!row)return false;
    const select=row.querySelector('select');
    if(select){
      const option=select.options[index];if(!option||option.disabled)return false;
      select.selectedIndex=index;select.dispatchEvent(new Event('input',{bubbles:true}));select.dispatchEvent(new Event('change',{bubbles:true}));
    }else{
      const type=row.querySelector('input[type="radio"]')?'radio':'checkbox';
      const inputs=[...row.querySelectorAll(`input[type="${type}"]`)];
      const input=inputs[index];if(!input||input.disabled)return false;
      if(type==='checkbox'){
        // Workplace on the official form may permit multiple simultaneous choices.
        // Keep this as a toggle; don't impose invented radio-style exclusivity.
        input.checked=!input.checked;
      }else input.checked=true;
      input.dispatchEvent(new Event('input',{bubbles:true}));input.dispatchEvent(new Event('change',{bubbles:true}));
    }
    schedule();sendSnapshot();submissionSnapshot();return true;
  }
  window.__etcNativeFormAction = payload => {
    if(!payload || typeof payload!=='object')return false;
    if(payload.kind==='field') { const updated=setValue(payload.name,payload.value); if(updated) submissionSnapshot(); return updated; }
    if(payload.kind==='choice')return selectOption(payload.group,payload.index);
    if(payload.kind==='breakRecalculate') {
      if(isLocked())return false;
      const button=form.querySelector('.etc-break-assistant-button');
      if(!button || button.disabled) return false;
      button.click(); sendSnapshot(); return true;
    }
    if(payload.kind==='save')return sendTemporarySave();
    if(payload.kind==='refresh'){sendSnapshot();return true;}
    return false;
  };
  let handling = false;
  const capture = event => {
    if(handling||isLocked()||busy||failed)return;
    if(!event.target || !form.contains(event.target) || !event.isTrusted)return;
    if(event.target.closest('input[name="apply"],input[name="temStorage"],button[type=submit]'))return;
    handling=true;
    schedule();queueMicrotask(()=>{handling=false;sendSnapshot();});
  };
  form.addEventListener('input',capture,true);
  form.addEventListener('change',capture,true);
  form.addEventListener('input',submissionSnapshot,true);
  form.addEventListener('change',submissionSnapshot,true);
  // Hide redundant buttons in the web fallback too; leave named official fields untouched.
  for(const button of form.querySelectorAll('input[type=button],button[type=button]')){
    if(/^(定時|定時外)$/.test(text(button))) button.style.display='none';
  }
  let old=null;try{old=sessionStorage.getItem('etc-v30-temp-pending');}catch(_){}
  if(old){
    sessionStorage.removeItem('etc-v30-temp-pending');
    try{const obj=JSON.parse(old);if(Date.now()-obj.at<25000 && obj.date===cachedDate)lastState='verify';}catch(_){}
  }
  sendSnapshot();submissionSnapshot();
})();
