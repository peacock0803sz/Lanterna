import Foundation
@testable import Lanterna
import Testing

/// What writing the config file produces, as text and as bytes.
///
/// Decoding tests live in `ConfigStoreTests`; these cover the way back:
/// whatever is written must read as the same settings, in the canonical
/// sorted-key shape, with absent keys left out.
struct ConfigEncodingTests {
  @Test
  func minimalConfigMatchesScaffold() {
    let config = ValidConfiguration(version: 1, sampleCount: nil, stopMonitorEverySeconds: nil)
    #expect(AppConfiguration.encode(config) == Data(AppConfiguration.scaffoldJSON.utf8))
  }

  @Test
  func sortedKeys() throws {
    var config = ValidConfiguration(version: 1, sampleCount: nil, stopMonitorEverySeconds: nil)
    config.appearanceMode = .dark
    let text = try #require(
      String(bytes: AppConfiguration.encode(config), encoding: .utf8)
    )
    #expect(text == "{\n  \"appearanceMode\": \"dark\",\n  \"version\": 1\n}\n")
  }

  @Test
  func roundTripsEveryKey() {
    var config = ValidConfiguration(version: 1, sampleCount: 3, stopMonitorEverySeconds: 7)
    config.otherSpaceMode = .hide
    config.hiddenAppMode = .show
    config.minimizedMode = .hide
    config.fullscreenMode = .separateAtBottom
    config.appearanceMode = .light
    config.romajiScope = .kanaOnly
    let decoded = AppConfiguration.decode(AppConfiguration.encode(config))
    #expect(decoded.successValue?.config == config)
  }

  @Test
  func omitsAbsentKeys() throws {
    let config = ValidConfiguration(version: 1, sampleCount: nil, stopMonitorEverySeconds: nil)
    let text = try #require(
      String(bytes: AppConfiguration.encode(config), encoding: .utf8)
    )
    #expect(!text.contains("sampleCount"))
    #expect(!text.contains("appearanceMode"))
  }
}
