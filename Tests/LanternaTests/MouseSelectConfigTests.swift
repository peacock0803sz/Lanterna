import Foundation
@testable import Lanterna
import Testing

// MARK: - MouseSelectConfigTests

struct MouseSelectConfigTests {

  // MARK: Internal

  @Test
  func switchesAreAbsentByDefault() throws {
    let decoded = try #require(decode("{\"version\": 1}").successValue)
    #expect(decoded.config.hoverSelect == nil)
    #expect(decoded.config.scrollSelect == nil)
    let values = SettingsValues.effective(from: decoded.config)
    #expect(values.hoverSelect == false)
    #expect(values.scrollSelect == false)
    let options = AppConfiguration.effectiveOptions(
      file: decoded.config,
      cli: LaunchArguments.Options()
    )
    #expect(options.hoverSelect == false)
    #expect(options.scrollSelect == false)
  }

  @Test
  func trueValuesDecode() throws {
    let decoded = try #require(
      decode("{\"version\": 1, \"hoverSelect\": true, \"scrollSelect\": true}").successValue
    )
    #expect(decoded.config.hoverSelect == true)
    #expect(decoded.config.scrollSelect == true)
    let values = SettingsValues.effective(from: decoded.config)
    #expect(values.hoverSelect == true)
    #expect(values.scrollSelect == true)
  }

  @Test
  func invalidValuesFailTheFile() {
    let cases: [(String, ConfigDecodeError)] = [
      ("{\"version\": 1, \"hoverSelect\": \"yes\"}", .invalidValue(key: "hoverSelect")),
      ("{\"version\": 1, \"hoverSelect\": 1}", .invalidValue(key: "hoverSelect")),
      ("{\"version\": 1, \"scrollSelect\": \"yes\"}", .invalidValue(key: "scrollSelect")),
      ("{\"version\": 1, \"scrollSelect\": 1}", .invalidValue(key: "scrollSelect")),
    ]
    for (text, expected) in cases {
      #expect(decode(text).failureValue == expected, "for \(text)")
    }
  }

  @Test
  func roundTripsBothSwitches() throws {
    var config = ValidConfiguration(version: 1, sampleCount: nil, stopMonitorEverySeconds: nil)
    config.hoverSelect = true
    config.scrollSelect = true
    let text = try #require(
      String(bytes: AppConfiguration.encode(config), encoding: .utf8)
    )
    #expect(text.contains("\"hoverSelect\": true"))
    #expect(text.contains("\"scrollSelect\": true"))
    let decoded = try #require(AppConfiguration.decode(Data(text.utf8)).successValue)
    #expect(decoded.config == config)
  }

  @Test
  func defaultValuesStayAbsentOnSave() {
    let config = SettingsValues.defaults.configuration(
      version: 1,
      sampleCount: nil,
      stopMonitorEverySeconds: nil
    )
    #expect(config.hoverSelect == nil)
    #expect(config.scrollSelect == nil)
  }

  // MARK: Private

  private func decode(_ text: String) -> Result<DecodedConfiguration, ConfigDecodeError> {
    AppConfiguration.decode(Data(text.utf8))
  }

}
