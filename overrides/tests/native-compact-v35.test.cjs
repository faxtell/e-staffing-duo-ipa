const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../');
const screens = fs.readFileSync(path.join(root, 'EStaffingTimeCard/NativeScreens.swift'), 'utf8');
const view = fs.readFileSync(path.join(root, 'EStaffingTimeCard/TimeCardView.swift'), 'utf8');
const daily = screens.split('struct NativeDailyScreen: View')[1].split('struct ClosingMonthData')[0];
const closing = screens.split('struct NativeClosingScreen: View')[1].split('struct NativePreferencesScreen: View')[0];

for (const token of [
  'NativeSurface(title:"勤務時間")', 'daily-shift-preview-inline',
  'daily-preview-break-menu', 'daily-break-minutes-input',
  'updateBreakMinutes(rest)', '"name":"rstTime"',
  'enteredRestMinutes ?? plannedBreakMinutes',
  'breakRecalculate', 'legalMinimumMinutes',
  'actualWorkMinutes', 'fieldEntry("備考",name:"remark")'
]) assert(daily.includes(token), 'Daily screen missing: ' + token);
assert(!daily.includes('NativeSurface(title:"休憩・備考")'), 'Separate break card remains');
assert(!daily.includes('previewRestOverride'), 'Comparison-only override must be removed');
assert(!daily.includes('nativeFormAction(["kind":"field","name":"endTime"'),
  'Forecast must never alter actual checkout time');

for (const token of [
  'closing-monthly-overview', 'closing-summary-worked', 'closing-summary-leave',
  'closing-summary-work-minutes', 'closing-summary-overtime',
  'closingSummary(columns: expanded ? 4 : 2)', 'NativeClosingMonthCalendar', 'NativeClosingList'
]) assert(closing.includes(token), 'Closing card layout missing: ' + token);
for (const token of [
  'nativeDestination("home"', 'nativeDestination("daily"',
  'nativeDestination("close"', 'nativeDestination("settings"'
]) assert(view.includes(token));
console.log('Editable break, merged work card, compact closing metrics: PASS');
