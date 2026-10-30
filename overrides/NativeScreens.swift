import SwiftUI
import WebKit

// Native front-end.  The single official WKWebView remains mounted behind it;
// the bridge sends only explicitly allowed UI field values and choice indices.
struct NativeApplicationScreen: View {
    @ObservedObject var model: NativeNavigationModel
    var body: some View {
        Group {
            if model.nativeSettingsOpen {
                NativePreferencesScreen(model:model)
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

struct NativeHomeScreen: View {
    @ObservedObject var model: NativeNavigationModel
    @AppStorage("etc-duo-v296-salary.enabled") private var salaryEnabled = false
    @AppStorage("etc-duo-v296-salary.hourlyJPY") private var rate = 0
    @AppStorage("etc-duo-v296-salary.premium") private var premium = true
    @State private var salaryHidden = false

    private var salaryValid: Bool {
        guard let worked=model.summary["worked"] as? Int,
              let valid=model.summary["valid"] as? Int else{return false}
        return valid == worked && model.summary["minutes"] is Int && model.summary["overtimeMinutes"] is Int
    }
    private var payroll: (Int,Int,Int) {
        let mins=model.summary["minutes"] as? Int ?? 0
        let overtime=model.summary["overtimeMinutes"] as? Int ?? 0
        let hourly=Double(rate)
        let base=Double(mins)*hourly/60.0
        let uplift=premium ? Double(overtime)*hourly/60.0*0.25 : 0
        let overtimePay=Double(overtime)*hourly/60.0+uplift
        return (Int((base+uplift).rounded()),Int(overtimePay.rounded()),Int(uplift.rounded()))
    }
    private func currency(_ amount:Int)->String {amount.formatted(.currency(code:"JPY").precision(.fractionLength(0)))}
    private func readable(_ number:Int)->String { salaryHidden ? "•••••" : currency(number) }
    private func minutes(_ number:Int)->String {"\(number/60)時間\(String(format:"%02d",number%60))分"}
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                Text("ホーム").font(.largeTitle.bold())
                if let start=model.summary["start"] as? String,let end=model.summary["end"] as? String {
                    Text("\(start) 〜 \(end)").font(.caption).foregroundStyle(.secondary)
                }
                NativeSurface(title:"勤務ダッシュボード") {
                    LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:16) {
                        metric("勤務日数",value:(model.summary["worked"] as? Int).map{"\($0)日"} ?? "—",icon:"calendar")
                        metric("記録なし",value:(model.summary["empty"] as? Int).map{"\($0)日"} ?? "—",icon:"calendar.badge.exclamationmark")
                        metric("実労働",value:salaryValid ? minutes(model.summary["minutes"] as? Int ?? 0) : "—",icon:"clock")
                        metric("残業",value:salaryValid ? minutes(model.summary["overtimeMinutes"] as? Int ?? 0) : "—",icon:"moon.stars")
                    }
                }
                if salaryEnabled && rate > 0 {
                    NativeSurface(title:"給与目安") {
                        HStack(alignment:.firstTextBaseline) {
                            VStack(alignment:.leading,spacing:6) {
                                Text(salaryValid ? readable(payroll.0) : "—").font(.system(.title,design:.rounded,weight:.bold))
                                Text("給与の概算").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { salaryHidden.toggle() } label: {
                                Image(systemName:salaryHidden ? "eye.slash" : "eye").font(.title3)
                            }.accessibilityLabel(salaryHidden ? "金額を表示" : "金額を隠す")
                        }
                        Divider()
                        HStack {Text("残業代");Spacer();Text(salaryValid ? readable(payroll.1) : "—").bold()}
                        HStack {Text("うち割増分");Spacer();Text(salaryValid ? readable(payroll.2) : "—").bold()}
                    }
                }
            }.padding(16).frame(maxWidth:750)
                .frame(maxWidth:.infinity)
        }
    }
    private func metric(_ title:String,value:String,icon:String)->some View {
        VStack(alignment:.leading,spacing:8) {
            Label(title,systemImage:icon).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(.title3,design:.rounded,weight:.semibold)).minimumScaleFactor(0.75).lineLimit(1)
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
}

struct NativeDailyScreen: View {
    @ObservedObject var model: NativeNavigationModel
    @State private var confirmDailyApplication = false
    @State private var tabletopDetailsExpanded = false
    // The forecast and the official break field share a single source of truth.
    @AppStorage("etc-duo-v33.shift.netMinutes") private var shiftNetMinutes = 450
    @AppStorage("etc-duo-v33.shift.breakMinutes") private var plannedBreakMinutes = 60
    private var previewRestMinutes: Int {
        enteredRestMinutes ?? plannedBreakMinutes
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
                            Text("実働\(duration(shiftNetMinutes)) + 休憩\(previewRestMinutes)分")
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
                            Label("休憩 \(previewRestMinutes)分",systemImage:"chevron.up.chevron.down")
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
        }
    }
    private var dailyWorkPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                dailyHeading
                dailyWorkCard
            }
            .padding(16).frame(maxWidth: 750).frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("daily-fold-work-pane")
    }
    private var dailyEditPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                dailyDetailsCard
                dailyActions
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
                    tabletopDailyMetric("休憩", value: "\(previewRestMinutes)分", icon: "cup.and.saucer")
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
                Text("変更は自動保存")
                    .font(.caption2).foregroundStyle(.secondary)
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
                    tabletopDailyDashboard.frame(height: max(0, fold.minY))
                    Color.clear.frame(height: max(0, fold.height))
                    tabletopDailyEditor.frame(height: max(0, proxy.size.height - fold.maxY))
                }
                .accessibilityIdentifier("daily-fold-tabletop")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 15) {
                        dailyHeading
                        dailyWorkCard
                        dailyDetailsCard
                        dailyActions
                    }
                    .padding(16).frame(maxWidth: 750).frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("daily-responsive-standard")
            }
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
            DatePicker("",selection:Binding(get:{timeValue(name)},set:{setTime(name,$0)}),displayedComponents:.hourAndMinute)
                .labelsHidden().datePickerStyle(.compact).frame(maxWidth:.infinity,alignment:.leading)
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
    if item.leave { return item.status.isEmpty ? "有給休暇" : item.status }
    if item.work { return item.status.isEmpty ? "勤務記録あり" : item.status }
    return item.holiday.isEmpty ? "記録なし" : item.holiday
}

private func closingColor(_ record: NativeCalendarRecord?) -> Color {
    guard let r=record, r.known else { return Color(uiColor:.tertiarySystemGroupedBackground) }
    if r.leave { return Color.purple.opacity(0.13) }
    if r.work { return Color.green.opacity(0.12) }
    return Color(uiColor:.secondarySystemGroupedBackground)
}

struct NativeClosingList: View {
    @ObservedObject var model: NativeNavigationModel
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
                        RoundedRectangle(cornerRadius:2)
                            .fill(row?.leave == true ? Color.purple : row?.work == true ? .green : .clear)
                            .frame(width:3)
                        VStack(alignment:.leading,spacing:5) {
                            Text(row?.work == true && !(row?.hours.isEmpty ?? true) ? row!.hours : closingStatus(row))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary).lineLimit(2)
                            let detail=[row?.place ?? "",(row?.rest.isEmpty == false ? "休憩 \(row!.rest)" : ""),
                                        (row?.work == true ? row?.status ?? "" : "")]
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
                }.buttonStyle(.plain)
                .accessibilityLabel("\(day)日 \(closingStatus(row)) \(row?.hours ?? "")")
            }
        }
        .accessibilityIdentifier("closing-outer-list")
    }
}

struct NativeClosingMonthCalendar: View {
    @ObservedObject var model: NativeNavigationModel
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
    }
    private func calendarDay(_ day: Int) -> some View {
        let key = month.key(day)
        let row = model.calendarRows[key]
        return Button { model.openCalendarDate(key) } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text("\(day)").font(.subheadline.weight(.bold))
                    .foregroundStyle(row?.holiday.isEmpty == false ? Color.red : Color.primary)
                if row?.work == true {
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
        .accessibilityLabel("\(day)日 \(closingStatus(row)) \(row?.hours ?? "")")
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
                                    Circle()
                                        .fill(record?.work == true ? Color.green :
                                              record?.leave == true ? Color.purple : Color.clear)
                                        .frame(width: 4, height: 4)
                                }
                                .frame(maxWidth: .infinity, minHeight: 29)
                                .background(closingColor(record), in: RoundedRectangle(cornerRadius: 7))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(day)日 \(closingStatus(record))")
                        } else {
                            Color.clear.frame(maxWidth: .infinity, minHeight: 29)
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("closing-tabletop-mini-calendar")
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
    private var leaveCount: Int {
        model.calendarRows.values.filter { $0.known && $0.leave }.count
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
                            summaryTile("年休", value: "\(leaveCount)日", icon: "sun.max")
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
            }
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
    @State private var company="pasona"
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
                        .textContentType(.organizationName).textFieldStyle(.roundedBorder)
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
                        .disabled(user.isEmpty || password.isEmpty)
                    Button {model.faceIDLogin()} label: {
                        Label("Face ID / 端末認証でログイン",systemImage:"faceid")
                    }.buttonStyle(.bordered)
                }
                Button("別のログイン方法") {model.showOfficial=true}
                    .font(.caption)
            }.padding(22).frame(maxWidth:530).frame(maxWidth:.infinity)
        }
    }
}
