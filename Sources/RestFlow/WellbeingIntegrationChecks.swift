import Foundation
import RestFlowCore

@MainActor
enum WellbeingIntegrationChecks {
    static func run() -> Int32 {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("restflow-wellbeing-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        var failures = 0
        func check(_ value: Bool, _ label: String) {
            print("\(value ? "PASS" : "FAIL") \(label)"); if !value { failures += 1 }
        }
        var mono = 0.0, idle = 0.0
        let origin = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 9))!
        var wall = origin
        var settings = AppSettings()
        settings.soundEnabled = false; settings.prealertEnabled = false; settings.checkForUpdatesAutomatically = false
        func model(_ name: String) -> AppModel {
            mono = 0; idle = 0; wall = origin
            let directory = root.appendingPathComponent(name)
            _ = try! ConfigurationStore(directory: directory).load(orCreate: settings)
            return AppModel(directory: directory, idleSeconds: { idle }, wallClock: { wall }, clock: { mono })
        }
        func advance(_ app: AppModel, _ seconds: Double, idle value: Double) {
            mono += seconds; wall.addTimeInterval(seconds); idle = value; app.refresh()
        }
        func day(_ app: AppModel) -> DailyStatistics { app.statistics.days["2026-11-09"] ?? DailyStatistics(id: "2026-11-09") }
        do {
            let app = model("away"); defer { app.stop() }
            advance(app, 59, idle: 59)
            check(!app.isAway && day(app).focusSeconds == 59, "short inactivity still counts normal timer time")
            advance(app, 1, idle: 60)
            check(app.isAway && app.isPaused && app.remaining == 1440, "idle minute freezes focus at its exact boundary")
            advance(app, 30, idle: 90)
            check(day(app).focusSeconds == 60 && day(app).awaySeconds == 30, "away time is separate from timer and rest totals")
            advance(app, 0, idle: 0)
            check(!app.isAway && !app.isPaused && app.remaining == 1440, "brief absence resumes the remaining focus time")
            advance(app, 400, idle: 400)
            check(app.isAway && app.remaining == 1380 && day(app).focusSeconds == 120, "delayed idle observation clips focus without replaying missed breaks")
            advance(app, 0, idle: 0)
            check(!app.isPaused && app.remaining == 1500 && app.completedWorkSessions == 0, "five-minute absence starts fresh focus")
        }
        do {
            let app = model("manual"); defer { app.stop() }
            app.togglePause()
            advance(app, 400, idle: 400)
            advance(app, 1, idle: 0)
            check(app.isPaused && !app.isAway && app.statistics.days.isEmpty, "idle detection never releases a manual pause")
            app.setScreenLocked(true); advance(app, 60, idle: 0); app.setScreenLocked(false)
            check(app.isPaused, "lock and unlock preserve manual pause")
        }
        do {
            let app = model("paused-rest-lock"); defer { app.stop() }
            app.restNow(); app.togglePause(); app.setScreenLocked(true); app.setScreenLocked(false)
            check(app.phase == .work && app.isPaused && !app.isAway, "screen lock preserves manual pause even when a paused rest is closed")
        }
        do {
            let app = model("lock"); defer { app.stop() }
            advance(app, 20, idle: 0); app.setScreenLocked(true)
            advance(app, 80, idle: 0); app.setScreenLocked(false)
            check(!app.isPaused && day(app).focusSeconds == 20 && day(app).awaySeconds == 80, "lock freezes focus immediately and records observed away time")
            app.setScreenLocked(true); app.willSleep()
            mono += 3600; wall.addTimeInterval(3600); app.didWake(); app.setScreenLocked(false)
            check(day(app).awaySeconds == 80 && app.remaining == 1500, "sleep is not backfilled into away statistics")
            app.settings.idleDetectionEnabled = false
            advance(app, 300, idle: 300)
            check(!app.isAway && day(app).focusSeconds == 320, "idle detection can be disabled for reading and video")
        }
        do {
            let app = model("preview"); defer { app.stop() }
            advance(app, 20, idle: 0)
            app.previewBreak(); advance(app, 4, idle: 0)
            check(app.isPreview && app.remaining == 26 && day(app).focusSeconds == 20 && day(app).restSeconds == 0, "preview counts down without collecting statistics")
            app.endBreak()
            check(!app.isPreview && !app.isPaused && app.remaining == 1480 && app.completedWorkSessions == 0, "preview Esc restores the exact previous running focus")
            app.togglePause(); app.previewBreak(); advance(app, 31, idle: 0)
            check(!app.isPreview && app.isPaused && app.remaining == 1480 && day(app).completedBreaks == 0 && day(app).insufficientBreaks == 0,
                  "natural preview completion restores manual pause without a break record")
        }
        do {
            let app = model("outside-preview"); defer { app.stop() }
            wall = origin.addingTimeInterval(-3600); app.refresh()
            app.previewBreak(); advance(app, 31, idle: 0)
            check(!app.isPreview && app.isOutsideOperatingHours && app.isPaused && app.statistics.days.isEmpty, "preview is available outside hours and restores the schedule pause")
        }
        do {
            let app = model("defer"); defer { app.stop() }
            advance(app, 1490, idle: 0)
            app.deferBreak()
            check(app.remaining == 190 && !app.canDefer && app.completedWorkSessions == 0, "menu delay extends the current focus once")
            app.deferBreak()
            check(app.remaining == 190, "repeated delay cannot extend the same phase again")
            app.restart(); app.settings.deferEnabled = false; app.deferBreak()
            check(app.remaining == 1500, "delay preference is honored")
            app.settings.deferEnabled = true; app.deferBreak(token: "stale")
            check(app.remaining == 1500 && app.canDefer, "stale notification action cannot delay a different focus phase")
        }
        return failures == 0 ? 0 : 1
    }
}
