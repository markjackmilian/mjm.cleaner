import Foundation
import Testing
@testable import CleanerCore

struct GitHubReleaseFeedTests {
    private static let v010 = AppVersion(major: 0, minor: 1, patch: 0)
    private static let v009 = AppVersion(major: 0, minor: 0, patch: 9)

    private func latest(_ body: Data, current: AppVersion = v009, status: Int = 200) async throws -> AvailableRelease? {
        try await GitHubReleaseFeed(http: FakeHTTP(status: status, body: body), currentVersion: current)
            .latestRelease(newerThan: current)
    }

    private func invalidRelease(_ body: Data) async {
        await #expect {
            try await latest(body, current: AppVersion(major: 0, minor: 0, patch: 1))
        } throws: { error in
            if case .invalidRelease = error as? UpdateError { true } else { false }
        }
    }

    @Test func readsTheRealResponseOfTheLatestRelease() async throws {
        let release = try #require(try await latest(try UpdateFixtures.data("latest-v0.1.0.json")))
        #expect(release.version == Self.v010)
        #expect(release.tag == "v0.1.0")
        #expect(release.assetName == "mjm.cleaner-v0.1.0-macos-universal.zip")
        #expect(release.assetURL.absoluteString
            == "https://github.com/markjackmilian/mjm.cleaner/releases/download/v0.1.0/mjm.cleaner-v0.1.0-macos-universal.zip")
        #expect(release.pageURL.absoluteString == "https://github.com/markjackmilian/mjm.cleaner/releases/tag/v0.1.0")
        #expect(release.size == 3_188_840)
        #expect(release.sha256 == "6c1dfc5c886b1cbc8a0849770fe66c4da07247f1e82094aeaa29cddf48154d07")
    }

    @Test func sendsTheGitHubHeadersToTheLatestReleaseEndpoint() async throws {
        let http = FakeHTTP(body: releaseJSON(tag: "v0.1.0"))
        _ = try await GitHubReleaseFeed(http: http, currentVersion: Self.v009).latestRelease(newerThan: Self.v009)
        let (url, headers) = try #require(http.requests.first)
        #expect(url.absoluteString == "https://api.github.com/repos/markjackmilian/mjm.cleaner/releases/latest")
        #expect(headers["Accept"] == "application/vnd.github+json")
        #expect(headers["User-Agent"] == "mjm.cleaner/0.0.9")
    }

    @Test(arguments: ["0.1.0", "0.1.1", "1.0.0"])
    func sameOrOlderReleaseMeansUpToDate(current: String) async throws {
        let version = try #require(AppVersion(current))
        #expect(try await latest(try UpdateFixtures.data("latest-v0.1.0.json"), current: version) == nil)
    }

    @Test func sameReleaseIsUpToDateEvenWithoutItsAsset() async throws {
        #expect(try await latest(releaseJSON(tag: "v0.1.0", assets: []), current: Self.v010) == nil)
    }

    @Test func uppercaseDigestIsNormalized() async throws {
        let body = releaseJSON(tag: "v0.2.0", assets: [asset("mjm.cleaner-v0.2.0-macos-universal.zip", digest: "sha256:" + String(repeating: "AB", count: 32))])
        #expect(try await latest(body)?.sha256 == String(repeating: "ab", count: 32))
    }

    @Test func missingAssetIsAnInvalidRelease() async {
        await invalidRelease(releaseJSON(tag: "v0.2.0", assets: []))
    }

    @Test func assetOfAnotherTagIsAnInvalidRelease() async {
        await invalidRelease(releaseJSON(tag: "v0.2.0", assets: [asset("mjm.cleaner-v0.1.0-macos-universal.zip")]))
    }

    @Test func duplicatedAssetIsAnInvalidRelease() async {
        let name = "mjm.cleaner-v0.2.0-macos-universal.zip"
        await invalidRelease(releaseJSON(tag: "v0.2.0", assets: [asset(name), asset(name)]))
    }

    @Test(arguments: [nil, "sha512:" + String(repeating: "ab", count: 32), "sha256:abc", "sha256:" + String(repeating: "zz", count: 32)] as [String?])
    func missingOrMalformedDigestIsAnInvalidRelease(digest: String?) async {
        await invalidRelease(releaseJSON(tag: "v0.2.0", assets: [asset("mjm.cleaner-v0.2.0-macos-universal.zip", digest: digest)]))
    }

    @Test func plainHTTPDownloadIsAnInvalidRelease() async {
        let name = "mjm.cleaner-v0.2.0-macos-universal.zip"
        await invalidRelease(releaseJSON(tag: "v0.2.0", assets: [asset(name, url: "http://github.com/\(name)")]))
    }

    @Test func emptyAssetIsAnInvalidRelease() async {
        await invalidRelease(releaseJSON(tag: "v0.2.0", assets: [asset("mjm.cleaner-v0.2.0-macos-universal.zip", size: 0)]))
    }

    @Test(arguments: ["0.2.0", "v0.2", "v0.2.0-rc1", "nightly"])
    func tagOutsideTheReleaseFormatIsAnInvalidRelease(tag: String) async {
        await invalidRelease(releaseJSON(tag: tag))
    }

    @Test(arguments: [403, 404, 500])
    func nonOKStatusIsReported(status: Int) async {
        await #expect(throws: UpdateError.httpStatus(status)) {
            try await latest(releaseJSON(tag: "v0.2.0"), status: status)
        }
    }

    @Test func unreadableBodyIsAnInvalidResponse() async {
        await #expect(throws: UpdateError.invalidResponse) {
            try await latest(Data("<html>".utf8))
        }
    }
}
