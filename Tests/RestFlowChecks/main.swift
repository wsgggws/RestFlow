// Portable deterministic checks, requiring only the Swift toolchain.
var failures = 0
func expectEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #filePath, line: UInt = #line) {
    if actual != expected {
        failures += 1
        print("FAIL \(file):\(line): \(actual) != \(expected)")
    }
}
func expectFalse(_ actual: Bool, file: StaticString = #filePath, line: UInt = #line) {
    expectEqual(actual, false, file: file, line: line)
}

import Foundation
import RestFlowCore

struct SessionEngineTests {
    private let plan = SessionPlan(workDuration: 60, shortBreakDuration: 10,
                                   longBreakDuration: 30, cycles: 2, warningSeconds: 5)

    func testCycleTransitionsAcrossShortAndLongBreaks() {
        var timer = SessionEngine(plan: plan, now: 0)
        expectEqual(timer.tick(at: 60), [.phaseChanged(.shortBreak)])
        expectEqual(timer.completedWorkSessions, 1)
        expectEqual(timer.tick(at: 70), [.phaseChanged(.work)])
        expectEqual(timer.tick(at: 130), [.phaseChanged(.longBreak)])
        expectEqual(timer.completedWorkSessions, 0)
        expectEqual(timer.remaining(at: 130), 30)
        expectEqual(timer.tick(at: 160), [.phaseChanged(.work)])
    }

    func testPauseResumeFreezesWorkAndBreakTime() {
        var timer = SessionEngine(plan: plan, now: 0)
        timer.pause(at: 20)
        expectEqual(timer.remaining(at: 1000), 40)
        expectEqual(timer.tick(at: 1000), [])
        timer.resume(at: 1000)
        expectEqual(timer.remaining(at: 1005), 35)
        _ = timer.tick(at: 1040)
        timer.pause(at: 1043)
        expectEqual(timer.remaining(at: 9000), 7)
        timer.resume(at: 9000)
        expectEqual(timer.tick(at: 9007), [.phaseChanged(.work)])
    }

    func testWarningIsEmittedOnceAcrossPauseAndRepeatedTicks() {
        var timer = SessionEngine(plan: plan, now: 0)
        expectEqual(timer.tick(at: 54), [])
        expectEqual(timer.tick(at: 55), [.warning])
        expectEqual(timer.tick(at: 56), [])
        timer.pause(at: 56)
        timer.resume(at: 100)
        expectEqual(timer.tick(at: 101), [])
        _ = timer.tick(at: 104)
        _ = timer.tick(at: 114)
        expectEqual(timer.tick(at: 169), [.warning])
    }

    func testRestartClearsPauseAndCycleDuringBreak() {
        var timer = SessionEngine(plan: plan, now: 0)
        _ = timer.tick(at: 60)
        timer.pause(at: 62)
        timer.restart(at: 100)
        expectEqual(timer.phase, .work)
        expectFalse(timer.isPaused)
        expectEqual(timer.completedWorkSessions, 0)
        expectEqual(timer.remaining(at: 100), 60)
        expectEqual(timer.tick(at: 155), [.warning])
    }

    func testDelayedRefreshDoesNotReplayMissedCycles() {
        var timer = SessionEngine(plan: plan, now: 0)
        expectEqual(timer.tick(at: 10000), [.phaseChanged(.shortBreak)])
        expectEqual(timer.remaining(at: 10000), 10)
        expectEqual(timer.completedWorkSessions, 1)
    }

    func testSettingsAffectNextPhaseWithoutChangingCurrentDeadline() {
        var timer = SessionEngine(plan: plan, now: 0)
        timer.plan = SessionPlan(workDuration: 120, shortBreakDuration: 25, cycles: 1)
        expectEqual(timer.remaining(at: 10), 50)
        expectEqual(timer.tick(at: 60), [.phaseChanged(.longBreak)])
        timer.endBreak(at: 70)
        expectEqual(timer.remaining(at: 70), 120)
        expectEqual(timer.completedWorkSessions, 0)
    }

    func testEarlyEndOfBreakPreservesCycleCount() {
        var timer = SessionEngine(plan: plan, now: 0)
        timer.endBreak(at: 2)
        expectEqual(timer.remaining(at: 2), 58)
        _ = timer.tick(at: 60)
        timer.endBreak(at: 62)
        expectEqual(timer.completedWorkSessions, 1)
        expectEqual(timer.tick(at: 122), [.phaseChanged(.longBreak)])
    }

    func testManualRestStartsWhilePausedAndPreservesCycle() {
        var timer = SessionEngine(plan: plan, now: 0)
        _ = timer.tick(at: 60)
        timer.endBreak(at: 62)
        expectEqual(timer.completedWorkSessions, 1)
        timer.pause(at: 65)
        timer.startShortBreak(at: 100)
        expectEqual(timer.phase, .shortBreak)
        expectFalse(timer.isPaused)
        expectEqual(timer.remaining(at: 102), 8)
        expectEqual(timer.completedWorkSessions, 1)
        timer.startShortBreak(at: 104)
        expectEqual(timer.remaining(at: 104), 6)
        expectEqual(timer.tick(at: 110), [.phaseChanged(.work)])
        expectEqual(timer.remaining(at: 110), 60)
        expectEqual(timer.tick(at: 170), [.phaseChanged(.longBreak)])
    }

    func testOneCycleAlwaysUsesLongBreakAndZeroWarningDisablesPrealert() {
        let plan = SessionPlan(workDuration: 5, shortBreakDuration: 1,
                               longBreakDuration: 3, cycles: 1, warningSeconds: 0)
        var timer = SessionEngine(plan: plan, now: 0)
        expectEqual(timer.tick(at: 4), [])
        expectEqual(timer.tick(at: 5), [.phaseChanged(.longBreak)])
    }
}

let suite = SessionEngineTests()
let checks: [(String, () -> Void)] = [
    ("short / long break cycle", suite.testCycleTransitionsAcrossShortAndLongBreaks),
    ("pause / resume work and rest", suite.testPauseResumeFreezesWorkAndBreakTime),
    ("warning emitted once", suite.testWarningIsEmittedOnceAcrossPauseAndRepeatedTicks),
    ("restart resets phase and cycle", suite.testRestartClearsPauseAndCycleDuringBreak),
    ("delayed refresh", suite.testDelayedRefreshDoesNotReplayMissedCycles),
    ("settings apply to next phase", suite.testSettingsAffectNextPhaseWithoutChangingCurrentDeadline),
    ("early end preserves cycle", suite.testEarlyEndOfBreakPreservesCycleCount),
    ("manual rest counts down from paused focus without changing cycles", suite.testManualRestStartsWhilePausedAndPreservesCycle),
    ("one-cycle plan and disabled warning", suite.testOneCycleAlwaysUsesLongBreakAndZeroWarningDisablesPrealert),
 ] + configurationChecks() + releaseChecks() + activityChecks() + wellbeingChecks() + audioChecks()
for (name, check) in checks {
    let before = failures
    check()
    print("\(before == failures ? "PASS" : "FAIL") \(name)")
}
print("\(checks.count) checks, \(failures) failures")
exit(failures == 0 ? 0 : 1)
