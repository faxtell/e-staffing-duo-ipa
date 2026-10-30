const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const path=require('node:path');
const root=path.resolve(__dirname,'..');
const source=fs.readFileSync(path.join(root,'EStaffingTimeCard/Resources/native-form-bridge.js'),'utf8');
const screen=fs.readFileSync(path.join(root,'EStaffingTimeCard/NativeScreens.swift'),'utf8');
const swift=fs.readFileSync(path.join(root,'EStaffingTimeCard/TimeCardView.swift'),'utf8');
const pbx=fs.readFileSync(path.join(root,'EStaffingTimeCard.xcodeproj/project.pbxproj'),'utf8');
class Input {
  constructor(name,value=''){this.name=name;this.value=value;this.disabled=true;this.readOnly=true;this.tagName='INPUT';this.dataset={};}
  dispatchEvent(){}
}
const fields=Object.fromEntries(['startTime','endTime','rstTime','nightRstTime','remark'].map(n=>[n,new Input(n)]));
const rows=[
  ['区分','通常'],['就業場所','オフィス'],['開始','1004'],['終了','1835'],['休憩時間','60'],['備考','']
].map(pair=>{
  const cells=pair.map(x=>({textContent:x}));
  return {querySelector:x=>x==='td,th'?cells[0]:null,
    querySelectorAll:x=>x===':scope > th,:scope > td'?cells:[]};
});
const header={textContent:'10月30日（金）承認済',children:[]};
const form={
  elements:{namedItem:name=>fields[name]||null},
  querySelector:q=>q.includes('.etc-today-status')?header:null,
  querySelectorAll:q=>q==='tr'?rows:q==='div,span'?[header]:[],
  addEventListener(){}
};
const events=[];
const document={querySelector:q=>q==='form[name="TMSINP01ActionForm"]'?form:null};
const window={webkit:{messageHandlers:{etcNativeFormBridge:{postMessage:v=>events.push(v)}}}};
const ctx={window,document,location:{origin:'https://m.e-staffing.ne.jp',pathname:'/s/TMSINP01/'},
  HTMLInputElement:Input,HTMLButtonElement:class {},setTimeout:()=>1,clearTimeout:()=>{},Event:class {},
  sessionStorage:{getItem:()=>null}};
vm.runInNewContext(source,ctx,{timeout:1000});
const snap=events.find(x=>x.action==='dailySnapshot');
assert(snap,'Read-only daily snapshot must still be published');
assert.equal(snap.readOnly,true);
assert.equal(snap.approvalStatus,'承認済');
assert.equal(snap.fields.startTime,'1004');
assert.equal(snap.fields.endTime,'1835');
assert.equal(snap.fields.rstTime,'60');
assert.equal(snap.category.value,'通常');
assert.equal(snap.workplace.value,'オフィス');
assert.equal(snap.canSave,false);
assert.equal(window.__etcNativeFormAction({kind:'field',name:'startTime',value:'0900'}),false);
assert.equal(window.__etcNativeFormAction({kind:'save'}),false);
assert.equal(window.__etcNativeFormAction({kind:'breakRecalculate'}),false);
assert.equal(window.__etcNativeSubmission({kind:'submit',form:'daily',confirmed:true,period:'10月30日（金）承認済'}),false);
assert.equal(fields.startTime.value,'','Approved original DOM must not be edited');
for(const token of ['nativeDailyLocked','nativeDailyCategoryDisplay','nativeDailyWorkplaceDisplay',
 'nativeDailyApprovalStatus','guard page == "daily", !nativeDailyLocked'])
 assert(swift.includes(token),token);
for(const token of ['daily-approved-lock-banner','daily-approved-recorded-times',
  'daily-approved-readonly-card','daily-approved-tabletop-dashboard',
  'daily-approved-tabletop-details','daily-approved-official-link',
  'if model.nativeDailyLocked'])
 assert(screen.includes(token),token);
assert(screen.includes('if item.leave { return "年休" }'),'Leave label must override short approval state');
assert(screen.includes('Text(row?.leave == true ? "年休"'),'List must prioritize leave before work');
assert(screen.includes('if row?.work == true && row?.leave != true'),'Month grid must prioritize leave');
assert(screen.includes('(row?.known == true ? row?.status ?? "" : "")'),'Approval status belongs to secondary label');
assert(pbx.includes('MARKETING_VERSION = 3.8;'),'Marketing version must be updated');
console.log('v3.8 approved read-only DOM values, locked controls, and leave labeling: PASS');
