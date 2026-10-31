import Foundation
@testable import Lanterna
import Testing

// MARK: - FastSearchConfigTests

/// The two Fast Search keys in the settings file: absent means off, only
/// what differs from the default is written, an unknown modifier is left
/// out on its own, and the switcher sections leave both alone.
@MainActor
struct FastSearchConfigTests {

  // MARK: Internal

  @Test
  func absentKeysReadAsOff() throws {
    let decoded = try #require(decode(#"{"version": 1}"#).successValue)
    let values = SettingsValues.effective(from: decoded.config)
    #expect(values.fastSearchModifiers.isEmpty)
    #expect(values.typingStartsFiltering == false)
  }

  @Test
  func modifiersAndTheTypingSwitchReadThrough() throws {
    let decoded = try #require(decode(
      #"{"version": 1, "fastSearchModifiers": ["rightCommand", "fn"], "typingStartsFiltering": true}"#
    ).successValue)
    let values = SettingsValues.effective(from: decoded.config)
    #expect(values.fastSearchModifiers == [.fn, .rightCommand])
    #expect(values.typingStartsFiltering == true)
    #expect(decoded.fastSearchModifierIssues.isEmpty)
  }

  @Test
  func anUnknownOrNonStringEntryIsLeftOutOnItsOwn() throws {
    let decoded = try #require(decode(
      #"{"version": 1, "fastSearchModifiers": ["fn", "hyper", 3, "capsLock"]}"#
    ).successValue)
    #expect(SettingsValues.effective(from: decoded.config).fastSearchModifiers == [.fn, .capsLock])
    #expect(decoded.fastSearchModifierIssues.map(\.diagnosticsLine) == [
      #"fast search modifier skipped (unknown value "hyper"): fastSearchModifiers[1]"#,
      "fast search modifier skipped (not a string): fastSearchModifiers[2]",
    ])
  }

  @Test
  func aRepeatedEntryCountsOnce() throws {
    let decoded = try #require(decode(#"{"version": 1, "fastSearchModifiers": ["fn", "fn"]}"#).successValue)
    #expect(decoded.config.fastSearchModifiers == [.fn])
    #expect(decoded.fastSearchModifierIssues.isEmpty)
  }

  @Test
  func aValueOfTheWrongTypeInvalidatesTheFile() {
    #expect(decode(#"{"version": 1, "fastSearchModifiers": "fn"}"#)
      .failureValue == .invalidValue(key: "fastSearchModifiers"))
    #expect(decode(#"{"version": 1, "typingStartsFiltering": "yes"}"#)
      .failureValue == .invalidValue(key: "typingStartsFiltering"))
  }

  @Test
  func onlyWhatDiffersFromTheDefaultIsWrittenInTheFixedOrder() throws {
    var values = SettingsValues.defaults
    values.fastSearchModifiers = [.rightOption, .capsLock, .fn]
    values.typingStartsFiltering = true
    let text = try encode(values)

    #expect(text.contains(#""fastSearchModifiers": ["fn", "capsLock", "rightOption"]"#))
    #expect(text.contains(#""typingStartsFiltering": true"#))
    let decoded = try #require(decode(text).successValue)
    #expect(SettingsValues.effective(from: decoded.config) == values)

    let plain = try encode(SettingsValues.defaults)
    #expect(!plain.contains("fastSearchModifiers"))
    #expect(!plain.contains("typingStartsFiltering"))
  }

  @Test
  func sectionKeysAreIgnoredWithNotes() throws {
    let decoded = try #require(decode(
      #"{"version": 1, "switchers": {"main": {"fastSearchModifiers": ["fn"]}, "parallel": {"typingStartsFiltering": true}}}"#
    ).successValue)

    let values = SettingsValues.effective(from: decoded.config)
    #expect(values.fastSearchModifiers.isEmpty)
    #expect(values.typingStartsFiltering == false)
    #expect(decoded.switcherNotes.contains(
      "switchers.main.fastSearchModifiers is shared by both switchers; write it at the top level"
    ))
    #expect(decoded.switcherNotes.contains(
      "switchers.parallel.typingStartsFiltering is shared by both switchers; write it at the top level"
    ))
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
