import Foundation
@testable import Lanterna
import Testing

/// What the keys deciding which rows the switcher lists, and how it
/// groups them, read as.
///
/// Decoding conventions live in `ConfigStoreTests`; these cover the new
/// keys: present values win, absent keys mean the defaults, and anything
/// outside the schema invalidates the whole file.
struct GroupingConfigTests {

  // MARK: Internal

  @Test
  func theScopeIsAbsentByDefault() throws {
    let decoded = try #require(decode("{\"version\": 1}").successValue)
    #expect(decoded.config.windowScope == nil)
    #expect(SettingsValues.effective(from: decoded.config).windowScope == .allApps)
  }

  @Test(arguments: [WindowScope.allApps, .frontApp])
  func theScopeDecodesWhenPresent(scope: WindowScope) throws {
    let decoded = try #require(decode("{\"version\": 1, \"windowScope\": \"\(scope.rawValue)\"}").successValue)
    #expect(decoded.config.windowScope == scope)
  }

  @Test(arguments: ["\"active\"", "\"FrontApp\"", "true", "1"])
  func anUnknownScopeInvalidatesTheFile(value: String) {
    let text = "{\"version\": 1, \"windowScope\": \(value)}"
    #expect(decode(text).failureValue == .invalidValue(key: "windowScope"))
  }

  /// The setting round-trips, and the default stays out of the file so a
  /// later change of default reaches saved files.
  @Test
  func theScopeSavesOnlyWhenChanged() throws {
    var values = SettingsValues.defaults
    let unchanged = values.configuration(version: 1, sampleCount: nil, stopMonitorEverySeconds: nil)
    #expect(unchanged.windowScope == nil)
    values.windowScope = .frontApp
    let changed = values.configuration(version: 1, sampleCount: nil, stopMonitorEverySeconds: nil)
    let text = try #require(String(bytes: AppConfiguration.encode(changed), encoding: .utf8))
    #expect(text.contains("\"windowScope\": \"frontApp\""))
    #expect(AppConfiguration.decode(AppConfiguration.encode(changed)).successValue?.config == changed)
  }

  /// The mode for applications with no window reads like the other modes,
  /// stays out by default, and is written with them on every save.
  @Test
  func theWindowlessModeReadsLikeTheOtherModes() throws {
    let absent = try #require(decode("{\"version\": 1}").successValue)
    #expect(absent.config.windowlessAppMode == nil)
    #expect(DisplayModes.effective(from: absent.config).windowlessApp == .hide)
    let present = try #require(decode("{\"version\": 1, \"windowlessAppMode\": \"separateAtBottom\"}").successValue)
    #expect(DisplayModes.effective(from: present.config).windowlessApp == .separateAtBottom)
    #expect(decode("{\"version\": 1, \"windowlessAppMode\": \"park\"}").failureValue == .invalidValue(key: "windowlessAppMode"))
    let saved = SettingsValues.defaults.configuration(version: 1, sampleCount: nil, stopMonitorEverySeconds: nil)
    let text = try #require(String(bytes: AppConfiguration.encode(saved), encoding: .utf8))
    #expect(text.contains("\"windowlessAppMode\": \"hide\""))
  }

  // MARK: Private

  private func decode(_ text: String) -> Result<DecodedConfiguration, ConfigDecodeError> {
    AppConfiguration.decode(Data(text.utf8))
  }

}
