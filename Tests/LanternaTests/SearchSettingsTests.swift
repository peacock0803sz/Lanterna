import Foundation
@testable import Lanterna
import Testing

/// What the three search-quality keys read as.
///
/// Decoding conventions live in `ConfigStoreTests`; these cover the new
/// keys: present values win, absent keys mean the defaults, and anything
/// outside the schema invalidates the whole file.
struct SearchSettingsTests {

  // MARK: Internal

  @Test
  func searchKeysAreAbsentByDefault() throws {
    let decoded = try #require(decode("{\"version\": 1}").successValue)
    #expect(decoded.config.shortcutMemoryLength == nil)
    #expect(decoded.config.fuzzyMatchEnabled == nil)
    #expect(decoded.config.resultOrder == nil)
  }

  @Test
  func searchKeysDecodeWhenPresent() throws {
    let text = "{\"version\": 1, \"shortcutMemoryLength\": 1, "
      + "\"fuzzyMatchEnabled\": false, \"resultOrder\": \"score\"}"
    let decoded = try #require(decode(text).successValue)
    #expect(decoded.config.shortcutMemoryLength == 1)
    #expect(decoded.config.fuzzyMatchEnabled == false)
    #expect(decoded.config.resultOrder == "score")
  }

  @Test
  func memoryLengthBounds() throws {
    let zero = try #require(decode("{\"version\": 1, \"shortcutMemoryLength\": 0}").successValue)
    #expect(zero.config.shortcutMemoryLength == 0)
    let five = try #require(decode("{\"version\": 1, \"shortcutMemoryLength\": 5}").successValue)
    #expect(five.config.shortcutMemoryLength == 5)
  }

  @Test
  func invalidSearchKeysFallBackAsAWhole() {
    let cases: [(String, ConfigDecodeError)] = [
      ("{\"version\": 1, \"shortcutMemoryLength\": 6}", .invalidValue(key: "shortcutMemoryLength")),
      ("{\"version\": 1, \"shortcutMemoryLength\": -1}", .invalidValue(key: "shortcutMemoryLength")),
      ("{\"version\": 1, \"shortcutMemoryLength\": true}", .invalidValue(key: "shortcutMemoryLength")),
      ("{\"version\": 1, \"fuzzyMatchEnabled\": 1}", .invalidValue(key: "fuzzyMatchEnabled")),
      ("{\"version\": 1, \"fuzzyMatchEnabled\": \"yes\"}", .invalidValue(key: "fuzzyMatchEnabled")),
      ("{\"version\": 1, \"resultOrder\": \"MRU\"}", .invalidValue(key: "resultOrder")),
      ("{\"version\": 1, \"resultOrder\": \"best\"}", .invalidValue(key: "resultOrder")),
      ("{\"version\": 1, \"resultOrder\": true}", .invalidValue(key: "resultOrder")),
    ]
    for (text, expected) in cases {
      #expect(decode(text).failureValue == expected, "for \(text)")
    }
  }

  @Test
  func searchKeysRoundTrip() throws {
    var config = ValidConfiguration(version: 1, sampleCount: nil, stopMonitorEverySeconds: nil)
    config.shortcutMemoryLength = 3
    config.fuzzyMatchEnabled = false
    config.resultOrder = "score"
    let decoded = AppConfiguration.decode(AppConfiguration.encode(config))
    #expect(decoded.successValue?.config == config)
    let text = try #require(String(bytes: AppConfiguration.encode(config), encoding: .utf8))
    #expect(text.contains("\"fuzzyMatchEnabled\": false"))
    #expect(text.contains("\"resultOrder\": \"score\""))
    #expect(text.contains("\"shortcutMemoryLength\": 3"))
  }

  @Test
  func settingsValuesFollowAbsentKeys() throws {
    let decoded = try #require(decode("{\"version\": 1}").successValue)
    let values = SettingsValues.effective(from: decoded.config)
    #expect(values.shortcutMemoryLength == 5)
    #expect(values.fuzzyMatchEnabled == true)
    #expect(values.resultOrder == .mru)
  }

  // MARK: Private

  private func decode(_ text: String) -> Result<DecodedConfiguration, ConfigDecodeError> {
    AppConfiguration.decode(Data(text.utf8))
  }

}
