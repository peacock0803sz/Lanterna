import Foundation
@testable import Lanterna
import Testing

// MARK: - DisplayConfigTests

struct DisplayConfigTests {

  // MARK: Internal

  @Test
  func displayKeysAreAbsentByDefault() throws {
    let decoded = try #require(decode("{\"version\": 1}").successValue)
    #expect(decoded.config.displayTarget == nil)
    #expect(decoded.config.panelWidth == nil)
    #expect(decoded.panelWidthIssue == nil)
    #expect(DisplayTarget.effective(from: decoded.config) == .primary)
    #expect(PanelWidth.effective(from: decoded.config) == .standard)
  }

  @Test
  func displayTargetDecodesEachWord() throws {
    let cases: [(String, DisplayTarget)] = [
      ("primary", .primary),
      ("cursor", .cursor),
      ("frontWindow", .frontWindow),
      ("all", .all),
    ]
    for (text, target) in cases {
      let decoded = try #require(
        decode("{\"version\": 1, \"displayTarget\": \"\(text)\"}").successValue
      )
      #expect(decoded.config.displayTarget == target, "for \(text)")
      #expect(DisplayTarget.effective(from: decoded.config) == target, "for \(text)")
    }
  }

  @Test
  func invalidDisplayTargetFailsTheFile() {
    let cases: [(String, ConfigDecodeError)] = [
      ("{\"version\": 1, \"displayTarget\": \"PRIMARY\"}", .invalidValue(key: "displayTarget")),
      ("{\"version\": 1, \"displayTarget\": \"mouse\"}", .invalidValue(key: "displayTarget")),
      ("{\"version\": 1, \"displayTarget\": 1}", .invalidValue(key: "displayTarget")),
      ("{\"version\": 1, \"displayTarget\": true}", .invalidValue(key: "displayTarget")),
    ]
    for (text, expected) in cases {
      #expect(decode(text).failureValue == expected, "for \(text)")
    }
  }

  @Test
  func panelWidthDecodesEachStep() throws {
    let cases: [(String, PanelWidth)] = [
      ("0.8", .narrowMinus),
      ("0.9", .narrow),
      ("1.0", .standard),
      ("1.15", .wide),
      ("1.3", .widePlus),
    ]
    for (text, step) in cases {
      let decoded = try #require(
        decode("{\"version\": 1, \"panelWidth\": \(text)}").successValue
      )
      #expect(decoded.panelWidthIssue == nil, "for \(text)")
      #expect(PanelWidth.effective(from: decoded.config) == step, "for \(text)")
    }
  }

  @Test
  func offStepWidthFallsBackWithANote() throws {
    let decoded = try #require(decode("{\"version\": 1, \"panelWidth\": 2.0}").successValue)
    #expect(decoded.config.panelWidth == nil)
    #expect(decoded.panelWidthIssue == "panelWidth is not a valid value; using 1.0")
    #expect(PanelWidth.effective(from: decoded.config) == .standard)
  }

  /// An explicit standard step reads as absent, so saving omits it
  /// the way absent does.
  @Test
  func explicitStandardWidthReadsAsAbsent() throws {
    for text in [
      "{\"version\": 1, \"panelWidth\": 1.0}",
      "{\"version\": 1, \"panelWidth\": 1}",
    ] {
      let decoded = try #require(decode(text).successValue)
      #expect(decoded.config.panelWidth == nil, "for \(text)")
      #expect(decoded.panelWidthIssue == nil, "for \(text)")
      #expect(PanelWidth.effective(from: decoded.config) == .standard, "for \(text)")
    }
  }

  @Test
  func displayKeysEncodeOnlyWhenSet() throws {
    var config = ValidConfiguration(version: 1, sampleCount: nil, stopMonitorEverySeconds: nil)
    let bare = try #require(String(data: AppConfiguration.encode(config), encoding: .utf8))
    #expect(!bare.contains("displayTarget"))
    #expect(!bare.contains("panelWidth"))
    config.displayTarget = .cursor
    config.panelWidth = 1.15
    let encoded = try #require(String(data: AppConfiguration.encode(config), encoding: .utf8))
    #expect(encoded.contains("\"displayTarget\": \"cursor\""))
    #expect(encoded.contains("\"panelWidth\": 1.15"))
    let roundTripped = try #require(AppConfiguration.decode(Data(encoded.utf8)).successValue)
    #expect(roundTripped.config.displayTarget == .cursor)
    #expect(roundTripped.panelWidthIssue == nil)
    #expect(PanelWidth.effective(from: roundTripped.config) == .wide)
  }

  @Test
  func settingsRoundTripPreservesBothValues() {
    var values = SettingsValues.defaults
    values.displayTarget = .all
    values.panelWidth = .widePlus
    let config = values.configuration(version: 1, sampleCount: nil, stopMonitorEverySeconds: nil)
    #expect(config.displayTarget == .all)
    #expect(config.panelWidth == 1.30)
  }

  @Test
  func decodedDisplayKeysReachSettingsAndLaunchOptions() throws {
    let decoded = try #require(
      decode("{\"version\": 1, \"displayTarget\": \"all\", \"panelWidth\": 1.3}").successValue
    )
    let values = SettingsValues.effective(from: decoded.config)
    #expect(values.displayTarget == .all)
    #expect(values.panelWidth == .widePlus)
    let options = AppConfiguration.effectiveOptions(
      file: decoded.config,
      cli: LaunchArguments.Options()
    )
    #expect(options.displayTarget == .all)
    #expect(options.panelWidth == .widePlus)
  }

  @Test
  func defaultValuesStayAbsentOnSave() {
    let config = SettingsValues.defaults.configuration(
      version: 1,
      sampleCount: nil,
      stopMonitorEverySeconds: nil
    )
    #expect(config.displayTarget == nil)
    #expect(config.panelWidth == nil)
  }

  // MARK: Private

  private func decode(_ text: String) -> Result<DecodedConfiguration, ConfigDecodeError> {
    AppConfiguration.decode(Data(text.utf8))
  }

}
