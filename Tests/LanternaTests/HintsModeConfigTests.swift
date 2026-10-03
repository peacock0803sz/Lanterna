import Foundation
@testable import Lanterna
import Testing

// MARK: - HintsModeConfigTests

struct HintsModeConfigTests {

  // MARK: Internal

  @Test
  func keyIsAbsentByDefault() throws {
    let decoded = try #require(decode("{\"version\": 1}").successValue)
    #expect(decoded.config.hintsMode == nil)
    let values = SettingsValues.effective(from: decoded.config)
    #expect(values.hintsMode == .prefix)
  }

  @Test
  func eachValueDecodes() throws {
    for mode in [HintsMode.prefix, .numbers, .neither] {
      let decoded = try #require(decode(
        "{\"version\": 1, \"hintsMode\": \"\(mode.rawValue)\"}"
      ).successValue)
      #expect(decoded.config.hintsMode == mode)
      let values = SettingsValues.effective(from: decoded.config)
      #expect(values.hintsMode == mode)
    }
  }

  @Test
  func invalidValuesFailTheFile() {
    let cases: [(String, ConfigDecodeError)] = [
      ("{\"version\": 1, \"hintsMode\": \"everywhere\"}", .invalidValue(key: "hintsMode")),
      ("{\"version\": 1, \"hintsMode\": 1}", .invalidValue(key: "hintsMode")),
      ("{\"version\": 1, \"hintsMode\": true}", .invalidValue(key: "hintsMode")),
    ]
    for (text, expected) in cases {
      #expect(decode(text).failureValue == expected, "for \(text)")
    }
  }

  @Test
  func modeIsIndependentOfNumberScope() throws {
    let decoded = try #require(decode(
      "{\"version\": 1, \"hintsMode\": \"neither\", \"numberScope\": \"allRows\"}"
    ).successValue)
    let values = SettingsValues.effective(from: decoded.config)
    #expect(values.hintsMode == .neither)
    #expect(values.numberScope == .allRows)
  }

  // MARK: Private

  private func decode(_ text: String) -> Result<DecodedConfiguration, ConfigDecodeError> {
    AppConfiguration.decode(Data(text.utf8))
  }

}
