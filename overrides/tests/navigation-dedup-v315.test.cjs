const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const screens = fs.readFileSync(path.join(root, 'EStaffingTimeCard/NativeScreens.swift'), 'utf8');
const view = fs.readFileSync(path.join(root, 'EStaffingTimeCard/TimeCardView.swift'), 'utf8');
const pbx = fs.readFileSync(path.join(root, 'EStaffingTimeCard.xcodeproj/project.pbxproj'), 'utf8');

function section(source, start, end) {
  assert(source.includes(start), 'Expected source section: ' + start);
  return source.split(start)[1].split(end)[0];
}
function count(source, token) { return source.split(token).length - 1; }

const home = section(screens, 'struct NativeHomeScreen: View {', 'private struct NativeAnalysisDatum: Identifiable {');
const analytics = section(screens, 'struct NativeAnalyticsScreen: View {', 'struct NativeDailyScreen: View {');
const closing = section(screens, 'struct NativeClosingScreen: View {', '// First-run walkthrough');
const settings = section(screens, 'struct NativePreferencesScreen: View {', 'struct NativeLoginScreen: View {');
const nav = section(view, 'struct TimeCardView: View {', 'struct OfficialTimeCardWebView: UIViewRepresentable {');

// Bottom navigation is the single persistent point for four top-level pages.
for(const [destination,label] of [
  ['home','ホーム'],['daily','日々勤怠'],['close','締め申請'],['settings','設定']
]){
  const item = 'nativeDestination("'+destination+'",title:"'+label+'"';
  assert.equal(count(nav,item),1,'Persistent bottom navigation: '+label);
}

// These destinations are already visible in the bottom bar: no duplicate
// navigation buttons on the home dashboard.
assert(!home.includes('クイックアクセス'),'Remove redundant quick-access grouping');
assert(!home.includes('model.navigate("close")'),'Never duplicate closing tab on home');
assert(!home.includes('model.navigate("daily")'),'Never duplicate daily tab on home');
assert(!home.includes('home-open-daily'),'Remove obsolete daily CTA from home');
assert(home.includes('NativeSurface(title: "今日の勤怠")'),
  'Keep today as a glanceable, read-only card');
assert(home.includes('home-today-state'),'Show quiet state capsule');
assert(home.includes('NativeSurface(title: "今月のサマリー")'),
  'Group related metrics rather than scattering separate cards');
assert(home.includes('LazyVGrid(columns:'),'Compact adaptive metric grid');

// Analysis is not a bottom tab; it has exactly one entry on the home.
assert.equal(count(home,'model.nativeAnalysisOpen = true'),1,
  'One analytics entry on the home dashboard');
assert.equal(count(home,'home-open-analytics'),1,
  'One discoverable analysis shortcut');
assert(!settings.includes('model.nativeAnalysisOpen = true'),
  'Settings must not repeat the analytics shortcut');
assert(!closing.includes('model.nativeAnalysisOpen = true'),
  'Closing calendar must not repeat the analytics shortcut');

// Analytics is an overlay subview, not another root destination: a single
// dismiss action, with the regular toolbar hidden until it closes.
assert(analytics.includes('Button { model.nativeAnalysisOpen = false }'),
  'Analysis must provide its own dismiss action');
assert(analytics.includes('analytics-close'),'Dismiss must be accessible');
assert(!analytics.includes('model.navigate("home")'),
  'No redundant home/back navigation on analytics');
const showNavigation = section(nav, 'private var showNavigation: Bool {',
  'private var showNativeScreen: Bool {');
assert(showNavigation.includes('!navigation.nativeAnalysisOpen'),
  'Do not draw bottom tabs beside analytics close button');
assert(nav.includes('navigation.page == "daily"'),'Keep Duo calendar routing');

// Existing primary attendance actions must survive simplification.
assert(screens.includes('daily-native-apply'),'Keep explicit daily application');
assert(screens.includes('closing-native-apply'),'Keep explicit closing application');
assert(screens.includes('tabletop-closing-native-apply'),'Keep tabletop submission');
assert(screens.includes('native-sync-status'),'Keep official sync provenance');
assert(screens.includes('daily-confirm-template'),'Keep confirmed templates');
assert(pbx.includes('MARKETING_VERSION = 3.15;'),'Release version 3.15');
console.log('v3.15 navigation deduplication and clean home hierarchy: PASS');
