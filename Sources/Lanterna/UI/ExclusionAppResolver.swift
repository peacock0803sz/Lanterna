import AppKit
import Foundation

// MARK: - ResolvedExclusionApp

/// An app shown beside an exclusion row, for display only.
struct ResolvedExclusionApp: Equatable, Sendable {
  var name: String
  var bundleIdentifier: String
}

// MARK: - ExclusionAppResolver

/// How an exclusion row finds the app it names, for display only.
///
/// Installed lookup wins, otherwise the running list is searched by
/// pattern, otherwise there is no match. Never used for judging.
@MainActor
enum ExclusionAppResolver {

  // MARK: Internal

  /// Finds the app named by one exclusion row.
  static func resolve(
    app: String,
    installed: @MainActor (String) -> ResolvedExclusionApp? = defaultInstalled,
    running: @MainActor () -> [ResolvedExclusionApp?] = defaultRunning
  ) -> ResolvedExclusionApp? {
    guard !app.isEmpty else { return nil }
    if let hit = installed(app) {
      return hit
    }
    guard let pattern = try? NSRegularExpression(pattern: app) else { return nil }
    for candidate in running() {
      guard let candidate else { continue }
      let name = candidate.name
      let range = NSRange(name.startIndex ..< name.endIndex, in: name)
      if pattern.firstMatch(in: name, range: range) != nil {
        return candidate
      }
    }
    return nil
  }

  // MARK: Private

  /// Installed lookup through the workspace, leaving case handling there.
  private static func defaultInstalled(_ bundleID: String) -> ResolvedExclusionApp? {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
      return nil
    }
    guard let bundle = Bundle(url: url) else { return nil }
    guard let identifier = bundle.bundleIdentifier else { return nil }
    let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
      ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
      ?? FileManager.default.displayName(atPath: url.path)
    return ResolvedExclusionApp(name: name, bundleIdentifier: identifier)
  }

  /// A snapshot of the running apps, with gaps kept as gaps.
  private static func defaultRunning() -> [ResolvedExclusionApp?] {
    NSWorkspace.shared.runningApplications.map { app in
      guard let name = app.localizedName else { return nil }
      guard let identifier = app.bundleIdentifier else { return nil }
      return ResolvedExclusionApp(name: name, bundleIdentifier: identifier)
    }
  }

}
