import SwiftUI
import UIKit
import WebKit
import LocalAuthentication
import UserNotifications

/// Single WKWebView remains the ONLY surface that can open or submit official
/// attendance pages. Read-only summaries are supplied from the official page.

/// Read-only data copied from already visited official closing pages. No
/// cookies, credentials, action URLs or form tokens leave the WKWebView.
struct NativeCalendarRecord: Identifiable {
    let date: String
    let known: Bool
    let work: Bool
    let leave: Bool
    let hours: String
    let status: String
    let place: String
    let rest: String
    let holiday: String
    var id: String { date }

    // Only the original site's explicit status justifies "承認済".
    // A generic short "済" is not treated as proof of approval.
    var stateLabel: String {
        if !known { return "未取得" }
        if leave { return "年休" }
        if status.contains("差戻") { return "差戻し" }
        if status.contains("承認済") { return "承認済" }
        if status.contains("申請済") || status.contains("申請中") { return "申請済み・確認待ち" }
        if status.contains("一時保存") || status.contains("保存中") { return "一時保存" }
        if work { return "勤務記録あり" }
        if !holiday.isEmpty { return "休日" }
        return "未入力"
    }
    var stateSymbol: String {
        if !known { return "questionmark.circle" }
        if leave { return "sun.max.fill" }
        if status.contains("差戻") { return "arrow.uturn.backward.circle.fill" }
        if status.contains("承認済") { return "checkmark.seal.fill" }
        if status.contains("申請済") || status.contains("申請中") { return "clock.badge.checkmark" }
        if work { return "clock.fill" }
        if !holiday.isEmpty { return "moon.stars" }
        return "circle.dashed"
    }
    var stateTint: Color {
        if !known { return .gray }
        if leave { return .purple }
        if status.contains("差戻") { return .orange }
        if status.contains("承認済") { return .green }
        if status.contains("申請済") || status.contains("申請中") { return .blue }
        if work { return .teal }
        return .secondary
    }
    var approvalDescription: String {
        if status.contains("承認済") { return "承認済" }
        if status.contains("申請済") || status.contains("申請中") { return "申請済み・確認待ち" }
        if status.contains("差戻") { return "差戻し" }
        if status.contains("一時保存") { return "一時保存" }
        if status == "済" { return "処理済（詳細未確認）" }
        return status
    }

    init?(value: [String: Any], month: String) {
        guard let date = value["date"] as? String,
              date.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
              date.hasPrefix(month + "-"),
              let known = value["known"] as? Bool,
              let work = value["work"] as? Bool,
              let leave = value["leave"] as? Bool else { return nil }
        self.date = date
        self.known = known
        self.work = known && work
        self.leave = known && leave
        func trimmed(_ key: String) -> String { String((value[key] as? String ?? "").prefix(100)) }
        self.hours = known ? trimmed("hours") : ""
        self.status = known ? trimmed("status") : ""
        self.place = known ? trimmed("place") : ""
        self.rest = known ? trimmed("rest") : ""
        self.holiday = trimmed("holiday")
    }
    var bridgeObject: [String: Any] {
        ["date":date, "known":known, "work":work, "leave":leave,
         "hours":hours, "status":status, "place":place,"rest":rest,"holiday":holiday]
    }
}

/// A calendar is a passive view: selecting a day only changes local text.
/// The official stateful form always remains in the *same* WKWebView.
struct NativeCalendarSidebar: View {
    @ObservedObject var model: NativeNavigationModel
    @State private var selected: String = ""
    @State private var previewDate: String?
    private let weekdays = ["日", "月", "火", "水", "木", "金", "土"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("勤務カレンダー", systemImage: "calendar")
                .font(.headline)
            Text(monthTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            // Weekday headers and date slots must not share ForEach identities:
            // the old LazyVGrid used weekday IDs 0...6 and day IDs 1...31,
            // which could cause days 1...6 to disappear on Duo's wide layout.
            VStack(spacing: 6) {
                HStack(spacing: 3) {
                    ForEach(0..<7, id: \.self) { weekday in
                        Text(weekdays[weekday])
                            .font(.caption2)
                            .foregroundStyle(weekday == 0 ? .red : .secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                ForEach(0..<weekCount, id: \.self) { week in
                    HStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { column in
                            let day = week * 7 + column - firstWeekday + 1
                            if (1...daysInMonth).contains(day) {
                                dayButton(day)
                                    .frame(maxWidth: .infinity)
                                    .accessibilityIdentifier("sidebar-day-\(day)")
                            } else {
                                Color.clear
                                    .frame(maxWidth: .infinity, minHeight: 34)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                }
            }
            .accessibilityIdentifier("sidebar-full-month-calendar")
            HStack(spacing: 10) {
                Label("出勤", systemImage: "clock.fill").foregroundStyle(.teal)
                Label("年休", systemImage: "sun.max.fill").foregroundStyle(.purple)
                Label("承認", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
            }
            .font(.system(size: 9))
            .accessibilityIdentifier("sidebar-attendance-legend")
            Divider()
            let current = model.calendarRows[selected]
            VStack(alignment: .leading, spacing: 6) {
                Text(selected.isEmpty ? "日付を選択" : selected)
                    .font(.subheadline.weight(.semibold))
                if let item = current {
                    if !item.known { Text(item.holiday.isEmpty ? "この日付は未取得" : item.holiday).foregroundStyle(.secondary) }
                    else if item.leave {
                        Label("年次有給休暇", systemImage: item.stateSymbol)
                            .foregroundStyle(item.stateTint)
                    } else if item.work {
                        Label(item.hours.isEmpty ? item.stateLabel : item.hours,
                              systemImage: item.stateSymbol)
                            .foregroundStyle(item.stateTint)
                        Text(([item.place,item.rest.isEmpty ? "" : "休憩 \(item.rest)分"].filter { !$0.isEmpty }).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(item.stateLabel).foregroundStyle(.secondary)
                    }
                    if !item.approvalDescription.isEmpty { Text(item.approvalDescription).font(.caption).foregroundStyle(.secondary) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 2)
            Text("日付を選ぶと、その日の勤怠入力へ移動します")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .accessibilityIdentifier("read-only-calendar-sidebar")
        .sheet(isPresented: Binding(
            get: { previewDate != nil },
            set: { if !$0 { previewDate = nil } }
        )) {
            NativeCalendarDayPreview(date: previewDate ?? "",
                                     record: model.calendarRows[previewDate ?? ""])
                .presentationDetents([.medium])
        }
    }
    // Explicit, stable week/column slots render every day 1...month end.
    private var weekCount: Int {
        (firstWeekday + daysInMonth + 6) / 7
    }
    private func dayButton(_ day: Int) -> some View {
        let key = model.calendarMonth + String(format: "-%02d", day)
        let record = model.calendarRows[key]
        return Button {
            selected = key
            // Use the CURRENT official DOM: never replay history or forge URLs.
            model.openCalendarDate(key)
        } label: {
            VStack(spacing: 2) {
                Text("\(day)").font(.system(size: 12, weight: .semibold))
                Image(systemName: record?.stateSymbol ?? "questionmark.circle")
                    .font(.system(size: 9))
                    .foregroundStyle(record?.stateTint ?? .gray)
                    .frame(height: 11)
            }
            .frame(maxWidth: .infinity, minHeight: 32)
            .foregroundStyle(record?.holiday.isEmpty == false ? Color.red : Color.primary)
            .background(selected == key ? Color.accentColor.opacity(0.2) :
                        Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: 0.55) { previewDate = key }
        .accessibilityLabel("\(day)日、\(label(for: record))")
        .accessibilityHint("長押しすると公式の取得済み内容をプレビューします")
    }
    private func label(for record: NativeCalendarRecord?) -> String {
        record?.stateLabel ?? "未取得"
    }
    private var monthTitle: String {
        let parts=model.calendarMonth.split(separator: "-")
        return parts.count == 2 ? "\(parts[0])年\(Int(parts[1]) ?? 0)月" : ""
    }
    private var firstWeekday: Int {
        guard let date=Calendar(identifier: .gregorian).date(from: DateComponents(year:year,month:month,day:1)) else { return 0 }
        return Calendar(identifier: .gregorian).component(.weekday, from: date)-1
    }
    private var daysInMonth: Int {
        guard let date=Calendar(identifier: .gregorian).date(from: DateComponents(year:year,month:month,day:1)) else { return 1 }
        return Calendar(identifier: .gregorian).range(of:.day,in:.month,for:date)?.count ?? 1
    }
    private var year: Int { Int(model.calendarMonth.prefix(4)) ?? 2026 }
    private var month: Int { Int(model.calendarMonth.suffix(2)) ?? 1 }
}

final class NativeNavigationModel: ObservableObject {
    @Published var page = "login"
    @Published var summary: [String: Any] = [:]
    @Published var nativeDailyFields: [String: String] = [:]
    @Published var nativeCategory: [[String: Any]] = []
    @Published var nativeWorkplace: [[String: Any]] = []
    @Published var nativeDailyReady = false
    @Published var nativeDailyLocked = false
    @Published var nativeDailyApprovalStatus = ""
    @Published var nativeDailyCategoryDisplay = ""
    @Published var nativeDailyWorkplaceDisplay = ""
    @Published var nativeSaveState = "idle"
    @Published var nativeTemplateMessage = ""
    @Published var lastOfficialDailyAt: Date?
    @Published var lastOfficialDashboardAt: Date?
    @Published var lastOfficialCalendarAt: Date?
    @Published var nativeDayTitle = ""
    @Published var nativeCanSave = false
    @Published var nativeCanDailyApply = false
    @Published var nativeCanCloseApply = false
    @Published var nativeDailyApplyPeriod = ""
    @Published var nativeCloseApplyPeriod = ""
    @Published var nativeSubmissionState = "idle"
    @Published var nativeSubmissionMessage = ""
    @Published var nativeSubmissionInFlight = false
    @Published var nativeSettingsOpen = false
    @Published var nativeAnalysisOpen = false
    @Published var showOnboarding = false
    @Published var nativeLoginReady = false
    @Published var recoveryActive = false
    @Published var recoveryLoading = false
    @Published var recoveryMessage = ""
    @Published var recoveryAutomatic = false
    var recoveryLoginHandler: (() -> Void)?
    func openRecoveryLogin() { recoveryLoginHandler?() }
    @Published var showOfficial = false
    var nativeReminderHandler: ((String, Bool, Int, Int, Int) -> Void)?
    var salaryUpdateHandler: (() -> Void)?
    @Published var isVisible = false
    @Published var navigationInProgress = false
    @Published var sheetOpen = false
    @Published var dashboardLoading = false
    @Published var dashboardProgress = "勤務情報を取得しています…"
    @Published var openingCalendarDay: String? = nil
    // User can dismiss the loading screen; the WebView is not destroyed.
    var cancelDashboard: (() -> Void)?
    @Published var websiteTheme = UserDefaults.standard.string(forKey: "etc-duo-native.theme") ?? "system"
    @Published var nativeReminderMessage = ""
    @Published var sidebarEnabled = true
    @Published var wideDisplay = false
    @Published var calendarMonth = ""
    @Published var calendarRows: [String: NativeCalendarRecord] = [:]

    func mergeCalendar(_ payload: [String: Any]) -> Bool {
        guard let month = payload["month"] as? String,
              month.range(of: #"^\d{4}-\d{2}$"#, options: .regularExpression) != nil,
              let start = payload["start"] as? String,
              let end = payload["end"] as? String,
              start.hasPrefix(month + "-"),end.hasPrefix(month + "-"), start <= end,
              let rows = payload["rows"] as? [[String: Any]],
              (28...31).contains(rows.count) else { return false }
        var merged = calendarMonth == month ? calendarRows : [:]
        for item in rows {
            guard let rec = NativeCalendarRecord(value:item,month:month) else { return false }
            if merged[rec.date]?.known == true && !rec.known { continue }
            merged[rec.date] = rec
        }
        calendarMonth = month
        calendarRows = merged
        lastOfficialCalendarAt = Date()
        return true
    }

    func resetCalendar() {
        calendarRows = [:]
        calendarMonth = ""
        lastOfficialCalendarAt = nil
    }

    weak var webView: WKWebView?
    var calendarDayRoute: ((String) -> Void)?
    var calendarDayRouteCancel: (() -> Void)?

    func consumeDashboard(_ aggregate: [String: Any]) {
        // A lightweight summary only. Never pass full daily rows, hrefs, or
        // request/hidden form tokens across the WebKit message bridge.
        guard let start = aggregate["start"] as? String,
              let end = aggregate["end"] as? String,
              start.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
              end.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
              let worked = aggregate["worked"] as? Int, (0...65).contains(worked),
              let empty = aggregate["empty"] as? Int, (0...65).contains(empty),
              let valid = aggregate["valid"] as? Int, (0...65).contains(valid),
              let minutes = aggregate["minutes"] as? Int, (0...65*24*60).contains(minutes),
              let overtime = aggregate["overtimeMinutes"] as? Int,
              (0...65*24*60).contains(overtime), overtime <= minutes else { return }
        summary = aggregate
        lastOfficialDashboardAt = Date()
    }

    var hasCompleteMonth: Bool {
        summary["coverage"] as? String == "month" &&
        summary["valid"] as? Int == summary["worked"] as? Int
    }
    var todayConfirmedState: String {
        let raw = (summary["todayStatus"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.contains("承認済") { return "承認済" }
        if raw.contains("申請済") || raw.contains("申請中") { return "申請済み・確認待ち" }
        if raw.contains("差戻") { return "差戻し" }
        if raw.contains("未入力") { return "未入力" }
        if raw.isEmpty || raw.contains("未確認") || raw.contains("対象期間外") { return "未確認" }
        return raw == "済" ? "詳細未確認" : "公式表示：" + String(raw.prefix(30))
    }
    var nativeSyncStatus: String {
        if recoveryActive { return "接続を復旧しています" }
        if navigationInProgress { return "公式画面の読み込み中" }
        if page == "daily" {
            switch nativeSaveState {
            case "locked": return "公式の閲覧専用記録"
            case "pending": return "変更あり・一時保存待ち"
            case "sending": return "公式へ保存処理中"
            case "verify": return "保存結果は未確認"
            case "error": return "保存処理エラー"
            case "local": return "入力内容のみ・保存未確認"
            default: return lastOfficialDailyAt == nil ? "公式記録を取得中" : "公式画面と照合済み・保存は未確認"
            }
        }
        if nativeSubmissionInFlight { return "申請処理中・結果未確認" }
        if page == "home" {
            return lastOfficialDashboardAt == nil ? "集計を取得中" :
                "公式画面から集計取得済み" +
                (summary["coverage"] as? String == "month" ? "" : "（一部期間）")
        }
        return lastOfficialCalendarAt == nil ? "勤務記録を取得中" : "公式画面から記録取得済み"
    }

    func publishNativeSalary() {
        let prefs=UserDefaults.standard
        let rate=max(0,min(100000,prefs.integer(forKey:"etc-duo-v296-salary.hourlyJPY")))
        let enabled=prefs.bool(forKey:"etc-duo-v296-salary.enabled") && rate>0
        let premium=prefs.object(forKey:"etc-duo-v296-salary.premium") as? Bool ?? true
        let payload: [String:Any]=["enabled":enabled,"rate":rate,"premium":premium]
        guard let data=try? JSONSerialization.data(withJSONObject:payload),
              let arg=String(data:data,encoding:.utf8) else{return}
        webView?.evaluateJavaScript("window.__etcSalaryStatus?.(\(arg))",completionHandler:nil)
    }

    func nativeLogin(_ payload: [String: Any]) {
        guard page == "login", nativeLoginReady, let view = webView,
              view.url?.host == "m.e-staffing.ne.jp",
              let companyRaw = payload["company"] as? String,
              !companyRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              companyRaw.count <= 128 else { return }
        // The login screen uses @AppStorage for the same ID. Ensure the
        // company field remains available for subsequent launches, without
        // exposing or persisting passwords in UserDefaults.
        UserDefaults.standard.set(companyRaw.trimmingCharacters(in: .whitespacesAndNewlines),
                                  forKey: "etc-duo-account.companyID")
        guard let bytes=try? JSONSerialization.data(withJSONObject:payload),
              let arg=String(data:bytes,encoding:.utf8) else{return}
        view.evaluateJavaScript("window.__etcNativeLogin?.(\(arg))",completionHandler:nil)
    }
    func faceIDLogin() {
        guard page == "login", nativeLoginReady, let view = webView else{return}
        view.evaluateJavaScript("window.webkit?.messageHandlers?.etcCredentialBridge?.postMessage({action:'authenticateAndLogin'})",completionHandler:nil)
    }

    func nativeFormAction(_ payload: [String: Any]) {
        guard page == "daily", !nativeDailyLocked, !navigationInProgress,
              let webView = webView,
              let url = webView.url, url.host == "m.e-staffing.ne.jp",
              url.path.hasPrefix("/s/") else { return }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let literal = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.__etcNativeFormAction?.(\(literal))", completionHandler: nil)
    }

    func receiveNativeSubmission(_ payload: [String: Any]) {
        guard let action = payload["action"] as? String,
              let kind = payload["kind"] as? String,
              ["daily", "close"].contains(kind) else { return }
        if action == "submissionSnapshot" {
            guard let period = payload["period"] as? String,
                  !period.isEmpty, period.count <= 120,
                  let available = payload["available"] as? Bool else { return }
            if kind == "daily" {
                nativeDailyApplyPeriod = period
                nativeCanDailyApply = available && !nativeDailyLocked && !nativeSubmissionInFlight
            } else {
                nativeCloseApplyPeriod = period
                nativeCanCloseApply = available && !nativeSubmissionInFlight
            }
        } else if action == "submissionState",
                  let status = payload["status"] as? String,
                  let message = payload["message"] as? String,
                  message.count <= 200, ["initiated", "error", "verify", "cancelled"].contains(status) {
            nativeSubmissionState = status
            nativeSubmissionMessage = message
            if status == "initiated" {
                nativeSubmissionInFlight = true
                nativeCanDailyApply = false
                nativeCanCloseApply = false
            } else {
                nativeSubmissionInFlight = false
            }
        }
    }

    // The first tap shows a SwiftUI confirmation alert. Only its explicit
    // "Apply" button calls this action; never reissue on retries/resizes.
    func nativeSubmit(_ kind: String) {
        guard ["daily", "close"].contains(kind),
              !navigationInProgress, !dashboardLoading, !nativeSubmissionInFlight,
              page == kind, !(kind == "daily" && nativeDailyLocked),
              let webView = webView, let url = webView.url,
              url.scheme == "https", url.host == "m.e-staffing.ne.jp",
              url.path.hasPrefix("/s/"),
              (kind == "daily" ? nativeCanDailyApply : nativeCanCloseApply) else { return }
        let period = kind == "daily" ? nativeDailyApplyPeriod : nativeCloseApplyPeriod
        guard !period.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: [
                "kind": "submit", "form": kind,
                "period": period, "confirmed": true
              ]),
              let literal = String(data: data, encoding: .utf8) else { return }
        nativeSubmissionInFlight = true
        nativeCanDailyApply = false
        nativeCanCloseApply = false
        nativeSubmissionState = "initiated"
        nativeSubmissionMessage = "公式フォームへの申請操作を確認しています。完了はまだ確認できていません。"
        webView.evaluateJavaScript("window.__etcNativeSubmission?.(\(literal))") { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if error == nil, let success = result as? Bool, success { return }
                // A page navigation can cancel the JS callback after an actual
                // click. Do not unlock for another click or claim success.
                self.nativeSubmissionState = "verify"
                self.nativeSubmissionMessage = "操作結果を確認できません。申請履歴を確認してください。再送信はしないでください。"
            }
        }
    }

    func receiveDaily(_ payload: [String: Any]) {
        guard let fields = payload["fields"] as? [String: String],
              let category = payload["category"] as? [String: Any],
              let workplace = payload["workplace"] as? [String: Any] else { return }
        let locked = payload["readOnly"] as? Bool ?? false
        nativeDailyLocked = locked
        nativeDailyApprovalStatus = String((payload["approvalStatus"] as? String ?? "").prefix(40))
        nativeDailyFields = fields
        lastOfficialDailyAt = Date()
        nativeCategory = locked ? [] : (category["options"] as? [[String: Any]] ?? [])
        nativeWorkplace = locked ? [] : (workplace["options"] as? [[String: Any]] ?? [])
        nativeDailyCategoryDisplay = String((category["value"] as? String ?? "").prefix(100))
        nativeDailyWorkplaceDisplay = String((workplace["value"] as? String ?? "").prefix(100))
        nativeCanSave = !locked && (payload["canSave"] as? Bool ?? false)
        if locked { nativeCanDailyApply = false }
        nativeDayTitle = payload["date"] as? String ?? ""
        nativeSaveState = locked ? "locked" : (payload["autosave"] as? String ?? "idle")
        nativeDailyReady = true
    }

    func navigate(_ destination: String) {
        nativeAnalysisOpen = false
        if destination == "settings" {
            nativeSettingsOpen = true
            showOfficial = false
            return
        }
        nativeSettingsOpen = false
        showOfficial = false
        guard !recoveryActive, ["home", "daily", "close", "settings"].contains(destination),
              let webView = webView else { return }
        // Do not re-enter an already-active official page: the site can reject
        // repeated navigation across its stateful attendance workflow.
        if destination != "settings" && (destination == page || navigationInProgress) { return }
        if page == "daily" && nativeSaveState == "pending" {
            // Avoid losing pending autosave edits on a user tab switch.
            nativeFormAction(["kind":"save"])
            return
        }
        // Click the already-created official in-page links. No URLs or tokens
        // need to be reconstructed, and form submission remains site-owned.
        guard let payload = try? JSONSerialization.data(withJSONObject: destination, options: [.fragmentsAllowed]),
              let arg = String(data: payload, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.__etcNativeNavigate?.(\(arg))", completionHandler: nil)
    }

    func openCalendarDate(_ date: String) {
        guard !navigationInProgress, !dashboardLoading,
              date.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
              date.hasPrefix(calendarMonth + "-"), calendarRows[date] != nil else { return }
        // Route state lives in the Coordinator, not in the official DOM or a
        // second WKWebView. Only user-initiated requests are accepted.
        calendarDayRoute?(date)
    }

    func receive(_ info: [String: Any]) {
        guard let state = info["page"] as? String,
              ["login", "home", "daily", "close", "settings", "other"].contains(state) else { return }
        if page != state {
            if state == "daily" {
                nativeDailyReady = false
                nativeDailyLocked = false
                nativeDailyFields = [:]
                nativeCategory = []
                nativeWorkplace = []
                nativeDailyCategoryDisplay = ""
                nativeDailyWorkplaceDisplay = ""
                nativeDailyApprovalStatus = ""
                nativeTemplateMessage = ""
                lastOfficialDailyAt = nil
            }
            nativeCanDailyApply = false
            nativeCanCloseApply = false
            nativeDailyApplyPeriod = ""
            nativeCloseApplyPeriod = ""
            // A navigation is not proof of a successful application.
            if nativeSubmissionInFlight {
                nativeSubmissionState = "verify"
                nativeSubmissionMessage = "公式画面の申請結果を確認してください。"
            }
        }
        page = state
        isVisible = info["visible"] as? Bool == true
        sheetOpen = info["sheetOpen"] as? Bool == true
        if UserDefaults.standard.string(forKey: "etc-duo-native.theme") == nil,
           let theme = info["theme"] as? String,
           ["light", "dark", "system"].contains(theme) {
            websiteTheme = theme
        }
    }

    func changeNativeTheme(_ value: String) {
        guard ["system", "light", "dark"].contains(value) else { return }
        UserDefaults.standard.set(value, forKey: "etc-duo-native.theme")
        websiteTheme = value
    }

    func updateNativeReminder(kind: String, enabled: Bool, hour: Int, minute: Int, day: Int) {
        nativeReminderHandler?(kind, enabled, hour, minute, day)
    }

    var preferredScheme: ColorScheme? {
        switch websiteTheme {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
    }
}


/// ONE WKWebView.  The calendar can appear alongside it on sufficiently wide
/// Duo inner layouts, but the calendar has NO navigation and is read-only.
struct TimeCardView: View {
    @StateObject private var navigation = NativeNavigationModel()
    @AppStorage("etc-duo-onboarding.completed") private var onboardingCompleted = false
    @State private var onboardingPresented = false

    private func initializeOnboarding() {
        // Migrate existing installations that already have a Keychain account
        // without replaying first-use onboarding or overwriting their ID.
        if UserDefaults.standard.string(forKey: "etc-duo-account.companyID") == nil,
           let saved = CredentialVault.read() {
            let id = saved.companyID.trimmingCharacters(in: .whitespacesAndNewlines)
            if !id.isEmpty && id.count <= 128 {
                UserDefaults.standard.set(id, forKey: "etc-duo-account.companyID")
            }
        }
        if !onboardingCompleted {
            if CredentialVault.exists() {
                onboardingCompleted = true
            } else {
                onboardingPresented = true
            }
        }
    }

    private var showNavigation: Bool {
        !navigation.recoveryActive && navigation.isVisible && !navigation.sheetOpen && !navigation.dashboardLoading && navigation.openingCalendarDay == nil
    }
    private var showNativeScreen: Bool {
        !navigation.recoveryActive && (navigation.isVisible || (navigation.page == "login" && navigation.nativeLoginReady)) && !navigation.showOfficial && !navigation.dashboardLoading &&
        navigation.openingCalendarDay == nil && (navigation.nativeSettingsOpen ||
          navigation.page == "home" || navigation.page == "close" || navigation.page == "login" ||
          (navigation.page == "daily" && navigation.nativeDailyReady))
    }
    private func showSidebar(_ width: CGFloat) -> Bool {
        width >= 690 && navigation.sidebarEnabled && !navigation.dashboardLoading &&
        navigation.calendarMonth.count == 7 && !navigation.calendarRows.isEmpty &&
        (navigation.page == "daily" || navigation.page == "close")
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    HStack(spacing: 0) {
                        if showSidebar(geometry.size.width) && !showNativeScreen {
                            NativeCalendarSidebar(model: navigation)
                                .frame(width: min(260,geometry.size.width * 0.36))
                                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12))
                            Divider()
                        }
                        // Stays the ONLY WKWebView even when Duo folds or opens.
                        OfficialTimeCardWebView(navigation: navigation)
                            .frame(maxWidth: .infinity,maxHeight: .infinity)
                            .opacity(showNativeScreen ? 0.01 : 1)
                            .allowsHitTesting(!showNativeScreen)
                    }
                    if showNativeScreen {
                        HStack(spacing:0) {
                            if navigation.page == "daily" &&
                               showSidebar(geometry.size.width) &&
                               !navigation.nativeSettingsOpen &&
                               !navigation.calendarRows.isEmpty {
                                NativeCalendarSidebar(model:navigation)
                                    .frame(width:min(260,geometry.size.width * 0.34))
                                Divider()
                            }
                            NativeApplicationScreen(model: navigation)
                                .frame(maxWidth:.infinity,maxHeight:.infinity)
                        }
                        .background(Color(uiColor:.systemGroupedBackground))
                    }
                    if let targetDay = navigation.openingCalendarDay {
                        Color(uiColor: .systemBackground).ignoresSafeArea()
                        VStack(spacing: 15) {
                            Image(systemName: "calendar.badge.clock")
                                .font(.system(size: 38)).foregroundStyle(.tint)
                            ProgressView().controlSize(.large)
                            Text("指定日の勤怠を開いています")
                                .font(.headline)
                            Text(targetDay).font(.subheadline).foregroundStyle(.secondary)
                            Button("中止") { navigation.calendarDayRouteCancel?() }
                                .buttonStyle(.bordered).padding(.top,8)
                        }.padding(26)
                    }
                    if navigation.dashboardLoading && !navigation.recoveryActive {
                        Color(uiColor: .systemBackground).ignoresSafeArea()
                        VStack(spacing: 16) {
                            Image(systemName: "calendar.badge.clock")
                                .font(.system(size:43,weight:.medium)).foregroundStyle(.tint)
                            ProgressView().controlSize(.large).padding(.top,3)
                            Text("勤務ダッシュボードを準備中").font(.title3.weight(.semibold))
                            Text(navigation.dashboardProgress)
                                .font(.subheadline).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Button("取得を中止") { navigation.cancelDashboard?() }
                                .buttonStyle(.bordered).padding(.top,12)
                        }
                        .padding(26).frame(maxWidth:420)
                        .accessibilityElement(children:.contain)
                    }
                }
                .background(Color(uiColor: .systemGroupedBackground))
                .overlay {
                    if navigation.recoveryActive {
                        NativeSessionRecoveryScreen(model: navigation)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
                    }
                }
                .onAppear { navigation.wideDisplay = geometry.size.width >= 690 }
                .onChange(of: geometry.size.width) { _, width in
                    navigation.wideDisplay = width >= 690
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden,for:.navigationBar)
            .toolbar {
                if showNavigation {
                    ToolbarItemGroup(placement: .bottomBar) {
                        nativeDestination("home",title:"ホーム",symbol:"house")
                        nativeDestination("daily",title:"日々勤怠",symbol:"calendar")
                        nativeDestination("close",title:"締め申請",symbol:"checkmark.rectangle")
                        nativeDestination("settings",title:"設定",symbol:"gearshape")
                    }
                }
            }
        }
        .preferredColorScheme(navigation.preferredScheme)
        .fullScreenCover(isPresented: $onboardingPresented) {
            NativeFirstRunGuide {
                onboardingCompleted = true
                onboardingPresented = false
            }
        }
        .onAppear { initializeOnboarding() }
        .onChange(of: navigation.showOnboarding) { _, show in
            if show {
                navigation.showOnboarding = false
                onboardingPresented = true
            }
        }
    }

    @ViewBuilder
    private func nativeDestination(_ destination: String, title: String, symbol: String) -> some View {
        let selected = navigation.nativeSettingsOpen ? destination == "settings" : navigation.page == destination
        Button { navigation.navigate(destination) } label: {
            Label(title,systemImage:selected && destination == "home" ? "house.fill" :
                  selected && destination == "close" ? "checkmark.rectangle.fill" : symbol)
        }
        .tint(selected ? .accentColor : .primary)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

struct OfficialTimeCardWebView: UIViewRepresentable {
    @ObservedObject var navigation: NativeNavigationModel
    private static let home = URL(string: "https://m.e-staffing.ne.jp/s/")!

    func makeCoordinator() -> Coordinator { Coordinator(navigation: navigation) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Default persistent data store: do NOT use nonPersistent(), do NOT
        // clear cookies on launch, and do NOT recreate the view on rotations.
        config.websiteDataStore = WKWebsiteDataStore.default()
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let controller = config.userContentController
        controller.add(context.coordinator, name: "etcCredentialBridge")
        controller.add(context.coordinator, name: "etcNavigationBridge")
        controller.add(context.coordinator, name: "etcProductivityBridge")
        controller.add(context.coordinator, name: "etcNativeFormBridge")

        // Early CSS suppresses the original UI before v4.5 transforms it.
        addScript("prepaint", to: controller, when: .atDocumentStart)
        addScript("duo-layout", to: controller, when: .atDocumentStart)
        addScript("japan-holidays", to: controller, when: .atDocumentStart)
        addScript("e-staffing-native-v4.6", to: controller, when: .atDocumentEnd, isMain: true)
        addScript("break-autofill", to: controller, when: .atDocumentEnd)
        addScript("credential-assistant", to: controller, when: .atDocumentEnd)
        addScript("productivity", to: controller, when: .atDocumentEnd)
        addScript("native-form-bridge", to: controller, when: .atDocumentEnd)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        // Browser-history swipe/Back can replay old Struts requests. Use
        // the official in-page navigation instead.
        webView.allowsBackForwardNavigationGestures = false
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        webView.isOpaque = false
        webView.backgroundColor = .systemGroupedBackground
        webView.scrollView.backgroundColor = .systemGroupedBackground
        context.coordinator.webView = webView
        navigation.webView = webView
        navigation.cancelDashboard = { [weak coordinator = context.coordinator] in
            coordinator?.cancelDashboardRefresh()
        }
        navigation.calendarDayRoute = { [weak coordinator = context.coordinator] date in
            coordinator?.requestCalendarDay(date)
        }
        navigation.calendarDayRouteCancel = { [weak coordinator = context.coordinator] in
            coordinator?.cancelCalendarDay()
        }
        navigation.recoveryLoginHandler = { [weak coordinator = context.coordinator] in
            coordinator?.openRecoveryLoginManually()
        }
        navigation.nativeReminderHandler = { [weak coordinator = context.coordinator] kind, enabled, hour, minute, day in
            coordinator?.updateReminderFromNative(kind: kind, enabled: enabled, hour: hour, minute: minute, day: day)
        }
        webView.load(URLRequest(url: Self.home))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // No reload here: resizing/rotation/folding must preserve the web session.
    }

    private func addScript(_ filename: String,
                           to controller: WKUserContentController,
                           when timing: WKUserScriptInjectionTime,
                           isMain: Bool = false) {
        guard let url = Bundle.main.url(forResource: filename, withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else { return }
        let wrapped: String
        if isMain {
            wrapped = """
            try {\n\(source)\n} catch (error) { console.error('TimeCard design:', error); }
            finally { document.documentElement.removeAttribute('data-etc-native-preparing'); }
            """
        } else {
            wrapped = source
        }
        controller.addUserScript(WKUserScript(source: wrapped,
            injectionTime: timing, forMainFrameOnly: true))
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        private let navigation: NativeNavigationModel

        init(navigation: NativeNavigationModel) {
            self.navigation = navigation
            super.init()
        }
        private var pending: TimeCardCredential?
        // One automatic attempt per app launch. This also prevents logging
        // users straight back in after an intentional LOGOUT.
        private var automaticSignInAttempted = false
        private var authenticationInProgress = false
        private var lastSubmissionWasAutomatic = false
        // Reauthentication is a fresh official login, never a replay of the
        // rejected request. At most one automatic recovery per app session.
        private var recoveryAutoAttempted = false
        private var recoveryAwaitingLogin = false
        private var recoveryAutoSubmitting = false
        private var recoveryManualRequested = false
        private var recoveryGeneration = 0
        // An automatic, sequential official-page visit ONCE per app launch.
        // Never open a second WKWebView or issue parallel session requests.
        private var dashboardRefreshAttempted = false
        private var dashboardRefreshInFlight = false
        private var dashboardFirst: [String: Any]?
        private var dashboardWaitingForSecond = false
        private var dashboardReturning = false
        private var dashboardSessionID = 0
        private var calendarRouteDate: String?
        private var calendarRouteSteps = 0
        private var calendarRouteID = 0
        private var calendarRouteBusy = false
        private var calendarRouteOpened = false
        private func endCalendarRoute(_ reason: String? = nil) {
            calendarRouteDate = nil
            navigation.openingCalendarDay = nil
            calendarRouteBusy = false
            calendarRouteSteps = 0
            calendarRouteOpened = false
            if let reason = reason { status(reason) }
        }
        func cancelCalendarDay() {
            // Cancel only the app-owned routing chain, not an in-flight
            // official submission or the site's current form.
            calendarRouteID += 1
            endCalendarRoute()
        }
        func requestCalendarDay(_ date: String) {
            guard !dashboardRefreshInFlight, !navigation.dashboardLoading,
                  !navigation.navigationInProgress, calendarRouteDate == nil,
                  date.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options:.regularExpression) != nil,
                  date.hasPrefix(navigation.calendarMonth + "-"),
                  navigation.calendarRows[date] != nil,
                  let view=webView, let url=view.url, isOfficialPage(url) else { return }
            calendarRouteDate=date
            navigation.openingCalendarDay=date
            calendarRouteSteps=0
            calendarRouteBusy=false
            calendarRouteOpened=false
            calendarRouteID += 1
            let routeID=calendarRouteID
            DispatchQueue.main.asyncAfter(deadline:.now()+15) { [weak self] in
                guard let self=self, self.calendarRouteID==routeID,
                      self.calendarRouteDate != nil else { return }
                self.endCalendarRoute("日付を開けませんでした。公式画面から日付を選択してください。")
            }
            continueCalendarRoute()
        }
        private func continueCalendarRoute() {
            guard let date=calendarRouteDate, !calendarRouteBusy,
                  calendarRouteSteps < 4,
                  let view=webView, let url=view.url, isOfficialPage(url) else {
                if calendarRouteDate != nil && calendarRouteSteps >= 4 {
                    endCalendarRoute("公式の日付画面へ移動できませんでした。")
                }
                return
            }
            calendarRouteBusy=true
            let routeID=calendarRouteID
            let arg=jsonLiteral(date) ?? "null"
            let script="""
            (()=>{if(document.querySelector('form[name="TMSINP01ActionForm"]')){
                if(!document.querySelector('#etc-native-nav .etc-nav-inner a:nth-of-type(3)'))return 'unsupported';
                window.setTimeout(()=>window.__etcNativeNavigate?.('close'),30);return 'navigating';}
            if(document.querySelector('form[name="TMSINP02ActionForm"]'))return window.__etcRouteCalendarDateStep?.(\(arg))||'unsupported';
            if(document.querySelector('form[name="TMSMNU01ActionForm"]')){
                if(!document.querySelector('#etc-native-nav .etc-nav-inner a:nth-of-type(3)'))return 'unsupported';
                window.setTimeout(()=>window.__etcNativeNavigate?.('close'),30);return 'navigating';}
            return 'unsupported';})()
            """
            // On daily pages, navigate to the closing list via its official
            // menu first. No browser history, direct form URLs, or parallel requests.
            view.evaluateJavaScript(script) { [weak self] result, error in
                guard let self=self, self.calendarRouteID==routeID,
                      self.calendarRouteDate==date else { return }
                self.calendarRouteBusy=false
                let state=result as? String ?? "unsupported"
                if error != nil || state=="unsupported" {
                    self.endCalendarRoute("日付への移動を確認できませんでした。締め申請の一覧から選択してください。")
                } else if ["period","opened","navigating"].contains(state) {
                    if state=="opened" { self.calendarRouteOpened=true }
                    self.calendarRouteSteps += 1
                    // Next step runs after didFinish on the same WKWebView.
                } else if state=="notClose" {
                    self.endCalendarRoute("ページの移動を確認できませんでした。")
                }
            }
        }


        private func showRecovery(message: String) {
            if !navigation.recoveryActive {
                navigation.recoveryActive = true
                recoveryManualRequested = false
                navigation.recoveryMessage = message
                navigation.recoveryAutomatic = false
                navigation.recoveryLoading = false
                cancelDashboardRefresh()
                if calendarRouteDate != nil { cancelCalendarDay() }
                navigation.nativeCanDailyApply = false
                navigation.nativeCanCloseApply = false
                navigation.nativeDailyReady = false
                navigation.showOfficial = false
                if navigation.nativeSubmissionInFlight {
                    navigation.nativeSubmissionInFlight = false
                    navigation.nativeSubmissionState = "verify"
                    navigation.nativeSubmissionMessage = "申請結果は不明です。再ログイン後に履歴を確認してください。"
                }
            }
            guard !recoveryAutoAttempted,
                  !recoveryAwaitingLogin,
                  UserDefaults.standard.object(forKey: "etc-duo-recovery.autoSignIn") as? Bool ?? true,
                  CredentialVault.exists() else { return }
            recoveryAutoAttempted = true
            navigation.recoveryAutomatic = true
            navigation.recoveryLoading = true
            navigation.recoveryMessage = "公式ログイン画面へ安全に移動しています…"
            followOfficialLoginLink()
        }

        private func followOfficialLoginLink() {
            guard let webView = webView, let url = webView.url,
                  isOfficialPage(url), navigation.recoveryActive else {
                navigation.recoveryLoading = false
                return
            }
            recoveryAwaitingLogin = true
            recoveryGeneration += 1
            let generation = recoveryGeneration
            // Click only the site's own explicit login link, never browser Back
            // and never resubmit the rejected Struts request.
            let script = """
            (() => {
                const anchors = [...document.querySelectorAll('a[href]')];
                const link = anchors.find(a => {
                    const text = (a.textContent || '').replace(/\\s+/g,' ').trim();
                    if (!text.includes('ログイン画面へ')) return false;
                    try {
                        const url = new URL(a.href, location.href);
                        return url.origin === 'https://m.e-staffing.ne.jp' &&
                               url.pathname.startsWith('/s/');
                    } catch (_) { return false; }
                });
                if (!link) return false;
                link.click();
                return true;
            })()
            """
            webView.evaluateJavaScript(script) { [weak self] result, error in
                guard let self = self, generation == self.recoveryGeneration,
                      self.navigation.recoveryActive else { return }
                if error != nil || (result as? Bool) != true {
                    self.recoveryAwaitingLogin = false
                    self.navigation.recoveryLoading = false
                    self.navigation.recoveryMessage =
                        "公式ログイン画面へ移動できませんでした。下のボタンからログインしてください。"
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 14) { [weak self] in
                guard let self = self, generation == self.recoveryGeneration,
                      self.recoveryAwaitingLogin else { return }
                self.recoveryAwaitingLogin = false
                self.navigation.recoveryLoading = false
                self.navigation.recoveryMessage = "自動接続を確認できません。ログイン画面からお試しください。"
            }
        }

        func openRecoveryLoginManually() {
            guard navigation.recoveryActive, !recoveryAutoSubmitting else { return }
            // The manual path does not read saved credentials without the
            // user's action and never silently retries the rejected action.
            automaticSignInAttempted = true
            recoveryManualRequested = true
            recoveryGeneration += 1
            recoveryAwaitingLogin = false
            recoveryAutoSubmitting = false
            navigation.recoveryAutomatic = false
            navigation.recoveryLoading = true
            navigation.recoveryMessage = "公式ログイン画面を開いています…"
            guard let webView = webView, let url = webView.url, isOfficialPage(url) else {
                navigation.recoveryLoading = false
                navigation.recoveryMessage = "公式サイトに接続できません。通信状況を確認してください。"
                return
            }
            if navigation.page == "login" && navigation.nativeLoginReady {
                navigation.recoveryActive = false
                navigation.recoveryLoading = false
                return
            }
            // When no official login anchor is present, start from the known
            // initial official home route; do not clear session cookies.
            let script = """
            (() => {
                const link = [...document.querySelectorAll('a[href]')].find(a =>
                    (a.textContent||'').includes('ログイン画面へ') &&
                    a.origin === 'https://m.e-staffing.ne.jp' &&
                    new URL(a.href).pathname.startsWith('/s/'));
                if (!link) return false;
                link.click(); return true;
            })()
            """
            webView.evaluateJavaScript(script) { [weak self, weak webView] result, error in
                guard let self = self, self.navigation.recoveryActive,
                      let view = webView, self.webView === view else { return }
                if error != nil || (result as? Bool) != true {
                    view.load(URLRequest(url: URL(string:"https://m.e-staffing.ne.jp/s/")!))
                }
            }
        }

        private func submitRecoveryCredentialsWithoutBiometrics() {
            guard recoveryAwaitingLogin, !recoveryAutoSubmitting,
                  navigation.recoveryActive, CredentialVault.exists(),
                  let view = webView, let url = view.url, isOfficialPage(url),
                  let credential = CredentialVault.read() else {
                navigation.recoveryLoading = false
                navigation.recoveryMessage = "保存済みのログイン情報を使用できません。手動でログインしてください。"
                return
            }
            recoveryAwaitingLogin = false
            recoveryManualRequested = false
            recoveryAutoSubmitting = true
            navigation.recoveryMessage = "保存済みアカウントでログインしています…"
            guard let json = jsonLiteral([
                "companyID": credential.companyID,
                "userID": credential.userID,
                "password": credential.password
            ]) else {
                recoveryAutoSubmitting = false
                navigation.recoveryLoading = false
                return
            }
            // Keychain uses WhenUnlockedThisDeviceOnly: this works only while
            // the device is unlocked. No new key storage or cookie extraction.
            // The JS helper validates the official login form/action.
            lastSubmissionWasAutomatic = true
            automaticSignInAttempted = true
            view.evaluateJavaScript("window.__etcCredentialAutoSubmit?.(\(json))") { [weak self] result, error in
                guard let self = self, self.navigation.recoveryActive else { return }
                if error == nil, let ok = result as? Bool, !ok {
                    self.recoveryAutoSubmitting = false
                    self.navigation.recoveryLoading = false
                    self.navigation.recoveryMessage = "公式ログインフォームが変更されたため、自動再ログインできませんでした。"
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 17) { [weak self] in
                guard let self = self, self.recoveryAutoSubmitting,
                      self.navigation.recoveryActive else { return }
                self.recoveryAutoSubmitting = false
                self.navigation.recoveryLoading = false
                self.navigation.recoveryMessage = "ログイン完了を確認できませんでした。手動ログインを利用してください。"
            }
        }

        // The e-staffing service may redirect to URLs without /s/ (or to
        // another official e-staffing subdomain).  A redirect is NOT a tap.
        // Keep these HTTPS pages inside the WebView instead of sending users
        // to Safari during app launch or login.
        private func isTrustedWebURL(_ url: URL) -> Bool {
            guard url.scheme?.lowercased() == "https",
                  let host = url.host?.lowercased() else { return false }
            return host == "e-staffing.ne.jp" || host.hasSuffix(".e-staffing.ne.jp")
        }

        // Keychain credentials must ONLY be read/filled on the mobile
        // WebTimeCard pages, even if other company pages are shown in-app.
        private func isOfficialPage(_ url: URL) -> Bool {
            guard isTrustedWebURL(url),
                  url.host?.lowercased() == "m.e-staffing.ne.jp" else { return false }
            return url.path == "/s" || url.path == "/s/" || url.path.hasPrefix("/s/")
        }

        private func isExternalUserLink(_ action: WKNavigationAction) -> Bool {
            action.navigationType == .linkActivated
        }

        private func mayOpenExternally(_ url: URL) -> Bool {
            guard let scheme = url.scheme?.lowercased() else { return false }
            return ["https", "http", "tel", "mailto"].contains(scheme)
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            // about:blank is a legitimate WebKit placeholder while a page loads.
            if url.scheme?.lowercased() == "about" {
                decisionHandler(.allow)
                return
            }
            if isTrustedWebURL(url) {
                decisionHandler(.allow)
                return
            }

            // For target=_blank, let WKUIDelegate decide.  It opens only a
            // link the user explicitly clicked, never a scripted popup.
            if navigationAction.targetFrame == nil {
                decisionHandler(.allow)
                return
            }

            // Critical v2.3 change: an automatic cross-domain redirect or a
            // JavaScript navigation MUST NOT open Safari on its own.
            if isExternalUserLink(navigationAction) && mayOpenExternally(url) {
                UIApplication.shared.open(url)
            } else {
                NSLog("TimeCard: blocked automatic offsite navigation to host: %@", url.host ?? "unknown")
            }
            decisionHandler(.cancel)
        }

        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            guard navigationAction.targetFrame == nil,
                  let url = navigationAction.request.url else { return nil }
            if isTrustedWebURL(url) {
                // Stay in the SAME WebView and retain cookies/session.
                webView.load(URLRequest(url: url))
            } else if isExternalUserLink(navigationAction) && mayOpenExternally(url) {
                // Explicit user tap on FAQ or other outside link.
                UIApplication.shared.open(url)
            } else {
                NSLog("TimeCard: ignored automatic popup to host: %@", url.host ?? "unknown")
            }
            return nil
        }

        // The official form may use window.confirm/window.alert for validations.
        // WKWebView needs an explicit UIDelegate to show those prompts.
        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping (Bool) -> Void) {
            guard frame.isMainFrame, let url = webView.url, isOfficialPage(url),
                  let host = webView.window?.rootViewController,
                  host.presentedViewController == nil else {
                completionHandler(false)
                return
            }
            let alert = UIAlertController(title: "e-staffing の確認",
                                          message: String(message.prefix(600)),
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "キャンセル", style: .cancel) { _ in
                completionHandler(false)
                webView.evaluateJavaScript("window.__etcNativeSubmissionCancel?.()", completionHandler: nil)
            })
            alert.addAction(UIAlertAction(title: "確認", style: .default) { _ in
                completionHandler(true)
            })
            host.present(alert, animated: true)
        }

        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping () -> Void) {
            guard frame.isMainFrame, let url = webView.url, isOfficialPage(url),
                  let host = webView.window?.rootViewController,
                  host.presentedViewController == nil else {
                completionHandler()
                return
            }
            let alert = UIAlertController(title: "e-staffing",
                                          message: String(message.prefix(600)),
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "閉じる", style: .default) { _ in
                completionHandler()
            })
            host.present(alert, animated: true)
        }

        func userContentController(_ controller: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            // This bridge transmits UI state only (page key/theme/modal flag),
            // never credentials or hidden form tokens.
            if message.name == "etcNavigationBridge" {
                guard message.frameInfo.isMainFrame,
                      let currentURL = webView?.url,
                      isOfficialPage(currentURL),
                      let payload = message.body as? [String: Any] else { return }
                navigation.receive(payload)
                return
            }
            if message.name == "etcNativeFormBridge" {
                guard message.frameInfo.isMainFrame,
                      let currentURL = webView?.url, isOfficialPage(currentURL),
                      let payload = message.body as? [String: Any],
                      let action = payload["action"] as? String,
                      navigation.page == "daily" || navigation.page == "close" ||
                        currentURL.path.contains("TMSINP01") ||
                        currentURL.path.contains("TMSINP02") else { return }
                if action == "dailySnapshot" {
                    navigation.receiveDaily(payload)
                } else if action == "templateResult" {
                    if let success = payload["success"] as? Bool {
                        navigation.nativeTemplateMessage = success ?
                            "テンプレートを入力欄に反映しました。保存結果は未確認です。" :
                            "反映できませんでした。公式画面で入力可否をご確認ください。"
                    }
                } else if action == "saveState", let state = payload["status"] as? String {
                    navigation.nativeSaveState = state
                } else if action == "submissionSnapshot" || action == "submissionState" {
                    navigation.receiveNativeSubmission(payload)
                }
                return
            }
            if message.name == "etcProductivityBridge" {
                guard message.frameInfo.isMainFrame,
                      let currentURL = webView?.url, isOfficialPage(currentURL),
                      let payload = message.body as? [String: Any],
                      let action = payload["action"] as? String else { return }
                switch action {
                case "calendarSnapshot":
                    guard currentURL.path.contains("TMSINP02") ||
                          currentURL.path.hasPrefix("/s/TMSMNU01/close") ||
                          navigation.page == "close" else { return }
                    if let snapshot = payload["snapshot"] as? [String: Any],
                       navigation.mergeCalendar(snapshot) {
                        publishMonthCalendar()
                    }
                case "dashboard":
                    guard currentURL.path.contains("TMSINP02") ||
                          currentURL.path.hasPrefix("/s/TMSMNU01/close") ||
                          navigation.page == "close" else { return }
                    guard let aggregate = payload["summary"] as? [String: Any] else { return }
                    if dashboardRefreshInFlight {
                        processAutomaticPeriod(aggregate)
                    } else if navigation.summary.isEmpty {
                        // A single manually viewed period is always labeled partial.
                        var partial = aggregate
                        partial["coverage"] = "partial"
                        navigation.consumeDashboard(partial)
                    }
                case "dashboardUnavailable":
                    if dashboardRefreshInFlight {
                        completeWithAvailablePeriod(message: "締め申請の期間データを読み取れませんでした。")
                    }
                case "openCalendarDate":
                    if let date=payload["date"] as? String { requestCalendarDay(date) }
                case "salaryStatus":
                    sendSalaryStatus()
                case "salarySave":
                    configureSalary(payload)
                case "reminderStatus":
                    sendReminderStatus()
                case "reminder":
                    configureReminder(payload)
                default: break
                }
                return
            }
            guard message.name == "etcCredentialBridge",
                  message.frameInfo.isMainFrame,
                  let currentURL = webView?.url,
                  isOfficialPage(currentURL),
                  let payload = message.body as? [String: Any],
                  let action = payload["action"] as? String else { return }
            switch action {
            case "status":
                status()
            case "candidate":
                // Store in memory only until the official server returns a home screen.
                guard let userID = payload["userID"] as? String,
                      let password = payload["password"] as? String,
                      !userID.isEmpty, !password.isEmpty,
                      userID.count <= 128, password.count <= 512 else { return }
                let fallback = UserDefaults.standard.string(forKey: "etc-duo-account.companyID") ?? "pasona"
                let companyID = (payload["companyID"] as? String ?? fallback)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !companyID.isEmpty, companyID.count <= 128 else { return }
                pending = TimeCardCredential(companyID: companyID, userID: userID, password: password)
            case "restore":
                restoreAfterDeviceAuthentication()
            case "authenticateAndLogin":
                // User-initiated retry is available after cancellation/errors.
                authenticateAndSubmitLogin()
            case "delete":
                confirmDelete()
            default:
                return
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            // Keep the native toolbar visible on signed-in pages; prevent
            // double navigation while the server is processing a request.
            self.navigation.navigationInProgress = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            self.navigation.navigationInProgress = false
            if self.navigation.nativeSubmissionInFlight {
                // Server navigation alone does not certify the new application.
                self.navigation.nativeSubmissionState = "verify"
                self.navigation.nativeSubmissionMessage =
                    "申請後の公式ページへ移動しました。申請履歴で受付結果を確認してください。"
                self.navigation.nativeSubmissionInFlight = false
            }
            guard let url = webView.url, isOfficialPage(url) else { return }
            // Inspect only this trusted page's visible error text. Never send
            // cookies, hidden fields or URLs to the native UI.
            let test = """
            (() => {
                const body = (document.body?.innerText || '').slice(0,12000);
                return {
                    unauthorized: body.includes('許可されていない操作が検知されました') &&
                                  body.includes('ログイン画面へ'),
                    home: !!document.querySelector('form[name="TMSMNU01ActionForm"]'),
                    login: !!document.querySelector('form[name="TMSLGN01ActionForm"]'),
                    close: !!document.querySelector('form[name="TMSINP02ActionForm"]'),
                    daily: !!document.querySelector('form[name="TMSINP01ActionForm"]')
                };
            })()
            """
            webView.evaluateJavaScript(test) { [weak self, weak webView] result, error in
                guard let self = self, let webView = webView,
                      self.webView === webView,
                      error == nil, let state = result as? [String: Bool] else { return }
                if state["unauthorized"] == true {
                    if self.navigation.recoveryActive && self.recoveryAutoAttempted {
                        self.recoveryAwaitingLogin = false
                        self.recoveryAutoSubmitting = false
                        self.navigation.recoveryLoading = false
                        self.navigation.recoveryMessage =
                            "自動再接続は完了できませんでした。公式ログイン画面からログインしてください。"
                    } else {
                        self.showRecovery(message: "e-staffingが操作を拒否しました。再ログインが必要です。")
                    }
                    return
                }
                self.publishDashboard()
                self.publishMonthCalendar()
                self.sendSalaryStatus()
                if state["home"] == true {
                    if self.navigation.recoveryActive {
                        self.recoveryManualRequested = false
                        self.recoveryAutoSubmitting = false
                        self.recoveryAwaitingLogin = false
                        self.recoveryGeneration += 1
                        self.navigation.recoveryActive = false
                        self.navigation.recoveryLoading = false
                        self.navigation.recoveryAutomatic = false
                        self.navigation.recoveryMessage = ""
                    }
                    self.navigation.nativeLoginReady = false
                    self.navigation.page = "home"
                    self.navigation.isVisible = true
                    if let candidate = self.pending {
                        if CredentialVault.save(candidate) {
                            UserDefaults.standard.set(candidate.companyID,
                                                      forKey: "etc-duo-account.companyID")
                        }
                    }
                    self.pending = nil
                    self.lastSubmissionWasAutomatic = false
                    // Respect explicit logout later in the same app session.
                    self.automaticSignInAttempted = true
                    if self.dashboardReturning {
                        self.dashboardReturning = false
                        self.dashboardRefreshInFlight = false
                        self.dashboardFirst = nil
                        self.dashboardWaitingForSecond = false
                        self.navigation.dashboardLoading = false
                    }
                    self.beginAutomaticDashboardRefresh()
                } else if state["login"] == true {
                    if self.navigation.recoveryActive && self.recoveryManualRequested {
                        self.recoveryManualRequested = false
                        self.recoveryGeneration += 1
                        self.navigation.recoveryActive = false
                        self.navigation.recoveryLoading = false
                        self.navigation.recoveryAutomatic = false
                        self.navigation.recoveryMessage = ""
                    }
                    if self.navigation.recoveryActive && self.recoveryAutoSubmitting {
                        self.recoveryAutoSubmitting = false
                        self.navigation.recoveryLoading = false
                        self.navigation.recoveryMessage =
                            "自動ログインできませんでした。ID・パスワードを確認してください。"
                    }
                    self.navigation.nativeLoginReady = true
                    self.navigation.page = "login"
                    self.navigation.isVisible = false
                    self.navigation.summary = [:]
                    self.navigation.resetCalendar()
                    self.dashboardRefreshInFlight = false
                    self.dashboardFirst = nil
                    self.dashboardWaitingForSecond = false
                    self.dashboardReturning = false
                    self.navigation.dashboardLoading = false
                    if self.recoveryAwaitingLogin {
                        self.submitRecoveryCredentialsWithoutBiometrics()
                    } else if self.navigation.recoveryActive {
                        // Recovery already tried; do not let the ordinary
                        // startup Face ID flow loop or hide the error.
                        self.lastSubmissionWasAutomatic = false
                    } else if self.pending != nil {
                        self.pending = nil  // Never retry incorrect credentials automatically.
                        if self.lastSubmissionWasAutomatic {
                            self.status("自動ログインできませんでした。ID・パスワードを確認するか、手動でログインしてください。")
                        }
                        self.lastSubmissionWasAutomatic = false
                    } else if !self.automaticSignInAttempted,
                              !self.authenticationInProgress,
                              CredentialVault.exists() {
                        self.automaticSignInAttempted = true
                        self.authenticateAndSubmitLogin()
                    }
                } else if self.dashboardRefreshInFlight && state["close"] != true {
                    // Do not hide a server-side unauthorized-operation page.
                    self.cancelDashboardRefresh()
                }
                if self.calendarRouteDate != nil {
                    if self.calendarRouteOpened {
                        if state["daily"] == true { self.endCalendarRoute() }
                        else { self.endCalendarRoute("指定日の公式画面を開けませんでした。") }
                    } else if state["login"] == true {
                        self.endCalendarRoute("セッションが終了しました。ログイン後にもう一度操作してください。")
                    } else {
                        DispatchQueue.main.asyncAfter(deadline: .now()+0.12) { [weak self] in
                            self?.continueCalendarRoute()
                        }
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            self.navigation.navigationInProgress = false
            if dashboardRefreshInFlight { cancelDashboardRefresh() }
            if calendarRouteDate != nil { endCalendarRoute("日付への移動でエラーが発生しました。") }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            self.navigation.navigationInProgress = false
            if dashboardRefreshInFlight { cancelDashboardRefresh() }
            if calendarRouteDate != nil { endCalendarRoute("日付への移動でエラーが発生しました。") }
        }

        // A saved account means the user explicitly opted in on a previous
        // successful login. Device-owner authentication is still required
        // before any password is supplied to the official login form.
        private func authenticateAndSubmitLogin() {
            guard !authenticationInProgress, CredentialVault.exists() else {
                status("保存済みのログイン情報がありません。")
                return
            }
            guard let view = webView,
                  let url = view.url, isOfficialPage(url) else { return }
            authenticationInProgress = true
            let context = LAContext()
            context.localizedCancelTitle = "キャンセル"
            var authError: NSError?
            guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
                authenticationInProgress = false
                status("Face ID／Touch IDまたは端末パスコードを設定し、手動でログインしてください。")
                return
            }
            context.evaluatePolicy(.deviceOwnerAuthentication,
                                   localizedReason: "保存したe-staffingアカウントでログインします") { [weak self] success, _ in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.authenticationInProgress = false
                    guard success else {
                        self.status("本人確認がキャンセルされました。手動ログインも利用できます。")
                        return
                    }
                    guard let activeView = self.webView,
                          activeView === view,
                          let url = activeView.url, self.isOfficialPage(url),
                          let credential = CredentialVault.read() else {
                        self.status("ログイン画面または保存情報を確認できませんでした。")
                        return
                    }
                    let payload: [String: String] = [
                        "companyID": credential.companyID,
                        "userID": credential.userID,
                        "password": credential.password
                    ]
                    guard let json = self.jsonLiteral(payload) else { return }
                    // Set pending before clicking submit. Login may navigate before
                    // JS messages reach the coordinator. Save only on menu success.
                    self.pending = credential
                    self.lastSubmissionWasAutomatic = true
                    activeView.evaluateJavaScript("window.__etcCredentialAutoSubmit?.(\(json))") { [weak self] result, error in
                        guard let self = self else { return }
                        if error == nil, let didSubmit = result as? Bool, !didSubmit {
                            self.pending = nil
                            self.lastSubmissionWasAutomatic = false
                            self.status("ログイン画面が変更されたため、自動ログインできませんでした。手動でログインしてください。")
                        }
                        // A navigation can cancel the JS completion callback
                        // even when the form POST has already been submitted.
                    }
                }
            }
        }

        private func beginAutomaticDashboardRefresh() {
            guard !dashboardRefreshAttempted, !dashboardRefreshInFlight,
                  let view = webView, let url = view.url,
                  isOfficialPage(url), navigation.page == "home" else { return }
            dashboardRefreshAttempted = true
            dashboardRefreshInFlight = true
            dashboardWaitingForSecond = false
            dashboardReturning = false
            dashboardFirst = nil
            navigation.resetCalendar()
            dashboardSessionID += 1
            let session = dashboardSessionID
            navigation.dashboardProgress = "最初の締め期間を確認しています…"
            navigation.dashboardLoading = true
            // Safety release if the server rejects the transition or no message arrives.
            DispatchQueue.main.asyncAfter(deadline: .now() + 22) { [weak self] in
                guard let self = self, self.dashboardSessionID == session,
                      self.dashboardRefreshInFlight else { return }
                if self.dashboardReturning {
                    // Even a failed home navigation must never trap the user
                    // under a permanent loading sheet.
                    self.cancelDashboardRefresh()
                } else {
                    self.completeWithAvailablePeriod(message: "時間内に2期間を確認できませんでした。")
                }
            }
            view.evaluateJavaScript("window.__etcBeginDashboardRefresh?.()") { [weak self, weak view] result, error in
                guard let self = self, let view = view, self.webView === view else { return }
                if error == nil && (result as? Bool) == false {
                    self.cancelDashboardRefresh()
                }
            }
        }

        // Only the official dates of two distinct half-month periods are added.
        // Invalid or alternative employer closing schedules remain partial.
        private func periodSide(_ value: [String: Any]) -> (String, Int)? {
            guard let start = value["start"] as? String,
                  let end = value["end"] as? String,
                  start.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
                  end.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
                  start.prefix(7) == end.prefix(7) else { return nil }
            let month = String(start.prefix(7))
            let parts = month.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 2, (1...12).contains(parts[1]),
                  let date = Calendar(identifier: .gregorian).date(from: DateComponents(year:parts[0], month:parts[1], day:1)),
                  let range = Calendar(identifier: .gregorian).range(of: .day, in: .month, for: date) else { return nil }
            if start.hasSuffix("-01") && end.hasSuffix("-15") { return (month, 1) }
            if start.hasSuffix("-16") && end.hasSuffix(String(format:"-%02d", range.count)) { return (month, 2) }
            return nil
        }

        private func processAutomaticPeriod(_ aggregate: [String: Any]) {
            guard dashboardRefreshInFlight, !dashboardReturning else { return }
            guard periodSide(aggregate) != nil else {
                if dashboardFirst == nil { dashboardFirst = aggregate }
                completeWithAvailablePeriod(message: "この契約では2つの半月期間を確認できませんでした。")
                return
            }
            if dashboardFirst == nil {
                dashboardFirst = aggregate
                guard let side = periodSide(aggregate)?.1 else { return }
                dashboardWaitingForSecond = true
                navigation.dashboardProgress = "もう一方の締め期間を確認しています…"
                let direction = side == 1 ? "next" : "prev"
                // Evaluate the real official prev/next anchor from the CURRENT DOM.
                let script = "window.__etcVisitSiblingPeriod?.('\(direction)')"
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    guard let self = self, self.dashboardRefreshInFlight,
                          self.dashboardWaitingForSecond, let view = self.webView else { return }
                    view.evaluateJavaScript(script) { [weak self] result, error in
                        if error == nil && (result as? Bool) == false {
                            self?.completeWithAvailablePeriod(message: "隣の期間へ移動できませんでした。")
                        }
                    }
                }
                return
            }
            // Duplicate messages from the same document must not terminate the scan.
            if let first = dashboardFirst,
               first["start"] as? String == aggregate["start"] as? String,
               first["end"] as? String == aggregate["end"] as? String { return }
            guard dashboardWaitingForSecond, let first = dashboardFirst,
                  let one = periodSide(first), let two = periodSide(aggregate),
                  one.0 == two.0, one.1 != two.1,
                  let monthly = mergePeriods(first, aggregate, month: one.0) else {
                completeWithAvailablePeriod(message: "2期間の年月が一致しないため、月間合計を表示できません。")
                return
            }
            navigation.consumeDashboard(monthly)
            navigation.dashboardProgress = "月間集計が完了しました。ホームへ戻ります…"
            returnDashboardHome()
        }

        private func mergePeriods(_ first: [String: Any], _ second: [String: Any], month: String) -> [String: Any]? {
            func value(_ dict: [String: Any], _ key: String) -> Int? {
                guard let v = dict[key] as? Int, v >= 0 else { return nil }
                return v
            }
            var result: [String: Any] = ["start": month + "-01", "coverage": "month", "month": month]
            let parts = month.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 2,
                  let date = Calendar(identifier:.gregorian).date(from:DateComponents(year:parts[0],month:parts[1],day:1)),
                  let count = Calendar(identifier:.gregorian).range(of:.day,in:.month,for:date)?.count else { return nil }
            result["end"] = month + String(format:"-%02d",count)
            for key in ["worked","empty","valid","minutes","overtimeMinutes","approved","pending"] {
                guard let a = value(first, key), let b = value(second, key) else { return nil }
                result[key] = a + b
            }
            if let a = first["unsent"] as? Int, let b = second["unsent"] as? Int {
                result["unsent"] = a + b
            } else { result["unsent"] = NSNull() }
            let now = DateFormatter()
            now.dateFormat = "yyyy-MM-dd"
            now.locale = Locale(identifier: "en_US_POSIX")
            let today = now.string(from: Date())
            if let firstStart = first["start"] as? String, let firstEnd = first["end"] as? String,
                firstStart <= today && today <= firstEnd { result["todayStatus"] = first["todayStatus"] ?? "未確認" }
            else if let secondStart = second["start"] as? String, let secondEnd = second["end"] as? String,
                secondStart <= today && today <= secondEnd { result["todayStatus"] = second["todayStatus"] ?? "未確認" }
            else { result["todayStatus"] = "対象期間外・未確認" }
            return result
        }

        private func completeWithAvailablePeriod(message: String) {
            if let first = dashboardFirst {
                var partial = first
                partial["coverage"] = "partial"
                partial["note"] = message
                navigation.consumeDashboard(partial)
            }
            navigation.dashboardProgress = message + " ホームへ戻ります…"
            returnDashboardHome()
        }

        private func returnDashboardHome() {
            guard dashboardRefreshInFlight, !dashboardReturning else { return }
            dashboardWaitingForSecond = false
            dashboardReturning = true
            guard let view = webView, let url = view.url, isOfficialPage(url) else {
                cancelDashboardRefresh(); return
            }
            // Use the official home navigation, never WKWebView.goBack().
            view.evaluateJavaScript("window.__etcNativeNavigate?.('home')") { [weak self] result, error in
                if error == nil && (result as? Bool) != true { self?.cancelDashboardRefresh() }
            }
        }

        func cancelDashboardRefresh() {
            dashboardSessionID += 1
            dashboardRefreshInFlight = false
            dashboardWaitingForSecond = false
            dashboardReturning = false
            dashboardFirst = nil
            navigation.dashboardLoading = false
        }

        private func publishMonthCalendar() {
            guard let view = webView, !navigation.calendarRows.isEmpty,
                  let json = jsonLiteral(navigation.calendarRows.values.map { $0.bridgeObject }) else { return }
            // Display-only: never invokes any link or form button.
            view.evaluateJavaScript("window.__etcReceiveMonthlyCalendar?.(\(json))",completionHandler:nil)
        }

        private func publishDashboard() {
            guard let view = webView, !navigation.summary.isEmpty,
                  let json = jsonLiteral(navigation.summary) else { return }
            view.evaluateJavaScript("window.__etcReceiveDashboard?.(\(json))", completionHandler: nil)
        }

        private let salaryKey = "etc-duo-v296-salary."
        private func sendSalaryStatus(message: String = "") {
            guard let view = webView else { return }
            let preferences = UserDefaults.standard
            let rate = preferences.integer(forKey: salaryKey + "hourlyJPY")
            let enabled = preferences.bool(forKey: salaryKey + "enabled")
            let premium = preferences.object(forKey: salaryKey + "premium") as? Bool ?? true
            let payload: [String: Any] = [
                "enabled": enabled && rate > 0,
                "rate": max(0, min(rate, 100000)),
                "premium": premium,
                "message": message
            ]
            guard let arg = jsonLiteral(payload) else { return }
            view.evaluateJavaScript("window.__etcSalaryStatus?.(\(arg))", completionHandler: nil)
        }

        private func configureSalary(_ payload: [String: Any]) {
            guard let enabled = payload["enabled"] as? Bool,
                  let rate = payload["rate"] as? Int, (0...100000).contains(rate),
                  let premium = payload["premium"] as? Bool else { return }
            if enabled && rate == 0 {
                sendSalaryStatus(message: "時給を入力してからオンにしてください。")
                return
            }
            let prefs = UserDefaults.standard
            prefs.set(rate, forKey: salaryKey + "hourlyJPY")
            prefs.set(enabled, forKey: salaryKey + "enabled")
            prefs.set(premium, forKey: salaryKey + "premium")
            sendSalaryStatus(message: enabled ? "給与目安を表示します" : "給与目安を非表示にしました")
        }

        private let reminderPrefix = "etc-duo-v29."
        private func sendReminderStatus(message: String = "") {
            guard let view = webView else { return }
            func values(_ kind: String, _ defaultHour: Int, _ defaultMinute: Int, _ defaultDay: Int) -> [String: Any] {
                let key = "etc-duo-reminder-" + kind
                return ["enabled": UserDefaults.standard.bool(forKey: key + ".enabled"),
                        "hour": UserDefaults.standard.object(forKey: key + ".hour") as? Int ?? defaultHour,
                        "minute": UserDefaults.standard.object(forKey: key + ".minute") as? Int ?? defaultMinute,
                        "day": UserDefaults.standard.object(forKey: key + ".day") as? Int ?? defaultDay,
                        "message": message]
            }
            let payload: [String: Any] = ["weekday": values("weekday", 18, 30, 15),
                                          "close": values("close", 17, 0, 15)]
            guard let json = jsonLiteral(payload) else { return }
            view.evaluateJavaScript("window.__etcReminderStatus?.(\(json))", completionHandler: nil)
        }

        func updateReminderFromNative(kind: String, enabled: Bool, hour: Int, minute: Int, day: Int) {
            configureReminder(["kind": kind, "enabled": enabled, "hour": hour, "minute": minute, "day": day])
        }

        private func configureReminder(_ data: [String: Any]) {
            guard let kind = data["kind"] as? String, ["weekday", "close"].contains(kind),
                  let enabled = data["enabled"] as? Bool,
                  let hour = data["hour"] as? Int, (0...23).contains(hour),
                  let minute = data["minute"] as? Int, (0...59).contains(minute),
                  let day = data["day"] as? Int, (1...28).contains(day) else { return }
            let center = UNUserNotificationCenter.current()
            let prefix = reminderPrefix + kind + "."
            let ids = kind == "weekday" ? (2...6).map { prefix + String($0) } : [prefix + "monthly"]
            center.removePendingNotificationRequests(withIdentifiers: ids)
            let key = "etc-duo-reminder-" + kind
            UserDefaults.standard.set(hour, forKey: key + ".hour")
            UserDefaults.standard.set(minute, forKey: key + ".minute")
            UserDefaults.standard.set(day, forKey: key + ".day")
            guard enabled else {
                UserDefaults.standard.set(false, forKey: key + ".enabled")
                navigation.nativeReminderMessage = "通知をオフにしました"
                sendReminderStatus(message: "通知をオフにしました")
                return
            }
            center.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, _ in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    guard granted else {
                        UserDefaults.standard.set(false, forKey: key + ".enabled")
                        self.navigation.nativeReminderMessage = "通知が許可されていません。iPhoneの設定から許可してください。"
                        self.sendReminderStatus(message: "通知の許可が必要です。設定アプリで許可してください。")
                        return
                    }
                    let texts = kind == "weekday"
                        ? ("今日の勤怠を確認", "勤務時間の入力・保存状況をe-staffingで確認してください。")
                        : ("締め申請の確認", "契約先の締め日と申請状況をe-staffingで確認してください。")
                    for id in ids {
                        let content = UNMutableNotificationContent()
                        content.title = texts.0
                        content.body = texts.1
                        content.sound = .default
                        var components = DateComponents()
                        components.hour = hour
                        components.minute = minute
                        if kind == "weekday" { components.weekday = Int(id.split(separator: ".").last ?? "2") }
                        else { components.day = day }
                        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
                    }
                    UserDefaults.standard.set(true, forKey: key + ".enabled")
                    UserDefaults.standard.set(hour, forKey: key + ".hour")
                    UserDefaults.standard.set(minute, forKey: key + ".minute")
                    UserDefaults.standard.set(day, forKey: key + ".day")
                    self.navigation.nativeReminderMessage = "通知を設定しました"
                    self.sendReminderStatus(message: "通知を設定しました（申請状況の自動確認は行いません）")
                }
            }
        }

        private func status(_ detail: String? = nil) {
            guard let webView = webView else { return }
            let flag = CredentialVault.exists() ? "true" : "false"
            let textArg = detail.flatMap { jsonLiteral($0) } ?? "null"
            webView.evaluateJavaScript("window.__etcCredentialStatus?.(\(flag),\(textArg))", completionHandler: nil)
        }

        private func restoreAfterDeviceAuthentication() {
            guard CredentialVault.exists() else {
                status("保存されたログイン情報はありません。"); return
            }
            let context = LAContext()
            context.localizedCancelTitle = "キャンセル"
            var error: NSError?
            guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
                status("端末のFace IDまたはパスコードを設定してから利用してください。"); return
            }
            context.evaluatePolicy(.deviceOwnerAuthentication,
                                   localizedReason: "保存したe-staffingのログイン情報を入力します") { [weak self] success, _ in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    guard success else {
                        self.status("認証がキャンセルされたため、入力していません。"); return
                    }
                    guard let credential = CredentialVault.read(),
                          let view = self.webView,
                          let currentURL = view.url,
                          self.isOfficialPage(currentURL) else { return }
                    let data: [String: String] = [
                        "companyID": credential.companyID,
                        "userID": credential.userID,
                        "password": credential.password
                    ]
                    guard let json = self.jsonLiteral(data) else { return }
                    view.evaluateJavaScript("window.__etcCredentialApply?.(\(json))", completionHandler: nil)
                }
            }
        }

        private func confirmDelete() {
            guard let view = webView,
                  let presenter = view.window?.rootViewController else { return }
            let alert = UIAlertController(title: "保存情報を削除", message: "このiPhoneに保存された企業ID・ユーザID・パスワードを削除します。公式サイトのセッションやCookieは削除しません。", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "キャンセル", style: .cancel))
            alert.addAction(UIAlertAction(title: "削除", style: .destructive) { [weak self] _ in
                let ok = CredentialVault.delete()
                self?.status(ok ? "保存したログイン情報を削除しました。" : "削除に失敗しました。")
            })
            presenter.present(alert, animated: true)
        }

        private func jsonLiteral(_ object: Any) -> String? {
            guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed]),
                  let text = String(data: data, encoding: .utf8) else { return nil }
            return text
        }
    }
}
