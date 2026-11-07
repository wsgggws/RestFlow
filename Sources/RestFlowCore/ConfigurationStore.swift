import Foundation

/// Atomic disk persistence with change detection. A broken external edit is never overwritten by the UI.
public final class ConfigurationStore {
    public let directory: URL
    public var fileURL: URL { directory.appendingPathComponent("config.json") }
    private var acceptedData: Data?
    private var inspectedData: Data?

    public static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/restflow", isDirectory: true)
    }

    public init(directory: URL = ConfigurationStore.defaultDirectory) {
        self.directory = directory
    }

    public static func decode(_ data: Data) throws -> AppSettings {
        try JSONDecoder().decode(AppSettings.self, from: data)
    }

    public static func encode(_ settings: AppSettings) throws -> Data {
        try settings.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(settings)
        data.append(0x0A)
        guard data.count <= 1024 * 1024 else { throw ConfigurationError.invalid("config.json must be smaller than 1 MB") }
        return data
    }

    public func load(orCreate defaults: AppSettings = AppSettings()) throws -> AppSettings {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let data = try read()
            let settings = try Self.decode(data)
            acceptedData = data
            inspectedData = data
            return settings
        }
        try write(defaults)
        return defaults
    }

    public func reload(force: Bool = false, validate: (AppSettings) throws -> Void = { _ in }) throws -> AppSettings? {
        let data = try read()
        guard force || data != inspectedData else { return nil }
        inspectedData = data
        let settings = try Self.decode(data)
        try validate(settings)
        acceptedData = data
        return settings
    }

    public func save(_ settings: AppSettings) throws {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let current = try read()
            guard current == acceptedData else {
                throw ConfigurationError.invalid("Configuration changed on disk. Reload it before saving UI changes.")
            }
        } else if acceptedData != nil {
            throw ConfigurationError.invalid("config.json was removed. Restore the file before saving UI changes.")
        }
        try write(settings)
    }

    public func resolve(_ path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        if path == "~" { return FileManager.default.homeDirectoryForCurrentUser }
        if path.hasPrefix("~/") {
            return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(String(path.dropFirst(2))).standardizedFileURL
        }
        if path.hasPrefix("/") { return URL(fileURLWithPath: path).standardizedFileURL }
        return directory.appendingPathComponent(path).standardizedFileURL
    }

    private func read() throws -> Data {
        let size = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 1024 * 1024 else { throw ConfigurationError.invalid("config.json must be smaller than 1 MB") }
        return try Data(contentsOf: fileURL)
    }

    private func write(_ settings: AppSettings) throws {
        let data = try Self.encode(settings)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        acceptedData = data
        inspectedData = data
    }
}
