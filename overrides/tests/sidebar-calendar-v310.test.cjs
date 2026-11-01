const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname,'..');
const swift = fs.readFileSync(path.join(root,'EStaffingTimeCard/TimeCardView.swift'),'utf8');
const pbx = fs.readFileSync(path.join(root,'EStaffingTimeCard.xcodeproj/project.pbxproj'),'utf8');
const sidebar = swift.split('struct NativeCalendarSidebar: View {')[1].split('final class NativeNavigationModel')[0];
for (const target of [
  'private var weekCount: Int', '(firstWeekday + daysInMonth + 6) / 7',
  'ForEach(0..<weekCount, id:', 'ForEach(0..<7, id:',
  'let day = week * 7 + column - firstWeekday + 1',
  'if (1...daysInMonth).contains(day)',
  'dayButton(day)', 'sidebar-day-', 'sidebar-full-month-calendar',
  'model.openCalendarDate(key)'
]) assert(sidebar.includes(target),'Missing: '+target);
assert(!sidebar.includes('LazyVGrid(columns: columns'), 'Do not reintroduce a shared identity grid');
assert(!sidebar.includes('ForEach(1...max(1, daysInMonth)'), 'Avoid weekday/day identity overlap');
assert(!sidebar.includes('ForEach(0..<firstWeekday'), 'Avoid a second anonymous placeholder collection');
assert(pbx.includes('MARKETING_VERSION = 3.10;'), 'App version must increment to 3.10');
// Sunday-first calendar: slots must cover all days in order, with no
// omissions, even for a month beginning on Sunday or Saturday.
function checkMonth(year,month) {
  const first = new Date(Date.UTC(year,month-1,1)).getUTCDay();
  const count = new Date(Date.UTC(year,month,0)).getUTCDate();
  const weeks = Math.ceil((first+count)/7);
  const slots = [];
  for (let week=0; week<weeks; week++) for(let col=0;col<7;col++) {
    const day=week*7+col-first+1;
    if(day>=1 && day<=count) slots.push(day);
  }
  assert.equal(slots.length,count,`Month ${year}-${month}: missing days`);
  assert.deepEqual(slots,Array.from({length:count},(_,i)=>i+1));
  assert.equal(slots[0],1);
}
for(let year=2024;year<=2028;year++) for(let month=1;month<=12;month++) checkMonth(year,month);
checkMonth(2026,11); // user screenshot: Nov 1 (Sunday) through Nov 30.
console.log('v3.10 complete Sunday-first calendar sidebar from day 1: PASS (60 months)');
