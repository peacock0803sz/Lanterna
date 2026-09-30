import Foundation
@testable import Lanterna
import Testing

/// How an exclusion row finds the app it names.
///
/// Installed lookup wins, otherwise the running list is searched by pattern,
/// otherwise there is no match.
@MainActor
struct ExclusionAppResolverTests {

  // MARK: Internal

  /// Installed lookup hit returns that app.
  @Test
  func installedHitReturnsInstalledApp() {
    let safari = ResolvedExclusionApp(name: "Safari", bundleIdentifier: "com.apple.Safari")
    let resolved = ExclusionAppResolver.resolve(
      app: "com.apple.Safari",
      installed: makeInstalled(entries: [safari]),
      running: makeRunning(entries: [])
    )
    #expect(resolved?.name == "Safari")
    #expect(resolved?.bundleIdentifier == "com.apple.Safari")
  }

  /// The resolver hands the raw text to installed lookup without folding.
  @Test
  func resolverPassesInputToInstalledUnchanged() {
    let canonical = ResolvedExclusionApp(name: "Safari", bundleIdentifier: "com.apple.Safari")
    var received: String?
    let table = [canonical.bundleIdentifier.lowercased(): canonical]
    let installed: @MainActor @Sendable (String) -> ResolvedExclusionApp? = { (query: String) -> ResolvedExclusionApp? in
      received = query
      return table[query.lowercased()]
    }
    let input = "CoM.ApPlE.SaFaRi"
    let resolved = ExclusionAppResolver.resolve(
      app: input,
      installed: installed,
      running: makeRunning(entries: [])
    )
    #expect(received == input)
    #expect(resolved?.bundleIdentifier == "com.apple.Safari")
  }

  /// The returned bundle identifier uses installed spelling, not input spelling.
  @Test
  func installedSpellingWinsOverInputSpelling() {
    let canonical = ResolvedExclusionApp(name: "Safari", bundleIdentifier: "com.apple.Safari")
    let resolved = ExclusionAppResolver.resolve(
      app: "COM.APPLE.SAFARI",
      installed: makeInstalled(entries: [canonical]),
      running: makeRunning(entries: [])
    )
    #expect(resolved?.name == "Safari")
    #expect(resolved?.bundleIdentifier == "com.apple.Safari")
  }

  /// Running pattern search returns the earliest match in running order.
  @Test
  func runningPatternReturnsFirstMatch() {
    let finder = ResolvedExclusionApp(name: "Finder", bundleIdentifier: "com.apple.Finder")
    let safari = ResolvedExclusionApp(name: "Safari", bundleIdentifier: "com.apple.Safari")
    let resolved = ExclusionAppResolver.resolve(
      app: "Finder|Safari",
      installed: makeInstalled(entries: []),
      running: makeRunning(entries: [finder, safari])
    )
    #expect(resolved?.name == "Finder")
    #expect(resolved?.bundleIdentifier == "com.apple.Finder")
    let reversed = ExclusionAppResolver.resolve(
      app: "Finder|Safari",
      installed: makeInstalled(entries: []),
      running: makeRunning(entries: [safari, finder])
    )
    #expect(reversed?.name == "Safari")
    #expect(reversed?.bundleIdentifier == "com.apple.Safari")
  }

  /// Empty text never resolves, even when installed lookup would answer it.
  @Test
  func emptyAppReturnsNil() {
    let finder = ResolvedExclusionApp(name: "Finder", bundleIdentifier: "com.apple.Finder")
    let resolved = ExclusionAppResolver.resolve(
      app: "",
      installed: { _ in finder },
      running: makeRunning(entries: [finder])
    )
    #expect(resolved?.bundleIdentifier == nil)
  }

  /// Unreadable patterns never resolve, even with candidates around.
  @Test
  func unreadablePatternReturnsNil() {
    let finder = ResolvedExclusionApp(name: "Finder", bundleIdentifier: "com.apple.Finder")
    let resolved = ExclusionAppResolver.resolve(
      app: "([",
      installed: makeInstalled(entries: []),
      running: makeRunning(entries: [finder])
    )
    #expect(resolved?.bundleIdentifier == nil)
  }

  /// A readable pattern with no match resolves to nothing.
  @Test
  func unmatchedPatternReturnsNil() {
    let finder = ResolvedExclusionApp(name: "Finder", bundleIdentifier: "com.apple.Finder")
    let resolved = ExclusionAppResolver.resolve(
      app: "NoSuchApp",
      installed: makeInstalled(entries: []),
      running: makeRunning(entries: [finder])
    )
    #expect(resolved?.bundleIdentifier == nil)
  }

  /// Installed hit wins even when the running pattern would also match.
  @Test
  func installedWinsOverRunningMatch() {
    let installedApp = ResolvedExclusionApp(name: "Installed", bundleIdentifier: "Finder")
    let runningApp = ResolvedExclusionApp(name: "Finder", bundleIdentifier: "com.example.Finder")
    let resolved = ExclusionAppResolver.resolve(
      app: "Finder",
      installed: makeInstalled(entries: [installedApp]),
      running: makeRunning(entries: [runningApp])
    )
    #expect(resolved?.name == "Installed")
    #expect(resolved?.bundleIdentifier == "Finder")
  }

  /// Running search is partial and case sensitive, with no added anchors.
  @Test
  func partialPatternIsCaseSensitiveWithoutAnchors() {
    let finder = ResolvedExclusionApp(name: "Finder", bundleIdentifier: "com.apple.Finder")
    let hit = ExclusionAppResolver.resolve(
      app: "Fin",
      installed: makeInstalled(entries: []),
      running: makeRunning(entries: [finder])
    )
    #expect(hit?.bundleIdentifier == "com.apple.Finder")
    let miss = ExclusionAppResolver.resolve(
      app: "fin",
      installed: makeInstalled(entries: []),
      running: makeRunning(entries: [finder])
    )
    #expect(miss?.bundleIdentifier == nil)
    let partial = ExclusionAppResolver.resolve(
      app: "ind",
      installed: makeInstalled(entries: []),
      running: makeRunning(entries: [finder])
    )
    #expect(partial?.bundleIdentifier == "com.apple.Finder")
  }

  /// Gaps in the running list are skipped while searching.
  @Test
  func runningEntriesWithoutBundleIdentifierAreSkipped() {
    let finder = ResolvedExclusionApp(name: "Finder", bundleIdentifier: "com.apple.Finder")
    let resolved = ExclusionAppResolver.resolve(
      app: "Finder",
      installed: makeInstalled(entries: []),
      running: makeRunning(entries: [nil, finder])
    )
    #expect(resolved?.bundleIdentifier == "com.apple.Finder")
    let onlyNil = ExclusionAppResolver.resolve(
      app: ".*",
      installed: makeInstalled(entries: []),
      running: makeRunning(entries: [nil])
    )
    #expect(onlyNil?.bundleIdentifier == nil)
  }

  // MARK: Private

  /// Case-insensitive table lookup standing in for system lookup.
  private func makeInstalled(entries: [ResolvedExclusionApp]) -> @MainActor @Sendable (String) -> ResolvedExclusionApp? {
    let table = Dictionary(uniqueKeysWithValues: entries.map { ($0.bundleIdentifier.lowercased(), $0) })
    return { query in table[query.lowercased()] }
  }

  /// Fixed running list standing in for the workspace snapshot.
  private func makeRunning(entries: [ResolvedExclusionApp?]) -> @MainActor @Sendable () -> [ResolvedExclusionApp?] {
    { entries }
  }

}
