import Foundation
@testable import Lanterna
import Testing

// MARK: - BuildKindTests

/// The build-kind resolution and the per-kind config paths.
struct BuildKindTests {

  // MARK: Internal

  /// A stamped release resolves to stable regardless of location.
  @Test
  func stampedStableWinsOverLocation() {
    #expect(BuildKind.resolve(stamped: "stable", executable: devExecutable) == .stable)
  }

  /// A stamped development build resolves to main regardless of location.
  @Test
  func stampedMainWinsOverLocation() {
    #expect(BuildKind.resolve(stamped: "main", executable: installedExecutable) == .main)
  }

  /// Without a known stamp, an installed app resolves to stable.
  @Test
  func installedLocationFallsBackToStable() {
    #expect(BuildKind.resolve(stamped: "bogus", executable: installedExecutable) == .stable)
  }

  /// Without a known stamp, anything else resolves to main.
  @Test
  func scratchLocationFallsBackToMain() {
    #expect(BuildKind.resolve(stamped: "", executable: devExecutable) == .main)
    #expect(BuildKind.resolve(stamped: "bogus", executable: outsideApp) == .main)
  }

  /// Stable keeps the long-standing path.
  @Test
  func stableKeepsLegacyPath() {
    let url = AppConfiguration.configFileURL(applicationSupport: support, kind: .stable)
    #expect(url.path.hasSuffix("Lanterna/config.json"))
  }

  /// Main and debug keep their own files beside the stable one.
  @Test
  func otherKindsHaveTheirOwnPaths() {
    let main = AppConfiguration.configFileURL(applicationSupport: support, kind: .main)
    let debug = AppConfiguration.configFileURL(applicationSupport: support, kind: .debug)
    #expect(main.path.hasSuffix("Lanterna/main/config.json"))
    #expect(debug.path.hasSuffix("Lanterna/debug/config.json"))
    #expect(main != debug)
  }

  // MARK: Private

  private var support: URL {
    URL(fileURLWithPath: "/Users/test/Library/Application Support", isDirectory: true)
  }

  private var installedExecutable: URL {
    URL(fileURLWithPath: "/Applications/Lanterna.app/Contents/MacOS/Lanterna")
  }

  private var devExecutable: URL {
    URL(fileURLWithPath: "/tmp/build/debug/Lanterna")
  }

  private var outsideApp: URL {
    URL(fileURLWithPath: "/Users/test/Scratch/Lanterna.app/Contents/MacOS/Lanterna")
  }

}
