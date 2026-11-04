const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const screens = fs.readFileSync(path.join(root, 'EStaffingTimeCard/NativeScreens.swift'), 'utf8');
const view = fs.readFileSync(path.join(root, 'EStaffingTimeCard/TimeCardView.swift'), 'utf8');
const pbx = fs.readFileSync(path.join(root, 'EStaffingTimeCard.xcodeproj/project.pbxproj'), 'utf8');
const guide = screens.split('struct NativeFirstRunGuide: View {')[1]?.split('struct NativePreferencesScreen: View {')[0] || '';
const settings = screens.split('struct NativePreferencesScreen: View {')[1]?.split('struct NativeLoginScreen: View {')[0] || '';
const login = screens.split('struct NativeLoginScreen: View {')[1] || '';
const rootView = view.split('struct TimeCardView: View {')[1]?.split('struct OfficialTimeCardWebView')[0] || '';
const model = view.split('final class NativeNavigationModel')[1]?.split('struct TimeCardView: View')[0] || '';

for(const token of [
  'onboarding-welcome','onboarding-howto','onboarding-setup',
  'onboarding-company-id','onboarding-next','onComplete()',
  '@AppStorage("etc-duo-account.companyID")',
  '@AppStorage("etc-duo-v33.shift.netMinutes")',
  '@AppStorage("etc-duo-v33.shift.breakMinutes")',
  '@AppStorage("etc-duo-recovery.autoSignIn")',
  'companyDraft.trimmingCharacters(in: .whitespacesAndNewlines)',
  'trimmed.count <= 128',
  '使い方','日々勤怠','締め申請','Keychain',
  '勤務記録の開始・終了・休憩欄へ自動入力しません'
]) assert(guide.includes(token),'Missing onboarding workflow: ' + token);
assert(!guide.includes('CredentialVault.save('),'Guide must not store passwords');
assert(!guide.includes('nativeFormAction('),'Guide must not submit or edit attendance');
assert(guide.includes('Button("スキップ")'),'First-run introduction must be skippable');
assert(guide.includes('Button(page == 2 ? "設定を保存してログインへ" : "次へ")'));
assert(guide.includes('savedCompanyID = companyDraft.trimmingCharacters'),'Wizard must save user-entered company ID');
assert(guide.includes('.frame(maxWidth: 620)'),'Responsive walkthrough for Duo');
for(const token of [
 '@AppStorage("etc-duo-account.companyID")',
 'settings-company-id','使い方と初期設定をもう一度見る',
 'model.showOnboarding = true','Face IDログイン情報は変更されません'
]) assert(settings.includes(token),'Missing editable settings: ' + token);
assert(login.includes('@AppStorage("etc-duo-account.companyID") private var company="pasona"'),
       'Login must load persisted company ID, with pasona as a default only');
assert(!login.includes('@State private var company="pasona"'),'Login cannot reset company ID on reopen');
assert(login.includes('login-company-id'));
assert(login.includes('model.nativeLogin(["company":company'),'Login submits the actual selected ID');
assert(login.includes('company.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty'));
for(const token of [
 '@AppStorage("etc-duo-onboarding.completed")',
 '.fullScreenCover(isPresented: $onboardingPresented)',
 'NativeFirstRunGuide {',
 'onboardingCompleted = true',
 'if CredentialVault.exists()',
 'CredentialVault.read()',
 'etc-duo-account.companyID',
 '.onChange(of: navigation.showOnboarding)'
]) assert(rootView.includes(token),'Missing onboarding host state: ' + token);
assert(model.includes('@Published var showOnboarding = false'));
assert(view.includes('case "candidate":'));
assert(view.includes('let fallback = UserDefaults.standard.string(forKey: "etc-duo-account.companyID") ?? "pasona"'));
assert(view.includes('if CredentialVault.save(candidate) {'),'Sync company only after official successful login');
assert(!guide.includes('password='),'No password in the setup wizard');
assert(pbx.includes('MARKETING_VERSION = 3.13;'),'Marketing version 3.13 required');
console.log('v3.13 first-run tutorial, setup, custom persistent company ID: PASS');
