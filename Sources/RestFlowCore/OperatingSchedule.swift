import Foundation

/// Two local daytime windows; Calendar handles weekday, timezone and daylight-saving changes.
public struct OperatingSchedule: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var weekdays: [Int] // Calendar weekday: Sunday = 1
    public var morningStartMinute: Int
    public var morningEndMinute: Int
    public var afternoonEnabled: Bool
    public var afternoonStartMinute: Int
    public var afternoonEndMinute: Int

    public init(enabled: Bool = true, weekdays: [Int] = [2, 3, 4, 5, 6],
                morningStartMinute: Int = 540, morningEndMinute: Int = 720,
                afternoonEnabled: Bool = true, afternoonStartMinute: Int = 810, afternoonEndMinute: Int = 1110) {
        self.enabled = enabled
        self.weekdays = weekdays
        self.morningStartMinute = morningStartMinute
        self.morningEndMinute = morningEndMinute
        self.afternoonEnabled = afternoonEnabled
        self.afternoonStartMinute = afternoonStartMinute
        self.afternoonEndMinute = afternoonEndMinute
    }

    public func validate() throws {
        guard !weekdays.isEmpty, Set(weekdays).count == weekdays.count,
              weekdays.allSatisfy({ (1...7).contains($0) }),
              (0...1439).contains(morningStartMinute), (1...1440).contains(morningEndMinute),
              morningStartMinute < morningEndMinute,
              (0...1439).contains(afternoonStartMinute), (1...1440).contains(afternoonEndMinute),
              afternoonStartMinute < afternoonEndMinute,
              !afternoonEnabled || morningEndMinute <= afternoonStartMinute else {
            throw ConfigurationError.invalid("Operating hours require unique weekdays, valid time ranges and nonoverlapping periods.")
        }
    }

    public func windows(on date: Date, calendar: Calendar = .current) -> [DateInterval] {
        guard weekdays.contains(calendar.component(.weekday, from: date)) else { return [] }
        let day = calendar.startOfDay(for: date)
        func time(_ minute: Int) -> Date {
            if minute == 1440 { return calendar.date(byAdding: .day, value: 1, to: day)! }
            return calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day)!
        }
        var result = [DateInterval(start: time(morningStartMinute), end: time(morningEndMinute))]
        if afternoonEnabled { result.append(DateInterval(start: time(afternoonStartMinute), end: time(afternoonEndMinute))) }
        return result
    }

    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard enabled else { return true }
        return windows(on: date, calendar: calendar).contains { date >= $0.start && date < $0.end }
    }

    /// Split only observed elapsed intervals; callers never supply time when the app was closed/asleep.
    public func segments(from start: Date, to end: Date, calendar: Calendar = .current) -> [DateInterval] {
        guard end > start else { return [] }
        var result: [DateInterval] = []
        var cursor = start
        while cursor < end {
            let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: cursor))!
            let limit = min(end, nextDay)
            if !enabled { result.append(DateInterval(start: cursor, end: limit)) }
            else {
                for window in windows(on: cursor, calendar: calendar) {
                    let lower = max(cursor, window.start), upper = min(limit, window.end)
                    if upper > lower { result.append(DateInterval(start: lower, end: upper)) }
                }
            }
            cursor = limit
        }
        return result
    }
}
