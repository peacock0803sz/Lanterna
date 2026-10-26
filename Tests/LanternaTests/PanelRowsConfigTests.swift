import Foundation
@testable import Lanterna
import Testing

// MARK: - PanelRowsConfigTests

struct PanelRowsConfigTests {

  // MARK: Internal

  @Test
  func absentKeyMeansTheStandardLimit() throws {
    let decoded = try #require(decode(#"{"version": 1}"#).successValue)
    #expect(decoded.config.panelRows == nil)
    #expect(decoded.panelRowsIssue == nil)
    #expect(PanelRows.effective(from: decoded.config) == .standard)
    #expect(PanelRows.standard.count == 10)
  }

  @Test
  func everyCountInRangeDecodes() throws {
    for count in PanelRows.range {
      let decoded = try #require(decode(#"{"version": 1, "panelRows": \#(count)}"#).successValue)
      #expect(decoded.panelRowsIssue == nil, "for \(count)")
      #expect(PanelRows.effective(from: decoded.config).count == count, "for \(count)")
    }
  }

  @Test
  func countsOutOfRangeFallBackWithANote() throws {
    for text in ["4", "31", "0", "-3"] {
      let decoded = try #require(decode(#"{"version": 1, "panelRows": \#(text)}"#).successValue)
      #expect(decoded.config.panelRows == nil, "for \(text)")
      #expect(decoded.panelRowsIssue == "panelRows is not a valid value; using 10", "for \(text)")
      #expect(PanelRows.effective(from: decoded.config) == .standard, "for \(text)")
    }
  }

  @Test
  func nonIntegerValuesFallBackWithANote() throws {
    for text in ["12.5", "\"12\"", "true", "null", "[12]"] {
      let decoded = try #require(decode(#"{"version": 1, "panelRows": \#(text)}"#).successValue)
      #expect(decoded.config.panelRows == nil, "for \(text)")
      #expect(decoded.panelRowsIssue == "panelRows is not a valid value; using 10", "for \(text)")
      #expect(PanelRows.effective(from: decoded.config) == .standard, "for \(text)")
    }
  }

  /// An explicit standard count reads as absent, so saving omits it the
  /// way absent does.
  @Test
  func explicitStandardCountReadsAsAbsent() throws {
    let decoded = try #require(decode(#"{"version": 1, "panelRows": 10}"#).successValue)
    #expect(decoded.config.panelRows == nil)
    #expect(decoded.panelRowsIssue == nil)
  }

  @Test
  func keyEncodesOnlyWhenSetAndRoundTrips() throws {
    var config = ValidConfiguration(version: 1, sampleCount: nil, stopMonitorEverySeconds: nil)
    let bare = try #require(String(data: AppConfiguration.encode(config), encoding: .utf8))
    #expect(!bare.contains("panelRows"))
    config.panelRows = 18
    let encoded = try #require(String(data: AppConfiguration.encode(config), encoding: .utf8))
    #expect(encoded.contains(#""panelRows": 18"#))
    let roundTripped = try #require(AppConfiguration.decode(Data(encoded.utf8)).successValue)
    #expect(roundTripped.panelRowsIssue == nil)
    #expect(PanelRows.effective(from: roundTripped.config).count == 18)
  }

  @Test
  func settingsSaveTheCountAndOmitTheDefault() throws {
    var values = SettingsValues.defaults
    let standard = values.configuration(version: 1, sampleCount: nil, stopMonitorEverySeconds: nil)
    #expect(standard.panelRows == nil)
    values.panelRows = try #require(PanelRows(count: 24))
    let saved = values.configuration(version: 1, sampleCount: nil, stopMonitorEverySeconds: nil)
    #expect(saved.panelRows == 24)
  }

  @Test
  func decodedCountReachesSettingsAndLaunchOptions() throws {
    let decoded = try #require(decode(#"{"version": 1, "panelRows": 7}"#).successValue)
    #expect(SettingsValues.effective(from: decoded.config).panelRows.count == 7)
    let options = AppConfiguration.effectiveOptions(file: decoded.config, cli: LaunchArguments.Options())
    #expect(options.panelRows.count == 7)
  }

  @Test
  func theRangeRejectsCountsOutsideIt() {
    #expect(PanelRows(count: 4) == nil)
    #expect(PanelRows(count: 5)?.count == 5)
    #expect(PanelRows(count: 30)?.count == 30)
    #expect(PanelRows(count: 31) == nil)
  }

  // MARK: Private

  private func decode(_ text: String) -> Result<DecodedConfiguration, ConfigDecodeError> {
    AppConfiguration.decode(Data(text.utf8))
  }

}
