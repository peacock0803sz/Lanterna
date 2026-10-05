import Foundation
@testable import Lanterna
import Testing

// MARK: - ConfigStoreTests

struct ConfigStoreTests {

  // MARK: Internal

  @Test
  func minimalFileIsValid() throws {
    let decoded = try #require(decode("{\"version\": 1}").successValue)
    #expect(decoded.config == ValidConfiguration(version: 1, sampleCount: nil, stopMonitorEverySeconds: nil))
    #expect(!decoded.assumedVersion)
  }

  @Test
  func fullFileIsValid() throws {
    let decoded = try #require(
      decode("{\"version\": 1, \"sampleCount\": 3, \"stopMonitorEvery\": 7}").successValue
    )
    #expect(decoded.config.sampleCount == 3)
    #expect(decoded.config.stopMonitorEverySeconds == 7)
    #expect(!decoded.assumedVersion)
  }

  @Test
  func missingVersionIsAssumed() throws {
    let decoded = try #require(decode("{\"sampleCount\": 3}").successValue)
    #expect(decoded.config.version == AppConfiguration.currentVersion)
    #expect(decoded.assumedVersion)
  }

  @Test
  func zeroCountIsValid() throws {
    let decoded = try #require(decode("{\"version\": 1, \"sampleCount\": 0}").successValue)
    #expect(decoded.config.sampleCount == 0)
  }

  @Test
  func commandLineWinsWhereItSaysAnything() throws {
    let file = ValidConfiguration(version: 1, sampleCount: 3, stopMonitorEverySeconds: 7)
    let cli = try LaunchArguments.parse(["Lanterna", "--sample-count", "5"])
    let effective = AppConfiguration.effectiveOptions(file: file, cli: cli)
    #expect(effective.sampleCount == 5)
    #expect(effective.stopMonitorEvery == .seconds(7))
  }

  @Test
  func fileCoversWhatTheCommandLineLeavesOut() throws {
    let file = ValidConfiguration(version: 1, sampleCount: 3, stopMonitorEverySeconds: 7)
    let cli = try LaunchArguments.parse(["Lanterna"])
    let effective = AppConfiguration.effectiveOptions(file: file, cli: cli)
    #expect(effective.sampleCount == 3)
    #expect(effective.stopMonitorEvery == .seconds(7))
  }

  /// The display modes come from the file, present keys winning and
  /// absent ones falling back to the defaults, whatever the command
  /// line says.
  @Test
  func displayModesComeFromTheFile() throws {
    let file = ValidConfiguration(
      version: 1,
      sampleCount: nil,
      stopMonitorEverySeconds: nil,
      hiddenAppMode: .show,
      fullscreenMode: .hide
    )
    let cli = try LaunchArguments.parse(["Lanterna", "--sample-count", "5"])
    let effective = AppConfiguration.effectiveOptions(file: file, cli: cli)
    #expect(
      effective.displayModes == DisplayModes(
        otherSpace: DisplayModes.defaults.otherSpace,
        hiddenApp: .show,
        minimized: DisplayModes.defaults.minimized,
        fullscreen: .hide
      )
    )
  }

  /// The show delay comes from the file, a spelled count winning and
  /// an absent one meaning off, whatever the command line says.
  @Test
  func showDelayComesFromTheFile() throws {
    var file = ValidConfiguration(version: 1, sampleCount: nil, stopMonitorEverySeconds: nil)
    let cli = try LaunchArguments.parse(["Lanterna", "--sample-count", "5"])
    #expect(AppConfiguration.effectiveOptions(file: file, cli: cli).showDelayMs == nil)
    file.showDelayMs = 250
    #expect(AppConfiguration.effectiveOptions(file: file, cli: cli).showDelayMs == 250)
  }

  @Test
  func appearanceModeComesFromTheFile() throws {
    let file = ValidConfiguration(
      version: 1,
      sampleCount: nil,
      stopMonitorEverySeconds: nil,
      appearanceMode: .dark
    )
    let cli = try LaunchArguments.parse(["Lanterna", "--sample-count", "5"])
    let effective = AppConfiguration.effectiveOptions(file: file, cli: cli)
    #expect(effective.appearanceMode == .dark)
    #expect(effective.sampleCount == 5)
  }

  @Test
  func configFileURLLivesUnderLanterna() {
    let base = URL(fileURLWithPath: "/tmp/ConfigStoreTests", isDirectory: true)
    #expect(
      AppConfiguration.configFileURL(applicationSupport: base).path
        == "/tmp/ConfigStoreTests/Lanterna/config.json"
    )
  }

  @Test
  func unreadableShapesFallBackAsAWhole() {
    let cases: [(String, ConfigDecodeError)] = [
      ("", .emptyFile),
      ("{", .notJSONObject),
      ("[1, 2]", .notJSONObject),
      ("\"just a string\"", .notJSONObject),
      ("{\"version\": \"one\"}", .invalidVersion("one")),
      ("{\"version\": 2}", .newerVersion(2)),
      ("{\"version\": 1, \"filterMode\": \"x\"}", .unknownKey("filterMode")),
      ("{\"version\": 1, \"sampleCount\": -1}", .invalidValue(key: "sampleCount")),
      ("{\"version\": 1, \"sampleCount\": \"three\"}", .invalidValue(key: "sampleCount")),
      ("{\"version\": 1, \"sampleCount\": true}", .invalidValue(key: "sampleCount")),
      (
        "{\"version\": 1, \"sampleCount\": 3, \"stopMonitorEvery\": 0}",
        .invalidValue(key: "stopMonitorEvery")
      ),
    ]
    for (text, expected) in cases {
      #expect(decode(text).failureValue == expected, "for \(text)")
    }
  }

  @Test
  func reasonsMatchTheDiagnosticsContract() {
    #expect(ConfigDecodeError.notJSONObject.reason == "not a JSON object")
    #expect(ConfigDecodeError.emptyFile.reason == "file is empty")
    #expect(ConfigDecodeError.newerVersion(2).reason == "version 2 is newer than 1")
    #expect(ConfigDecodeError.unknownKey("filterMode").reason == "unknown key \"filterMode\"")
    #expect(
      ConfigDecodeError.invalidValue(key: "sampleCount").reason == "sampleCount is not a valid value"
    )
  }

  @Test
  func mruKeysAreRejectedAndNeverStored() throws {
    let error = try #require(decode("{\"version\": 1, \"mru\": []}").failureValue)
    #expect(error == .unknownKey("mru"))
  }

  @Test
  func existingFilesAreLeftUntouched() throws {
    let base = try tempDirectory()
    let url = AppConfiguration.configFileURL(applicationSupport: base)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let original = "{\"version\": 1, \"sampleCount\": 3}"
    try Data(original.utf8).write(to: url)
    let (outcome, found) = AppConfiguration.loadOrScaffold(applicationSupport: base)
    #expect(found == url)
    guard case .loaded(let decoded) = outcome else {
      Issue.record("expected loaded, found \(outcome)")
      return
    }
    #expect(decoded.config.sampleCount == 3)
    #expect(try String(contentsOf: url, encoding: .utf8) == original)
  }

  @Test
  func missingFilesAreScaffolded() throws {
    let base = try tempDirectory()
    let (outcome, url) = AppConfiguration.loadOrScaffold(applicationSupport: base)
    #expect(outcome == .created)
    #expect(try String(contentsOf: url, encoding: .utf8) == AppConfiguration.scaffoldJSON)
  }

  @Test
  func scaffoldWritesDefaults() throws {
    let base = try tempDirectory()
    let url = AppConfiguration.configFileURL(applicationSupport: base)
    try AppConfiguration.writeScaffold(to: url)
    let written = try String(contentsOf: url, encoding: .utf8)
    #expect(written == AppConfiguration.scaffoldJSON)
    let decoded = try #require(AppConfiguration.decode(Data(written.utf8)).successValue)
    #expect(decoded.config == ValidConfiguration(version: 1, sampleCount: nil, stopMonitorEverySeconds: nil))
  }

  @Test
  func displayModesAreAbsentByDefault() throws {
    let decoded = try #require(decode("{\"version\": 1}").successValue)
    #expect(decoded.config.otherSpaceMode == nil)
    #expect(decoded.config.hiddenAppMode == nil)
    #expect(decoded.config.minimizedMode == nil)
    #expect(decoded.config.fullscreenMode == nil)
  }

  @Test
  func displayModesDecodeWhenPresent() throws {
    let decoded = try #require(
      decode(
        "{\"version\": 1, \"otherSpaceMode\": \"hide\", "
          + "\"hiddenAppMode\": \"show\", \"minimizedMode\": \"separateAtBottom\", "
          + "\"fullscreenMode\": \"hide\"}"
      ).successValue
    )
    #expect(decoded.config.otherSpaceMode == .hide)
    #expect(decoded.config.hiddenAppMode == .show)
    #expect(decoded.config.minimizedMode == .separateAtBottom)
    #expect(decoded.config.fullscreenMode == .hide)
  }

  @Test
  func partialDisplayModesAreValid() throws {
    let decoded = try #require(
      decode("{\"version\": 1, \"minimizedMode\": \"hide\"}").successValue
    )
    #expect(decoded.config.minimizedMode == .hide)
    #expect(decoded.config.otherSpaceMode == nil)
  }

  @Test
  func invalidDisplayModesFallBackAsAWhole() {
    let cases: [(String, ConfigDecodeError)] = [
      ("{\"version\": 1, \"minimizedMode\": \"HIDE\"}", .invalidValue(key: "minimizedMode")),
      ("{\"version\": 1, \"minimizedMode\": \"separate-at-bottom\"}", .invalidValue(key: "minimizedMode")),
      ("{\"version\": 1, \"minimizedMode\": 1}", .invalidValue(key: "minimizedMode")),
      ("{\"version\": 1, \"minimizedMode\": true}", .invalidValue(key: "minimizedMode")),
      ("{\"version\": 1, \"otherSpaceMode\": \"hide\", \"mysteryMode\": \"show\"}", .unknownKey("mysteryMode")),
    ]
    for (text, expected) in cases {
      #expect(decode(text).failureValue == expected, "for \(text)")
    }
  }

  @Test
  func romajiScopeIsAbsentByDefault() throws {
    let decoded = try #require(decode("{\"version\": 1}").successValue)
    #expect(decoded.config.romajiScope == nil)
    #expect(RomajiScope.effective(from: decoded.config) == .kanaKanji)
  }

  @Test
  func romajiScopeDecodesWhenPresent() throws {
    let kana = try #require(decode("{\"version\": 1, \"romajiScope\": \"kana\"}").successValue)
    #expect(kana.config.romajiScope == .kanaOnly)
    #expect(RomajiScope.effective(from: kana.config) == .kanaOnly)
    let kanji = try #require(decode("{\"version\": 1, \"romajiScope\": \"kanji\"}").successValue)
    #expect(kanji.config.romajiScope == .kanaKanji)
  }

  @Test
  func invalidRomajiScopeFallsBackAsAWhole() {
    let cases: [(String, ConfigDecodeError)] = [
      ("{\"version\": 1, \"romajiScope\": \"KANA\"}", .invalidValue(key: "romajiScope")),
      ("{\"version\": 1, \"romajiScope\": \"kana-only\"}", .invalidValue(key: "romajiScope")),
      ("{\"version\": 1, \"romajiScope\": true}", .invalidValue(key: "romajiScope")),
      ("{\"version\": 1, \"romajiScope\": 1}", .invalidValue(key: "romajiScope")),
    ]
    for (text, expected) in cases {
      #expect(decode(text).failureValue == expected, "for \(text)")
    }
  }

  @Test
  func fullFileWithRomajiScopeIsValid() throws {
    let decoded = try #require(
      decode("{\"version\": 1, \"sampleCount\": 2, \"romajiScope\": \"kana\"}").successValue
    )
    #expect(decoded.config.sampleCount == 2)
    #expect(decoded.config.romajiScope == .kanaOnly)
    #expect(RomajiScope.effective(from: decoded.config) == .kanaOnly)
  }

  @Test
  func romajiScopeWithUnknownKeyFallsBackAsAWhole() {
    #expect(
      decode("{\"version\": 1, \"romajiScope\": \"kana\", \"mystery\": 1}").failureValue
        == .unknownKey("mystery")
    )
  }

  @Test
  func absentDisplayModesMeanDefaults() {
    let config = ValidConfiguration(version: 1, sampleCount: nil, stopMonitorEverySeconds: nil)
    let modes = DisplayModes.effective(from: config)
    #expect(modes == DisplayModes.defaults)
  }

  @Test
  func presentDisplayModesOverrideDefaults() {
    var config = ValidConfiguration(version: 1, sampleCount: nil, stopMonitorEverySeconds: nil)
    config.minimizedMode = .hide
    config.fullscreenMode = .separateAtBottom
    let modes = DisplayModes.effective(from: config)
    #expect(modes.minimized == .hide)
    #expect(modes.fullscreen == .separateAtBottom)
    #expect(modes.otherSpace == .show)
    #expect(modes.hiddenApp == .separateAtBottom)
  }

  @Test
  func savingToOneKindLeavesTheOtherAlone() throws {
    let base = try tempDirectory()
    let stableURL = AppConfiguration.configFileURL(applicationSupport: base, kind: .stable)
    let mainURL = AppConfiguration.configFileURL(applicationSupport: base, kind: .main)
    var main = ValidConfiguration(version: 1, sampleCount: nil, stopMonitorEverySeconds: nil)
    main.appearanceMode = .dark
    #expect(SettingsSaver.save(main, to: mainURL, replacingInvalidFile: false) == .saved)
    #expect(!FileManager.default.fileExists(atPath: stableURL.path))
    let decoded = try #require(AppConfiguration.decode(try Data(contentsOf: mainURL)).successValue)
    #expect(decoded.config.appearanceMode == .dark)
  }

  @Test
  func kindsLoadIndependently() throws {
    let base = try tempDirectory()
    var stable = ValidConfiguration(version: 1, sampleCount: nil, stopMonitorEverySeconds: nil)
    stable.appearanceMode = .light
    var main = ValidConfiguration(version: 1, sampleCount: nil, stopMonitorEverySeconds: nil)
    main.appearanceMode = .dark
    let stableURL = AppConfiguration.configFileURL(applicationSupport: base, kind: .stable)
    let mainURL = AppConfiguration.configFileURL(applicationSupport: base, kind: .main)
    #expect(SettingsSaver.save(stable, to: stableURL, replacingInvalidFile: false) == .saved)
    #expect(SettingsSaver.save(main, to: mainURL, replacingInvalidFile: false) == .saved)
    let (stableOutcome, _) = AppConfiguration.loadOrScaffold(applicationSupport: base, kind: .stable)
    let (mainOutcome, _) = AppConfiguration.loadOrScaffold(applicationSupport: base, kind: .main)
    guard case .loaded(let stableDecoded) = stableOutcome else {
      Issue.record("expected stable loaded, found \(stableOutcome)")
      return
    }
    guard case .loaded(let mainDecoded) = mainOutcome else {
      Issue.record("expected main loaded, found \(mainOutcome)")
      return
    }
    #expect(stableDecoded.config.appearanceMode == .light)
    #expect(mainDecoded.config.appearanceMode == .dark)
  }

  @Test
  func brokenKindFileFallsBackAlone() throws {
    let base = try tempDirectory()
    let stableURL = AppConfiguration.configFileURL(applicationSupport: base, kind: .stable)
    let mainURL = AppConfiguration.configFileURL(applicationSupport: base, kind: .main)
    var stable = ValidConfiguration(version: 1, sampleCount: nil, stopMonitorEverySeconds: nil)
    stable.appearanceMode = .light
    #expect(SettingsSaver.save(stable, to: stableURL, replacingInvalidFile: false) == .saved)
    try FileManager.default.createDirectory(
      at: mainURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data("not json".utf8).write(to: mainURL)
    let (mainOutcome, _) = AppConfiguration.loadOrScaffold(applicationSupport: base, kind: .main)
    guard case .failed(let reason) = mainOutcome else {
      Issue.record("expected main failed, found \(mainOutcome)")
      return
    }
    #expect(!reason.isEmpty)
    let (stableOutcome, _) = AppConfiguration.loadOrScaffold(applicationSupport: base, kind: .stable)
    guard case .loaded(let stableDecoded) = stableOutcome else {
      Issue.record("expected stable loaded, found \(stableOutcome)")
      return
    }
    #expect(stableDecoded.config.appearanceMode == .light)
  }

  // MARK: Private

  private func decode(_ text: String) -> Result<DecodedConfiguration, ConfigDecodeError> {
    AppConfiguration.decode(Data(text.utf8))
  }

  private func tempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

}

extension Result where Failure == ConfigDecodeError {
  var successValue: Success? {
    guard case .success(let value) = self else { return nil }
    return value
  }

  var failureValue: Failure? {
    guard case .failure(let error) = self else { return nil }
    return error
  }
}
