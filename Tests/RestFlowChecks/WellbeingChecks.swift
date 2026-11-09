import Foundation
import RestFlowCore

func wellbeingChecks() -> [(String, () -> Void)] {
    [
        ("new preferences migrate without changing an existing content selection", {
            do {
                let old = try ConfigurationStore.decode(Data(#"{"shortMessageID":"water","soundEnabled":false}"#.utf8))
                expectEqual(old.contentStyle, .personal)
                expectEqual(old.shortMessageID, "water")
                expectEqual(old.soundEnabled, false)
                expectEqual(old.idleDetectionEnabled, true)
                var updated = old
                updated.favoriteMessageIDs = ["water", "journey"]
                updated.favoriteVisualIDs = ["lotus"]
                updated.contentStyle = .classical
                expectEqual(try ConfigurationStore.decode(ConfigurationStore.encode(updated)), updated)
                updated.favoriteMessageIDs = ["missing"]
                do { try updated.validate(); expectEqual(true, false) } catch {}
                updated.favoriteMessageIDs = []
                updated.favoriteVisualIDs = ["lotus", "lotus"]
                do { try updated.validate(); expectEqual(true, false) } catch {}
            } catch { expectEqual(error.localizedDescription, "success") }
        }),
        ("favorite random pools retain unique display text and avoid consecutive choices", {
            var settings = AppSettings()
            settings.shortMessageID = ReminderMessage.randomID
            settings.longMessageID = ReminderMessage.randomID
            settings.visualID = BuiltinVisual.randomID
            settings.favoriteMessageIDs = ["water", "journey"]
            settings.favoriteVisualIDs = ["lotus", "forest"]
            let content = BreakContent(settings: settings, avoidingMessageID: "water", avoidingVisual: .lotus, choose: { $0.first! })
            expectEqual(content.shortMessageID, "journey")
            expectEqual(content.longMessageID, "journey")
            expectEqual(content.visual, .forest)
            settings.favoriteMessageIDs = ["water"]
            expectEqual(BreakContent(settings: settings, avoidingMessageID: "water").shortMessageID, "water")
            settings.messages.append(ReminderMessage(id: "alias", text: "上善若水。"))
            settings.favoriteMessageIDs = ["water", "alias"]
            expectEqual(settings.randomMessages.count, 1)
        }),
        ("classical movement and quiet styles preserve personal selections", {
            var settings = AppSettings()
            settings.contentStyle = .classical
            expectEqual(settings.randomMessages.count, 8)
            settings.contentStyle = .movement
            expectEqual(settings.randomMessages.count, 4)
            settings.favoriteMessageIDs = ["water", "eyes"]
            expectEqual(settings.randomMessages.map(\.id), ["eyes"])
            settings.contentStyle = .quiet
            expectEqual(settings.message(for: .shortBreak), "")
            expectEqual(settings.showsBreakScreen(for: .shortBreak), true)
            settings.visualID = BuiltinVisual.noneID
            expectEqual(settings.showsBreakScreen(for: .shortBreak), false)
            settings.contentStyle = .personal
            expectEqual(settings.shortMessageID, "eyes")
            settings.messages = [ReminderMessage(id: "custom", text: "hello")]
            settings.contentStyle = .movement
            let resolved = BreakContent(settings: settings, choose: { $0.first! })
            expectEqual(resolved.message(for: .shortBreak, settings: settings).isEmpty, false)
        }),
        ("defer adds exactly three minutes once without advancing the cycle", {
            var engine = SessionEngine(plan: SessionPlan(workDuration: 60, warningSeconds: 15), now: 0)
            expectEqual(engine.tick(at: 45), [.warning])
            expectEqual(engine.deferBreak(at: 46), true)
            expectEqual(engine.remaining(at: 46), 194)
            expectEqual(engine.deferBreak(at: 47), false)
            expectEqual(engine.tick(at: 225), [])
            expectEqual(engine.tick(at: 240), [.phaseChanged(.shortBreak)])
            expectEqual(engine.completedWorkSessions, 1)
            expectEqual(engine.deferBreak(at: 241), false)
            engine.endBreak(at: 242)
            engine.pause(at: 243)
            expectEqual(engine.deferBreak(at: 243), false)
            engine.resume(at: 244)
            expectEqual(engine.deferBreak(at: 244), true)
        }),
        ("returning after absence retains cycle and uses the latest work duration", {
            var engine = SessionEngine(now: 0)
            engine.restNow(at: 1)
            engine.endBreak(at: 2)
            engine.pause(at: 10)
            engine.plan.workDuration = 1200
            engine.resumeAfterAbsence(at: 400)
            expectEqual(engine.remaining(at: 400), 1200)
            expectEqual(engine.completedWorkSessions, 1)
            engine.restNow(at: 401)
            expectEqual(engine.phase, .longBreak)
        }),
        ("old daily records load with zero away time and away stays separate", {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let old = #"{"version":1,"days":[{"id":"2026-11-09","focusSeconds":60,"restSeconds":5,"completedBreaks":1,"insufficientBreaks":2}]}"#
                try Data(old.utf8).write(to: directory.appendingPathComponent("statistics.json"))
                let store = StatisticsStore(directory: directory)
                try store.load()
                expectEqual(store.days["2026-11-09"]?.awaySeconds, 0)
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(secondsFromGMT: 0)!
                let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 11, minute: 59))!
                store.recordAway(from: start, to: start.addingTimeInterval(180), schedule: OperatingSchedule(), calendar: calendar)
                try store.save()
                let restored = StatisticsStore(directory: directory); try restored.load()
                expectEqual(restored.days["2026-11-09"]?.awaySeconds, 60)
                expectEqual(restored.days["2026-11-09"]?.focusSeconds, 60)
                expectEqual(restored.days["2026-11-09"]?.restSeconds, 5)
            } catch { expectEqual(error.localizedDescription, "success") }
        }),
    ]
}
