import Foundation

// MARK: - BuildKind

/// Which configuration slot this build reads and writes.
///
/// Stable keeps the long-standing `Lanterna/config.json`; main and debug
/// keep their own files beside it, so switching builds never resets the
/// settings another build saved.
enum BuildKind: String, Sendable {
  case stable
  case main
  case debug

  // MARK: Internal

  /// Resolves the kind for this launch: a debug build first, then the
  /// build-time stamp, then the executable's location as a fallback.
  static func of(
    stamped: String = StampedBuildKind.kind,
    executable: URL,
    home: URL = FileManager.default.homeDirectoryForCurrentUser
  ) -> BuildKind {
    #if DEBUG
    return .debug
    #else
    return resolve(stamped: stamped, executable: executable, home: home)
    #endif
  }

  /// The stamp-and-location rules alone, kept pure so the matrix stays
  /// unit-testable in any build configuration.
  static func resolve(
    stamped: String,
    executable: URL,
    home: URL = FileManager.default.homeDirectoryForCurrentUser
  ) -> BuildKind {
    switch stamped {
    case BuildKind.stable.rawValue:
      .stable
    case BuildKind.main.rawValue:
      .main
    default:
      fallback(executable: executable, home: home)
    }
  }

  // MARK: Private

  /// The location fallback, mirroring `LogOrigin`: an executable inside an
  /// `.app` under the install roots reads as stable, anything else as main.
  /// Kept as a mirror rather than shared so the log origins stay untouched.
  private static func fallback(executable: URL, home: URL) -> BuildKind {
    let path = executable.standardizedFileURL.path
    guard path.contains(".app/") else { return .main }
    let roots = ["/Applications/", home.standardizedFileURL.path + "/Applications/", "/nix/store/"]
    return roots.contains { path.hasPrefix($0) } ? .stable : .main
  }
}
