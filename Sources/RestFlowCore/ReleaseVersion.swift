import Foundation

/// Numeric stable versions only; GitHub's latest endpoint excludes prereleases.
public struct ReleaseVersion: Comparable, Equatable, Sendable {
    private let components: [Int]

    public init?(_ text: String) {
        let value = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...4).contains(parts.count) else { return nil }
        var parsed: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }), let number = Int(part) else { return nil }
            parsed.append(number)
        }
        components = parsed + Array(repeating: 0, count: 4 - parsed.count)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.components.lexicographicallyPrecedes(rhs.components)
    }
}

public struct GitHubRelease: Decodable, Sendable {
    public let tagName: String
    public let draft: Bool
    public let prerelease: Bool

    public init(tagName: String, draft: Bool = false, prerelease: Bool = false) {
        self.tagName = tagName
        self.draft = draft
        self.prerelease = prerelease
    }

    public static func fromRedirect(_ url: URL) -> GitHubRelease? {
        guard url.scheme == "https", url.host == "github.com", url.user == nil, url.password == nil,
              url.port == nil, url.query == nil, url.fragment == nil else { return nil }
        let path = url.pathComponents
        guard path.count == 6, Array(path.prefix(5)) == ["/", "wsgggws", "RestFlow", "releases", "tag"],
              ReleaseVersion(path[5]) != nil else { return nil }
        return GitHubRelease(tagName: path[5])
    }

    enum CodingKeys: String, CodingKey { case tagName = "tag_name", draft, prerelease }

    public func isNewer(than current: String) -> Bool {
        guard !draft, !prerelease, let latest = ReleaseVersion(tagName), let installed = ReleaseVersion(current) else { return false }
        return latest > installed
    }

    /// Construct a URL within our fixed repository; never open URLs from release text.
    public var releaseURL: URL? {
        guard ReleaseVersion(tagName) != nil else { return nil }
        return URL(string: "https://github.com/wsgggws/RestFlow/releases/tag/\(tagName)")
    }
}
