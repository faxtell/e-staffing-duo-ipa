const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const base = path.resolve(__dirname, '../EStaffingTimeCard');
const source = fs.readFileSync(path.join(base, 'NativeScreens.swift'), 'utf8');
const pbx = fs.readFileSync(path.resolve(__dirname, '../EStaffingTimeCard.xcodeproj/project.pbxproj'), 'utf8');
const daily = source.split('struct NativeDailyScreen: View')[1].split('struct ClosingMonthData')[0];
const closing = source.split('struct NativeClosingScreen: View')[1].split('struct NativePreferencesScreen: View')[0];
const mini = source.split('private struct NativeClosingTabletopCalendar: View')[1].split('struct NativeClosingScreen: View')[0];

for (const key of [
  'daily-tabletop-dashboard', 'tabletop-daily-forecast', 'daily-tabletop-editor',
  'tabletop-daily-break-input', 'tabletop-daily-details',
  'tabletop-daily-sticky-actions', 'DisclosureGroup(isExpanded: $tabletopDetailsExpanded)',
  'updateBreakMinutes(rest)', 'daily-fold-tabletop'
]) assert(daily.includes(key), 'Missing tablet-style daily element: ' + key);
const dashboard = daily.split('private var tabletopDailyDashboard: some View')[1].split('private var tabletopDailyEditor: some View')[0];
const editor = daily.split('private var tabletopDailyEditor: some View')[1].split('var body: some View')[0];
assert(!dashboard.includes('DatePicker'), 'Upper glanceable dashboard must be read-only');
assert(editor.includes('timeItem("開始", name: "startTime")'), 'Start editing must remain below');
assert(editor.includes('timeItem("終了", name: "endTime")'), 'End editing must remain below');
assert(editor.includes('"name":"rstTime"'), 'Break editing must use the official form field');
assert(editor.includes('model.nativeFormAction(["kind":"save"])'), 'Manual temporary save must remain');
assert(editor.includes('model.showOfficial = true'), 'Official application access must remain');
assert(editor.indexOf('Divider()\n            HStack(spacing: 8)') > editor.indexOf('.scrollDismissesKeyboard(.interactively)'),
       'Persistent action footer should be outside scrolling controls');

for (const key of [
  'closing-tabletop-dashboard', 'closing-tabletop-records',
  'tabletop-closing-sticky-action', 'closing-tabletop-mini-calendar',
  'tabletopClosingDashboard(month: month, width: proxy.size.width)',
  'tabletopClosingRecords(month: month)', 'closing-fold-tabletop'
]) assert((closing + mini).includes(key), 'Missing tabletop closing element: ' + key);
for (const key of ['month.firstWeekday + month.days + 6', '(1...month.days).contains(day)',
                   'model.openCalendarDate(key)', 'closingStatus(record)'])
  assert(mini.includes(key), 'Compact calendar must support all days: ' + key);
assert(closing.includes('closingCalendar(month: month)'), 'Expanded calendar must remain');
assert(closing.includes('closingRecords(month: month)'), 'Compact normal list must remain');
assert(source.includes('duoDivisionFrame(in: proxy)'), 'Fold-safe API must remain');
assert(pbx.includes('MARKETING_VERSION = 3.6;'), 'Version must increase with new IPA');
console.log('v3.6 tabletop daily/closing polish, official actions, and version: PASS');
