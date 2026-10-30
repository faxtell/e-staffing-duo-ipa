const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const root=path.resolve(__dirname,'..');
const swift=fs.readFileSync(path.join(root,'EStaffingTimeCard/TimeCardView.swift'),'utf8');
const screen=fs.readFileSync(path.join(root,'EStaffingTimeCard/NativeScreens.swift'),'utf8');
const pbx=fs.readFileSync(path.join(root,'EStaffingTimeCard.xcodeproj/project.pbxproj'),'utf8');
function expect(source, fragments) {
  fragments.forEach(key=>assert(source.includes(key),'Missing: '+key));
}
expect(swift,[
  'native-session-recovery', 'recoveryActive = false',
  'private var recoveryAutoAttempted = false',
  'private func showRecovery(message: String)',
  "body.includes('許可されていない操作が検知されました')",
  "body.includes('ログイン画面へ')",
  'if state["unauthorized"] == true',
  'if self.navigation.recoveryActive && self.recoveryAutoAttempted',
  'if self.navigation.recoveryActive && self.recoveryManualRequested',
  'if self.recoveryAwaitingLogin',
  'private func followOfficialLoginLink()',
  'private func submitRecoveryCredentialsWithoutBiometrics()',
  'UserDefaults.standard.object(forKey: "etc-duo-recovery.autoSignIn")',
  'CredentialVault.exists()', 'CredentialVault.read()',
  'window.__etcCredentialAutoSubmit?.',
  'recoveryGeneration', 'recoveryManualRequested',
  'self.navigation.recoveryActive = false',
  'recoveryLoginHandler', 'openRecoveryLoginManually()'
]);
const flow=swift.split('private func showRecovery(message: String)')[1].split('private func followOfficialLoginLink()')[0];
assert(flow.includes('recoveryAutoAttempted = true'),'At most one automatic recovery');
assert(flow.indexOf('guard !recoveryAutoAttempted') < flow.indexOf('recoveryAutoAttempted = true'));
const submit=swift.split('private func submitRecoveryCredentialsWithoutBiometrics()')[1].split('private func isTrustedWebURL')[0];
assert(submit.includes('let url = view.url, isOfficialPage(url)'),'Reauth only trusted original host');
assert(!submit.includes('LAContext()'),'Biometrics-free recovery must not prompt for device auth');
assert(submit.includes('recoveryAwaitingLogin') && submit.includes('recoveryAutoSubmitting'));
assert(!submit.includes('.goBack('),'Never use browser Back');
const login=swift.split('private func followOfficialLoginLink()')[1].split('func openRecoveryLoginManually()')[0];
assert(login.includes("text.includes('ログイン画面へ')"),'Use official login link');
assert(login.includes("url.origin === 'https://m.e-staffing.ne.jp'"),'Cross-domain must be rejected');
const app=swift.split('struct TimeCardView: View')[1].split('struct OfficialTimeCardWebView')[0];
assert(app.includes('if navigation.recoveryActive'));
assert(app.includes('NativeSessionRecoveryScreen(model: navigation)'));
assert(app.includes('!navigation.recoveryActive && navigation.isVisible'),'Hide bottom nav during recovery');
expect(screen,[
  'struct NativeSessionRecoveryScreen: View', 'exclamationmark.shield.fill',
  '再ログインが必要です', 'session-recovery-open-login',
  'モデル', // placeholder intentionally removed below
  '@AppStorage("etc-duo-recovery.autoSignIn")',
  'エラー時にFace IDなしで再ログイン',
  '前の画面で拒否された入力・保存・申請操作は自動で再送信しません',
  'iPhoneのロック解除が必要'
].filter(x=>x!=='モデル'));
assert(pbx.includes('MARKETING_VERSION = 3.9;'));
console.log('v3.9 unauthorized page detection, native recovery, one-shot optional re-login: PASS');
