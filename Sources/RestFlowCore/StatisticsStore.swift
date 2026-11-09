import Foundation

public struct DailyStatistics: Codable, Equatable, Identifiable, Sendable {
    public var id: String // Local yyyy-MM-dd at the time of observation
    public var focusSeconds: Double = 0
    public var restSeconds: Double = 0
    public var completedBreaks: Int = 0
    public var insufficientBreaks: Int = 0
    public init(id: String) { self.id = id }
}

/// Local aggregates only; corrupt files and concurrent writers are never overwritten.
public final class StatisticsStore {
    private struct Document: Codable { var version = 1; var days: [DailyStatistics] }
    public let fileURL: URL
    public private(set) var days: [String: DailyStatistics] = [:]
    private var acceptedData: Data?
    private var writable = false
    private var dirty = false

    public init(directory: URL) { fileURL = directory.appendingPathComponent("statistics.json") }

    public func load() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { writable = true; return }
        let size = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 4 * 1024 * 1024 else { throw ConfigurationError.invalid("statistics.json is too large") }
        let data = try Data(contentsOf: fileURL)
        let document = try JSONDecoder().decode(Document.self, from: data)
        guard document.version == 1, Set(document.days.map(\.id)).count == document.days.count,
              document.days.allSatisfy({ day in
                  day.id.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil &&
                  day.focusSeconds.isFinite && (0...172800).contains(day.focusSeconds) &&
                  day.restSeconds.isFinite && (0...172800).contains(day.restSeconds) &&
                  (0...100000).contains(day.completedBreaks) && (0...100000).contains(day.insufficientBreaks)
              }) else { throw ConfigurationError.invalid("Invalid statistics.json") }
        days = Dictionary(uniqueKeysWithValues: document.days.map { ($0.id, $0) })
        acceptedData = data
        writable = true
    }

    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    @discardableResult
    public func record(from start: Date, to end: Date, phase: SessionPhase,
                       schedule: OperatingSchedule, calendar: Calendar = .current) -> Double {
        var recorded: Double = 0
        for interval in schedule.segments(from: start, to: end, calendar: calendar) {
            let key = Self.dayKey(interval.start, calendar: calendar)
            var day = days[key] ?? DailyStatistics(id: key)
            if phase.isBreak { day.restSeconds += interval.duration }
            else { day.focusSeconds += interval.duration }
            days[key] = day
            recorded += interval.duration
            dirty = true
        }
        return recorded
    }

    public func finishBreak(on date: Date, completed: Bool, calendar: Calendar = .current) {
        let key = Self.dayKey(date, calendar: calendar)
        var day = days[key] ?? DailyStatistics(id: key)
        if completed { day.completedBreaks += 1 } else { day.insufficientBreaks += 1 }
        days[key] = day
        dirty = true
    }

    public func recentDays(_ count: Int, ending date: Date = Date(), calendar: Calendar = .current) -> [DailyStatistics] {
        (0..<count).reversed().map { offset in
            let key = Self.dayKey(calendar.date(byAdding: .day, value: -offset, to: date)!, calendar: calendar)
            return days[key] ?? DailyStatistics(id: key)
        }
    }

    public func save() throws {
        guard writable else { throw ConfigurationError.invalid("Repair statistics.json before saving statistics.") }
        guard dirty else { return }
        let current = try? Data(contentsOf: fileURL)
        guard current == acceptedData else { throw ConfigurationError.invalid("statistics.json changed externally; restart after resolving the conflict.") }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Document(days: days.values.sorted { $0.id < $1.id }))
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        acceptedData = data
        dirty = false
    }
}
