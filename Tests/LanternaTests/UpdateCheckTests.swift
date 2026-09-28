import Foundation
@testable import Lanterna
import Testing

/// The seam the check offers the tests: releases that never touch
/// the network, with scripted answers for every read the check does.
private struct FakeReleases: ReleaseFetching {
    var releases: [PublishedRelease]
    var error: Error?

    func fetchReleases() async throws -> [PublishedRelease] {
        if let error {
            throw error
        }
        return releases
    }
}

private struct ProbeError: Error, Sendable {}

private func release(
    _ tag: String,
    prerelease: Bool = false
) -> PublishedRelease {
    PublishedRelease(
        number: ReleaseNumber.parse(tag)!,
        isPrerelease: prerelease,
        pageURL: URL(string: "https://example.com/release")!
    )
}

struct UpdateCheckTests {
    private func decode(_ text: String) -> Result<DecodedConfiguration, ConfigDecodeError> {
        AppConfiguration.decode(Data(text.utf8))
    }

    // MARK: - The setting in the file

    @Test func booleanValuesAreValid() throws {
        let enabled = try #require(decode("{\"version\": 1, \"updateCheckEnabled\": true}").successValue)
        #expect(enabled.config.updateCheckEnabled == true)
        let disabled = try #require(decode("{\"version\": 1, \"updateCheckEnabled\": false}").successValue)
        #expect(disabled.config.updateCheckEnabled == false)
    }

    @Test func absentMeansNil() throws {
        let decoded = try #require(decode("{\"version\": 1}").successValue)
        #expect(decoded.config.updateCheckEnabled == nil)
        #expect(decoded.config.updateChannel == nil)
    }

    @Test func integersAndStringsAreInvalid() {
        #expect(decode("{\"version\": 1, \"updateCheckEnabled\": 1}").failureValue != nil)
        #expect(decode("{\"version\": 1, \"updateCheckEnabled\": 0}").failureValue != nil)
        #expect(decode("{\"version\": 1, \"updateCheckEnabled\": \"on\"}").failureValue != nil)
    }

    @Test func channelWordsAreValid() throws {
        let stable = try #require(decode("{\"version\": 1, \"updateChannel\": \"stable\"}").successValue)
        #expect(stable.config.updateChannel == "stable")
        let beta = try #require(decode("{\"version\": 1, \"updateChannel\": \"beta\"}").successValue)
        #expect(beta.config.updateChannel == "beta")
    }

    @Test func otherChannelWordsAreInvalid() {
        #expect(decode("{\"version\": 1, \"updateChannel\": \"nightly\"}").failureValue != nil)
        #expect(decode("{\"version\": 1, \"updateChannel\": 1}").failureValue != nil)
        #expect(decode("{\"version\": 1, \"updateChannel\": true}").failureValue != nil)
    }

    @Test func unknownKeysAndNewerVersionsAreInvalid() {
        #expect(decode("{\"version\": 1, \"updateCheckEnabled\": true, \"filterMode\": \"x\"}").failureValue != nil)
        #expect(decode("{\"version\": 2, \"updateCheckEnabled\": true}").failureValue != nil)
    }

    @Test func encodedFormRoundTrips() throws {
        var config = ValidConfiguration(version: 1, sampleCount: nil, stopMonitorEverySeconds: nil)
        config.updateCheckEnabled = true
        config.updateChannel = "beta"
        let decoded = try #require(AppConfiguration.decode(AppConfiguration.encode(config)).successValue)
        #expect(decoded.config.updateCheckEnabled == true)
        #expect(decoded.config.updateChannel == "beta")
    }

    @Test func encodedFormKeepsCanonicalOrder() throws {
        var config = ValidConfiguration(version: 1, sampleCount: nil, stopMonitorEverySeconds: nil)
        config.updateCheckEnabled = true
        config.updateChannel = "beta"
        let text = try #require(String(bytes: AppConfiguration.encode(config), encoding: .utf8))
        let expected = "{\n  \"updateChannel\": \"beta\",\n  \"updateCheckEnabled\": true,\n  \"version\": 1\n}\n"
        #expect(text == expected)
    }

    @Test func settingsValuesRoundTrips() {
        var file = ValidConfiguration(version: 1, sampleCount: nil, stopMonitorEverySeconds: nil)
        file.updateCheckEnabled = true
        file.updateChannel = "beta"
        let values = SettingsValues.effective(from: file)
        #expect(values.updateCheckEnabled == true)
        #expect(values.updateChannel == .beta)
        let absent = SettingsValues.effective(from: ValidConfiguration(
            version: 1,
            sampleCount: nil,
            stopMonitorEverySeconds: nil
        ))
        #expect(absent.updateCheckEnabled == false)
        #expect(absent.updateChannel == .stable)
        let saved = values.configuration(version: 1, sampleCount: nil, stopMonitorEverySeconds: nil)
        #expect(saved.updateCheckEnabled == true)
        #expect(saved.updateChannel == "beta")
    }

    // MARK: - Release numbers

    @Test func releaseNumbersParseTagsAndShortVersions() {
        #expect(ReleaseNumber.parse("v0.6.0") == ReleaseNumber(major: 0, minor: 6, patch: 0))
        #expect(ReleaseNumber.parse("0.6.0") == ReleaseNumber(major: 0, minor: 6, patch: 0))
        #expect(ReleaseNumber.parse("v0.6.0-34-ga95f21e-dirty")?.shortName == "0.6.0")
        #expect(ReleaseNumber.parse("v10.2.30")?.shortName == "10.2.30")
    }

    @Test func releaseNumbersRejectNonReleases() {
        #expect(ReleaseNumber.parse("ga95f21e") == nil)
        #expect(ReleaseNumber.parse("v0.6") == nil)
        #expect(ReleaseNumber.parse("v0.6.0-beta")?.shortName == "0.6.0")
        #expect(ReleaseNumber.parse("") == nil)
    }

    @Test func releaseNumbersCompareNumerically() {
        let older = ReleaseNumber(major: 0, minor: 6, patch: 0)
        #expect(older < ReleaseNumber(major: 0, minor: 7, patch: 0))
        #expect(older < ReleaseNumber(major: 0, minor: 6, patch: 1))
        #expect(older < ReleaseNumber(major: 1, minor: 0, patch: 0))
        #expect(!(older < ReleaseNumber(major: 0, minor: 6, patch: 0)))
    }

    // MARK: - The decision

    @Test func newerReleasesAreFound() {
        let result = UpdateCheck.decide(
            currentVersion: "0.6.0",
            releases: [release("v0.6.0"), release("v0.7.0")],
            channel: .stable
        )
        guard case let .found(version, _) = result else {
            Issue.record("expected a newer release")
            return
        }
        #expect(version == "0.7.0")
    }

    @Test func equalVersionsAreNotNewer() {
        let result = UpdateCheck.decide(
            currentVersion: "0.6.0",
            releases: [release("v0.6.0")],
            channel: .stable
        )
        #expect(result == .upToDate(version: "0.6.0"))
    }

    @Test func stableSkipsPrereleases() {
        let result = UpdateCheck.decide(
            currentVersion: "0.6.0",
            releases: [release("v0.7.0", prerelease: true)],
            channel: .stable
        )
        #expect(result == .upToDate(version: "0.6.0"))
    }

    @Test func betaIncludesPrereleases() {
        let result = UpdateCheck.decide(
            currentVersion: "0.6.0",
            releases: [release("v0.7.0", prerelease: true)],
            channel: .beta
        )
        guard case let .found(version, _) = result else {
            Issue.record("expected a prerelease")
            return
        }
        #expect(version == "0.7.0")
    }

    @Test func undeterminableVersionsFail() {
        #expect(UpdateCheck.decide(
            currentVersion: "0.0.0",
            releases: [release("v0.7.0")],
            channel: .stable
        ) == .failed(reason: "cannot determine current version"))
        #expect(UpdateCheck.decide(
            currentVersion: "not a version",
            releases: [release("v0.7.0")],
            channel: .stable
        ) == .failed(reason: "cannot determine current version"))
    }

    // MARK: - Presentation and lines

    @Test func onlyFoundShowsADialog() throws {
        let page = try #require(URL(string: "https://example.com/release"))
        #expect(UpdateCheck.showsDialog(.found(version: "0.7.0", pageURL: page)) == true)
        #expect(UpdateCheck.showsDialog(.upToDate(version: "0.6.0")) == false)
        #expect(UpdateCheck.showsDialog(.failed(reason: "no network")) == false)
    }

    @Test func diagnosticsLinesMatchTheContract() throws {
        let page = try #require(URL(string: "https://example.com/release"))
        #expect(UpdateCheck.diagnosticsLine(.found(version: "0.7.0", pageURL: page), channel: .beta)
            == "update check found 0.7.0 (channel is beta)")
        #expect(UpdateCheck.diagnosticsLine(.upToDate(version: "0.6.0"), channel: .stable)
            == "update check up to date (0.6.0) (channel is stable)")
        #expect(UpdateCheck.diagnosticsLine(.failed(reason: "no network"), channel: .stable)
            == "update check failed (no network) (channel is stable)")
    }

    @Test func historyPointsAtTheReleasesPage() {
        #expect(UpdateCheck.releasesPageURL.absoluteString == "https://github.com/peacock0803sz/Lanterna/releases")
    }

    // MARK: - The fetch

    @Test func performFindsThroughAFake() async {
        let result = await UpdateCheck.perform(
            channel: .stable,
            currentVersion: "0.6.0",
            fetcher: FakeReleases(releases: [release("v0.7.0")], error: nil)
        )
        guard case let .found(version, _) = result else {
            Issue.record("expected a newer release")
            return
        }
        #expect(version == "0.7.0")
    }

    @Test func performMapsFailuresToReasons() async {
        let offline = await UpdateCheck.perform(
            channel: .stable,
            currentVersion: "0.6.0",
            fetcher: FakeReleases(releases: [], error: URLError(.notConnectedToInternet))
        )
        #expect(offline == .failed(reason: "no network"))
        let unreachable = await UpdateCheck.perform(
            channel: .stable,
            currentVersion: "0.6.0",
            fetcher: FakeReleases(releases: [], error: ProbeError())
        )
        #expect(unreachable == .failed(reason: "cannot reach releases"))
        let unreadable = await UpdateCheck.perform(
            channel: .stable,
            currentVersion: "0.6.0",
            fetcher: FakeReleases(
                releases: [],
                error: DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "probe"))
            )
        )
        #expect(unreadable == .failed(reason: "unreadable response"))
    }

    @Test func performMapsTypedFetchErrors() async {
        let unreachable = await UpdateCheck.perform(
            channel: .stable,
            currentVersion: "0.6.0",
            fetcher: FakeReleases(releases: [], error: ReleaseFetchError.unreachable)
        )
        #expect(unreachable == .failed(reason: "cannot reach releases"))
        let unreadable = await UpdateCheck.perform(
            channel: .stable,
            currentVersion: "0.6.0",
            fetcher: FakeReleases(releases: [], error: ReleaseFetchError.unreadable)
        )
        #expect(unreadable == .failed(reason: "unreadable response"))
    }

    @Test func httpPageRowsAreDropped() throws {
        let httpPage = try #require(URL(string: "http://example.com/release"))
        let row = GitHubRelease(tagName: "v0.7.0", prerelease: false, pageURL: httpPage)
        #expect(PublishedRelease(github: row) == nil)
    }
}
