import Foundation

/// Which releases a check covers: full releases only, or prereleases too.
enum UpdateChannel: String, Equatable, Sendable {
    case stable
    case beta
}

/// A release number as three integers, so newer and older stay comparable.
///
/// Tags name releases with a leading `v` and development builds carry a
/// suffix past a `-`; both are stripped before reading the numbers, so
/// `v0.6.0-34-ga95f21e-dirty` reads as 0.6.0. Anything without three
/// plain numbers names no release.
struct ReleaseNumber: Comparable, Equatable, Sendable {
    let major: Int
    let minor: Int
    let patch: Int

    /// Reads the number from a tag or a short version, or nil.
    static func parse(_ text: String) -> ReleaseNumber? {
        var core = text
        if core.hasPrefix("v") {
            core.removeFirst()
        }
        core = String(core.prefix(while: { $0 != "-" }))
        let parts = core.split(separator: ".")
        guard parts.count == 3,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isNumber } }),
              let major = Int(parts[0]),
              let minor = Int(parts[1]),
              let patch = Int(parts[2])
        else {
            return nil
        }
        return ReleaseNumber(major: major, minor: minor, patch: patch)
    }

    static func < (lhs: ReleaseNumber, rhs: ReleaseNumber) -> Bool {
        if lhs.major != rhs.major {
            return lhs.major < rhs.major
        }
        if lhs.minor != rhs.minor {
            return lhs.minor < rhs.minor
        }
        return lhs.patch < rhs.patch
    }

    /// The short `X.Y.Z` form, for on-screen and diagnostics lines.
    var shortName: String {
        "\(major).\(minor).\(patch)"
    }
}

/// One published release: its number, whether it is a prerelease, and
/// the page that describes it.
struct PublishedRelease: Equatable, Sendable {
    let number: ReleaseNumber
    let isPrerelease: Bool
    let pageURL: URL
}

/// What one check found: a newer release, nothing newer, or a failure.
/// A failure never claims a newer release exists.
enum UpdateCheckResult: Equatable, Sendable {
    case found(version: String, pageURL: URL)
    case upToDate(version: String)
    case failed(reason: String)
}

/// The network side of a check, behind a seam.
///
/// The live implementation reads the published releases; tests bring a
/// fake, so no test run ever touches the network.
protocol ReleaseFetching: Sendable {
    func fetchReleases() async throws -> [PublishedRelease]
}

/// Why a listing read failed, so the check can explain what happened.
enum ReleaseFetchError: Error, Sendable {
    case unreachable
    case unreadable
}

/// Reads the published releases from the releases listing.
///
/// Manual checks only, so the modest rate limit for anonymous reads is
/// never approached by ordinary use.
struct LiveReleaseFetcher: ReleaseFetching {
    func fetchReleases() async throws -> [PublishedRelease] {
        var request = URLRequest(url: UpdateCheck.releasesAPIURL)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            throw ReleaseFetchError.unreachable
        }
        let decoded = try JSONDecoder().decode([GitHubRelease].self, from: data)
        if decoded.isEmpty {
            return []
        }
        let kept = decoded.compactMap { PublishedRelease(github: $0) }
        guard !kept.isEmpty else {
            throw ReleaseFetchError.unreadable
        }
        return kept
    }
}

/// One row of the releases listing, as the API describes it.
struct GitHubRelease: Decodable {
    var tagName: String
    var prerelease: Bool
    var pageURL: URL

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case prerelease
        case pageURL = "html_url"
    }
}

extension PublishedRelease {
    /// Keeps rows that name a release, dropping rows that do not.
    init?(github release: GitHubRelease) {
        guard let number = ReleaseNumber.parse(release.tagName) else {
            return nil
        }
        self.init(number: number, isPrerelease: release.prerelease, pageURL: release.pageURL)
    }
}

/// Decides what a check means and how it reads.
///
/// The entry point only announces: it never downloads, replaces, or
/// restarts anything.
enum UpdateCheck {
    /// Where the published releases live, for the history link.
    static let releasesPageURL = URL(string: "https://github.com/peacock0803sz/Lanterna/releases")!
    /// What the live fetcher reads.
    static let releasesAPIURL = URL(string: "https://api.github.com/repos/peacock0803sz/Lanterna/releases")!

    /// Runs one check through the given fetcher.
    ///
    /// A pure decision over the fetched rows except for the fetch itself,
    /// so failures of the network read as failures of the check and never
    /// stop the run.
    static func perform(
        channel: UpdateChannel,
        currentVersion: String,
        fetcher: any ReleaseFetching
    ) async -> UpdateCheckResult {
        let releases: [PublishedRelease]
        do {
            releases = try await fetcher.fetchReleases()
        } catch let error as URLError where error.code == .notConnectedToInternet {
            return .failed(reason: "no network")
        } catch let error as ReleaseFetchError {
            switch error {
            case .unreachable:
                return .failed(reason: "cannot reach releases")
            case .unreadable:
                return .failed(reason: "unreadable response")
            }
        } catch is DecodingError {
            return .failed(reason: "unreadable response")
        } catch {
            return .failed(reason: "cannot reach releases")
        }
        return decide(currentVersion: currentVersion, releases: releases, channel: channel)
    }

    /// Decides the result from the running version and the published ones.
    ///
    /// A pure function over its inputs, so every combination stays countable
    /// without touching the network. Prereleases only count when the channel
    /// includes them, and equal versions are not newer. A running version
    /// without a release shape cannot be compared: the `0.0.0` fallback names
    /// no release, so it reads as undeterminable rather than as the oldest.
    static func decide(
        currentVersion: String,
        releases: [PublishedRelease],
        channel: UpdateChannel
    ) -> UpdateCheckResult {
        guard currentVersion != "0.0.0",
              let current = ReleaseNumber.parse(currentVersion)
        else {
            return .failed(reason: "cannot determine current version")
        }
        let candidates = releases.filter { channel == .beta || !$0.isPrerelease }
        let newer = candidates.filter { $0.number > current }
        guard let latest = newer.max(by: { $0.number < $1.number }) else {
            return .upToDate(version: currentVersion)
        }
        return .found(version: latest.number.shortName, pageURL: latest.pageURL)
    }

    /// Whether the result interrupts with a dialog: only a newer release does.
    static func showsDialog(_ result: UpdateCheckResult) -> Bool {
        if case .found = result {
            return true
        }
        return false
    }

    /// The diagnostics line for one check.
    static func diagnosticsLine(_ result: UpdateCheckResult, channel: UpdateChannel) -> String {
        let channelText = channel.rawValue
        switch result {
        case let .found(version, _):
            return "update check found \(version) (channel is \(channelText))"
        case let .upToDate(version):
            return "update check up to date (\(version)) (channel is \(channelText))"
        case let .failed(reason):
            return "update check failed (\(reason)) (channel is \(channelText))"
        }
    }
}
