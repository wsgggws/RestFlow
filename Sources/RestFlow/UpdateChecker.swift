import AppKit
import Combine
import Foundation
import RestFlowCore

@MainActor
final class UpdateChecker: ObservableObject {
    enum State { case idle, checking, current, available(String, URL), noRelease, failed }
    static let releasesURL = URL(string: "https://github.com/wsgggws/RestFlow/releases")!
    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    @Published private(set) var state: State = .idle
    private var lastAutomaticCheck: Date?
    private var task: Task<Void, Never>?
    var onChange: (() -> Void)?

    func checkAutomaticallyIfNeeded(enabled: Bool) {
        guard enabled, lastAutomaticCheck.map({ Date().timeIntervalSince($0) >= 24 * 60 * 60 }) ?? true else { return }
        lastAutomaticCheck = Date()
        check()
    }

    func stop() { task?.cancel() }

    func check() {
        if case .checking = state { return }
        state = .checking
        onChange?()
        task = Task { [weak self] in
            guard let self else { return }
            do {
                var request = URLRequest(url: URL(string: "https://api.github.com/repos/wsgggws/RestFlow/releases/latest")!)
                request.timeoutInterval = 15
                request.cachePolicy = .reloadIgnoringLocalCacheData
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                request.setValue("RestFlow/\(currentVersion)", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await URLSession.shared.data(for: request)
                try Task.checkCancellation()
                guard let response = response as? HTTPURLResponse, data.count <= 1_048_576 else { throw URLError(.badServerResponse) }
                if response.statusCode == 403 || response.statusCode == 429 {
                    // Public API quotas are shared by users behind the same network.
                    // GitHub's official latest redirect does not consume that API quota.
                    try await checkViaRedirect()
                } else if response.statusCode == 404 { state = .noRelease }
                else {
                    guard response.statusCode == 200 else { throw URLError(.badServerResponse) }
                    let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                    guard ReleaseVersion(release.tagName) != nil else { throw URLError(.cannotParseResponse) }
                    if release.isNewer(than: currentVersion), let url = release.releaseURL {
                        state = .available(release.tagName, url)
                    } else { state = .current }
                }
            } catch is CancellationError { return }
            catch { state = .failed }
            onChange?()
        }
    }

    private func checkViaRedirect() async throws {
        var request = URLRequest(url: Self.releasesURL.appendingPathComponent("latest"))
        request.httpMethod = "HEAD"
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("RestFlow/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (_, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if http.statusCode == 404 || (http.statusCode == 200 && http.url == Self.releasesURL) { state = .noRelease; return }
        guard http.statusCode == 200, let url = http.url, let release = GitHubRelease.fromRedirect(url) else {
            throw URLError(.cannotParseResponse)
        }
        if release.isNewer(than: currentVersion), let url = release.releaseURL { state = .available(release.tagName, url) }
        else { state = .current }
    }

    func openRelease() {
        if case .available(_, let url) = state { NSWorkspace.shared.open(url) }
        else { NSWorkspace.shared.open(Self.releasesURL) }
    }

    func status(in language: AppLanguage) -> String {
        switch state {
        case .idle: return language.text("检查更新…", "Check for updates…")
        case .checking: return language.text("正在检查更新…", "Checking for updates…")
        case .current: return language.text("已是最新版本", "You're up to date")
        case .available(let version, _): return language.text("可升级至 \(version)…", "Update to \(version)…")
        case .noRelease: return language.text("暂无已发布版本", "No release published yet")
        case .failed: return language.text("检查失败，点击重试", "Check failed. Click to retry")
        }
    }
}
