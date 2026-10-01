import Foundation
@testable import Lanterna
import Testing

/// The log keys of the config file: the retired level key, read past so
/// it never costs the rest of the file, and the switch for saving logs.
/// Apart from `ConfigStoreTests`, which stands near the length limit.
struct LogConfigTests {

  // MARK: Internal

  @Test(arguments: [#""debug""#, #""WARN""#, "true", "3", "null", "[1]"])
  func theRetiredLevelKeyKeepsTheRestOfTheFile(value: String) throws {
    let decoded = try #require(
      decode(#"{"version": 1, "logLevel": \#(value), "launchAtLogin": true}"#).successValue
    )
    #expect(decoded.config.launchAtLogin == true)
    #expect(decoded.deprecatedKeys == ["logLevel"])
  }

  @Test
  func aFileWithoutTheRetiredKeyNamesNone() throws {
    let decoded = try #require(decode(#"{"version": 1}"#).successValue)
    #expect(decoded.deprecatedKeys.isEmpty)
  }

  @Test
  func savingLogsIsAbsentByDefaultAndReadWhenPresent() throws {
    #expect(try #require(decode(#"{"version": 1}"#).successValue).config.saveLogsToDisk == nil)
    #expect(try #require(decode(#"{"version": 1, "saveLogsToDisk": false}"#).successValue).config.saveLogsToDisk == false)
    #expect(SettingsValues.effective(from: ValidConfiguration(version: 1, sampleCount: nil, stopMonitorEverySeconds: nil))
      .saveLogsToDisk)
  }

  @Test
  func aSavingLogsValueThatIsNotABooleanFallsBackAsAWhole() {
    #expect(decode(#"{"version": 1, "saveLogsToDisk": 1}"#).failureValue == .invalidValue(key: "saveLogsToDisk"))
  }

  // MARK: Private

  private func decode(_ text: String) -> Result<DecodedConfiguration, ConfigDecodeError> {
    AppConfiguration.decode(Data(text.utf8))
  }

}
