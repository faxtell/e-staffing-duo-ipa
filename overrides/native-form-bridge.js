/* v3.0: read-only DOM snapshots + strictly allow-listed actions against ONE official WKWebView.
   Never exports form tokens/cookies. Only the official temporary-save button may be auto-activated.
   Never activates apply/cloApply or submits an application automatically. */
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
  const form = document.querySelector('form[name="TMSINP01ActionForm"]');
  if (!form) return;
  const post = payload => { try { window.webkit?.messageHandlers?.etcNativeFormBridge?.postMessage(payload); } catch(_){} };
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
  const values = () => Object.fromEntries(fieldNames.map(name=>[name, typeof field(name)?.value==='string' ? field(name).value.slice(0,120) : '']));
  function sendSnapshot() {
    const data={action:'dailySnapshot',date:dateText().slice(0,100),fields:values(),category:optionsFor(category()),workplace:optionsFor(workplace()),autosave:status(),canSave:!!form.querySelector('input[name="temStorage"]:not([disabled]),button[name="temStorage"]:not([disabled])')};
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
    if(busy || failed) return;
    revision++;
    clearTimeout(timer);
    updateStatus('pending');
    timer=setTimeout(() => {timer=null;sendTemporarySave();},2400);
  }
  function sendTemporarySave() {
    if(busy || failed)return false;
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
    schedule();sendSnapshot();return true;
  }
  function selectOption(which,index){
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
    schedule();sendSnapshot();return true;
  }
  window.__etcNativeFormAction = payload => {
    if(!payload || typeof payload!=='object')return false;
    if(payload.kind==='field')return setValue(payload.name,payload.value);
    if(payload.kind==='choice')return selectOption(payload.group,payload.index);
    if(payload.kind==='breakRecalculate') {
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
    if(handling||busy||failed)return;
    if(!event.target || !form.contains(event.target) || !event.isTrusted)return;
    if(event.target.closest('input[name="apply"],input[name="temStorage"],button[type=submit]'))return;
    handling=true;
    schedule();queueMicrotask(()=>{handling=false;sendSnapshot();});
  };
  form.addEventListener('input',capture,true);
  form.addEventListener('change',capture,true);
  // Hide redundant buttons in the web fallback too; leave named official fields untouched.
  for(const button of form.querySelectorAll('input[type=button],button[type=button]')){
    if(/^(定時|定時外)$/.test(text(button))) button.style.display='none';
  }
  let old=null;try{old=sessionStorage.getItem('etc-v30-temp-pending');}catch(_){}
  if(old){
    sessionStorage.removeItem('etc-v30-temp-pending');
    try{const obj=JSON.parse(old);if(Date.now()-obj.at<25000 && obj.date===cachedDate)lastState='verify';}catch(_){}
  }
  sendSnapshot();
})();
