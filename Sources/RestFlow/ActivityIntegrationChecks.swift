import Foundation
import RestFlowCore

@MainActor
enum ActivityIntegrationChecks {
    static func run() -> Int32 {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("restflow-activity-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        var settings = AppSettings()
        settings.workMinutes = 1; settings.shortBreakSeconds = 5; settings.longBreakMinutes = 1
        settings.soundEnabled = false; settings.prealertEnabled = false; settings.checkForUpdatesAutomatically = false
        var failures = 0
        func check(_ condition: Bool, _ label: String) {
            print("\(condition ? "PASS" : "FAIL") \(label)")
            if !condition { failures += 1 }
        }
        func date(_ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
            Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: hour, minute: minute, second: second))!
        }
        func folder(_ name: String) -> URL {
            let url = directory.appendingPathComponent(name)
            _ = try? ConfigurationStore(directory: url).load(orCreate: settings)
            return url
        }
        do {
            var mono: TimeInterval = 0, wall = date(9)
            let model = AppModel(directory: folder("actual"), wallClock: { wall }, clock: { mono })
            defer { model.stop() }
            func advance(_ seconds: Double) { mono += seconds; wall.addTimeInterval(seconds); model.refresh() }
            func day() -> DailyStatistics { model.statistics.days["2026-11-09"] ?? DailyStatistics(id: "2026-11-09") }
            advance(20)
            model.togglePause(); advance(120)
            check(day().focusSeconds == 20, "paused time is excluded from daily focus totals")
            model.togglePause(); advance(20)
            model.restNow()
            check(model.phase == .shortBreak && model.completedWorkSessions == 1, "rest now advances the first short-break cycle")
            advance(2)
            model.restNow()
            check(model.remaining == 3 && model.completedWorkSessions == 1, "rest now during a break preserves its countdown and cycle")
            model.endBreak()
            check(day().restSeconds == 2 && day().insufficientBreaks == 1 && day().completedBreaks == 0,
                  "Esc preserves actual rest seconds and marks the break incomplete")
            model.restNow()
            check(model.phase == .longBreak && model.completedWorkSessions == 0, "rest now chooses long rest at the cycle boundary")
            advance(65)
            check(day().focusSeconds == 40 && day().restSeconds == 62 && day().completedBreaks == 1,
                  "natural rest completion caps elapsed time at its deadline")
            let loaded = StatisticsStore(directory: model.configuration.directory)
            try loaded.load()
            check(loaded.days == model.statistics.days, "statistics persist independently of preference settings")
            model.willSleep()
            mono += 3600; wall.addTimeInterval(3600)
            model.didWake()
            check(day().focusSeconds == 40, "sleep and wake do not backfill focus time")
            wall.addTimeInterval(3600); model.refresh()
            check(day().focusSeconds == 40, "wall-clock correction does not invent elapsed time")
        } catch { check(false, "activity persistence: \(error)") }
        do {
            var mono: TimeInterval = 0, wall = date(11,59,50)
            let model = AppModel(directory: folder("lunch"), wallClock: { wall }, clock: { mono })
            defer { model.stop() }
            func advance(_ seconds: Double) { mono += seconds; wall.addTimeInterval(seconds); model.refresh() }
            advance(15)
            check(model.isOutsideOperatingHours && model.isPaused && model.remaining == 50,
                  "lunch freezes focus at the exact operating-hours boundary")
            check(model.statistics.days["2026-11-09"]?.focusSeconds == 10, "time after noon is excluded from daily totals")
            model.restNow()
            check(model.phase == .work && model.completedWorkSessions == 0, "rest now is inactive outside operating hours")
            advance(5395)
            check(!model.isOutsideOperatingHours && !model.isPaused && model.remaining == 50,
                  "afternoon start resumes only the automatic schedule pause")
            advance(10)
            check(model.statistics.days["2026-11-09"]?.focusSeconds == 20, "afternoon totals exclude the lunch gap")
        }
        do {
            var mono: TimeInterval = 0, wall = date(11,59,50)
            let model = AppModel(directory: folder("manual-pause"), wallClock: { wall }, clock: { mono })
            defer { model.stop() }
            model.togglePause()
            mono += 5410; wall = date(13,30); model.refresh()
            check(model.isPaused && !model.isOutsideOperatingHours, "a user pause survives lunch and afternoon opening")
        }
        do {
            var mono: TimeInterval = 0, wall = date(11,59,58)
            let model = AppModel(directory: folder("interrupted"), wallClock: { wall }, clock: { mono })
            defer { model.stop() }
            model.restNow()
            mono += 3; wall.addTimeInterval(3); model.refresh()
            let day = model.statistics.days["2026-11-09"]
            check(day?.restSeconds == 2 && day?.insufficientBreaks == 1 && model.phase == .work && model.isPaused,
                  "a rest crossing into lunch closes and records only its in-hours portion")
        }
        do {
            var mono: TimeInterval = 0, wall = date(8)
            let model = AppModel(directory: folder("closed"), wallClock: { wall }, clock: { mono })
            defer { model.stop() }
            mono += 3600; wall = date(9); model.refresh()
            check(!model.isPaused && model.statistics.days.isEmpty, "startup outside hours waits without counting unobserved time")
        }
        return failures == 0 ? 0 : 1
    }
}
