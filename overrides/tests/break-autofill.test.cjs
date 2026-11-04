const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const script = fs.readFileSync(
  path.resolve(__dirname, '../EStaffingTimeCard/Resources/break-autofill.js'),'utf8'
);

function fixture({startTime='',endTime='',restTime='',readOnly=false,disabled=false}={}) {
  const generated = [];
  const target = {children:[],append(...nodes) {this.children.push(...nodes);}};
  class Element {
    constructor(tagName='div'){
      this.tagName=tagName.toUpperCase(); this.children=[]; this.handlers={};
      this.textContent=''; this.disabled=false; this.readOnly=false;
      this.className=''; this.type=''; this.dataset={};
      this.events=[];
    }
    append(...items){this.children.push(...items);}
    setAttribute(name,val){this[name]=val;}
    addEventListener(kind,callback){(this.handlers[kind] ||= []).push(callback);}
    dispatchEvent(event){
      this.events.push(event.type);
      for (const fn of this.handlers[event.type]||[])fn(event);
    }
    click(){this.dispatchEvent({type:'click'});}
    closest(){return target;}
  }
  class Input extends Element {
    constructor(name,value){
      super('input');this.name=name;this._value=value;this.writes=0;
    }
    get value(){return this._value;}
    set value(next){this._value=next;this.writes++;}
  }
  class Event { constructor(type,opts={}){this.type=type;this.bubbles=opts.bubbles;} }
  const start=new Input('startTime',startTime);
  const end=new Input('endTime',endTime);
  const rest=new Input('rstTime',restTime);
  rest.readOnly=readOnly; rest.disabled=disabled;
  const form={dataset:{},querySelector(query){
    if(query==='input[name="startTime"]')return start;
    if(query==='input[name="endTime"]')return end;
    if(query==='input[name="rstTime"]')return rest;
    return null;
  }};
  const head={append(){},appendChild(){}};
  const document={
    querySelector:query=>query==='form[name="TMSINP01ActionForm"]'?form:null,
    createElement:tag=>{const node=new Element(tag);generated.push(node);return node;},
    head,documentElement:head
  };
  vm.runInNewContext(script,{document,location:{hostname:'m.e-staffing.ne.jp',
    pathname:'/s/TMSINP01/'},HTMLInputElement:Input,Event},{timeout:1000});
  const button=generated.find(el=>el.className==='etc-break-assistant-button');
  const caption=generated.find(el=>el.className==='etc-break-assistant-caption');
  assert(button&&caption,'Must render hint + explicit apply button');
  return {start,end,rest,form,button,caption,Event,
    enter(field,value){
      field.value=value;
      field.dispatchEvent(new Event('input',{bubbles:true}));
      field.dispatchEvent(new Event('change',{bubbles:true}));
    }};
}

// Loading never mutates official form fields, even when long work hours are present.
const loaded=fixture({startTime:'0900',endTime:'1800'});
assert.equal(loaded.rest.value,'');
assert.equal(loaded.rest.writes,0);
assert.equal(loaded.rest.events.length,0);
assert.equal(loaded.button.disabled,false);
assert.match(loaded.caption.textContent,/60分/);

// Reaching or crossing the legal guidance tiers NEVER fills blank/0 fields.
const blank=fixture();
blank.enter(blank.start,'0900');
blank.enter(blank.end,'1501');
assert.equal(blank.rest.value,'','More than six hours must not populate a break');
assert.match(blank.caption.textContent,/45分/);
blank.enter(blank.end,'1730');
assert.equal(blank.rest.value,'','More than eight hours must not populate a break');
assert.match(blank.caption.textContent,/60分/);
assert.equal(blank.rest.writes,0,'Guidance is strictly read-only');
assert.equal(blank.rest.events.length,0,'Guidance must not cause autosave');

// Preserve explicit user-entered breaks, including zero and short actual breaks.
for(const value of ['0','15','30','45','90']){
  const f=fixture({startTime:'0900',endTime:'1900',restTime:value});
  f.enter(f.end,'2000');
  assert.equal(f.rest.value,value,'Do not overwrite actual '+value+' minute break');
  assert.equal(f.rest.writes,0);
}

// Apply only after a deliberate click; only then fire standard DOM changes.
blank.button.click();
assert.equal(blank.rest.value,'60');
assert.deepEqual(blank.rest.events,['input','change']);
assert.equal(blank.rest.writes,1);
assert.equal(blank.start.value,'0900');
assert.equal(blank.end.value,'1730');

// Approved/read-only inputs are never altered, even if the action is invoked.
const locked=fixture({startTime:'0900',endTime:'1800',readOnly:true});
assert.equal(locked.button.disabled,true);
locked.button.click();
assert.equal(locked.rest.writes,0);
assert.equal(locked.rest.value,'');
const disabled=fixture({startTime:'0900',endTime:'1800',disabled:true});
disabled.button.click();
assert.equal(disabled.rest.writes,0);

// No input mutation without user action and no form/network submission.
assert(!/\bfetch\s*\(/.test(script));
assert(!/\bform\.submit\s*\(/.test(script));
assert(!/\btemStorage\b/.test(script));
assert(!/\bapply\s*\(/.test(script));
assert(script.includes("action.addEventListener('click'"));
console.log('BREAK GUIDANCE: thresholds are display-only; explicit click required: PASS');
