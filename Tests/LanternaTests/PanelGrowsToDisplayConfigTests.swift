import Foundation
@testable import Lanterna
import Testing

// MARK: - PanelGrowsToDisplayConfigTests

/// The grow-to-display switch in the settings file: absent means off, only
/// a real boolean counts, only an engaged switch is written, and the
/// switcher sections leave it alone.
@MainActor
struct PanelGrowsToDisplayConfigTests {

  // MARK: Internal

  @Test
  func absentSwitchReadsAsOff() throws {
    let decoded = try #require(decode(#"{"version": 1}"#).successValue)
    #expect(decoded.config.panelGrowsToDisplay == nil)
    #expect(SettingsValues.effective(from: decoded.config).panelGrowsToDisplay == false)
    #expect(AppConfiguration.effectiveOptions(file: decoded.config, cli: .init()).panelGrowsToDisplay == false)
  }

  @Test
  func engagedSwitchReadsThrough() throws {
    let decoded = try #require(decode(#"{"version": 1, "panelGrowsToDisplay": true}"#).successValue)
    #expect(SettingsValues.effective(from: decoded.config).panelGrowsToDisplay == true)
    #expect(AppConfiguration.effectiveOptions(file: decoded.config, cli: .init()).panelGrowsToDisplay == true)
  }

  @Test
  func nonBooleanSwitchInvalidatesTheFile() {
    #expect(decode(#"{"version": 1, "panelGrowsToDisplay": "yes"}"#)
      .failureValue == .invalidValue(key: "panelGrowsToDisplay"))
    #expect(decode(#"{"version": 1, "panelGrowsToDisplay": 1}"#)
      .failureValue == .invalidValue(key: "panelGrowsToDisplay"))
  }

  @Test
  func onlyAnEngagedSwitchIsWritten() throws {
    var values = SettingsValues.defaults
    values.panelGrowsToDisplay = true
    let text = try encode(values)

    #expect(text.contains(#""panelGrowsToDisplay": true"#))
    let decoded = try #require(decode(text).successValue)
    #expect(SettingsValues.effective(from: decoded.config).panelGrowsToDisplay == true)
    #expect(try !encode(SettingsValues.defaults).contains("panelGrowsToDisplay"))
  }

  /// The switch and the row limit are separate settings: turning the
  /// switch on neither writes nor drops the limit, so turning it off again
  /// finds the limit where it was.
  @Test
  func theSwitchKeepsTheRowLimitBesideIt() throws {
    var values = SettingsValues.defaults
    values.panelRows = try #require(PanelRows(count: 12))
    values.panelGrowsToDisplay = true
    let decoded = try #require(decode(encode(values)).successValue)
    let read = SettingsValues.effective(from: decoded.config)
    #expect(read.panelGrowsToDisplay == true)
    #expect(read.panelRows.count == 12)
  }

  @Test
  func sectionSwitchesAreIgnoredWithNotes() throws {
    let decoded = try #require(decode(
      #"{"version": 1, "switchers": {"main": {"panelGrowsToDisplay": true}, "parallel": {"panelGrowsToDisplay": true}}}"#
    ).successValue)

    #expect(SettingsValues.effective(from: decoded.config).panelGrowsToDisplay == false)
    #expect(decoded.switcherNotes.contains(
      "switchers.main.panelGrowsToDisplay is shared by both switchers; write it at the top level"
    ))
    #expect(decoded.switcherNotes.contains(
      "switchers.parallel.panelGrowsToDisplay is shared by both switchers; write it at the top level"
    ))
  }

  @Test
  func schemaListsTheSwitchAsATopLevelBoolean() throws {
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("config/config-schema.json")
    let data = try Data(contentsOf: url)
    let schema = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let properties = try #require(schema["properties"] as? [String: Any])
    let fragment = try #require(properties["panelGrowsToDisplay"] as? [String: Any])
    #expect(fragment["type"] as? String == "boolean")
  }

  // MARK: Private

  private func decode(_ text: String) -> Result<DecodedConfiguration, ConfigDecodeError> {
    AppConfiguration.decode(Data(text.utf8))
  }

  private func encode(_ values: SettingsValues) throws -> String {
    let config = values.configuration(version: 1, sampleCount: nil, stopMonitorEverySeconds: nil)
    return try #require(String(bytes: AppConfiguration.encode(config), encoding: .utf8))
  }

}
