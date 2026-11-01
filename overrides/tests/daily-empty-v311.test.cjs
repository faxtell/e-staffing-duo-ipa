const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const path=require('node:path');
const root=path.resolve(__dirname,'..');
const bridge=fs.readFileSync(path.join(root,'EStaffingTimeCard/Resources/native-form-bridge.js'),'utf8');
const screens=fs.readFileSync(path.join(root,'EStaffingTimeCard/NativeScreens.swift'),'utf8');
const pbx=fs.readFileSync(path.join(root,'EStaffingTimeCard.xcodeproj/project.pbxproj'),'utf8');
const daily=screens.split('struct NativeDailyScreen: View')[1].split('struct ClosingMonthData')[0];

class Input {
 constructor(name,value='') {this.name=name;this.value=value;this.disabled=false;this.readOnly=false;this.tagName='INPUT';this.type='text';this.dataset={};}
 dispatchEvent(){}
}
const fields=Object.fromEntries(['startTime','endTime','rstTime','nightRstTime','remark'].map(n=>[n,new Input(n)]));
const labels=[['開始','09:00'],['終了','17:30'],['休憩時間','60'],['深夜休憩','30'],['区分','--']];
const rows=labels.map(([label,value])=>{
 const cells=[{textContent:label},{textContent:value}];
 return {querySelector:q=>q==='td,th'?cells[0]:null,
         querySelectorAll:q=>q===':scope > th,:scope > td'?cells:[]};
});
const header={textContent:'11月01日（日）：',children:[]};
const temp=new Input('temStorage');temp.type='submit';
const form={
 elements:{namedItem:n=>fields[n]||null},
 querySelector:q=>{
   if(q.includes('temStorage'))return temp;
   if(q.includes('.etc-today-status'))return header;
   if(q.includes('.etc-period'))return header;
   return null;
 },
 querySelectorAll:q=>q==='tr'?rows:q==='div,span'?[header]:[],
 addEventListener(){}
};
const events=[],window={webkit:{messageHandlers:{etcNativeFormBridge:{postMessage:p=>events.push(p)}}}};
const document={querySelector:q=>q==='form[name="TMSINP01ActionForm"]'?form:null};
const ctx={window,document,HTMLInputElement:Input,HTMLButtonElement:class {},CSS:{escape:x=>x},
 location:{origin:'https://m.e-staffing.ne.jp',pathname:'/s/TMSINP01/'},
 sessionStorage:{getItem:()=>null},clearTimeout:()=>{},setTimeout:()=>1,
 Event:class {},queueMicrotask:fn=>fn()};
vm.runInNewContext(bridge,ctx,{timeout:1000});
let snap=events.find(e=>e.action==='dailySnapshot');
assert(snap,'Must emit the actual official form snapshot');
assert.equal(snap.readOnly,false,'New unentered day must stay editable');
for(const name of ['startTime','endTime','rstTime','nightRstTime','remark'])
 assert.equal(snap.fields[name],'',name+' must not be inferred from adjacent label or template');
assert.equal(events.filter(e=>e.action==='saveState').length,0,'Initial load must not autosave');
assert.equal(window.__etcNativeFormAction({kind:'field',name:'startTime',value:'1004'}),true);
snap=events.filter(e=>e.action==='dailySnapshot').at(-1);
assert.equal(snap.fields.startTime,'1004','Explicit user entry must still flow through');
for(const name of ['endTime','rstTime','nightRstTime'])
 assert.equal(snap.fields[name],'','Other values must remain truly blank');
assert(daily.includes('if minuteOfDay(field(name)) != nil'),'Empty time must not render DatePicker default');
assert(daily.includes('Label("未入力", systemImage:"clock.badge.questionmark")'),'Empty time needs a visible placeholder');
assert(daily.includes('Button("この時刻を入力")'),'Time editor must commit only after user action');
assert(daily.includes('enteredRestMinutes == nil ? "予定休憩" : "休憩"'),'Preview break must be clearly labeled planned');
assert(daily.includes('enteredRestMinutes == nil ? "休憩目安'),'Planned break must not be recorded as actual');
assert(pbx.includes('MARKETING_VERSION = 3.11;'));
console.log('v3.11 unentered editable days stay blank, deliberate entry remains possible: PASS');
