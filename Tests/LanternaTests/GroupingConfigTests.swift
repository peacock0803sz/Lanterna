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

  /// Grouping and the placements read when present, stay out of the file
  /// at their defaults, and anything outside their words invalidates it.
  @Test
  func groupingAndPlacementsRoundTrip() throws {
    let absent = try #require(decode("{\"version\": 1}").successValue)
    #expect(SettingsValues.effective(from: absent.config).grouping == GroupingPolicy())
    let text = "{\"version\": 1, \"grouping\": \"bySpace\", \"minimizedPlacement\": \"withinGroup\", "
      + "\"windowlessAppPlacement\": \"endOfList\"}"
    let present = try #require(decode(text).successValue)
    let grouping = SettingsValues.effective(from: present.config).grouping
    #expect(grouping.mode == .bySpace)
    #expect(grouping.placement(of: .minimized) == .withinGroup)
    #expect(grouping.placement(of: .hiddenApp) == .endOfList)
    var values = SettingsValues.defaults
    let unchanged = values.configuration(version: 1, sampleCount: nil, stopMonitorEverySeconds: nil)
    #expect(unchanged.grouping == nil)
    #expect(unchanged.subgroupPlacements.isEmpty)
    values.grouping = grouping
    let saved = values.configuration(version: 1, sampleCount: nil, stopMonitorEverySeconds: nil)
    let written = try #require(String(bytes: AppConfiguration.encode(saved), encoding: .utf8))
    #expect(written.contains("\"grouping\": \"bySpace\""))
    #expect(written.contains("\"minimizedPlacement\": \"withinGroup\""))
    #expect(!written.contains("windowlessAppPlacement"))
    #expect(AppConfiguration.decode(AppConfiguration.encode(saved)).successValue?.config == saved)
  }

  @Test(arguments: [
    ("grouping", "\"bySpaces\""),
    ("grouping", "true"),
    ("hiddenAppPlacement", "\"inside\""),
    ("fullscreenPlacement", "1"),
  ])
  func anUnknownGroupingWordInvalidatesTheFile(key: String, value: String) {
    #expect(decode("{\"version\": 1, \"\(key)\": \(value)}").failureValue == .invalidValue(key: key))
  }

  /// The manual group keys read and write back, keeping names and
  /// assignments past the count, and leaving defaults out of the file.
  @Test
  func manualGroupsRoundTrip() throws {
    let text = "{\"version\": 1, \"grouping\": \"manual\", \"groupCount\": 2, \"groupHeadingStyle\": \"name\", "
      + "\"groupNames\": {\"1\": \"Work\", \"3\": \"Later\"}, "
      + "\"groupAssignments\": [{\"bundleID\": \"com.apple.Safari\", \"group\": 1}, {\"bundleID\": \"x.y\", \"group\": 3}]}"
    let decoded = try #require(decode(text).successValue)
    let grouping = SettingsValues.effective(from: decoded.config).grouping
    #expect(grouping.groupCount == 2)
    #expect(grouping.headingStyle == .name)
    #expect(grouping.names == [1: "Work", 3: "Later"])
    #expect(grouping.assignments == [
      GroupAssignment(bundleID: "com.apple.Safari", group: 1),
      GroupAssignment(bundleID: "x.y", group: 3),
    ])
    #expect(grouping.group(forBundleID: "x.y") == 1)
    var values = SettingsValues.defaults
    values.grouping = grouping
    let saved = values.configuration(version: 1, sampleCount: nil, stopMonitorEverySeconds: nil)
    #expect(AppConfiguration.decode(AppConfiguration.encode(saved)).successValue?.config == saved)
    let written = try #require(String(bytes: AppConfiguration.encode(saved), encoding: .utf8))
    #expect(written.contains("\"3\": \"Later\""))
    #expect(written.contains("\"bundleID\": \"x.y\", \"group\": 3"))
    let plain = SettingsValues.defaults.configuration(version: 1, sampleCount: nil, stopMonitorEverySeconds: nil)
    let plainText = try #require(String(bytes: AppConfiguration.encode(plain), encoding: .utf8))
    #expect(!plainText.contains("group"))
  }

  /// A bad count, style or name refuses the file, like any other bad value.
  @Test(arguments: [
    ("groupCount", "0"),
    ("groupCount", "10"),
    ("groupHeadingStyle", "\"title\""),
    ("groupNames", "{\"0\": \"Zero\"}"),
    ("groupNames", "{\"01\": \"Padded\"}"),
    ("groupNames", "{\"1\": 1}"),
    ("groupNames", "[\"Work\"]"),
    ("groupAssignments", "{\"bundleID\": \"a\"}"),
  ])
  func aBadManualKeyInvalidatesTheFile(key: String, value: String) {
    #expect(decode("{\"version\": 1, \"\(key)\": \(value)}").failureValue == .invalidValue(key: key))
  }

  /// One bad or repeated assignment costs only itself, and says why.
  @Test
  func badAssignmentsAreLeftOutOneByOne() throws {
    let text = "{\"version\": 1, \"groupAssignments\": ["
      + "{\"bundleID\": \"com.apple.mail\", \"group\": 2}, "
      + "{\"bundleID\": \"\", \"group\": 1}, "
      + "{\"bundleID\": \"COM.APPLE.MAIL\", \"group\": 1}, "
      + "{\"bundleID\": \"far\", \"group\": 12}, "
      + "\"oops\"]}"
    let decoded = try #require(decode(text).successValue)
    #expect(decoded.config.groupAssignments == [GroupAssignment(bundleID: "com.apple.mail", group: 2)])
    #expect(decoded.groupAssignmentIssues.map(\.diagnosticsLine) == [
      "group assignment skipped (unreadable entry): groupAssignments[1]",
      "group assignment skipped (duplicate bundleID COM.APPLE.MAIL): groupAssignments[2]",
      "group assignment skipped (group out of range 12): groupAssignments[3]",
      "group assignment skipped (unreadable entry): groupAssignments[4]",
    ])
  }

  /// Saving drops blank rows and a row repeating an earlier application.
  @Test
  func savingKeepsTheFirstOfEachApplication() {
    var values = SettingsValues.defaults
    values.grouping.assignments = [
      GroupAssignment(bundleID: "com.apple.mail", group: 2),
      GroupAssignment(bundleID: " ", group: 1),
      GroupAssignment(bundleID: "Com.Apple.Mail", group: 1),
    ]
    let saved = values.configuration(version: 1, sampleCount: nil, stopMonitorEverySeconds: nil)
    #expect(saved.groupAssignments == [GroupAssignment(bundleID: "com.apple.mail", group: 2)])
  }

  // MARK: Private

  private func decode(_ text: String) -> Result<DecodedConfiguration, ConfigDecodeError> {
    AppConfiguration.decode(Data(text.utf8))
  }

}
