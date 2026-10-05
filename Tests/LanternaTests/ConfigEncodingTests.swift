import Foundation
@testable import Lanterna
import Logging
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
    config.saveLogsToDisk = false
    config.hoverSelect = true
    config.scrollSelect = true
    config.numberJump = true
    config.numberReorder = true
    config.numberScope = .allRows
    config.rowOrder = [RowOrderEntry(group: 1, keys: ["a\nb"])]
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
    #expect(!text.contains("logLevel"))
    #expect(!text.contains("saveLogsToDisk"))
    #expect(!text.contains("hoverSelect"))
    #expect(!text.contains("scrollSelect"))
    #expect(!text.contains("numberJump"))
    #expect(!text.contains("numberReorder"))
    #expect(!text.contains("numberScope"))
    #expect(!text.contains("rowOrder"))
  }

  /// A file still holding the retired level key saves without it.
  @Test
  func theRetiredLevelKeyIsNotWrittenBack() throws {
    let decoded = try #require(
      AppConfiguration.decode(Data(#"{"version": 1, "logLevel": "debug", "launchAtLogin": true}"#.utf8)).successValue
    )
    let text = try #require(String(bytes: AppConfiguration.encode(decoded.config), encoding: .utf8))
    #expect(!text.contains("logLevel"))
    #expect(text.contains("launchAtLogin"))
  }

  /// An unknown key reads past with its text kept, and saves back unchanged.
  @Test
  func unknownKeysAreKeptAndWrittenBack() throws {
    let decoded = try #require(
      AppConfiguration.decode(Data(#"{"version": 1, "mystery": {"a": [1, true, "x"]}}"#.utf8)).successValue
    )
    #expect(decoded.config.unknownFields == [UnknownField(key: "mystery", json: #"{"a": [1, true, "x"]}"#)])
    let text = try #require(String(bytes: AppConfiguration.encode(decoded.config), encoding: .utf8))
    #expect(text == "{\n  \"mystery\": {\"a\": [1, true, \"x\"]},\n  \"version\": 1\n}\n")
  }

  /// Scalar unknowns keep their spelling across a save.
  @Test
  func scalarUnknownsRoundTrip() throws {
    let decoded = try #require(
      AppConfiguration.decode(Data(#"{"version": 1, "future": 2, "flag": true}"#.utf8)).successValue
    )
    #expect(decoded.config.unknownFields == [
      UnknownField(key: "flag", json: "true"),
      UnknownField(key: "future", json: "2"),
    ])
    let reread = try #require(
      AppConfiguration.decode(AppConfiguration.encode(decoded.config)).successValue
    )
    #expect(reread.config.unknownFields == decoded.config.unknownFields)
  }
}
