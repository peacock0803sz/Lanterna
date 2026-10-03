import Foundation
@testable import Lanterna
import Testing

// MARK: - NumberJumpConfigTests

struct NumberJumpConfigTests {

  // MARK: Internal

  @Test
  func keysAreAbsentByDefault() throws {
    let decoded = try #require(decode("{\"version\": 1}").successValue)
    #expect(decoded.config.numberJump == nil)
    #expect(decoded.config.numberReorder == nil)
    #expect(decoded.config.numberScope == nil)
    #expect(decoded.config.rowOrder == [])
    let values = SettingsValues.effective(from: decoded.config)
    #expect(values.numberJump == false)
    #expect(values.numberReorder == false)
    #expect(values.numberScope == .windows)
    let options = AppConfiguration.effectiveOptions(
      file: decoded.config,
      cli: LaunchArguments.Options()
    )
    #expect(options.numberJump == false)
    #expect(options.numberReorder == false)
  }

  @Test
  func trueValuesDecode() throws {
    let decoded = try #require(decode(
      "{\"version\": 1, \"numberJump\": true, \"numberReorder\": true, \"numberScope\": \"allRows\"}"
    ).successValue)
    #expect(decoded.config.numberJump == true)
    #expect(decoded.config.numberReorder == true)
    #expect(decoded.config.numberScope == .allRows)
    let values = SettingsValues.effective(from: decoded.config)
    #expect(values.numberJump == true)
    #expect(values.numberReorder == true)
    #expect(values.numberScope == .allRows)
  }

  @Test
  func invalidValuesFailTheFile() {
    let cases: [(String, ConfigDecodeError)] = [
      ("{\"version\": 1, \"numberJump\": \"yes\"}", .invalidValue(key: "numberJump")),
      ("{\"version\": 1, \"numberJump\": 1}", .invalidValue(key: "numberJump")),
      ("{\"version\": 1, \"numberReorder\": \"yes\"}", .invalidValue(key: "numberReorder")),
      ("{\"version\": 1, \"numberScope\": \"everywhere\"}", .invalidValue(key: "numberScope")),
      ("{\"version\": 1, \"numberScope\": 1}", .invalidValue(key: "numberScope")),
      ("{\"version\": 1, \"rowOrder\": {}}", .invalidValue(key: "rowOrder")),
    ]
    for (text, expected) in cases {
      #expect(decode(text).failureValue == expected, "for \(text)")
    }
  }

  @Test
  func rowOrderDecodes() throws {
    let decoded = try #require(decode(
      "{\"version\": 1, \"rowOrder\": [{\"group\": 1, \"keys\": [\"com.example.app\\nFront\"]}]}"
    ).successValue)
    #expect(decoded.config.rowOrder == [RowOrderEntry(group: 1, keys: ["com.example.app\nFront"])])
    #expect(decoded.rowOrderIssues == [])
  }

  @Test
  func singleBadRowOrderEntryIsSkipped() throws {
    let decoded = try #require(decode(
      "{\"version\": 1, \"rowOrder\": [{\"group\": 99, \"keys\": [\"x\\ny\"]}, {\"group\": 1, \"keys\": [\"a\\nb\"]}]}"
    ).successValue)
    #expect(decoded.config.rowOrder == [RowOrderEntry(group: 1, keys: ["a\nb"])])
    #expect(decoded.rowOrderIssues.map(\.diagnosticsLine) == [
      "row order skipped (unreadable entry): rowOrder[0]"
    ])
  }

  @Test
  func roundTripsEnabledValues() throws {
    var config = ValidConfiguration(version: 1, sampleCount: nil, stopMonitorEverySeconds: nil)
    config.numberJump = true
    config.numberReorder = true
    config.numberScope = .allRows
    config.rowOrder = [RowOrderEntry(group: 1, keys: ["com.example.app\nFront"])]
    let text = try #require(
      String(bytes: AppConfiguration.encode(config), encoding: .utf8)
    )
    #expect(text.contains("\"numberJump\": true"))
    #expect(text.contains("\"numberReorder\": true"))
    #expect(text.contains("\"numberScope\": \"allRows\""))
    #expect(text.contains("\"rowOrder\""))
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
    #expect(config.numberJump == nil)
    #expect(config.numberReorder == nil)
    #expect(config.numberScope == nil)
    #expect(config.rowOrder == [])
  }

  // MARK: Private

  private func decode(_ text: String) -> Result<DecodedConfiguration, ConfigDecodeError> {
    AppConfiguration.decode(Data(text.utf8))
  }

}
