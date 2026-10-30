const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const path=require('node:path');
const root=path.resolve(__dirname,'..');
const source=fs.readFileSync(path.join(root,'EStaffingTimeCard/Resources/native-form-bridge.js'),'utf8');
const swift=fs.readFileSync(path.join(root,'EStaffingTimeCard/TimeCardView.swift'),'utf8');
const screens=fs.readFileSync(path.join(root,'EStaffingTimeCard/NativeScreens.swift'),'utf8');
const pbx=fs.readFileSync(path.join(root,'EStaffingTimeCard.xcodeproj/project.pbxproj'),'utf8');
function fixture(kind) {
  const events=[],clicks=[];
  class Input {
    constructor(name,value=''){this.name=name;this.type='submit';this.tagName='INPUT';this.readOnly=false;this.disabled=false;this.value=value;this.dataset={};}
    closest(which){return which==='form'?form:null}
    click(){clicks.push(this.name)}
    dispatchEvent(){}
  }
  class Button extends Input {}
  const target=new Input(kind==='daily'?'apply':'cloApply');
  const temp=new Input('temStorage');
  const fields=Object.fromEntries(['startTime','endTime','rstTime','nightRstTime','remark']
    .map(k=>[k,new Input(k,k==='startTime'?'0900':k==='endTime'?'1730':k==='rstTime'?'60':'')]));
  const form={
    dataset:{},
    elements:{namedItem:n=>fields[n]},
    querySelector(query) {
      if(query.startsWith('input[name="apply"]') && kind==='daily')return target;
      if(query.startsWith('input[name="cloApply"]') && kind==='close')return target;
      if(query.includes('temStorage'))return temp;
      if(query.includes('.etc-period') || query.includes('.etc-today-status'))return {textContent:'2026年10月16日～31日'};
      return null;
    },
    querySelectorAll(){return []},
    addEventListener(){}
  };
  const document={
    querySelector(query){
      if(query==='form[name="TMSLGN01ActionForm"]')return null;
      if(query==='form[name="TMSINP01ActionForm"]')return kind==='daily'?form:null;
      if(query==='form[name="TMSINP02ActionForm"]')return kind==='close'?form:null;
      return null;
    }
  };
  const window={webkit:{messageHandlers:{etcNativeFormBridge:{postMessage:x=>events.push(x)}}}};
  const context={window,document,location:{origin:'https://m.e-staffing.ne.jp',pathname:'/s/'},
    HTMLInputElement:Input,HTMLButtonElement:Button,
    setTimeout:()=>1,clearTimeout:()=>{},sessionStorage:{getItem:()=>null},Event:class {}};
  vm.runInNewContext(source,context,{filename:'native-form-bridge.js',timeout:1000});
  return {window,events,clicks,target};
}
for(const kind of ['daily','close']){
  const f=fixture(kind);
  const first=f.events.find(x=>x.action==='submissionSnapshot');
  assert.equal(first.kind,kind);
  assert.equal(first.available,true);
  assert.equal(f.clicks.length,0,'Do not send on bootstrap');
  const call={kind:'submit',form:kind,confirmed:true,period:first.period};
  assert.equal(f.window.__etcNativeSubmission({...call,confirmed:false}),false);
  assert.equal(f.window.__etcNativeSubmission({...call,period:'別の期間'}),false);
  assert.equal(f.window.__etcNativeSubmission({...call,form:kind==='daily'?'close':'daily'}),false);
  assert.equal(f.clicks.length,0,'Reject unconfirmed, stale or wrong form submissions');
  f.target.disabled=true;
  assert.equal(f.window.__etcNativeSubmission(call),false);
  f.target.disabled=false;
  assert.equal(f.window.__etcNativeSubmission(call),true);
  assert.deepEqual(f.clicks,[kind==='daily'?'apply':'cloApply'],'Must click original named official control once');
  assert.equal(f.window.__etcNativeSubmission(call),false,'Never duplicate an application');
  assert.equal(f.window.__etcNativeSubmissionCancel(),true,'Official confirm cancellation unlocks');
  assert.equal(f.window.__etcNativeSubmission(call),true,'Explicit subsequent user action can retry after cancellation');
}
for(const token of [
  'nativeCanDailyApply','nativeCanCloseApply','nativeSubmit(_ kind: String)',
  'nativeSubmissionInFlight', 'receiveNativeSubmission',
  'runJavaScriptConfirmPanelWithMessage','runJavaScriptAlertPanelWithMessage',
  'window.__etcNativeSubmission?.','navigation.page == "close"'
])assert(swift.includes(token),'Swift bridge missing: '+token);
for(const token of ['daily-native-apply','tabletop-daily-native-apply',
  'closing-native-apply','tabletop-closing-native-apply',
  'confirmDailyApplication','confirmCloseApplication',
  'model.nativeSubmit("daily")','model.nativeSubmit("close")',
  'model.nativeCloseApplyPeriod'])
  assert(screens.includes(token),'Native UI missing: '+token);
assert(source.includes("button.click()"),'Must use original official action');
assert(!source.includes('fetch('),'Must not fabricate network requests');
assert(!source.includes('form.submit()'),'Must not bypass official form validation');
assert(!screens.includes('申請が完了しました'),'Do not claim server success from mere click');
assert(pbx.includes('MARKETING_VERSION = 3.7;'),'Version must increment');
console.log('v3.7 native daily/close submission, confirmation, no duplicates: PASS');
