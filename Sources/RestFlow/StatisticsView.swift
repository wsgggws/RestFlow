import SwiftUI
import Charts
import RestFlowCore

struct StatisticsView: View {
    @ObservedObject var model: AppModel
    @StateObject private var selection = StatisticsSelection()
    private var period: Int { selection.period }
    private func t(_ zh: String, _ en: String) -> String { model.text(zh, en) }
    private var days: [DailyStatistics] {
        let recorded = Dictionary(uniqueKeysWithValues: model.statisticsDays.map { ($0.id, $0) })
        return (0..<period).reversed().map { offset in
            let date = Calendar.current.date(byAdding: .day, value: -offset, to: Date())!
            let key = StatisticsStore.dayKey(date)
            return recorded[key] ?? DailyStatistics(id: key)
        }
    }
    private var today: DailyStatistics { days.last ?? DailyStatistics(id: StatisticsStore.dayKey(Date())) }
    private var away: Double { days.reduce(0) { $0 + $1.awaySeconds } }
    private var focus: Double { days.reduce(0) { $0 + $1.focusSeconds } }
    private var rest: Double { days.reduce(0) { $0 + $1.restSeconds } }
    private var completed: Int { days.reduce(0) { $0 + $1.completedBreaks } }
    private var insufficient: Int { days.reduce(0) { $0 + $1.insufficientBreaks } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(t("今天计时 \(duration(today.focusSeconds))，休息 \(duration(today.restSeconds))；完成 \(today.completedBreaks) 次，提前结束 \(today.insufficientBreaks) 次。",
                       "Today: \(duration(today.focusSeconds)) on the timer, \(duration(today.restSeconds)) resting; \(today.completedBreaks) completed, \(today.insufficientBreaks) ended early."))
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
                Picker(t("统计范围", "Range"), selection: $selection.period) {
                    Text(t("最近一周", "Last 7 days")).tag(7)
                    Text(t("最近一个月", "Last 30 days")).tag(30)
                }.pickerStyle(.segmented)
                HStack(spacing: 24) {
                    summary(t("计时", "Timer"), value: duration(focus))
                    summary(t("休息", "Rest"), value: duration(rest))
                    Spacer()
                    summary(t("完成休息", "Completed"), value: "\(completed)")
                    summary(t("提前结束", "Ended early"), value: "\(insufficient)")
                }
                Chart(days) { day in
                    BarMark(x: .value(t("日期", "Date"), day.id),
                            y: .value(t("小时", "Hours"), day.focusSeconds / 3600))
                        .foregroundStyle(by: .value(t("阶段", "Phase"), t("计时", "Timer")))
                    BarMark(x: .value(t("日期", "Date"), day.id),
                            y: .value(t("小时", "Hours"), day.restSeconds / 3600))
                        .foregroundStyle(by: .value(t("阶段", "Phase"), t("休息", "Rest")))
                }
                .chartForegroundStyleScale(domain: [t("计时", "Timer"), t("休息", "Rest")], range: [Color(red: 0.28, green: 0.53, blue: 0.43), Color(red: 0.65, green: 0.77, blue: 0.69)])
                .chartXAxis {
                    AxisMarks(values: days.enumerated().filter { period == 7 || $0.offset % 5 == 0 || $0.offset == period - 1 }.map { $0.element.id }) { value in
                        AxisValueLabel {
                            if let id = value.as(String.self) { Text(String(id.suffix(5))) }
                        }
                    }
                }
                .chartYScale(domain: 0...max(0.1, days.map { ($0.focusSeconds + $0.restSeconds) / 3600 }.max() ?? 1))
                .chartYAxisLabel(t("小时", "Hours"))
                .frame(height: 170)
                Text(t("离开 \(duration(away))。计时代表专注计时器运行时长。暂停、睡眠、预览及非运行时段不计入计时与休息。",
                       "Away: \(duration(away)). Timer time means the focus timer was running. Pauses, sleep, previews and time outside operating hours are excluded."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if focus + rest == 0 {
                    Text(t("还没有记录，运行一段时间后会在这里显示。", "No activity yet. Your timer activity will appear here."))
                        .foregroundStyle(.secondary).padding(.vertical, 8)
                }
                if let error = model.statisticsError {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.caption).textSelection(.enabled)
                }
                DisclosureGroup(t("每日明细", "Daily details")) {
                HStack {
                    Text(t("日期", "Date"))
                    Spacer()
                    Text(t("计时 / 休息 / 离开 / 提前结束", "Timer / Rest / Away / Ended early"))
                }.font(.caption).foregroundStyle(.secondary)
                ForEach(days.reversed()) { day in
                    HStack {
                        Text(day.id).monospacedDigit()
                        Spacer()
                        Text("\(duration(day.focusSeconds)) / \(duration(day.restSeconds)) / \(duration(day.awaySeconds)) / \(day.insufficientBreaks)").monospacedDigit()
                    }.font(.caption)
                    .accessibilityElement(children: .combine)
                }
                }
            }.padding(12)
        }
    }

    private func summary(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 19, weight: .medium, design: .rounded)).monospacedDigit()
        }
    }

    private func duration(_ seconds: Double) -> String {
        let total = Int(seconds)
        if total < 60 { return t("\(total)秒", "\(total)s") }
        let minutes = total / 60
        return minutes < 60 ? t("\(minutes)分", "\(minutes)m") : t("\(minutes / 60)时\(minutes % 60)分", "\(minutes / 60)h \(minutes % 60)m")
    }
}

private final class StatisticsSelection: ObservableObject { @Published var period = 7 }
