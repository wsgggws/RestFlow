import Foundation
import RestFlowCore

func activityChecks() -> [(String, () -> Void)] {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }
    return [
        ("operating hours default to weekdays with a lunch gap and exclusive end", {
            let schedule = OperatingSchedule()
            for (hour, minute, active) in [(8,59,false),(9,0,true),(11,59,true),(12,0,false),(13,29,false),(13,30,true),(18,29,true),(18,30,false)] {
                expectEqual(schedule.contains(date(9, hour, minute), calendar: calendar), active)
            }
            expectEqual(schedule.contains(date(14,10), calendar: calendar), false)
            expectEqual(schedule.contains(date(15,10), calendar: calendar), false)
            expectEqual(schedule.segments(from: date(9,8), to: date(9,20), calendar: calendar).reduce(0) { $0 + $1.duration }, 8 * 3600)
        }),
        ("operating schedule validates weekdays overlap and reversed periods", {
            var schedule = OperatingSchedule()
            for bad in [OperatingSchedule(weekdays: []), OperatingSchedule(weekdays: [2,2]), OperatingSchedule(morningStartMinute: 800), OperatingSchedule(afternoonStartMinute: 700)] {
                do { try bad.validate(); expectEqual(true, false) } catch {}
            }
            schedule.enabled = false
            expectEqual(schedule.contains(date(15,2), calendar: calendar), true)
            schedule = OperatingSchedule(afternoonEnabled: false)
            expectEqual(schedule.contains(date(9,14), calendar: calendar), false)
        }),
        ("schedule and random sound migrate from old files and round-trip", {
            do {
                let old = try ConfigurationStore.decode(Data("{}".utf8))
                expectEqual(old.operatingSchedule, OperatingSchedule())
                var settings = old
                settings.soundName = AppSettings.randomSoundID
                expectEqual(try ConfigurationStore.decode(ConfigurationStore.encode(settings)), settings)
                var candidates: [String] = []
                expectEqual(settings.selectedSound { candidates = $0; return $0.last! }, "Blow")
                expectEqual(candidates, AppSettings.systemSounds)
                expectEqual(settings.hasSound, true)
                settings.soundName = AppSettings.noSoundID
                expectEqual(settings.selectedSound(), AppSettings.noSoundID)
                expectEqual(settings.hasSound, false)
            } catch { expectEqual(error.localizedDescription, "success") }
        }),
        ("rest now advances short and long cycle without resetting an existing rest", {
            var engine = SessionEngine(now: 0)
            engine.pause(at: 2)
            engine.restNow(at: 3)
            expectEqual(engine.phase, .shortBreak)
            expectEqual(engine.completedWorkSessions, 1)
            expectEqual(engine.isPaused, false)
            engine.restNow(at: 4)
            expectEqual(engine.remaining(at: 4), 29)
            engine.endBreak(at: 5)
            engine.restNow(at: 6)
            expectEqual(engine.phase, .longBreak)
            expectEqual(engine.completedWorkSessions, 0)
            expectEqual(engine.remaining(at: 6), 300)
            engine.endBreak(at: 7)
            engine.restNow(at: 8)
            expectEqual(engine.phase, .shortBreak)
        }),
        ("statistics split local days ignore lunch weekends and retain actual rest", {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: dir) }
            do {
                let store = StatisticsStore(directory: dir); try store.load()
                expectEqual(store.record(from: date(9,8), to: date(9,20), phase: .work, schedule: OperatingSchedule(), calendar: calendar), 8 * 3600)
                expectEqual(store.record(from: date(14,9), to: date(14,18), phase: .work, schedule: OperatingSchedule(), calendar: calendar), 0)
                let start = date(9,11,59), end = date(9,12,1)
                expectEqual(store.record(from: start, to: end, phase: .shortBreak, schedule: OperatingSchedule(), calendar: calendar), 60)
                store.finishBreak(on: start, completed: false, calendar: calendar)
                store.finishBreak(on: date(9,15), completed: true, calendar: calendar)
                try store.save()
                let loaded = StatisticsStore(directory: dir); try loaded.load()
                let day = loaded.days["2026-11-09"]!
                expectEqual(day.focusSeconds, 28800)
                expectEqual(day.restSeconds, 60)
                expectEqual(day.insufficientBreaks, 1)
                expectEqual(day.completedBreaks, 1)
                expectEqual(loaded.recentDays(7, ending: date(9,20), calendar: calendar).count, 7)
                let always = OperatingSchedule(enabled: false)
                _ = store.record(from: date(9,23,59), to: date(10,0,1), phase: .work, schedule: always, calendar: calendar)
                expectEqual(store.days["2026-11-10"]?.focusSeconds, 60)
            } catch { expectEqual(error.localizedDescription, "success") }
        }),
        ("statistics protect corrupt files and concurrent edits", {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: dir) }
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let file = dir.appendingPathComponent("statistics.json")
                let corrupt = Data("broken".utf8); try corrupt.write(to: file)
                let store = StatisticsStore(directory: dir)
                do { try store.load(); expectEqual(true,false) } catch {}
                _ = store.record(from: date(9,9), to: date(9,10), phase: .work, schedule: OperatingSchedule(), calendar: calendar)
                do { try store.save(); expectEqual(true,false) } catch {}
                expectEqual(try Data(contentsOf: file), corrupt)
                try FileManager.default.removeItem(at: file)
                let valid = StatisticsStore(directory: dir); try valid.load()
                _ = valid.record(from: date(9,9), to: date(9,10), phase: .work, schedule: OperatingSchedule(), calendar: calendar)
                try valid.save()
                try corrupt.write(to: file)
                try valid.save() // No pending change leaves external data untouched.
                valid.finishBreak(on: date(9,10), completed: false, calendar: calendar)
                do { try valid.save(); expectEqual(true,false) } catch {}
                expectEqual(try Data(contentsOf: file), corrupt)
            } catch { expectEqual(error.localizedDescription, "success") }
        }),
        ("schedule handles daylight-saving day lengths using the local calendar", {
            var local = Calendar(identifier: .gregorian); local.timeZone = TimeZone(identifier:"America/New_York")!
            let start = local.date(from: DateComponents(year:2026,month:3,day:8))!
            let end = local.date(byAdding:.day,value:1,to:start)!
            let schedule = OperatingSchedule(enabled:false)
            expectEqual(schedule.segments(from:start,to:end,calendar:local).reduce(0) { $0 + $1.duration }, 23 * 3600)
        }),
    ]
}
