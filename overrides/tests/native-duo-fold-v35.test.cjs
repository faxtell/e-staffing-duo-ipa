const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const screens = fs.readFileSync(path.join(root, 'EStaffingTimeCard/NativeScreens.swift'), 'utf8');
const pbx = fs.readFileSync(path.join(root, 'EStaffingTimeCard.xcodeproj/project.pbxproj'), 'utf8');
const daily = screens.split('struct NativeDailyScreen: View')[1].split('struct ClosingMonthData')[0];
const closing = screens.split('struct NativeClosingScreen: View')[1].split('struct NativePreferencesScreen: View')[0];
const settings = screens.split('struct NativePreferencesScreen: View')[1].split('struct NativeLoginScreen: View')[0];
for(const content of [daily, closing]) {
    assert(content.includes('proxy.reservedRegions(kind: .division)'), 'Must use active fold reservation, not assumed screen width');
    assert(content.includes('fold.height > fold.width'), 'Book fold must support horizontal arrangement');
    assert(content.includes('fold.width >= fold.height'), 'Tabletop fold must support vertical arrangement');
    assert(content.includes('Color.clear.frame(width: max(0, fold.width))'), 'Book view must leave hinge clear');
    assert(content.includes('Color.clear.frame(height: max(0, fold.height))'), 'Tabletop view must leave hinge clear');
}
for(const key of [
    'daily-fold-book', 'daily-fold-tabletop', 'daily-responsive-standard',
    'daily-fold-work-pane', 'daily-fold-edit-pane',
    'daily-shift-preview-inline', 'daily-break-minutes-input'
]) assert(daily.includes(key), key);
for(const key of [
    'closing-fold-book', 'closing-fold-tabletop', 'closing-outer-mode',
    'closing-inner-mode', 'closing-fold-overview-pane', 'closing-fold-calendar-pane',
    'closing-monthly-overview', 'closing-summary-work-minutes'
]) assert(closing.includes(key), key);
assert(closing.includes('.id("closing-month-\\(model.calendarMonth)"),'), 'Month ID should remain stable when folding');
assert(pbx.includes('MARKETING_VERSION = 3.5;'), 'IPA version must increment');
assert(settings.includes('CFBundleShortVersionString'), 'UI must read actual bundle version');
console.log('Duo book/tabletop division, working controls, version 3.5: PASS');
