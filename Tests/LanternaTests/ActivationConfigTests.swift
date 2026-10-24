import Foundation
@testable import Lanterna
import Testing

// MARK: - ActivationConfigTests

/// The two commit switches in the settings file: absent means off, only
/// real booleans count, only an engaged switch is written, and the
/// switcher sections leave both alone.
@MainActor
struct ActivationConfigTests {

  // MARK: Internal

  @Test
  func absentSwitchesReadAsOff() throws {
    let decoded = try #require(decode(#"{"version": 1}"#).successValue)
    #expect(decoded.config.reopenWindowlessApps == nil)
    #expect(decoded.config.raiseOnlyChosenWindow == nil)
    let values = SettingsValues.effective(from: decoded.config)
    #expect(values.activationPolicy == .off)
  }

  @Test
  func engagedSwitchesReadThrough() throws {
    let decoded = try #require(decode(
      #"{"version": 1, "reopenWindowlessApps": true, "raiseOnlyChosenWindow": true}"#
    ).successValue)
    let values = SettingsValues.effective(from: decoded.config)
    #expect(values.reopenWindowlessApps == true)
    #expect(values.raiseOnlyChosenWindow == true)
    #expect(values.activationPolicy == ActivationPolicy(
      reopensWindowlessApps: true,
      raisesOnlyChosenWindow: true
    ))
  }

  @Test
  func nonBooleanSwitchesInvalidateTheFile() {
    #expect(decode(#"{"version": 1, "reopenWindowlessApps": "yes"}"#)
      .failureValue == .invalidValue(key: "reopenWindowlessApps"))
    #expect(decode(#"{"version": 1, "raiseOnlyChosenWindow": 1}"#)
      .failureValue == .invalidValue(key: "raiseOnlyChosenWindow"))
  }

  @Test
  func onlyEngagedSwitchesAreWritten() throws {
    var values = SettingsValues.defaults
    values.reopenWindowlessApps = true
    let text = try encode(values)

    #expect(text.contains(#""reopenWindowlessApps": true"#))
    #expect(!text.contains("raiseOnlyChosenWindow"))
    let decoded = try #require(decode(text).successValue)
    #expect(SettingsValues.effective(from: decoded.config).reopenWindowlessApps == true)
    #expect(SettingsValues.effective(from: decoded.config).raiseOnlyChosenWindow == false)
  }

  @Test
  func disengagedSwitchesStayOmittedOnSave() throws {
    let text = try encode(SettingsValues.defaults)

    #expect(!text.contains("reopenWindowlessApps"))
    #expect(!text.contains("raiseOnlyChosenWindow"))
  }

  @Test
  func sectionSwitchesAreIgnoredWithNotes() throws {
    let decoded = try #require(decode(
      #"{"version": 1, "raiseOnlyChosenWindow": true, "switchers": {"main": {"reopenWindowlessApps": true, "raiseOnlyChosenWindow": false}, "parallel": {"reopenWindowlessApps": true, "raiseOnlyChosenWindow": true}}}"#
    ).successValue)
    let values = SettingsValues.effective(from: decoded.config)

    #expect(values.reopenWindowlessApps == false)
    #expect(values.raiseOnlyChosenWindow == true)
    #expect(decoded.switcherNotes.contains(
      "switchers.main.reopenWindowlessApps is shared by both switchers; write it at the top level"
    ))
    #expect(decoded.switcherNotes.contains(
      "switchers.main.raiseOnlyChosenWindow is shared by both switchers; write it at the top level"
    ))
    #expect(decoded.switcherNotes.contains(
      "switchers.parallel.reopenWindowlessApps is shared by both switchers; write it at the top level"
    ))
    #expect(decoded.switcherNotes.contains(
      "switchers.parallel.raiseOnlyChosenWindow is shared by both switchers; write it at the top level"
    ))
  }

  @Test
  func schemaListsBothSwitchesAsTopLevelBooleans() throws {
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("config/config-schema.json")
    let data = try Data(contentsOf: url)
    let schema = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let properties = try #require(schema["properties"] as? [String: Any])
    for key in ["reopenWindowlessApps", "raiseOnlyChosenWindow"] {
      let fragment = try #require(properties[key] as? [String: Any])
      #expect(fragment["type"] as? String == "boolean", "for \(key)")
    }
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
