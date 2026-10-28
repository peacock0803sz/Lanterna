import Foundation
@testable import Lanterna
import Testing

// MARK: - AppIconBadgesConfigTests

/// The badge switch in the settings file: absent means off, only a real
/// boolean counts, only an engaged switch is written, and the switcher
/// sections leave it alone.
@MainActor
struct AppIconBadgesConfigTests {

  // MARK: Internal

  @Test
  func absentSwitchReadsAsOff() throws {
    let decoded = try #require(decode(#"{"version": 1}"#).successValue)
    #expect(decoded.config.appIconBadges == nil)
    #expect(SettingsValues.effective(from: decoded.config).appIconBadges == false)
  }

  @Test
  func engagedSwitchReadsThrough() throws {
    let decoded = try #require(decode(#"{"version": 1, "appIconBadges": true}"#).successValue)
    #expect(SettingsValues.effective(from: decoded.config).appIconBadges == true)
  }

  @Test
  func nonBooleanSwitchInvalidatesTheFile() {
    #expect(decode(#"{"version": 1, "appIconBadges": "yes"}"#)
      .failureValue == .invalidValue(key: "appIconBadges"))
    #expect(decode(#"{"version": 1, "appIconBadges": 1}"#)
      .failureValue == .invalidValue(key: "appIconBadges"))
  }

  @Test
  func onlyAnEngagedSwitchIsWritten() throws {
    var values = SettingsValues.defaults
    values.appIconBadges = true
    let text = try encode(values)

    #expect(text.contains(#""appIconBadges": true"#))
    let decoded = try #require(decode(text).successValue)
    #expect(SettingsValues.effective(from: decoded.config).appIconBadges == true)
    #expect(try !encode(SettingsValues.defaults).contains("appIconBadges"))
  }

  @Test
  func sectionSwitchesAreIgnoredWithNotes() throws {
    let decoded = try #require(decode(
      #"{"version": 1, "switchers": {"main": {"appIconBadges": true}, "parallel": {"appIconBadges": true}}}"#
    ).successValue)

    #expect(SettingsValues.effective(from: decoded.config).appIconBadges == false)
    #expect(decoded.switcherNotes.contains(
      "switchers.main.appIconBadges is shared by both switchers; write it at the top level"
    ))
    #expect(decoded.switcherNotes.contains(
      "switchers.parallel.appIconBadges is shared by both switchers; write it at the top level"
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
    let fragment = try #require(properties["appIconBadges"] as? [String: Any])
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
