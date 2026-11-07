import Foundation
import RestFlowCore

func releaseChecks() -> [(String, () -> Void)] {
    [
        ("versions compare numerically and normalize missing zero components", {
            expectEqual(ReleaseVersion("v0.4.0"), ReleaseVersion("0.4"))
            expectEqual(ReleaseVersion("1.0.0.0"), ReleaseVersion("1.0.0"))
            expectEqual(ReleaseVersion("0.10.0")! > ReleaseVersion("0.9.9")!, true)
            expectEqual(ReleaseVersion("1.0.0")! > ReleaseVersion("0.99.99")!, true)
            for value in ["", "latest", "v", "1", "0.4.0-beta.1", "0..4", "0.-1.0", "1.0.0/evil", "1.2.3.4.5", "０.４.０"] {
                expectEqual(ReleaseVersion(value), nil)
            }
        }),
        ("latest redirect stays within the official release path", {
            expectEqual(GitHubRelease.fromRedirect(URL(string: "https://github.com/wsgggws/RestFlow/releases/tag/v0.4.0")!)?.tagName, "v0.4.0")
            for url in ["http://github.com/wsgggws/RestFlow/releases/tag/v0.4.0",
                        "https://example.com/wsgggws/RestFlow/releases/tag/v0.4.0",
                        "https://github.com/other/RestFlow/releases/tag/v0.4.0",
                        "https://github.com/wsgggws/RestFlow/releases/tag/v0.4.0/extra",
                        "https://github.com/wsgggws/RestFlow/releases/latest",
                        "https://github.com/wsgggws/RestFlow/releases/tag/v0.4.0?redirect=1"] {
                expectEqual(GitHubRelease.fromRedirect(URL(string: url)!)?.tagName, nil)
            }
        }),
        ("release payload ignores drafts and prereleases and uses fixed repository URL", {
            do {
                func release(_ tag: String, draft: Bool = false, prerelease: Bool = false) throws -> GitHubRelease {
                    let data = try JSONSerialization.data(withJSONObject: ["tag_name":tag,"draft":draft,"prerelease":prerelease,"html_url":"https://untrusted.invalid"])
                    return try JSONDecoder().decode(GitHubRelease.self, from: data)
                }
                let newer = try release("v0.10.0")
                expectEqual(newer.isNewer(than: "0.4.0"), true)
                expectEqual(newer.releaseURL?.absoluteString, "https://github.com/wsgggws/RestFlow/releases/tag/v0.10.0")
                expectEqual(try release("v0.4.0").isNewer(than: "0.4.0"), false)
                expectEqual(try release("v0.3.0").isNewer(than: "0.4.0"), false)
                expectEqual(try release("v9.0.0", draft: true).isNewer(than: "0.4.0"), false)
                expectEqual(try release("v9.0.0", prerelease: true).isNewer(than: "0.4.0"), false)
                expectEqual(try release("not-a-version").releaseURL, nil)
            } catch { failures += 1; print("FAIL release decoding: \(error)") }
        }),
    ]
}
