import SwiftUI
import RestFlowCore

struct OperatingHoursView: View {
    @Binding var schedule: OperatingSchedule
    let language: AppLanguage
    @StateObject private var state = HoursEditorState()
    private func t(_ zh: String, _ en: String) -> String { language.text(zh, en) }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(t("按时段运行", "Use operating hours"), isOn: $schedule.enabled)
                if schedule.enabled {
                    HStack(spacing: 6) {
                        ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { day in
                            let selected = schedule.weekdays.contains(day)
                            Button(dayName(day)) {
                                var updated = schedule
                                if selected { updated.weekdays.removeAll { $0 == day } }
                                else { updated.weekdays.append(day); updated.weekdays.sort() }
                                schedule = updated
                            }
                            .buttonStyle(.bordered)
                            .tint(selected ? .green : .gray)
                            .opacity(selected ? 1 : 0.55)
                            .disabled(selected && schedule.weekdays.count == 1)
                            .accessibilityValue(selected ? t("已选", "Selected") : t("未选", "Not selected"))
                        }
                    }
                    HStack {
                        Text(t("上午", "Morning")).frame(width: 95, alignment: .leading)
                        timePicker(t("上午开始", "Morning starts"), key: \.morningStartMinute)
                        Text("–")
                        timePicker(t("上午结束", "Morning ends"), key: \.morningEndMinute)
                        Spacer()
                    }
                    HStack {
                        Toggle(t("下午", "Afternoon"), isOn: Binding(get: { schedule.afternoonEnabled }, set: { value in
                            var updated = schedule; updated.afternoonEnabled = value; apply(updated)
                        })).frame(width: 95, alignment: .leading)
                        timePicker(t("下午开始", "Afternoon starts"), key: \.afternoonStartMinute)
                        Text("–")
                        timePicker(t("下午结束", "Afternoon ends"), key: \.afternoonEndMinute)
                        Spacer()
                    }
                    if let error = state.error { Text(error).font(.caption).foregroundStyle(.red) }
                    Text(t("午休及其他时段自动暂停提醒和统计。", "Reminders and statistics pause during lunch and outside these hours."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding(10)
        } label: { Text(t("运行时段", "Operating hours")) }
    }

    private func dayName(_ day: Int) -> String {
        let zh = ["日", "一", "二", "三", "四", "五", "六"]
        let en = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return language == .english ? en[day - 1] : "周" + zh[day - 1]
    }

    private func timePicker(_ title: String, key: WritableKeyPath<OperatingSchedule, Int>) -> some View {
        DatePicker(title, selection: Binding(get: {
            let minute = schedule[keyPath: key]
            return Calendar.current.date(bySettingHour: minute / 60 % 24, minute: minute % 60, second: 0, of: Date())!
        }, set: { date in
            var updated = schedule
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            updated[keyPath: key] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            apply(updated)
        }), displayedComponents: [.hourAndMinute])
        .labelsHidden().accessibilityLabel(title).frame(width: 105)
    }

    private func apply(_ updated: OperatingSchedule) {
        do { try updated.validate(); schedule = updated; state.error = nil }
        catch { state.error = t("开始需早于结束，两个时段不能重叠。", "Start must precede end; periods cannot overlap.") }
    }
}

private final class HoursEditorState: ObservableObject { @Published var error: String? }
