import SwiftUI
import WebKit
import Charts

// Native front-end.  The single official WKWebView remains mounted behind it;
// the bridge sends only explicitly allowed UI field values and choice indices.
struct NativeApplicationScreen: View {
    @ObservedObject var model: NativeNavigationModel
    var body: some View {
        Group {
            if model.nativeSettingsOpen {
                NativePreferencesScreen(model:model)
            } else if model.nativeAnalysisOpen {
                NativeAnalyticsScreen(model:model)
            } else {
                switch model.page {
                case "login": NativeLoginScreen(model:model)
                case "home": NativeHomeScreen(model:model)
                case "daily": NativeDailyScreen(model:model)
                case "close": NativeClosingScreen(model:model)
                default: EmptyView()
                }
            }
        }
        .accessibilityIdentifier("native-main-content")
    }
}

// Native recovery replaces the raw server error, while the original
// trusted WKWebView remains mounted behind it with the same cookie store.
struct NativeSessionRecoveryScreen: View {
    @ObservedObject var model: NativeNavigationModel

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "exclamationmark.shield.fill")
                            .font(.system(size: 44, weight: .medium))
                            .foregroundStyle(.orange)
                            .frame(width: 76, height: 76)
                            .background(Color.orange.opacity(0.12),
                                        in: RoundedRectangle(cornerRadius: 23))
                        Text("再ログインが必要です")
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        Text("e-staffingで許可されていない操作が検出されました。セッションを安全に接続し直します。")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    NativeSurface(title: "接続状態") {
                        HStack(alignment: .center, spacing: 12) {
                            if model.recoveryLoading {
                                ProgressView().controlSize(.regular)
                                    .accessibilityLabel("再ログイン処理中")
                            } else {
                                Image(systemName: "info.circle.fill")
                                    .foregroundStyle(.orange)
                            }
                            Text(model.recoveryMessage.isEmpty
                                 ? "再ログインしてください。"
                                 : model.recoveryMessage)
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if model.recoveryAutomatic && model.recoveryLoading {
                            Label("Face IDを使わず、保存済みのアカウントを使用しています",
                                  systemImage: "key.fill")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Button { model.openRecoveryLogin() } label: {
                        Label("公式ログイン画面へ", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(model.recoveryLoading)
                    .accessibilityIdentifier("session-recovery-open-login")
                    Text("前の画面で拒否された入力・保存・申請操作は自動で再送信しません。申請直後の場合は、ログイン後に申請履歴をご確認ください。")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(22)
                .frame(maxWidth: 510)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .center)
            }
            .background(Color(uiColor: .systemGroupedBackground))
        }
        .accessibilityIdentifier("native-session-recovery")
    }
}

// Keep the iOS 27.1-only fold API behind an availability check; the app's
// deployment target also supports earlier iOS versions.
private func duoDivisionFrame(in proxy: GeometryProxy) -> CGRect? {
    if #available(iOS 27.1, *) {
        return proxy.reservedRegions(kind: .division).first?.frame
    }
    return nil
}

private struct NativeSurface<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading,spacing:12) {
            Text(title).font(.headline)
            content
        }
        .frame(maxWidth:.infinity,alignment:.leading)
        .padding(16)
        .background(Color(uiColor:.secondarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:20))
    }
}

// A single official-state vocabulary is reused on the home, calendar,
// analytics and the date preview. Unfetched periods never become zeroes.
private struct NativeSyncStatusBanner: View {
    @ObservedObject var model: NativeNavigationModel
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: model.nativeSaveState == "error" ? "exclamationmark.triangle.fill" :
                  model.navigationInProgress ? "arrow.triangle.2.circlepath" : "checkmark.shield")
                .foregroundStyle(model.nativeSaveState == "error" ? Color.orange : Color.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.nativeSyncStatus).font(.caption.weight(.semibold))
                if let date = model.page == "daily" ? model.lastOfficialDailyAt :
                              model.page == "home" ? model.lastOfficialDashboardAt :
                              model.lastOfficialCalendarAt {
                    Text("公式画面から最終取得：" +
                         date.formatted(date: .omitted, time: .shortened))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(uiColor: .tertiarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 13))
        .accessibilityIdentifier("native-sync-status")
    }
}

struct NativeCalendarDayPreview: View {
    let date: String
    let record: NativeCalendarRecord?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 11) {
                        Image(systemName: record?.stateSymbol ?? "questionmark.circle")
                            .font(.title2).foregroundStyle(record?.stateTint ?? .secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(record?.stateLabel ?? "未取得")
                                .font(.title3.bold())
                            Text(date).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    if let record, record.known {
                        if !record.hours.isEmpty {
                            LabeledContent("勤務時間", value: record.hours)
                        }
                        if !record.rest.isEmpty {
                            LabeledContent("休憩", value: record.rest + "分")
                        }
                        if !record.place.isEmpty {
                            LabeledContent("就業場所", value: record.place)
                        }
                        if !record.approvalDescription.isEmpty {
                            LabeledContent("申請状態", value: record.approvalDescription)
                        }
                        if !record.holiday.isEmpty {
                            LabeledContent("休日情報", value: record.holiday)
                        }
                    } else {
                        Label("この日付の公式データはまだ取得されていません。",
                              systemImage: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                    Text("表示内容は公式画面から取得できた情報のみです。長押ししても申請や保存は行いません。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .navigationTitle("勤務記録のプレビュー")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("native-calendar-day-preview")
    }
}

private struct NativeWorkTemplate: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var startTime: String
    var endTime: String
    var breakMinutes: String

    static let presets: [NativeWorkTemplate] = [
        .init(id: "default", name: "通常勤務", startTime: "0900", endTime: "1730", breakMinutes: "60"),
        .init(id: "late", name: "遅番", startTime: "1100", endTime: "1930", breakMinutes: "60"),
        .init(id: "short", name: "時短勤務", startTime: "0900", endTime: "1500", breakMinutes: "0")
    ]
    private func time(_ raw: String) -> String {
        guard raw.count == 4 else { return raw }
        return String(raw.prefix(2)) + ":" + String(raw.suffix(2))
    }
    var summary: String {
        time(startTime) + "〜" + time(endTime) + " · 休憩" + breakMinutes + "分"
    }
}

struct NativeHomeScreen: View {
    @ObservedObject var model: NativeNavigationModel
    @AppStorage("etc-duo-v296-salary.enabled") private var salaryEnabled = false
    @AppStorage("etc-duo-v296-salary.hourlyJPY") private var rate = 0
    @AppStorage("etc-duo-v296-salary.premium") private var premium = true
    @State private var salaryHidden = false

    private var salaryValid: Bool { model.hasCompleteMonth }
    private var payroll: (Int, Int, Int) {
        let mins = model.summary["minutes"] as? Int ?? 0
        let overtime = model.summary["overtimeMinutes"] as? Int ?? 0
        let hourly = Double(rate)
        let base = Double(mins) * hourly / 60
        let uplift = premium ? Double(overtime) * hourly / 60 * 0.25 : 0
        return (Int((base + uplift).rounded()),
                Int((Double(overtime) * hourly / 60 + uplift).rounded()),
                Int(uplift.rounded()))
    }
    private func currency(_ amount: Int) -> String {
        amount.formatted(.currency(code: "JPY").precision(.fractionLength(0)))
    }
    private func readable(_ number: Int) -> String {
        salaryHidden ? "•••••" : currency(number)
    }
    private func minutes(_ number: Int) -> String {
        "\(number / 60)時間" + String(format: "%02d", number % 60) + "分"
    }
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour < 11 ? "おはようございます。" :
               hour < 18 ? "こんにちは。" : "おつかれさまです。"
    }
    private var todayKey: String {
        Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))
    }
    private var todayRecord: NativeCalendarRecord? { model.calendarRows[todayKey] }
    private var todayStatus: String {
        if let record = todayRecord, record.known { return record.stateLabel }
        return model.todayConfirmedState
    }
    private var knownCoverage: Bool { model.summary["coverage"] as? String == "month" }
    private var pendingCount: Int? { model.summary["pending"] as? Int }
    private var unsentCount: Int? { model.summary["unsent"] as? Int }
    private func metric(_ title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(.title3, design: .rounded, weight: .semibold))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
        .padding(13)
        .background(Color(uiColor: .tertiarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 15))
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("WebTimeCard").font(.caption.weight(.semibold)).foregroundStyle(.tint)
                    Text(greeting)
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text(Date.now.formatted(date: .complete, time: .omitted))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.bottom, 2)
                NativeSurface(title: "今日の勤怠") {
                    HStack(alignment: .center) {
                        Label(todayStatus,
                              systemImage: todayRecord?.stateSymbol ?? "calendar.badge.clock")
                            .font(.headline)
                            .foregroundStyle(todayRecord?.stateTint ?? Color.primary)
                        Spacer()
                        Text("公式データに基づく表示")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    if let rec = todayRecord, rec.known, !rec.hours.isEmpty {
                        Text(rec.hours)
                            .font(.system(.title, design: .rounded, weight: .semibold))
                            .monospacedDigit()
                    } else {
                        Text("開始 --:--   終了 --:--")
                            .font(.system(.title3, design: .rounded, weight: .medium))
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                    Button { model.navigate("daily") } label: {
                        Label("日々勤怠を開く", systemImage: "square.and.pencil")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .accessibilityIdentifier("home-open-daily")
                    if todayRecord == nil && model.todayConfirmedState == "未確認" {
                        Text("今日の記録は未確認です。未入力と断定しません。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 9) {
                    metric("出勤日数", value: (model.summary["worked"] as? Int).map { "\($0)日" } ?? "—",
                           icon: "calendar.badge.checkmark")
                    metric("未送信", value: unsentCount.map { "\($0)件" } ?? "未確認",
                           icon: "tray.full")
                }
                HStack(spacing: 9) {
                    metric("申請確認中", value: pendingCount.map { "\($0)件" } ?? "未確認",
                           icon: "clock.badge.checkmark")
                    metric("実働", value: salaryValid ?
                           minutes(model.summary["minutes"] as? Int ?? 0) : "—",
                           icon: "clock")
                }
                if !knownCoverage {
                    Label("集計は一部期間のみです。未取得の日を0日・0時間として扱いません。",
                          systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
                NativeSurface(title: "クイックアクセス") {
                    HStack(spacing: 10) {
                        Button { model.navigate("close") } label: {
                            Label("締め申請", systemImage: "checkmark.rectangle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        Button { model.nativeAnalysisOpen = true } label: {
                            Label("勤務分析", systemImage: "chart.bar.xaxis")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("home-open-analytics")
                    }
                }
                NativeSyncStatusBanner(model: model)
                if salaryEnabled && rate > 0 {
                    NativeSurface(title: "給与目安") {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(salaryValid ? readable(payroll.0) : "—")
                                    .font(.system(.title, design: .rounded, weight: .bold))
                                Text("給与の概算・公式の確定額ではありません")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { salaryHidden.toggle() } label: {
                                Image(systemName: salaryHidden ? "eye.slash" : "eye")
                            }
                            .accessibilityLabel(salaryHidden ? "金額を表示" : "金額を隠す")
                        }
                        Divider()
                        HStack {
                            Text("残業代"); Spacer()
                            Text(salaryValid ? readable(payroll.1) : "—").bold()
                        }
                        HStack {
                            Text("うち割増分"); Spacer()
                            Text(salaryValid ? readable(payroll.2) : "—").bold()
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("native-home-priority-dashboard")
    }
}

private struct NativeAnalysisDatum: Identifiable {
    let name: String
    let count: Int
    var id: String { name }
}

struct NativeAnalyticsScreen: View {
    @ObservedObject var model: NativeNavigationModel
    private var fullMonth: Bool { model.summary["coverage"] as? String == "month" }
    private var completeHours: Bool { model.hasCompleteMonth }
    private var filteredRows: [NativeCalendarRecord] {
        model.calendarRows.values
            .filter { $0.date.hasPrefix(model.calendarMonth + "-") }
    }
    private var knownRows: [NativeCalendarRecord] { filteredRows.filter(\.known) }
    private var chartRows: [NativeAnalysisDatum] {
        let rows = knownRows
        return [
            .init(name: "出勤", count: rows.filter { $0.work && !$0.leave }.count),
            .init(name: "年休", count: rows.filter(\.leave).count),
            .init(name: "その他", count: rows.filter { !$0.work && !$0.leave }.count)
        ]
    }
    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(.title2, design: .rounded, weight: .semibold))
                .monospacedDigit().minimumScaleFactor(0.7).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(uiColor: .tertiarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 14))
    }
    private func time(_ key: String) -> String {
        guard completeHours, let value = model.summary[key] as? Int else { return "—" }
        return "\(value / 60)時間\(String(format: "%02d", value % 60))分"
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("勤務分析")
                            .font(.largeTitle.bold())
                        Text(fullMonth ? "月間集計" : "取得済み期間の集計")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { model.navigate("home") } label: {
                        Label("ホーム", systemImage: "house")
                    }
                    .buttonStyle(.bordered)
                }
                NativeSurface(title: "公式データの集計") {
                    HStack(spacing: 10) {
                        metric("出勤", (model.summary["worked"] as? Int).map { "\($0)日" } ?? "—")
                        metric("有休", knownRows.isEmpty ? "—" :
                               "\(knownRows.filter(\.leave).count)日")
                    }
                    HStack(spacing: 10) {
                        metric("実働時間", time("minutes"))
                        metric("残業時間", time("overtimeMinutes"))
                    }
                    if !completeHours {
                        Label("勤務時間は、全期間と全勤務記録の取得・検証が完了した場合のみ表示します。",
                              systemImage: "info.circle")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                NativeSurface(title: "取得した勤務記録の内訳") {
                    if knownRows.isEmpty {
                        ContentUnavailableView("記録をまだ取得していません",
                            systemImage: "chart.bar.xaxis",
                            description: Text("締め申請画面で公式の勤務記録を読み込むと表示できます。"))
                    } else {
                        Chart(chartRows) { datum in
                            BarMark(
                                x: .value("種類", datum.name),
                                y: .value("日数", datum.count)
                            )
                            .foregroundStyle(by: .value("種類", datum.name))
                        }
                        .frame(height: 195)
                        .accessibilityIdentifier("analytics-official-status-chart")
                        Text("取得済み \(knownRows.count)日・未取得 \(filteredRows.filter { !$0.known }.count)日")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                NativeSyncStatusBanner(model: model)
                Text("この分析はe-staffingの公式画面から取得できた範囲の参考表示です。給与や申請の確定記録とは異なります。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(16).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("native-monthly-analytics")
    }
}

struct NativeDailyScreen: View {
    @ObservedObject var model: NativeNavigationModel
    @State private var confirmDailyApplication = false
    @State private var tabletopDetailsExpanded = false
    @AppStorage("etc-duo.templates.custom-v1") private var customTemplatesJSON = "[]"
    @AppStorage("etc-duo.tips.break-v1") private var breakTipSeen = false
    @AppStorage("etc-duo.tips.templates-v1") private var templateTipSeen = false
    @State private var templatePreview: NativeWorkTemplate?
    @State private var saveTemplateName = ""
    @State private var showSaveTemplate = false
    @State private var editingTimeName: String?
    @State private var editingTimeValue = Date()
    // The forecast and the official break field share a single source of truth.
    @AppStorage("etc-duo-v33.shift.netMinutes") private var shiftNetMinutes = 450
    @AppStorage("etc-duo-v33.shift.breakMinutes") private var plannedBreakMinutes = 60
    private var previewRestMinutes: Int {
        enteredRestMinutes ?? plannedBreakMinutes
    }
    private var previewRestDescription: String {
        enteredRestMinutes == nil ? "休憩目安\(plannedBreakMinutes)分" : "休憩\(previewRestMinutes)分"
    }
    private func updateBreakMinutes(_ value: Int) {
        guard (0...960).contains(value) else { return }
        model.nativeFormAction(["kind":"field","name":"rstTime","value":"\(value)"])
    }
    private var expectedEndTime: String? {
        ShiftEndForecast.endTime(startHHmm: field("startTime"),
                                 netMinutes: shiftNetMinutes,
                                 breakMinutes: previewRestMinutes)
    }
    private func field(_ name:String)->String {model.nativeDailyFields[name] ?? ""}
    private func timeValue(_ name:String)->Date {
        let value=field(name)
        let hour=value.count==4 ? Int(value.prefix(2)) ?? 9 : (name=="startTime" ? 9 : 18)
        let minute=value.count==4 ? Int(value.suffix(2)) ?? 0 : 0
        return Calendar.current.date(from: DateComponents(year:2001,month:1,day:1,hour:hour,minute:minute)) ?? Date()
    }
    private func setTime(_ name:String,_ date:Date) {
        let comps=Calendar.current.dateComponents([.hour,.minute],from:date)
        let value=String(format:"%02d%02d",comps.hour ?? 0,comps.minute ?? 0)
        model.nativeFormAction(["kind":"field","name":name,"value":value])
    }
    private var canApplyDaily: Bool {
        model.nativeCanDailyApply && !model.nativeSubmissionInFlight &&
        !model.navigationInProgress &&
        !["pending", "sending", "error", "verify", "local"].contains(model.nativeSaveState)
    }
    private var saveText:String {
        switch model.nativeSaveState {
        case "pending":return "自動保存待ち"
        case "sending":return "一時保存中…"
        case "verify":return "保存結果を確認してください"
        case "local":return "入力を保持中"
        case "error":return "自動保存できませんでした"
        default:return "変更は自動で一時保存"
        }
    }
    private func minuteOfDay(_ raw: String) -> Int? {
        guard raw.count == 4, let hour = Int(raw.prefix(2)),
              let minute = Int(raw.suffix(2)), hour < 24, minute < 60 else { return nil }
        return hour * 60 + minute
    }
    private var elapsedMinutes: Int? {
        guard let start = minuteOfDay(field("startTime")),
              let end = minuteOfDay(field("endTime")) else { return nil }
        let elapsed = (end - start + 1440) % 1440
        return elapsed > 0 && elapsed <= 960 ? elapsed : nil
    }
    private var recommendedRestMinutes: Int? {
        guard let span = elapsedMinutes else { return nil }
        // Conservative guidance based on time between start and end. The legal
        // threshold itself depends on ACTUAL working time, not elapsed span.
        return span > 480 ? 60 : span > 360 ? 45 : 0
    }
    private var enteredRestMinutes: Int? {
        let raw = field("rstTime").trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return nil }
        if let value = Int(raw), value >= 0, value <= 960 { return value }
        let parts = raw.split(separator: ":")
        if parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
           h >= 0, h <= 16, m >= 0, m < 60 { return h * 60 + m }
        return nil
    }
    private var actualWorkMinutes: Int? {
        guard let span = elapsedMinutes, let rest = enteredRestMinutes,
              rest <= span else { return nil }
        return span - rest
    }
    private var legalMinimumMinutes: Int? {
        guard let worked = actualWorkMinutes else { return nil }
        return worked > 480 ? 60 : worked > 360 ? 45 : 0
    }
    private func duration(_ total: Int) -> String {
        total % 60 == 0 ? "\(total / 60)時間" : "\(total / 60)時間\(total % 60)分"
    }
    private func readOnlyTime(_ name: String) -> String {
        let raw = field(name).trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.count == 4, let hour = Int(raw.prefix(2)),
              let minute = Int(raw.suffix(2)), hour < 24, minute < 60 else {
            return raw.isEmpty ? "—" : raw
        }
        return String(format: "%02d:%02d", hour, minute)
    }
    private func readOnlyValue(_ name: String, suffix: String = "") -> String {
        let raw = field(name).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "—" }
        return raw + (suffix.isEmpty || raw.hasSuffix(suffix) ? "" : suffix)
    }
    private func lockedRow(_ title: String, value: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 21)
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 6)
            Text(value).fontWeight(.semibold)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.vertical, 5)
    }
    private var lockedDailyInfo: some View {
        Label(model.nativeDailyApprovalStatus.isEmpty
              ? "この記録は編集できません"
              : "\(model.nativeDailyApprovalStatus)・編集できません",
              systemImage: "lock.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("daily-approved-lock-banner")
    }
    private var dailyReadOnlyCard: some View {
        NativeSurface(title: "記録済みの勤務内容") {
            lockedDailyInfo
            Divider()
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("開始").font(.caption).foregroundStyle(.secondary)
                    Text(readOnlyTime("startTime"))
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("終了").font(.caption).foregroundStyle(.secondary)
                    Text(readOnlyTime("endTime"))
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                }
            }
            .accessibilityIdentifier("daily-approved-recorded-times")
            Divider()
            lockedRow("休憩", value: readOnlyValue("rstTime",suffix:"分"), icon: "cup.and.saucer")
            if !field("nightRstTime").isEmpty {
                lockedRow("深夜休憩", value: readOnlyValue("nightRstTime",suffix:"分"), icon: "moon")
            }
            lockedRow("区分", value: model.nativeDailyCategoryDisplay.isEmpty
                      ? "—" : model.nativeDailyCategoryDisplay, icon: "square.grid.2x2")
            lockedRow("就業場所", value: model.nativeDailyWorkplaceDisplay.isEmpty
                      ? "—" : model.nativeDailyWorkplaceDisplay, icon: "building.2")
            if !field("remark").isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 5) {
                    Text("備考").font(.caption).foregroundStyle(.secondary)
                    Text(field("remark")).font(.subheadline)
                }
            }
            if field("startTime").isEmpty && field("endTime").isEmpty {
                Label("公式画面で表示されている勤務記録を確認してください。",
                      systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("daily-approved-readonly-card")
    }
    private var dailyLockedActions: some View {
        Button { model.showOfficial = true } label: {
            Label("公式画面で記録を確認", systemImage: "arrow.up.right.square")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered).controlSize(.large)
        .accessibilityIdentifier("daily-approved-official-link")
    }
    private var tabletopLockedDashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("日々勤怠").font(.headline)
                if !model.nativeDayTitle.isEmpty {
                    Text(model.nativeDayTitle).font(.caption).foregroundStyle(.secondary)
                }
                Label(model.nativeDailyApprovalStatus.isEmpty
                      ? "閲覧のみ" : model.nativeDailyApprovalStatus,
                      systemImage: "lock.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 18) {
                    VStack(alignment: .leading) {
                        Text("開始").font(.caption).foregroundStyle(.secondary)
                        Text(readOnlyTime("startTime")).font(.system(.title2, design: .rounded, weight: .bold))
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("終了").font(.caption).foregroundStyle(.secondary)
                        Text(readOnlyTime("endTime")).font(.system(.title2, design: .rounded, weight: .bold))
                    }
                }.monospacedDigit()
            }
            .padding(16).frame(maxWidth: 750).frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .accessibilityIdentifier("daily-approved-tabletop-dashboard")
    }
    private var tabletopLockedDetails: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                dailyReadOnlyCard
                dailyLockedActions
            }
            .padding(16).frame(maxWidth: 750).frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("daily-approved-tabletop-details")
    }
    // iOS 27.1 reports an active reserved division when Duo is partly folded.
    // Divide the *actual* available view rectangle; do not infer a fold from
    // orientation, window size or device identifiers.
    private var dailyHeading: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("日々勤怠").font(.largeTitle.bold())
            if !model.nativeDayTitle.isEmpty {
                Text(model.nativeDayTitle)
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
    private var dailyWorkCard: some View {
        NativeSurface(title:"勤務時間") {
                    HStack(spacing:12) {
                        timeItem("開始",name:"startTime")
                        timeItem("終了",name:"endTime")
                    }
                    Divider()
                    HStack(alignment:.center,spacing:12) {
                        VStack(alignment:.leading,spacing:3) {
                            Text("退勤予定").font(.caption).foregroundStyle(.secondary)
                            Text(expectedEndTime ?? "—")
                                .font(.system(.title2,design:.rounded,weight:.bold))
                                .monospacedDigit()
                                .accessibilityIdentifier("daily-expected-end")
                            Text("実働\(duration(shiftNetMinutes)) + \(previewRestDescription)")
                                .font(.caption2).foregroundStyle(.secondary)
                                .accessibilityIdentifier("daily-expected-assumption")
                        }
                        Spacer(minLength:0)
                        Menu {
                            ForEach([0,30,45,60,90,120], id: \.self) { rest in
                                Button {
                                    updateBreakMinutes(rest)
                                } label: {
                                    Label("休憩\(rest)分", systemImage: previewRestMinutes == rest ? "checkmark.circle.fill" : "clock")
                                }
                            }
                        } label: {
                            Label(enteredRestMinutes == nil ? "予定休憩 \(plannedBreakMinutes)分" : "休憩 \(previewRestMinutes)分",systemImage:"chevron.up.chevron.down")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityIdentifier("daily-preview-break-menu")
                    }
                    .accessibilityIdentifier("daily-shift-preview-inline")
                    Divider()
                    HStack(spacing: 8) {
                        Label("実際の休憩",systemImage:"cup.and.saucer")
                            .font(.subheadline.weight(.medium))
                        Spacer(minLength:0)
                        TextField("分",text:Binding(
                            get: { field("rstTime") },
                            set: { model.nativeFormAction(["kind":"field","name":"rstTime","value":$0]) }
                        ))
                            .keyboardType(.numbersAndPunctuation)
                            .textInputAutocapitalization(.never)
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 82)
                            .accessibilityIdentifier("daily-break-minutes-input")
                        Text("分").font(.caption).foregroundStyle(.secondary)
                    }
                    if !breakTipSeen {
                        HStack(alignment: .top, spacing: 10) {
                            Label("休憩の目安と実際の取得時間は別です。目安を超えても休憩欄は自動入力しません。",
                                  systemImage: "lightbulb")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                            Button("了解") { breakTipSeen = true }
                                .font(.caption.weight(.semibold))
                        }
                        .padding(10)
                        .background(Color(uiColor: .tertiarySystemGroupedBackground),
                                    in: RoundedRectangle(cornerRadius: 11))
                        .accessibilityIdentifier("daily-break-context-tip")
                    }
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("休憩の目安").font(.caption2).foregroundStyle(.secondary)
                            Text(recommendedRestMinutes.map { "\($0)分" } ?? "—")
                                .font(.subheadline.weight(.semibold))
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text("実労働時間").font(.caption2).foregroundStyle(.secondary)
                            Text(actualWorkMinutes.map(duration) ?? "—")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    if let required = legalMinimumMinutes, let entered = enteredRestMinutes,
                       required > entered {
                        Label("実労働時間に対する最低休憩は\(required)分です。取得した休憩を確認してください。",
                              systemImage:"exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.orange)
                    } else if let required = legalMinimumMinutes {
                        Label("実労働時間に対する法定最低休憩：\(required)分",
                              systemImage:"checkmark.circle")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if enteredRestMinutes == nil ||
                        (recommendedRestMinutes != nil && (enteredRestMinutes ?? 0) < (recommendedRestMinutes ?? 0)) {
                        Button { model.nativeFormAction(["kind":"breakRecalculate"]) } label: {
                            Label("休憩の目安を入力",systemImage:"arrow.clockwise")
                        }.buttonStyle(.bordered)
                    }
                    if model.nativeDailyFields["nightRstTime"] != nil && !field("nightRstTime").isEmpty {
                        fieldEntry("深夜休憩",name:"nightRstTime")
                    }
                }
    }
    private var storedTemplates: [NativeWorkTemplate] {
        let bytes = Data(customTemplatesJSON.utf8)
        return (try? JSONDecoder().decode([NativeWorkTemplate].self, from: bytes)) ?? []
    }
    private var allTemplates: [NativeWorkTemplate] {
        NativeWorkTemplate.presets + storedTemplates
    }
    private var canStoreCurrentTemplate: Bool {
        minuteOfDay(field("startTime")) != nil &&
        minuteOfDay(field("endTime")) != nil &&
        enteredRestMinutes != nil &&
        !model.nativeDailyLocked
    }
    private func saveCurrentTemplate() {
        let name = saveTemplateName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canStoreCurrentTemplate, !name.isEmpty, name.count <= 30,
              let rest = enteredRestMinutes else { return }
        var list = storedTemplates
        guard list.count < 20 else { return }
        list.append(.init(id: UUID().uuidString, name: name,
                          startTime: field("startTime"), endTime: field("endTime"),
                          breakMinutes: String(rest)))
        if let bytes = try? JSONEncoder().encode(list),
           let value = String(data: bytes, encoding: .utf8) {
            customTemplatesJSON = value
            saveTemplateName = ""
        }
    }
    private func applyConfirmedTemplate(_ template: NativeWorkTemplate) {
        guard model.nativeDailyReady, !model.nativeDailyLocked,
              !model.navigationInProgress else { return }
        model.nativeTemplateMessage = ""
        model.nativeFormAction([
            "kind": "template", "confirmed": true,
            "values": ["startTime": template.startTime,
                       "endTime": template.endTime,
                       "rstTime": template.breakMinutes]
        ])
    }
    private var templateCard: some View {
        NativeSurface(title: "勤務パターン") {
            HStack(spacing: 10) {
                Menu {
                    ForEach(allTemplates) { template in
                        Button(template.name + "  " + template.summary) {
                            templatePreview = template
                        }
                    }
                } label: {
                    Label("テンプレートから入力", systemImage: "square.stack.3d.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("daily-select-work-template")
                Button {
                    saveTemplateName = ""
                    showSaveTemplate = true
                } label: {
                    Image(systemName: "plus.square.on.square")
                }
                .buttonStyle(.bordered)
                .disabled(!canStoreCurrentTemplate || storedTemplates.count >= 20)
                .accessibilityLabel("現在の勤務時間をテンプレートに登録")
            }
            if !templateTipSeen {
                HStack(spacing: 10) {
                    Label("選んだだけでは入力されません。変更前に内容を確認できます。",
                          systemImage: "lightbulb")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("了解") { templateTipSeen = true }
                        .font(.caption.weight(.semibold))
                }
                .accessibilityIdentifier("daily-template-context-tip")
            }
            if !model.nativeTemplateMessage.isEmpty {
                Label(model.nativeTemplateMessage, systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !storedTemplates.isEmpty {
                Text("保存したパターン：\(storedTemplates.count)件。設定からリセットできます。")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("native-work-template-card")
    }
    private var templatePreviewCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let template = templatePreview {
                Text(template.name)
                    .font(.title2.bold())
                Text("入力される内容").font(.subheadline).foregroundStyle(.secondary)
                LabeledContent("開始", value: String(template.startTime.prefix(2)) + ":" +
                               String(template.startTime.suffix(2)))
                LabeledContent("終了", value: String(template.endTime.prefix(2)) + ":" +
                               String(template.endTime.suffix(2)))
                LabeledContent("休憩", value: template.breakMinutes + "分")
                Divider()
                Text("現在の入力がある場合は上書きします。選択を確定しても申請は行いません。")
                    .font(.caption).foregroundStyle(.secondary)
                Button {
                    applyConfirmedTemplate(template)
                    templatePreview = nil
                } label: {
                    Label("この内容を入力する", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("daily-confirm-template")
                Button("キャンセル") { templatePreview = nil }
                    .buttonStyle(.bordered)
            }
        }
        .padding(22)
        .frame(maxWidth: 420)
        .accessibilityIdentifier("daily-template-preview")
    }
    private var dailyDetailsCard: some View {
        NativeSurface(title:"勤務区分・就業場所") {
                    Text("区分").font(.subheadline.weight(.semibold))
                    choices(model.nativeCategory,group:"category")
                    Divider()
                    Text("就業場所").font(.subheadline.weight(.semibold))
                    choices(model.nativeWorkplace,group:"workplace")
                    Divider()
                    fieldEntry("備考",name:"remark")
                }
    }
    private var dailyActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing:10) {
                    Label(saveText,systemImage:model.nativeSaveState == "error" ? "exclamationmark.triangle" : "arrow.triangle.2.circlepath")
                        .font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer(minLength:0)
                    if model.nativeCanSave {
                        Button("一時保存") {model.nativeFormAction(["kind":"save"])}
                            .buttonStyle(.bordered).controlSize(.small)
                            .disabled(model.nativeSaveState == "sending")
                    }
                }
                HStack(spacing: 10) {
                    Button { confirmDailyApplication = true } label: {
                        Label("日々申請", systemImage: "checkmark.seal")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(!canApplyDaily)
                    .accessibilityIdentifier("daily-native-apply")
                    Button { model.showOfficial = true } label: {
                        Label("公式画面", systemImage: "arrow.up.right")
                    }
                    .buttonStyle(.bordered).controlSize(.large)
                }
                if !model.nativeSubmissionMessage.isEmpty {
                    Label(model.nativeSubmissionMessage, systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
                NativeSyncStatusBanner(model: model)
        }
    }
    private var dailyWorkPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                dailyHeading
                if model.nativeDailyLocked {
                    dailyReadOnlyCard
                } else {
                    dailyWorkCard
                }
            }
            .padding(16).frame(maxWidth: 750).frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("daily-fold-work-pane")
    }
    private var dailyEditPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                if model.nativeDailyLocked {
                    lockedDailyInfo
                    dailyLockedActions
                } else {
                    templateCard
                    dailyDetailsCard
                    dailyActions
                }
            }
            .padding(16).frame(maxWidth: 750).frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("daily-fold-edit-pane")
    }

    // Tabletop posture uses the upper leaf as a glanceable dashboard and
    // the lower leaf as a touch-first editor. Neither leaf overlaps the hinge.
    private func tabletopDailyMetric(_ title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: icon)
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            Text(value)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 14))
    }
    private var tabletopDailyDashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("日々勤怠").font(.headline)
                        if !model.nativeDayTitle.isEmpty {
                            Text(model.nativeDayTitle)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 8)
                    Label("退勤予定", systemImage: "clock.badge.checkmark")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(expectedEndTime ?? "—")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                        .accessibilityIdentifier("tabletop-daily-forecast")
                    Spacer(minLength: 6)
                    Text("開始時刻＋実働目標＋休憩")
                        .font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(2).multilineTextAlignment(.trailing)
                }
                HStack(spacing: 8) {
                    tabletopDailyMetric("目標実働", value: duration(shiftNetMinutes), icon: "timer")
                    tabletopDailyMetric(enteredRestMinutes == nil ? "予定休憩" : "休憩", value: "\(previewRestMinutes)分", icon: "cup.and.saucer")
                    tabletopDailyMetric("実労働", value: actualWorkMinutes.map(duration) ?? "—", icon: "clock")
                }
                if let required = legalMinimumMinutes, let entered = enteredRestMinutes,
                   entered < required {
                    Label("必要な休憩は\(required)分。休憩時間を確認してください。",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: 750).frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .accessibilityIdentifier("daily-tabletop-dashboard")
    }
    private var tabletopDailyEditor: some View {
        VStack(spacing: 0) {
            HStack {
                Label("勤怠を編集", systemImage: "square.and.pencil")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(model.nativeSyncStatus)
                    .font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        timeItem("開始", name: "startTime")
                        timeItem("終了", name: "endTime")
                    }
                    HStack(spacing: 8) {
                        Label("休憩", systemImage: "cup.and.saucer")
                            .font(.subheadline.weight(.medium))
                        Spacer(minLength: 2)
                        Menu {
                            ForEach([0,30,45,60,90,120], id: \.self) { rest in
                                Button {
                                    updateBreakMinutes(rest)
                                } label: {
                                    Label("\(rest)分",
                                          systemImage: previewRestMinutes == rest ? "checkmark.circle.fill" : "clock")
                                }
                            }
                        } label: {
                            Label("\(previewRestMinutes)分", systemImage: "chevron.down")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        TextField("分", text: Binding(
                            get: { field("rstTime") },
                            set: { model.nativeFormAction(["kind":"field","name":"rstTime","value":$0]) }
                        ))
                        .keyboardType(.numbersAndPunctuation)
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 66)
                        .accessibilityIdentifier("tabletop-daily-break-input")
                        Text("分").font(.caption).foregroundStyle(.secondary)
                    }
                    if enteredRestMinutes == nil ||
                       (recommendedRestMinutes != nil &&
                        (enteredRestMinutes ?? 0) < (recommendedRestMinutes ?? 0)) {
                        Button {
                            model.nativeFormAction(["kind":"breakRecalculate"])
                        } label: {
                            Label("休憩の目安を入力", systemImage: "arrow.clockwise")
                        }
                        .font(.caption).buttonStyle(.bordered).controlSize(.small)
                    }
                    templateCard
                    DisclosureGroup(isExpanded: $tabletopDetailsExpanded) {
                        VStack(alignment: .leading, spacing: 12) {
                            dailyDetailsCard
                            if model.nativeDailyFields["nightRstTime"] != nil &&
                               !field("nightRstTime").isEmpty {
                                fieldEntry("深夜休憩", name: "nightRstTime")
                            }
                        }
                        .padding(.top, 10)
                    } label: {
                        Label("区分・就業場所・備考", systemImage: "slider.horizontal.3")
                            .font(.subheadline.weight(.medium))
                    }
                    .accessibilityIdentifier("tabletop-daily-details")
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .frame(maxWidth: 750).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            Divider()
            HStack(spacing: 8) {
                Label(saveText,
                      systemImage: model.nativeSaveState == "error" ? "exclamationmark.triangle" : "checkmark.circle")
                    .font(.caption2)
                    .foregroundStyle(model.nativeSaveState == "error" ? Color.orange : Color.secondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 2)
                if model.nativeCanSave {
                    Button("保存") { model.nativeFormAction(["kind":"save"]) }
                        .buttonStyle(.bordered).controlSize(.small)
                        .disabled(model.nativeSaveState == "sending")
                }
                Button { confirmDailyApplication = true } label: {
                    Label("日々申請", systemImage: "checkmark.seal")
                }
                .buttonStyle(.borderedProminent).controlSize(.small)
                .disabled(!canApplyDaily)
                .accessibilityIdentifier("tabletop-daily-native-apply")
                Button { model.showOfficial = true } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                .accessibilityLabel("公式画面で確認")
                .buttonStyle(.bordered).controlSize(.small)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .accessibilityIdentifier("tabletop-daily-sticky-actions")
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .accessibilityIdentifier("daily-tabletop-editor")
    }
    var body: some View {
        GeometryReader { proxy in
            let fold = duoDivisionFrame(in: proxy)
            if let fold, fold.height > fold.width,
               fold.minX >= 270, proxy.size.width - fold.maxX >= 270 {
                // Book pose: start/end, forecast and break on the first leaf;
                // workplace, remarks and save on the other leaf.
                HStack(spacing: 0) {
                    dailyWorkPane.frame(width: max(0, fold.minX))
                    Color.clear.frame(width: max(0, fold.width))
                    dailyEditPane.frame(width: max(0, proxy.size.width - fold.maxX))
                }
                .accessibilityIdentifier("daily-fold-book")
            } else if let fold, fold.width >= fold.height,
                      fold.minY >= 145, proxy.size.height - fold.maxY >= 145 {
                // Tabletop pose: touch controls live on the stable lower leaf.
                VStack(spacing: 0) {
                    if model.nativeDailyLocked {
                        tabletopLockedDashboard.frame(height: max(0, fold.minY))
                    } else {
                        tabletopDailyDashboard.frame(height: max(0, fold.minY))
                    }
                    Color.clear.frame(height: max(0, fold.height))
                    if model.nativeDailyLocked {
                        tabletopLockedDetails.frame(height: max(0, proxy.size.height - fold.maxY))
                    } else {
                        tabletopDailyEditor.frame(height: max(0, proxy.size.height - fold.maxY))
                    }
                }
                .accessibilityIdentifier("daily-fold-tabletop")
            } else {
                if proxy.size.width >= 660 {
                    // Fully expanded Duo: persistent side-by-side time and
                    // details, each independently scrollable.
                    HStack(spacing: 0) {
                        dailyWorkPane.frame(maxWidth: .infinity)
                        Divider()
                        dailyEditPane.frame(maxWidth: .infinity)
                    }
                    .accessibilityIdentifier("daily-expanded-two-column")
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 15) {
                            dailyHeading
                            if model.nativeDailyLocked {
                                dailyReadOnlyCard
                                dailyLockedActions
                            } else {
                                dailyWorkCard
                                templateCard
                                dailyDetailsCard
                                dailyActions
                            }
                        }
                        .padding(16).frame(maxWidth: 750).frame(maxWidth: .infinity)
                    }
                    .accessibilityIdentifier("daily-responsive-standard")
                }
            }
        }
        .sheet(item: $templatePreview) { _ in
            templatePreviewCard
                .presentationDetents([.medium])
        }
        .alert("勤務パターンを登録", isPresented: $showSaveTemplate) {
            TextField("名前（30文字以内）", text: $saveTemplateName)
            Button("キャンセル", role: .cancel) {}
            Button("登録") { saveCurrentTemplate() }
        } message: {
            Text("現在入力されている開始・終了・休憩時間を端末に保存します。勤怠の送信は行いません。")
        }
        .alert("日々勤怠を申請しますか？", isPresented: $confirmDailyApplication) {
            Button("キャンセル", role: .cancel) {}
            Button("日々申請する") { model.nativeSubmit("daily") }
        } message: {
            Text("対象：\(model.nativeDailyApplyPeriod)\n入力した勤怠を公式e-staffingへ申請します。一時保存とは異なり、取り消しや修正には制限がある場合があります。")
        }
    }
    private func timeItem(_ label:String,name:String)->some View {
        VStack(alignment:.leading,spacing:8) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            if minuteOfDay(field(name)) != nil {
                DatePicker("",selection:Binding(get:{timeValue(name)},set:{setTime(name,$0)}),
                           displayedComponents:.hourAndMinute)
                    .labelsHidden().datePickerStyle(.compact)
                    .frame(maxWidth:.infinity,alignment:.leading)
            } else {
                // DatePicker requires a concrete Date. Its former getter used
                // 09:00/18:00 when the official field was empty, making an
                // unentered day look like a recorded shift.
                Button {
                    editingTimeValue = timeValue(name)
                    editingTimeName = name
                } label: {
                    Label("未入力", systemImage:"clock.badge.questionmark")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth:.infinity,alignment:.leading)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("daily-empty-\(name)")
                .popover(isPresented: Binding(
                    get: { editingTimeName == name },
                    set: { if !$0 { editingTimeName = nil } }
                )) {
                    VStack(spacing: 14) {
                        Text("\(label)時刻を入力").font(.headline)
                        DatePicker("",selection:$editingTimeValue,displayedComponents:.hourAndMinute)
                            .labelsHidden().datePickerStyle(.wheel)
                        Button("この時刻を入力") {
                            setTime(name,editingTimeValue)
                            editingTimeName = nil
                        }
                        .buttonStyle(.borderedProminent)
                        Button("キャンセル") { editingTimeName = nil }
                            .buttonStyle(.bordered)
                    }
                    .padding(20).frame(minWidth:260)
                    .presentationCompactAdaptation(.sheet)
                }
            }
            Button {setTime(name,Date())} label: {Label("今",systemImage:"clock")}
                .buttonStyle(.bordered).controlSize(.small)
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
    @ViewBuilder private func choices(_ entries:[[String:Any]],group:String)->some View {
        if entries.isEmpty {Text("選択肢を読み込んでいます").font(.caption).foregroundStyle(.secondary)}
        else {
            LazyVGrid(columns:[GridItem(.adaptive(minimum:115),spacing:8)],spacing:8) {
                ForEach(Array(entries.enumerated()),id:\.offset) { index,entry in
                    let title=(entry["label"] as? String ?? "項目").prefix(40)
                    let selected=entry["selected"] as? Bool ?? false
                    Button {model.nativeFormAction(["kind":"choice","group":group,"index":entry["index"] as? Int ?? index])} label: {
                        HStack(spacing:6) {
                            if selected {Image(systemName:"checkmark.circle.fill")}
                            Text(String(title)).lineLimit(2).minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth:.infinity,minHeight:38)
                    }
                    .buttonStyle(.bordered).tint(selected ? .accentColor : .secondary)
                    .disabled(entry["disabled"] as? Bool == true)
                }
            }
        }
    }
    private func fieldEntry(_ label:String,name:String)->some View {
        VStack(alignment:.leading,spacing:5) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label,text:Binding(get:{field(name)},set:{model.nativeFormAction(["kind":"field","name":name,"value":$0])}))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
        }
    }
}

// Native closing screen adapts to Duo outer/inner display WITHOUT loading
// a second official page. The same snapshot powers both layouts.
struct ClosingMonthData {
    let month: String
    let days: Int
    let firstWeekday: Int
    init(_ month: String) {
        self.month = month
        let parts = month.split(separator: "-")
        let y = parts.count == 2 ? Int(parts[0]) ?? 2026 : 2026
        let m = parts.count == 2 ? Int(parts[1]) ?? 1 : 1
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year:y,month:m,day:1)) ?? Date()
        self.days = calendar.range(of:.day,in:.month,for:date)?.count ?? 30
        self.firstWeekday = calendar.component(.weekday,from:date) - 1
    }
    var title: String {
        let bits = month.split(separator:"-")
        guard bits.count == 2 else { return "勤務記録" }
        return "\(bits[0])年\(Int(bits[1]) ?? 1)月"
    }
    func key(_ day: Int) -> String { month + String(format:"-%02d",day) }
    func dateText(_ day: Int) -> String { "\(day)日" }
}

// For known dates, show official state only. Missing half-period data must
// stay '未取得' rather than being misreported as absent work.
private func closingStatus(_ record: NativeCalendarRecord?) -> String {
    guard let item=record else { return "未取得" }
    if !item.known { return "未取得" }
    return item.stateLabel
}

private func closingColor(_ record: NativeCalendarRecord?) -> Color {
    guard let r=record, r.known else { return Color(uiColor:.tertiarySystemGroupedBackground) }
    return r.stateTint.opacity(0.10)
}

struct NativeClosingList: View {
    @ObservedObject var model: NativeNavigationModel
    @State private var previewDate: String?
    let month: ClosingMonthData
    private let weekdayNames=["日","月","火","水","木","金","土"]
    var body: some View {
        LazyVStack(spacing: 9) {
            ForEach(1...month.days,id:\.self) { day in
                let key=month.key(day)
                let row=model.calendarRows[key]
                let w=(month.firstWeekday + day - 1) % 7
                Button { model.openCalendarDate(key) } label: {
                    HStack(alignment:.center,spacing:13) {
                        VStack(spacing:2) {
                            Text("\(day)").font(.title3.bold()).monospacedDigit()
                            Text(weekdayNames[w]).font(.caption2)
                                .foregroundStyle(w == 0 ? .red : w == 6 ? .blue : .secondary)
                        }.frame(width:39)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(row?.stateTint ?? .gray)
                            .frame(width: 3)
                        VStack(alignment:.leading,spacing:5) {
                            Text(row?.leave == true ? "年休" : row?.work == true && !(row?.hours.isEmpty ?? true) ? row!.hours : closingStatus(row))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary).lineLimit(2)
                            let detail=[row?.place ?? "",(row?.rest.isEmpty == false ? "休憩 \(row!.rest)" : ""),
                                        (row?.known == true ? row?.approvalDescription ?? "" : "")]
                                .filter{ !$0.isEmpty }.joined(separator:" · ")
                            if !detail.isEmpty {
                                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            } else if let holiday=row?.holiday,!holiday.isEmpty {
                                Text(holiday).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength:0)
                        Image(systemName:"chevron.right").font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal,12).padding(.vertical,12)
                    .frame(maxWidth:.infinity,alignment:.leading)
                    .background(closingColor(row),in:RoundedRectangle(cornerRadius:14))
                }
                .buttonStyle(.plain)
                .onLongPressGesture(minimumDuration: 0.55) { previewDate = key }
                .accessibilityLabel("\(day)日 \(closingStatus(row)) \(row?.hours ?? "")")
                .accessibilityHint("長押しで勤務記録をプレビュー")
            }
        }
        .accessibilityIdentifier("closing-outer-list")
        .sheet(isPresented: Binding(
            get: { previewDate != nil },
            set: { if !$0 { previewDate = nil } }
        )) {
            NativeCalendarDayPreview(date: previewDate ?? "",
                                     record: model.calendarRows[previewDate ?? ""])
                .presentationDetents([.medium])
        }
    }
}

struct NativeClosingMonthCalendar: View {
    @ObservedObject var model: NativeNavigationModel
    @State private var previewDate: String?
    let month: ClosingMonthData
    private let weekdays=["日","月","火","水","木","金","土"]
    // Fixed, non-lazy rows with unique slot IDs. This always renders days 1...last,
    // including days for which the official site has not supplied records.
    private var slotCount: Int {
        let total = month.firstWeekday + month.days
        return ((total + 6) / 7) * 7
    }
    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { weekday in
                    Text(weekdays[weekday]).font(.caption.weight(.semibold))
                        .foregroundStyle(weekday == 0 ? Color.red : weekday == 6 ? Color.blue : Color.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(0..<(slotCount / 7), id: \.self) { week in
                HStack(alignment: .top, spacing: 6) {
                    ForEach(0..<7, id: \.self) { column in
                        let day = week * 7 + column - month.firstWeekday + 1
                        if (1...month.days).contains(day) {
                            calendarDay(day)
                                .frame(maxWidth: .infinity)
                                .accessibilityIdentifier("closing-day-\(day)")
                        } else {
                            Color.clear.frame(maxWidth: .infinity, minHeight: 105)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("closing-inner-calendar")
        .sheet(isPresented: Binding(
            get: { previewDate != nil },
            set: { if !$0 { previewDate = nil } }
        )) {
            NativeCalendarDayPreview(date: previewDate ?? "",
                                     record: model.calendarRows[previewDate ?? ""])
                .presentationDetents([.medium])
        }
    }
    private func calendarDay(_ day: Int) -> some View {
        let key = month.key(day)
        let row = model.calendarRows[key]
        return Button { model.openCalendarDate(key) } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 3) {
                    Text("\(day)").font(.subheadline.weight(.bold))
                        .foregroundStyle(row?.holiday.isEmpty == false ? Color.red : Color.primary)
                    Spacer(minLength: 0)
                    Image(systemName: row?.stateSymbol ?? "questionmark.circle")
                        .foregroundStyle(row?.stateTint ?? .gray)
                        .font(.system(size: 10))
                }
                if row?.work == true && row?.leave != true {
                    Text(row?.hours ?? "")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary).lineLimit(2).minimumScaleFactor(0.75)
                    if let place = row?.place, !place.isEmpty {
                        Text(place).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if let rest = row?.rest, !rest.isEmpty {
                        Text("休 \(rest)").font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                    }
                } else {
                    Text(closingStatus(row)).font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary).lineLimit(2)
                    if let state = row?.approvalDescription, !state.isEmpty {
                        Text(state).font(.system(size: 9)).foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 93, maxHeight: 93, alignment: .topLeading)
            .padding(6)
            .background(closingColor(row), in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11)
                .strokeBorder(key == todayKey ? Color.accentColor : .clear, lineWidth: 1.4))
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: 0.55) { previewDate = key }
        .accessibilityLabel("\(day)日 \(closingStatus(row)) \(row?.hours ?? "")")
        .accessibilityHint("長押しで勤務記録をプレビュー")
    }
    private var todayKey:String {
        let c=Calendar.current.dateComponents([.year,.month,.day],from:Date())
        return String(format:"%04d-%02d-%02d",c.year ?? 0,c.month ?? 0,c.day ?? 0)
    }
}

// Low-profile month grid for the upper leaf of the tabletop Duo pose.
// Unlike the expanded month grid, every day fits into a touch-friendly
// compact row; day-to-record routing is preserved.
private struct NativeClosingTabletopCalendar: View {
    @ObservedObject var model: NativeNavigationModel
    @State private var previewDate: String?
    let month: ClosingMonthData
    private let weekdays = ["日","月","火","水","木","金","土"]
    private var weekCount: Int {
        (month.firstWeekday + month.days + 6) / 7
    }
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(0..<7, id: \.self) { weekday in
                    Text(weekdays[weekday])
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(weekday == 0 ? Color.red : weekday == 6 ? Color.blue : Color.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(0..<weekCount, id: \.self) { week in
                HStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { column in
                        let day = week * 7 + column - month.firstWeekday + 1
                        if (1...month.days).contains(day) {
                            let key = month.key(day)
                            let record = model.calendarRows[key]
                            Button { model.openCalendarDate(key) } label: {
                                VStack(spacing: 2) {
                                    Text("\(day)")
                                        .font(.caption.weight(.semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(record?.holiday.isEmpty == false ? Color.red : Color.primary)
                                    Image(systemName: record?.stateSymbol ?? "questionmark.circle")
                                        .font(.system(size: 9))
                                        .foregroundStyle(record?.stateTint ?? .gray)
                                        .frame(height: 11)
                                }
                                .frame(maxWidth: .infinity, minHeight: 29)
                                .background(closingColor(record), in: RoundedRectangle(cornerRadius: 7))
                            }
                            .buttonStyle(.plain)
                            .onLongPressGesture(minimumDuration: 0.55) { previewDate = key }
                            .accessibilityLabel("\(day)日 \(closingStatus(record))")
                        } else {
                            Color.clear.frame(maxWidth: .infinity, minHeight: 29)
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("closing-tabletop-mini-calendar")
        .sheet(isPresented: Binding(
            get: { previewDate != nil },
            set: { if !$0 { previewDate = nil } }
        )) {
            NativeCalendarDayPreview(date: previewDate ?? "",
                                     record: model.calendarRows[previewDate ?? ""])
                .presentationDetents([.medium])
        }
    }
}

struct NativeClosingScreen: View {
    @ObservedObject var model: NativeNavigationModel
    @State private var confirmCloseApplication = false
    private var canApplyClosing: Bool {
        model.nativeCanCloseApply && !model.navigationInProgress &&
        !model.dashboardLoading && !model.nativeSubmissionInFlight
    }
    private var closeSubmitControls: some View {
        HStack(spacing: 8) {
            Button { confirmCloseApplication = true } label: {
                Label("締め申請", systemImage: "checkmark.seal")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(!canApplyClosing)
            .accessibilityIdentifier("closing-native-apply")
            Button { model.showOfficial = true } label: {
                Label("公式画面", systemImage: "arrow.up.right")
            }
            .buttonStyle(.bordered).controlSize(.small)
        }
    }
    private var closeApplicationNotice: some View {
        VStack(alignment: .leading, spacing: 5) {
            if !model.nativeCloseApplyPeriod.isEmpty {
                Text("申請対象：\(model.nativeCloseApplyPeriod)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("締め申請は公式画面で表示中の締め期間が対象です。月間集計全体とは限りません。")
                .font(.caption2).foregroundStyle(.secondary)
            if !model.nativeSubmissionMessage.isEmpty {
                Label(model.nativeSubmissionMessage, systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func mins(_ m:Int) -> String { "\(m / 60)時間\(String(format:"%02d",m % 60))分" }
    private var leaveCount: Int? {
        let rows = model.calendarRows.values.filter {
            $0.date.hasPrefix(model.calendarMonth + "-") && $0.known
        }
        return rows.isEmpty ? nil : rows.filter(\.leave).count
    }
    private func summaryTile(_ title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: icon)
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 13))
    }
    private var closingHeading: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("締め申請").font(.largeTitle.bold())
                if model.calendarMonth.count == 7 {
                    Text(ClosingMonthData(model.calendarMonth).title)
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            closeSubmitControls
        }
    }
    private func closingSummary(columns: Int) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8),
                                                         count: columns), spacing: 8) {
                            summaryTile("出勤", value: (model.summary["worked"] as? Int).map { "\($0)日" } ?? "—",
                                        icon: "calendar.badge.checkmark")
                                .accessibilityIdentifier("closing-summary-worked")
                            summaryTile("年休", value: leaveCount.map { "\($0)日" } ?? "—", icon: "sun.max")
                                .accessibilityIdentifier("closing-summary-leave")
                            summaryTile("実労働", value: (model.summary["minutes"] as? Int).map(mins) ?? "—",
                                        icon: "clock")
                                .accessibilityIdentifier("closing-summary-work-minutes")
                            summaryTile("残業", value: (model.summary["overtimeMinutes"] as? Int).map(mins) ?? "—",
                                        icon: "moon.stars")
                                .accessibilityIdentifier("closing-summary-overtime")
                        }
                        .accessibilityIdentifier("closing-monthly-overview")
    }
    private func closingCalendar(month: ClosingMonthData) -> some View {
        NativeSurface(title: "月間カレンダー") {
            HStack {
                Text("長押し：プレビュー / タップ：その日の勤怠")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button { model.nativeAnalysisOpen = true } label: {
                    Label("分析", systemImage: "chart.bar.xaxis")
                }
                .font(.caption)
            }
            NativeClosingMonthCalendar(model:model,month:month)
        }
    }
    private func closingRecords(month: ClosingMonthData) -> some View {
        NativeSurface(title: "勤務記録") {
            NativeClosingList(model:model,month:month)
        }
    }
    private var closingUnavailable: some View {
        VStack(spacing: 12) {
            ContentUnavailableView("勤務記録を読み込めませんでした",
                systemImage: "calendar.badge.exclamationmark",
                description: Text("締め申請画面の読み込み後に表示されます"))
            Button("申請・履歴へ") { model.showOfficial = true }
                .buttonStyle(.borderedProminent)
        }
    }
    private func closingOverviewPane(month: ClosingMonthData) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                closingHeading
                NativeSyncStatusBanner(model: model)
                closeApplicationNotice
                closingSummary(columns: 2)
                closingRecords(month: month)
            }
            .padding(16).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("closing-fold-overview-pane")
    }
    private func closingCalendarPane(month: ClosingMonthData) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                closingCalendar(month: month)
            }
            .padding(16).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("closing-fold-calendar-pane")
    }
    private func tabletopClosingDashboard(month: ClosingMonthData, width: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("締め申請")
                        .font(.headline)
                    Text(month.title)
                        .font(.subheadline).foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Label("月間", systemImage: "calendar")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                closingSummary(columns: width >= 600 ? 4 : 2)
                closeApplicationNotice
                NativeSyncStatusBanner(model: model)
                NativeClosingTabletopCalendar(model: model, month: month)
                    .padding(12)
                    .background(Color(uiColor: .secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: 750).frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .accessibilityIdentifier("closing-tabletop-dashboard")
    }
    private func tabletopClosingRecords(month: ClosingMonthData) -> some View {
        VStack(spacing: 0) {
            HStack {
                Label("日別の勤務記録", systemImage: "list.bullet.rectangle")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("タップして確認")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            Divider()
            ScrollView {
                NativeClosingList(model:model,month:month)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
            Divider()
            HStack(spacing: 10) {
                Button { confirmCloseApplication = true } label: {
                    Label("締め申請する", systemImage: "checkmark.seal")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canApplyClosing)
                .accessibilityIdentifier("tabletop-closing-native-apply")
                Button { model.showOfficial = true } label: {
                    Label("公式履歴", systemImage: "arrow.up.right")
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.regular)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .accessibilityIdentifier("tabletop-closing-sticky-action")
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .accessibilityIdentifier("closing-tabletop-records")
    }
    var body: some View {
        GeometryReader { proxy in
            let expanded = proxy.size.width >= 690
            let fold = duoDivisionFrame(in: proxy)
            if model.calendarMonth.count == 7, let fold,
               fold.height > fold.width,
               fold.minX >= 320, proxy.size.width - fold.maxX >= 320 {
                let month = ClosingMonthData(model.calendarMonth)
                HStack(spacing: 0) {
                    closingOverviewPane(month: month)
                        .frame(width: max(0, fold.minX))
                    Color.clear.frame(width: max(0, fold.width))
                    closingCalendarPane(month: month)
                        .frame(width: max(0, proxy.size.width - fold.maxX))
                }
                .accessibilityIdentifier("closing-fold-book")
            } else if model.calendarMonth.count == 7, let fold,
                      fold.width >= fold.height,
                      fold.minY >= 145, proxy.size.height - fold.maxY >= 145 {
                let month = ClosingMonthData(model.calendarMonth)
                VStack(spacing: 0) {
                    tabletopClosingDashboard(month: month, width: proxy.size.width)
                        .frame(height: max(0, fold.minY))
                    Color.clear.frame(height: max(0, fold.height))
                    tabletopClosingRecords(month: month)
                        .frame(height: max(0, proxy.size.height - fold.maxY))
                }
                .accessibilityIdentifier("closing-fold-tabletop")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 15) {
                        closingHeading
                        NativeSyncStatusBanner(model: model)
                        closeApplicationNotice
                        if model.calendarMonth.count == 7 {
                            let month = ClosingMonthData(model.calendarMonth)
                            closingSummary(columns: expanded ? 4 : 2)
                            if expanded {
                                closingCalendar(month: month)
                            } else {
                                closingRecords(month: month)
                            }
                        } else {
                            closingUnavailable
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: expanded ? 1220 : 640)
                    .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier(expanded ? "closing-inner-mode" : "closing-outer-mode")
            }
        }
        // Fold/unfold must not discard the selected month or reset the screen.
        .accessibilityIdentifier("closing-responsive")
        .id("closing-month-\(model.calendarMonth)")
        .alert("締め申請を送信しますか？", isPresented: $confirmCloseApplication) {
            Button("キャンセル", role: .cancel) {}
            Button("締め申請する") { model.nativeSubmit("close") }
        } message: {
            Text("対象：\(model.nativeCloseApplyPeriod)\n公式e-staffingで現在表示されている締め期間の申請です。表示中の月全体ではありません。送信後は申請結果を確認してください。")
        }
    }
}

// First-run walkthrough is SwiftUI-only; it never sends credentials or
// attendance edits. All setup values are ordinary on-device preferences.
struct NativeFirstRunGuide: View {
    @AppStorage("etc-duo-account.companyID") private var savedCompanyID = "pasona"
    @AppStorage("etc-duo-v33.shift.netMinutes") private var shiftNetMinutes = 450
    @AppStorage("etc-duo-v33.shift.breakMinutes") private var plannedBreakMinutes = 60
    @AppStorage("etc-duo-recovery.autoSignIn") private var autoRecovery = true
    @State private var page = 0
    @State private var companyDraft = ""
    let onComplete: () -> Void

    private let steps = ["ようこそ", "使い方", "初期設定"]
    private var companyValid: Bool {
        let trimmed = companyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 128
    }

    private func complete() {
        guard companyValid else { return }
        savedCompanyID = companyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        onComplete()
    }

    private func feature(_ title: String, detail: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 45, height: 45)
                .background(Color.accentColor.opacity(0.1),
                            in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 17))
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "checkmark.rectangle.stack.fill")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
                .frame(width: 88, height: 88)
                .background(Color.accentColor.opacity(0.1),
                            in: RoundedRectangle(cornerRadius: 25))
                .padding(.bottom, 6)
            Text("勤怠管理を、もっと簡単に。")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            Text("WebTimeCardへようこそ！使い方と初期設定を3ステップでご案内します。")
                .font(.body).foregroundStyle(.secondary)
            feature("日々勤怠", detail: "開始・終了・休憩を、使いやすいネイティブ画面で入力します。",
                    icon: "clock")
            feature("iPhone Duo", detail: "閉じた状態・本型・卓上の半開きでも、画面に合わせて表示します。",
                    icon: "rectangle.split.2x1")
        }
        .accessibilityIdentifier("onboarding-welcome")
    }

    private var walkthrough: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("毎日の使い方")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text("必要な操作が分かれば、あとはいつもどおり。")
                .foregroundStyle(.secondary)
            feature("① 日々勤怠", detail: "日付を選び、開始・終了時刻と実際の休憩時間を入力。入力内容は公式フォームへ反映されます。",
                    icon: "calendar")
            feature("② 日々申請", detail: "内容を確認してから申請。承認済みの記録は閲覧専用になります。",
                    icon: "checkmark.seal")
            feature("③ 締め申請", detail: "勤務記録や月間カレンダーを確認し、対象期間を確かめて申請します。",
                    icon: "calendar.badge.checkmark")
            Label("休憩の目安は案内のみ。実際の休憩時間を勝手に入力しません。",
                  systemImage: "info.circle")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.top, 7)
        }
        .accessibilityIdentifier("onboarding-howto")
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("最初の設定")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text("いつでも設定画面から変更できます。")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12) {
                Label("企業ID", systemImage: "building.2.crop.circle")
                    .font(.headline)
                TextField("企業IDを入力", text: $companyDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.organizationName)
                    .submitLabel(.done)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("onboarding-company-id")
                if !companyValid {
                    Label("企業IDは1〜128文字で入力してください。", systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.orange)
                } else {
                    Text("例：pasona。お勤め先から指定された企業IDを入力してください。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 17))
            VStack(alignment: .leading, spacing: 14) {
                Label("勤務時間の目安", systemImage: "timer")
                    .font(.headline)
                Stepper(value: $shiftNetMinutes, in: 60...900, step: 15) {
                    LabeledContent("目標の実働時間", value: "\(shiftNetMinutes / 60)時間\(shiftNetMinutes % 60 == 0 ? "" : "\(shiftNetMinutes % 60)分")")
                }
                Stepper(value: $plannedBreakMinutes, in: 0...240, step: 15) {
                    LabeledContent("標準休憩", value: "\(plannedBreakMinutes)分")
                }
                Text("退勤予定の計算用です。勤務記録の開始・終了・休憩欄へ自動入力しません。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 17))
            VStack(alignment: .leading, spacing: 7) {
                Toggle("接続エラー時に自動再ログインを試みる", isOn: $autoRecovery)
                Text("ログイン情報をKeychainに保存した場合のみ利用できます。iPhoneのロック解除中に1回試行し、勤怠の保存・申請を再送信することはありません。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 17))
            Label("次のログイン画面でユーザーIDとパスワードを入力します。保存する場合、iPhoneのKeychainで保護されます。",
                  systemImage: "lock.shield")
                .font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("onboarding-setup")
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text("はじめてのWebTimeCard")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(page + 1) / \(steps.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 12)
                HStack(spacing: 7) {
                    ForEach(0..<steps.count, id: \.self) { index in
                        Capsule().fill(index <= page ? Color.accentColor :
                                       Color(uiColor: .tertiarySystemFill))
                            .frame(height: 5)
                    }
                }
                .padding(.horizontal, 22).padding(.bottom, 8)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if page == 0 { intro }
                        else if page == 1 { walkthrough }
                        else { setup }
                    }
                    .padding(.horizontal, 22).padding(.vertical, 18)
                    .frame(maxWidth: 620)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                Divider()
                HStack(spacing: 12) {
                    if page > 0 {
                        Button("戻る") { page -= 1 }
                            .buttonStyle(.bordered).controlSize(.large)
                    } else {
                        Button("スキップ") { complete() }
                            .buttonStyle(.bordered).controlSize(.large)
                            .disabled(!companyValid)
                    }
                    Spacer(minLength: 0)
                    Button(page == 2 ? "設定を保存してログインへ" : "次へ") {
                        if page < 2 { page += 1 } else { complete() }
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(page == 2 && !companyValid)
                    .accessibilityIdentifier("onboarding-next")
                }
                .padding(.horizontal, 22).padding(.vertical, 14)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemGroupedBackground))
            .onAppear {
                companyDraft = savedCompanyID
            }
        }
        .accessibilityIdentifier("native-onboarding-guide")
    }
}

struct NativePreferencesScreen: View {
    @ObservedObject var model: NativeNavigationModel
    @AppStorage("etc-duo-v296-salary.enabled") private var showSalary = false
    @AppStorage("etc-duo-v296-salary.hourlyJPY") private var rate = 0
    @AppStorage("etc-duo-v296-salary.premium") private var premium = true
    @AppStorage("etc-duo-v33.shift.netMinutes") private var shiftNetMinutes = 450
    @AppStorage("etc-duo-v33.shift.breakMinutes") private var plannedBreakMinutes = 60
    @AppStorage("etc-duo-reminder-weekday.enabled") private var weekdayEnabled = false
    @AppStorage("etc-duo-reminder-weekday.hour") private var weekdayHour = 18
    @AppStorage("etc-duo-reminder-weekday.minute") private var weekdayMinute = 30
    @AppStorage("etc-duo-reminder-close.enabled") private var closeEnabled = false
    @AppStorage("etc-duo-reminder-close.hour") private var closeHour = 17
    @AppStorage("etc-duo-reminder-close.minute") private var closeMinute = 0
    @AppStorage("etc-duo-reminder-close.day") private var closeDay = 15
    @AppStorage("etc-duo-recovery.autoSignIn") private var autoRecovery = true
    @AppStorage("etc-duo.templates.custom-v1") private var customTemplatesJSON = "[]"
    @AppStorage("etc-duo.tips.break-v1") private var breakTipSeen = false
    @AppStorage("etc-duo.tips.templates-v1") private var templateTipSeen = false
    @AppStorage("etc-duo-account.companyID") private var companyID = "pasona"
    @State private var confirmDelete = false
    @State private var credentialsSaved = CredentialVault.exists()
    @State private var deletedMessage = ""

    private func durationText(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h)時間" : "\(h)時間\(m)分"
    }
    private func saveReminder(_ kind: String) {
        let workday = kind == "weekday"
        model.updateNativeReminder(kind: kind,
            enabled: workday ? weekdayEnabled : closeEnabled,
            hour: workday ? weekdayHour : closeHour,
            minute: workday ? weekdayMinute : closeMinute,
            day: workday ? 15 : closeDay)
    }
    private func timeBinding(_ kind: String) -> Binding<Date> {
        Binding(get: {
            let hour = kind == "weekday" ? weekdayHour : closeHour
            let minute = kind == "weekday" ? weekdayMinute : closeMinute
            return Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 29,
                hour: hour, minute: minute)) ?? Date()
        }, set: { newTime in
            let values = Calendar.current.dateComponents([.hour, .minute], from: newTime)
            if kind == "weekday" {
                weekdayHour = values.hour ?? 18
                weekdayMinute = values.minute ?? 30
            } else {
                closeHour = values.hour ?? 17
                closeMinute = values.minute ?? 0
            }
            saveReminder(kind)
        })
    }

    var body: some View {
        Form {
            Section {
                TextField("企業ID", text: $companyID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.organizationName)
                    .accessibilityIdentifier("settings-company-id")
                Button {
                    model.showOnboarding = true
                } label: {
                    Label("使い方と初期設定をもう一度見る", systemImage: "book.closed")
                }
                if credentialsSaved {
                    Text("保存済みのFace IDログイン情報は変更されません。新しい企業IDを使うときは、ログイン画面で再ログインしてアカウント情報を保存してください。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: { Text("アカウント・はじめの設定") }
              footer: { Text("企業IDはこのiPhoneに記憶され、次回のログイン画面にも自動で表示されます。") }
            Section("外観") {
                Picker("表示モード", selection: Binding(
                    get: { model.websiteTheme },
                    set: { model.changeNativeTheme($0) })) {
                    Text("自動").tag("system")
                    Text("ライト").tag("light")
                    Text("ダーク").tag("dark")
                }.pickerStyle(.segmented)
            }
            Section {
                Toggle("給与目安を表示", isOn: $showSalary)
                HStack {
                    Text("時給")
                    Spacer()
                    TextField("円", value: $rate, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 130)
                    Text("円").foregroundStyle(.secondary)
                }
                Toggle("1日8時間超の25%割増", isOn: $premium)
            } header: { Text("給与計算") }
              footer: { Text("給与・残業代は税引前の目安です。") }
            Section {
                Stepper(value: $shiftNetMinutes, in: 60...900, step: 15) {
                    LabeledContent("目標の実働時間", value: durationText(shiftNetMinutes))
                }
                Stepper(value: $plannedBreakMinutes, in: 0...240, step: 15) {
                    LabeledContent("標準の休憩時間", value: "\(plannedBreakMinutes)分")
                }
            } header: { Text("勤務時間の目安") }
              footer: { Text("退勤予定の計算専用。勤務記録や自動保存には反映しません。") }
            Section {
                Toggle("平日の勤怠確認", isOn: Binding(
                    get: { weekdayEnabled }, set: { weekdayEnabled = $0; saveReminder("weekday") }))
                if weekdayEnabled {
                    DatePicker("通知時刻", selection: timeBinding("weekday"), displayedComponents: .hourAndMinute)
                }
                Toggle("毎月の締め確認", isOn: Binding(
                    get: { closeEnabled }, set: { closeEnabled = $0; saveReminder("close") }))
                if closeEnabled {
                    DatePicker("通知時刻", selection: timeBinding("close"), displayedComponents: .hourAndMinute)
                    Picker("確認日", selection: $closeDay) {
                        ForEach(1...28, id: \.self) { day in Text("毎月\(day)日").tag(day) }
                    }.onChange(of: closeDay) { _, _ in saveReminder("close") }
                }
                if !model.nativeReminderMessage.isEmpty {
                    Text(model.nativeReminderMessage).font(.caption).foregroundStyle(.secondary)
                }
            } header: { Text("通知") }
              footer: { Text("通知は確認のためのリマインダーです。勤務記録や申請状態を自動確認しません。") }
            Section("iPhone Duo") {
                Toggle("日々勤怠にカレンダーを並べる", isOn: $model.sidebarEnabled)
                Text("画面を開いたときはカレンダー・勤務入力・詳細を並べ、卓上時は上にサマリー、下に操作をまとめます。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button {
                    model.nativeSettingsOpen = false
                    model.nativeAnalysisOpen = true
                } label: {
                    Label("勤務分析を開く", systemImage: "chart.bar.xaxis")
                }
                Button {
                    breakTipSeen = false
                    templateTipSeen = false
                } label: {
                    Label("操作ヒントをもう一度見る", systemImage: "lightbulb")
                }
                Button("自分で登録した勤務パターンを消去", role: .destructive) {
                    customTemplatesJSON = "[]"
                }
                .disabled(customTemplatesJSON == "[]")
            } header: { Text("便利な機能") }
              footer: { Text("勤務テンプレートはこのiPhoneのみに保存します。消去しても公式の勤怠記録は変わりません。") }
            Section {
                Toggle("エラー時にFace IDなしで再ログイン", isOn: $autoRecovery)
                    .disabled(!credentialsSaved)
                if !credentialsSaved {
                    Text("自動再ログインにはログイン情報の保存が必要です。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: { Text("セッションの復旧") }
              footer: { Text("許可されていない操作の画面が表示されたときのみ、保存済みのKeychain情報を使って公式ログインを1回試みます。iPhoneのロック解除が必要です。直前の申請や保存操作は再送信しません。") }
            Section {
                LabeledContent("ログイン情報", value: credentialsSaved ? "このiPhoneに保存済み" : "未保存")
                if credentialsSaved {
                    Button("保存済みログイン情報を削除", role: .destructive) { confirmDelete = true }
                }
                if !deletedMessage.isEmpty {Text(deletedMessage).font(.caption).foregroundStyle(.secondary)}
            } header: { Text("アカウントとプライバシー") }
              footer: { Text("保存したアカウント情報はiPhoneのKeychainで保護されます。") }
            Section {
                LabeledContent("アプリバージョン", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                Text("WebTimeCard · 勤怠管理").foregroundStyle(.secondary)
            } header: { Text("アプリ情報") }
        }
        .navigationTitle("設定")
        .alert("保存済みのログイン情報を削除しますか？", isPresented: $confirmDelete) {
            Button("キャンセル", role: .cancel) {}
            Button("削除", role: .destructive) {
                let deleted = CredentialVault.delete()
                credentialsSaved = CredentialVault.exists()
                deletedMessage = deleted ? "このiPhoneのログイン情報を削除しました" : "削除できませんでした"
            }
        } message: { Text("次回からログインIDとパスワードの入力が必要になります。") }
        .onAppear { credentialsSaved = CredentialVault.exists() }
        .onChange(of: showSalary) { _, _ in model.publishNativeSalary() }
        .onChange(of: rate) { _, _ in model.publishNativeSalary() }
        .onChange(of: premium) { _, _ in model.publishNativeSalary() }
    }
}

struct NativeLoginScreen: View {
    @ObservedObject var model:NativeNavigationModel
    @AppStorage("etc-duo-account.companyID") private var company="pasona"
    @State private var user=""
    @State private var password=""
    @State private var remember=true
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                Label("WebTimeCard",systemImage:"checkmark.shield.fill")
                    .font(.headline).foregroundStyle(.tint)
                Text("ログイン").font(.largeTitle.bold())
                NativeSurface(title:"アカウント情報") {
                    TextField("企業ID",text:$company)
                        .textContentType(.organizationName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("login-company-id")
                    Text("企業IDは自動的に記憶されます。設定画面からも変更できます。")
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("ユーザーID",text:$user)
                        .textContentType(.username).textFieldStyle(.roundedBorder)
                    SecureField("パスワード",text:$password)
                        .textContentType(.password).textFieldStyle(.roundedBorder)
                    Toggle("ログイン情報をこのiPhoneに保存",isOn:$remember).font(.caption)
                    Button {
                        model.nativeLogin(["company":company,"user":user,"password":password,"remember":remember])
                    } label: {
                        Text("ログイン").frame(maxWidth:.infinity)
                    }.buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(company.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                  company.count > 128 || user.isEmpty || password.isEmpty)
                    Button {model.faceIDLogin()} label: {
                        Label("Face ID / 端末認証でログイン",systemImage:"faceid")
                    }.buttonStyle(.bordered)
                }
                HStack(spacing: 16) {
                    Button {
                        model.showOnboarding = true
                    } label: {
                        Label("使い方と初期設定", systemImage: "book.closed")
                    }
                    Button("別のログイン方法") { model.showOfficial = true }
                }
                .font(.caption)
            }.padding(22).frame(maxWidth:530).frame(maxWidth:.infinity)
        }
    }
}
