import Foundation
import RestFlowCore

func wellbeingChecks() -> [(String, () -> Void)] {
    [
        ("default catalog has twelve unique messages and twelve scenes without the retired quote", {
            let settings = AppSettings()
            expectEqual(settings.messages.count, 12)
            expectEqual(Set(settings.messages.map(\.id)).count, 12)
            expectEqual(settings.messages.contains { $0.text.contains("上善若水") }, false)
            expectEqual(settings.messages.contains { $0.text == "知止而后有定。" }, true)
            expectEqual(settings.availableVisuals.count, 12)
        }),
        ("retired built-in migration retains selected references and user-authored text", {
            do {
                var old = AppSettings()
                old.messages = [ReminderMessage(id: "water", text: "上善若水。", englishText: "The highest goodness is like water."),
                                ReminderMessage(id: "pause", text: "My own message")]
                old.shortMessageID = "water"; old.longMessageID = "water"
                let migrated = try ConfigurationStore.decode(ConfigurationStore.encode(old))
                expectEqual(migrated.messages.count, 2)
                expectEqual(migrated.message(for: .shortBreak), "知止而后有定。")
                expectEqual(migrated.longMessageID, migrated.shortMessageID)
                expectEqual(migrated.messages.first { $0.id == "pause" }?.text, "My own message")
                old.messages[0].text = "A custom message using the former ID"
                let custom = try ConfigurationStore.decode(ConfigurationStore.encode(old))
                expectEqual(custom.message(for: .shortBreak), "A custom message using the former ID")
            } catch { expectEqual(error.localizedDescription, "success") }
        }),
        ("legacy favorites and presets migrate to unrestricted simple selectors", {
            do {
                let old = try ConfigurationStore.decode(Data(#"{"contentStyle":"classical","favoriteMessageIDs":["water"],"favoriteVisualIDs":["lotus"],"shortMessageID":"water"}"#.utf8))
                expectEqual(old.contentStyle, .personal)
                expectEqual(old.shortMessageID, ReminderMessage.randomID)
                expectEqual(old.randomMessages.count, 12)
                expectEqual(old.randomVisualIDs.count, 12)
                expectEqual(old.favoriteMessageIDs, [])
                expectEqual(old.favoriteVisualIDs, [])
                let quiet = try ConfigurationStore.decode(Data(#"{"contentStyle":"quiet"}"#.utf8))
                expectEqual(quiet.shortMessageID, ReminderMessage.noneID)
                expectEqual(quiet.longMessageID, ReminderMessage.noneID)
                expectEqual(try ConfigurationStore.decode(ConfigurationStore.encode(old)), old)
            } catch { expectEqual(error.localizedDescription, "success") }
        }),
        ("message deletion clears shared selections and restoration preserves custom entries", {
            var settings = AppSettings()
            settings.shortMessageID = "pause"; settings.longMessageID = "pause"
            expectEqual(settings.deleteMessage("pause"), true)
            expectEqual(settings.messages.count, 11)
            expectEqual(settings.shortMessageID, ReminderMessage.noneID)
            expectEqual(settings.longMessageID, ReminderMessage.noneID)
            expectEqual(settings.randomMessages.contains { $0.id == "pause" }, false)
            settings.messages.append(ReminderMessage(id: "custom", text: "Keep me 💚"))
            settings.restoreBuiltinMessages(); settings.restoreBuiltinMessages()
            expectEqual(settings.messages.count, 13)
            expectEqual(settings.messages.last { $0.id == "custom" }?.text, "Keep me 💚")
        }),
        ("deleted visuals stay out of the picker and random until restored", {
            do {
                var settings = AppSettings()
                expectEqual(settings.deleteVisual("rings"), true)
                expectEqual(settings.visualID, BuiltinVisual.noneID)
                expectEqual(settings.availableVisuals.count, 11)
                expectEqual(settings.deleteVisual("rings"), false)
                settings.visualID = BuiltinVisual.randomID
                expectEqual(settings.randomVisualIDs.contains("rings"), false)
                expectEqual(try ConfigurationStore.decode(ConfigurationStore.encode(settings)), settings)
                settings.excludedVisualIDs = []
                expectEqual(settings.availableVisuals.count, 12)
            } catch { expectEqual(error.localizedDescription, "success") }
        }),
        ("empty libraries remain silent and random never samples an empty array", {
            do {
                var settings = AppSettings()
                for id in settings.messages.map(\.id) { _ = settings.deleteMessage(id) }
                for visual in BuiltinVisual.allCases { _ = settings.deleteVisual(visual.rawValue) }
                settings.shortMessageID = ReminderMessage.randomID; settings.longMessageID = ReminderMessage.randomID
                settings.visualID = BuiltinVisual.randomID; settings.soundName = AppSettings.noSoundID
                try settings.validate()
                expectEqual(settings.showsBreakScreen(for: .shortBreak), false)
                expectEqual(settings.shouldPrealert(for: .shortBreak), false)
                let content = BreakContent(settings: settings, choose: { _ in fatalError("Empty pools must not be sampled") })
                expectEqual(content.shortMessageID, ReminderMessage.noneID)
                expectEqual(try ConfigurationStore.decode(ConfigurationStore.encode(settings)), settings)
                settings.restoreBuiltinMessages(); settings.excludedVisualIDs = []
                expectEqual(settings.showsBreakScreen(for: .shortBreak), true)
            } catch { expectEqual(error.localizedDescription, "success") }
        }),
        ("random still deduplicates labels and avoids consecutive content", {
            var settings = AppSettings()
            settings.messages = [ReminderMessage(id: "a", text: "One"), ReminderMessage(id: "b", text: "Two"), ReminderMessage(id: "c", text: " One ")]
            settings.shortMessageID = ReminderMessage.randomID; settings.longMessageID = ReminderMessage.randomID
            settings.visualID = BuiltinVisual.randomID
            settings.excludedVisualIDs = BuiltinVisual.allCases.filter { $0 != .forest && $0 != .lotus }.map(\.rawValue)
            let content = BreakContent(settings: settings, avoidingMessageID: "a", avoidingVisual: .lotus, choose: { $0.first! })
            expectEqual(content.shortMessageID, "b")
            expectEqual(content.visual, .forest)
            expectEqual(settings.randomMessages.count, 2)
            settings.shortMessageID = "a"; settings.longMessageID = "c"
            expectEqual(settings.deleteMessage("a"), true)
            expectEqual(settings.messages.map(\.id), ["b"])
            expectEqual(settings.shortMessageID, ReminderMessage.noneID)
            expectEqual(settings.longMessageID, ReminderMessage.noneID)
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
