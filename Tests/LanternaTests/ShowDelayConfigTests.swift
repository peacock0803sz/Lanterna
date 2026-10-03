import Foundation
@testable import Lanterna
import Testing

// MARK: - ShowDelayConfigTests

struct ShowDelayConfigTests {

  // MARK: Internal

  @Test
  func showDelayIsAbsentByDefault() throws {
    let decoded = try #require(decode("{\"version\": 1}").successValue)
    #expect(decoded.config.showDelayMs == nil)
    #expect(decoded.showDelayIssue == nil)
  }

  @Test
  func showDelayDecodesCounts() throws {
    for text in ["150", "275", "1000"] {
      let decoded = try #require(
        decode("{\"version\": 1, \"showDelayMs\": \(text)}").successValue
      )
      #expect(decoded.config.showDelayMs == Double(text), "for \(text)")
      #expect(decoded.showDelayIssue == nil, "for \(text)")
    }
  }

  @Test
  func zeroReadsAsAbsent() throws {
    for text in [
      "{\"version\": 1, \"showDelayMs\": 0}",
      "{\"version\": 1, \"showDelayMs\": 0.0}",
    ] {
      let decoded = try #require(decode(text).successValue)
      #expect(decoded.config.showDelayMs == nil, "for \(text)")
      #expect(decoded.showDelayIssue == nil, "for \(text)")
    }
  }

  @Test
  func pastTheMaximumClampsWithANote() throws {
    let decoded = try #require(decode("{\"version\": 1, \"showDelayMs\": 5000}").successValue)
    #expect(decoded.config.showDelayMs == 1000)
    #expect(decoded.showDelayIssue == "showDelayMs is above the maximum; using 1000")
  }

  @Test
  func negativeFallsBackWithANote() throws {
    let decoded = try #require(decode("{\"version\": 1, \"showDelayMs\": -1}").successValue)
    #expect(decoded.config.showDelayMs == 150)
    #expect(decoded.showDelayIssue == "showDelayMs is not a valid value; using 150")
  }

  @Test
  func unreadableFallsBackWithANote() throws {
    for text in [
      "{\"version\": 1, \"showDelayMs\": \"soon\"}",
      "{\"version\": 1, \"showDelayMs\": true}",
    ] {
      let decoded = try #require(decode(text).successValue)
      #expect(decoded.config.showDelayMs == 150, "for \(text)")
      #expect(
        decoded.showDelayIssue == "showDelayMs is not a valid value; using 150",
        "for \(text)"
      )
    }
  }

  @Test
  func unknownKeysStillFailTheFile() {
    #expect(decode("{\"version\": 1, \"showDelayMs\": 150, \"frobnicate\": 1}").failureValue != nil)
  }

  /// A spelled count round-trips; absent and zero stay omitted on save.
  @Test
  func showDelayRoundTrip() throws {
    let decoded = try #require(
      decode("{\"version\": 1, \"showDelayMs\": 250}").successValue
    )
    let text = try #require(
      String(bytes: AppConfiguration.encode(decoded.config), encoding: .utf8)
    )
    #expect(text.contains("\"showDelayMs\": 250"))
    let omitted = try #require(
      decode("{\"version\": 1}").successValue
    )
    let omittedText = try #require(
      String(bytes: AppConfiguration.encode(omitted.config), encoding: .utf8)
    )
    #expect(!omittedText.contains("showDelayMs"))
  }

  /// A clamped count saves the clamped value it read as.
  @Test
  func clampedDelaySavesClamped() throws {
    let decoded = try #require(
      decode("{\"version\": 1, \"showDelayMs\": 5000}").successValue
    )
    let text = try #require(
      String(bytes: AppConfiguration.encode(decoded.config), encoding: .utf8)
    )
    #expect(text.contains("\"showDelayMs\": 1000"))
  }

  /// The settings snapshot carries the validated count through.
  @Test
  func settingsValuesCarryTheCount() throws {
    let decoded = try #require(
      decode("{\"version\": 1, \"showDelayMs\": 250}").successValue
    )
    #expect(SettingsValues.effective(from: decoded.config).showDelayMs == 250)
    let absent = try #require(decode("{\"version\": 1}").successValue)
    #expect(SettingsValues.effective(from: absent.config).showDelayMs == nil)
  }

  // MARK: Private

  private func decode(_ text: String) -> Result<DecodedConfiguration, ConfigDecodeError> {
    AppConfiguration.decode(Data(text.utf8))
  }

}
