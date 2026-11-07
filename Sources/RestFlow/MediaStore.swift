import AppKit
import Lottie
import RestFlowCore
import UniformTypeIdentifiers

enum MediaStore {
    struct ImportedMedia { let folder: String; let fileName: String }
    static var root: URL { ConfigurationStore.defaultDirectory.appendingPathComponent("media", isDirectory: true) }

    static func validate(_ source: URL, language: AppLanguage = .english) throws {
        func error(_ zh: String, _ en: String) -> ConfigurationError { .invalid(language.text(zh, en)) }
        let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 20 * 1024 * 1024 else { throw error("素材不能超过 20 MB。", "Media must be no larger than 20 MB.") }
        if source.pathExtension.lowercased() == "json" {
            _ = try externalAssets(source, language: language)
        } else {
            guard ["png", "jpg", "jpeg", "gif"].contains(source.pathExtension.lowercased()),
                  let image = NSImage(contentsOf: source), image.isValid else {
                throw error("无法读取图片或 GIF。", "Unable to read this image or GIF.")
            }
        }
    }

    /// Validate every referenced image before accepting JSON, including direct config-file paths.
    private static func externalAssets(_ source: URL, language: AppLanguage) throws -> [String] {
        func error(_ zh: String, _ en: String) -> ConfigurationError { .invalid(language.text(zh, en)) }
        let data = try Data(contentsOf: source)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["layers"] is [Any], let rate = json["fr"] as? Double, rate > 0,
              let width = json["w"] as? Double, width > 0,
              let height = json["h"] as? Double, height > 0,
              let start = json["ip"] as? Double, let end = json["op"] as? Double, end > start,
              (try? LottieAnimation.from(data: data)) != nil else {
            throw error("文件不是有效的 Lottie 动画 JSON。", "This is not a valid Lottie animation JSON file.")
        }
        let assets = json["assets"] as? [[String: Any]] ?? []
        let external = assets.filter {
            guard let path = $0["p"] as? String else { return false }
            return !path.isEmpty && !path.hasPrefix("data:")
        }
        guard external.count <= 100 else { throw error("配套图片不能超过 100 张。", "No more than 100 image assets are supported.") }
        let directory = source.deletingLastPathComponent()
        let safeRoot = directory.resolvingSymlinksInPath().path + "/"
        var totalSize = 0
        return try external.map { asset in
            let relative = (asset["u"] as? String ?? "") + (asset["p"] as? String ?? "")
            guard !relative.hasPrefix("/"), !relative.contains(":"), !relative.contains("\\"),
                  !relative.split(separator: "/").contains("..") else {
                throw error("动画图片必须使用同目录下的相对路径。", "Animation images must use local paths inside the animation folder.")
            }
            let url = directory.appendingPathComponent(relative)
            guard url.resolvingSymlinksInPath().path.hasPrefix(safeRoot),
                  let image = NSImage(contentsOf: url), image.isValid else {
                throw error("找不到配套图片：\(relative)", "Missing image asset: \(relative)")
            }
            totalSize += try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard totalSize <= 100 * 1024 * 1024 else {
                throw error("配套图片总大小不能超过 100 MB。", "Image assets must total no more than 100 MB.")
            }
            return relative
        }
    }

    @MainActor
    static func chooseAndImport(language: AppLanguage) throws -> ImportedMedia? {
        let panel = NSOpenPanel()
        panel.title = language.text("选择休息图片或动画", "Choose break media")
        panel.message = language.text("PNG、JPEG、GIF 或 Lottie JSON；将复制到配置目录。",
                                      "PNG, JPEG, GIF or Lottie JSON. A copy is saved in the config folder.")
        panel.allowedContentTypes = [.png, .jpeg, .gif, .json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let source = panel.url else { return nil }
        try validate(source, language: language)
        let isJSON = source.pathExtension.lowercased() == "json"
        let assets = isJSON ? try externalAssets(source, language: language) : []
        if !assets.isEmpty {
            let directoryPanel = NSOpenPanel()
            directoryPanel.title = language.text("读取 Lottie 配套图片", "Read Lottie image assets")
            directoryPanel.message = language.text("请选择该 JSON 所在的文件夹。", "Select the folder containing this JSON file.")
            directoryPanel.canChooseFiles = false
            directoryPanel.canChooseDirectories = true
            directoryPanel.directoryURL = source.deletingLastPathComponent()
            guard directoryPanel.runModal() == .OK, let directory = directoryPanel.url else { return nil }
            guard directory.standardizedFileURL == source.deletingLastPathComponent().standardizedFileURL else {
                throw ConfigurationError.invalid(language.text("请选择该 JSON 所在文件夹。", "Select the folder containing this JSON file."))
            }
        }
        let manager = FileManager.default
        let folder = UUID().uuidString
        let destination = root.appendingPathComponent(folder, isDirectory: true)
        try manager.createDirectory(at: destination, withIntermediateDirectories: true)
        do {
            let name = isJSON ? "animation.json" : "image.\(source.pathExtension.lowercased())"
            try manager.copyItem(at: source, to: destination.appendingPathComponent(name))
            for relative in Set(assets) {
                guard relative != name else { throw ConfigurationError.invalid("Image asset conflicts with animation.json") }
                let target = destination.appendingPathComponent(relative)
                try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try manager.copyItem(at: source.deletingLastPathComponent().appendingPathComponent(relative), to: target)
            }
            return ImportedMedia(folder: folder, fileName: name)
        } catch {
            try? manager.removeItem(at: destination)
            throw error
        }
    }

    static func removeManaged(path: String?) {
        guard let path else { return }
        let parts = path.split(separator: "/")
        guard parts.count == 3, parts[0] == "media", UUID(uuidString: String(parts[1])) != nil,
              parts[2] != ".." else { return }
        try? FileManager.default.removeItem(at: root.appendingPathComponent(String(parts[1])))
    }
}
