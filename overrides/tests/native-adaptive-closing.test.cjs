const fs=require('node:fs'), assert=require('node:assert/strict'), path=require('node:path');
const p=path.resolve(__dirname,'../EStaffingTimeCard');
const screens=fs.readFileSync(path.join(p,'NativeScreens.swift'),'utf8');
const view=fs.readFileSync(path.join(p,'TimeCardView.swift'),'utf8');
const bridge=fs.readFileSync(path.join(p,'Resources/native-form-bridge.js'),'utf8');
for(const key of [
  'struct NativeClosingList','struct NativeClosingMonthCalendar',
  'closing-outer-list','closing-inner-calendar','proxy.size.width >= 690',
  'NativeClosingList(model:model','NativeClosingMonthCalendar(model:model',
  'row!.hours','row!.rest'
]) assert(screens.includes(key),key);
for(const key of [
  '休憩の目安','実労働時間','法定最低休憩',
  '日々申請','締め申請','breakRecalculate'
]) assert(screens.includes(key),key);
assert(bridge.includes("if(payload.kind==='breakRecalculate')"));
assert(screens.includes('struct ClosingMonthData'));
assert(!screens.includes('private struct ClosingMonthData'));
assert(view.includes('navigation.page == "daily" &&'));
assert(!screens.includes('公式フォームでその他の項目・申請を確認'));
assert(!screens.includes('公式画面で申請・確認'));
console.log('Native closing calendar/list, legal break, native apply, single WKWebView: PASS');
