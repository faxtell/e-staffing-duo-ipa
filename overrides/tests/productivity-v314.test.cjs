const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const path=require('node:path');
const root=path.resolve(__dirname,'..');
const screens=fs.readFileSync(path.join(root,'EStaffingTimeCard/NativeScreens.swift'),'utf8');
const swift=fs.readFileSync(path.join(root,'EStaffingTimeCard/TimeCardView.swift'),'utf8');
const bridge=fs.readFileSync(path.join(root,'EStaffingTimeCard/Resources/native-form-bridge.js'),'utf8');
const pbx=fs.readFileSync(path.join(root,'EStaffingTimeCard.xcodeproj/project.pbxproj'),'utf8');

function fixture(locked=false){
  const events=[];
  class Input {
    constructor(name,value=''){
      this.name=name;this.value=value;this.disabled=locked;
      this.readOnly=locked;this.tagName='INPUT';this.dataset={};
      this.type='text';this.writes=0;
    }
    dispatchEvent(){this.writes++;}
  }
  const fields=Object.fromEntries(['startTime','endTime','rstTime','nightRstTime','remark']
    .map(name=>[name,new Input(name)]));
  const temp=new Input('temStorage');temp.type='submit';temp.disabled=locked;
  const header={textContent:locked?'10月30日 承認済':'11月9日 入力中',children:[]};
  const form={
    elements:{namedItem:name=>fields[name]||null},
    querySelector(q){
      if(q.includes('temStorage'))return locked?null:temp;
      if(q.includes('.etc-today-status')||q.includes('.etc-period'))return header;
      return null;
    },
    querySelectorAll(q){return q==='div,span'?[header]:[];},
    addEventListener(){}
  };
  const document={querySelector:q=>q==='form[name="TMSINP01ActionForm"]'?form:null};
  const window={webkit:{messageHandlers:{etcNativeFormBridge:{
    postMessage:event=>events.push(event)
  }}}};
  const ctx={window,document,HTMLInputElement:Input,HTMLButtonElement:class {},
    location:{origin:'https://m.e-staffing.ne.jp',pathname:'/s/TMSINP01/'},
    sessionStorage:{getItem:()=>null},clearTimeout:()=>{},
    setTimeout:()=>1,Event:class{constructor(type){this.type=type;}},
    queueMicrotask:fn=>fn()};
  vm.runInNewContext(bridge,ctx,{timeout:1500});
  return {events,fields,action:window.__etcNativeFormAction};
}
const values={startTime:'0900',endTime:'1730',rstTime:'60'};
const edit=fixture(false);
assert.deepEqual(
 Object.fromEntries(Object.entries(edit.fields).map(([k,f])=>[k,f.value])),
 {startTime:'',endTime:'',rstTime:'',nightRstTime:'',remark:''}
);
assert.equal(edit.action({kind:'template',values,confirmed:false}),false,
 'Opening a preview must never edit official fields');
assert.equal(edit.fields.startTime.value,'');
assert.equal(edit.action({kind:'template',values,confirmed:true}),true);
assert.equal(edit.fields.startTime.value,'0900');
assert.equal(edit.fields.endTime.value,'1730');
assert.equal(edit.fields.rstTime.value,'60');
assert.equal(edit.fields.nightRstTime.value,'','Templates cannot fake night break');
assert.equal(edit.events.filter(e=>e.action==='templateResult'&&e.success).length,1);
assert.equal(edit.events.filter(e=>e.action==='saveState'&&e.status==='pending').length,1,
 'One atomic confirmed template -> one local pending save');
assert.equal(edit.action({kind:'template',values:{...values,rstTime:'1000'},confirmed:true}),false);
assert.equal(edit.action({kind:'template',values:{...values,startTime:'2460'},confirmed:true}),false);
assert.equal(edit.action({kind:'template',values:{...values,remark:'hello'},confirmed:true}),false);
assert.equal(edit.fields.rstTime.value,'60');
const approved=fixture(true);
assert.equal(approved.action({kind:'template',values,confirmed:true}),false);
assert.equal(approved.fields.startTime.value,'');
assert.equal(approved.fields.rstTime.value,'');

for(const key of [
 'native-home-priority-dashboard','home-open-analytics',
 'native-monthly-analytics','analytics-official-status-chart',
 'native-sync-status','native-calendar-day-preview',
 'daily-select-work-template','daily-template-preview',
 'daily-confirm-template','daily-template-context-tip',
 'daily-break-context-tip','daily-expanded-two-column',
 'daily-fold-book','daily-fold-tabletop',
 'closing-outer-list','closing-inner-calendar','closing-tabletop-mini-calendar',
 'NativeSyncStatusBanner(model: model)','NativeWorkTemplate.presets'
])assert(screens.includes(key),'Missing functionality: '+key);
for(const key of [
 'var stateLabel: String','var stateSymbol: String','var stateTint: Color',
 'var approvalDescription: String','status.contains("承認済")',
 'if !known { return "未取得" }',
 'if work { return "勤務記録あり" }',
 '@Published var nativeAnalysisOpen = false',
 'var nativeSyncStatus: String','lastOfficialDailyAt = Date()',
 'lastOfficialDashboardAt = Date()','lastOfficialCalendarAt = Date()',
 'if page == "daily"','"保存結果は未確認"',
 'action == "templateResult"','func navigate(_ destination: String)'
])assert(swift.includes(key),'Missing state/sync logic: '+key);
assert(!swift.includes('if status == "済" { return "承認済" }'),
 'Generic short completed state is not approval');
assert(screens.includes('if !completeHours'),'Incomplete periods cannot invent zero hours');
assert(screens.includes('knownRows.isEmpty ? "—"'),'Missing annual-leave data must not mean zero');
assert(screens.includes('onLongPressGesture(minimumDuration: 0.55)'),
 'Long-press preview is required');
assert(!screens.includes('申請前スマートチェック'),
 'Requested feature 6 must remain excluded');
assert(pbx.includes('MARKETING_VERSION = 3.14;'),'Release version must match 3.14');
console.log('v3.14 verified: official status, home, templates, analytics, sync, Duo, help tips: PASS');
