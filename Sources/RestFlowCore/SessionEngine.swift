import Foundation

public enum SessionPhase: String, Codable, CaseIterable, Sendable {
    case work, shortBreak, longBreak

    public var title: String {
        switch self {
        case .work: return "专注"
        case .shortBreak: return "短休息"
        case .longBreak: return "长休息"
        }
    }

    public var isBreak: Bool { self != .work }
}

public struct SessionPlan: Equatable, Sendable {
    public var workDuration: TimeInterval
    public var shortBreakDuration: TimeInterval
    public var longBreakDuration: TimeInterval
    public var cycles: Int
    public var warningSeconds: TimeInterval

    public init(workDuration: TimeInterval = 1500, shortBreakDuration: TimeInterval = 30,
                longBreakDuration: TimeInterval = 300, cycles: Int = 2,
                warningSeconds: TimeInterval = 15) {
        self.workDuration = Self.validDuration(workDuration)
        self.shortBreakDuration = Self.validDuration(shortBreakDuration)
        self.longBreakDuration = Self.validDuration(longBreakDuration)
        self.cycles = max(1, min(cycles, 20))
        self.warningSeconds = warningSeconds.isFinite ? max(0, warningSeconds) : 0
    }

    private static func validDuration(_ value: TimeInterval) -> TimeInterval {
        value.isFinite ? max(1, value) : 60
    }

    public func duration(for phase: SessionPhase) -> TimeInterval {
        switch phase {
        case .work: return workDuration
        case .shortBreak: return shortBreakDuration
        case .longBreak: return longBreakDuration
        }
    }
}

/// All transitions are driven by an injected monotonic clock, independent of UI refresh rate.
public struct SessionEngine: Sendable {
    public enum Event: Equatable, Sendable {
        case warning
        case phaseChanged(SessionPhase)
    }

    public var plan: SessionPlan
    public private(set) var phase: SessionPhase = .work
    public private(set) var isPaused = false
    public private(set) var completedWorkSessions = 0
    public private(set) var phaseDuration: TimeInterval
    private var deadline: TimeInterval
    private var pausedRemaining: TimeInterval = 0
    private var didWarn = false
    public private(set) var didDefer = false

    public init(plan: SessionPlan = SessionPlan(), now: TimeInterval) {
        self.plan = plan
        phaseDuration = plan.workDuration
        deadline = now + plan.workDuration
    }

    public func remaining(at now: TimeInterval) -> TimeInterval {
        max(0, isPaused ? pausedRemaining : deadline - now)
    }

    public mutating func tick(at now: TimeInterval) -> [Event] {
        guard !isPaused else { return [] }
        // A delayed UI refresh starts one fresh phase, never a burst of missed breaks.
        if remaining(at: now) <= 0 {
            if phase == .work {
                completedWorkSessions += 1
                if completedWorkSessions >= plan.cycles {
                    completedWorkSessions = 0
                    begin(.longBreak, at: now)
                } else {
                    begin(.shortBreak, at: now)
                }
            } else {
                begin(.work, at: now)
            }
            return [.phaseChanged(phase)]
        }
        if phase == .work, !didWarn, plan.warningSeconds > 0,
           remaining(at: now) <= min(plan.warningSeconds, phaseDuration) {
            didWarn = true
            return [.warning]
        }
        return []
    }

    public mutating func pause(at now: TimeInterval) {
        guard !isPaused else { return }
        pausedRemaining = remaining(at: now)
        isPaused = true
    }

    public mutating func resume(at now: TimeInterval) {
        guard isPaused else { return }
        deadline = now + pausedRemaining
        isPaused = false
    }

    public mutating func restart(at now: TimeInterval) {
        completedWorkSessions = 0
        begin(.work, at: now)
    }

    /// A manual rest starts immediately without completing or resetting a focus cycle.
    public mutating func startShortBreak(at now: TimeInterval) {
        guard !phase.isBreak else { return }
        begin(.shortBreak, at: now)
    }

    /// Rest now replaces the current focus segment and advances the normal short/long cycle.
    public mutating func restNow(at now: TimeInterval) {
        guard !phase.isBreak else { return }
        completedWorkSessions += 1
        let long = completedWorkSessions >= plan.cycles
        if long { completedWorkSessions = 0 }
        begin(long ? .longBreak : .shortBreak, at: now)
    }

    public mutating func endBreak(at now: TimeInterval) {
        guard phase.isBreak else { return }
        begin(.work, at: now)
    }

    /// A single extension per focus phase; the cycle and plan remain unchanged.
    @discardableResult
    public mutating func deferBreak(at now: TimeInterval) -> Bool {
        guard phase == .work, !isPaused, !didDefer, remaining(at: now) > 0 else { return false }
        deadline += 180
        phaseDuration += 180
        didDefer = true
        didWarn = true
        return true
    }

    /// A sufficiently long absence starts fresh focus while retaining the long-break cycle.
    public mutating func resumeAfterAbsence(at now: TimeInterval) { begin(.work, at: now) }

    private mutating func begin(_ phase: SessionPhase, at now: TimeInterval) {
        self.phase = phase
        phaseDuration = plan.duration(for: phase)
        deadline = now + phaseDuration
        pausedRemaining = 0
        isPaused = false
        didWarn = false
        didDefer = false
    }
}
