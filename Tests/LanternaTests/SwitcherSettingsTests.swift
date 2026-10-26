import Foundation
@testable import Lanterna
import Testing

/// The switcher sections in the file and on the way back out: what each
/// shape reads as, what an unreadable item falls back to, and which shape
/// a save takes. Decoding is read here through `decode` into effective
/// values; saving through `configuration` into encoded text.
struct SwitcherSettingsTests {

  // MARK: Internal

  @Test
  func absentSectionsReadAsLongStandingDefaults() throws {
    let decoded = try #require(decode("{}").successValue)
    let values = SettingsValues.effective(from: decoded.config)

    #expect(values.mainSwitcher == .mainDefaults)
    #expect(values.parallelSwitcher.windowScope == .frontApp)
    #expect(values.parallelOverrides == .defaults)
    #expect(values.hasSwitchersSection == false)
    #expect(decoded.config.hasSwitchersSection == false)
    #expect(decoded.switcherNotes.isEmpty)
  }

  @Test
  func emptyParallelSectionMeansFrontAppAndOn() throws {
    let decoded = try #require(decode(#"{"version": 1, "switchers": {"parallel": {}}}"#).successValue)
    let values = SettingsValues.effective(from: decoded.config)

    #expect(values.parallelSwitcher.windowScope == .frontApp)
    #expect(values.parallelOverrides.isEnabled)
    #expect(values.hasSwitchersSection)
    #expect(decoded.switcherNotes.isEmpty)
  }

  @Test
  func parallelInheritFollowsMain() throws {
    let decoded = try #require(decode(
      #"{"version": 1, "windowScope": "frontApp", "switchers": {"parallel": {"windowScope": "inherit"}}}"#
    ).successValue)
    let values = SettingsValues.effective(from: decoded.config)

    #expect(values.mainSwitcher.windowScope == .frontApp)
    #expect(values.parallelSwitcher.windowScope == .frontApp)
    #expect(values.parallelOverrides.windowScope == .follow)
  }

  @Test
  func mainWinsOverTopLevelWithNote() throws {
    let decoded = try #require(decode(
      #"{"version": 1, "minimizedMode": "hide", "switchers": {"main": {"minimizedMode": "show"}}}"#
    ).successValue)
    let values = SettingsValues.effective(from: decoded.config)

    #expect(values.mainSwitcher.displayModes.minimized == .show)
    #expect(decoded.switcherNotes.contains(
      "top-level minimizedMode is unused; switchers.main.minimizedMode wins"
    ))
  }

  @Test
  func mainInheritFallsBackToTopLevelWithNote() throws {
    let decoded = try #require(decode(
      #"{"version": 1, "minimizedMode": "hide", "switchers": {"main": {"minimizedMode": "inherit"}}}"#
    ).successValue)
    let values = SettingsValues.effective(from: decoded.config)

    #expect(values.mainSwitcher.displayModes.minimized == .hide)
    #expect(decoded.switcherNotes.contains(where: {
      $0.contains("switchers.main.minimizedMode") && $0.contains("top-level key")
    }))
  }

  @Test
  func parallelInvalidFallsBackWithNote() throws {
    let decoded = try #require(decode(
      #"{"version": 1, "switchers": {"parallel": {"minimizedMode": "bogus", "enabled": "yes"}}}"#
    ).successValue)
    let values = SettingsValues.effective(from: decoded.config)

    #expect(values.parallelOverrides.minimizedMode == .follow)
    #expect(values.parallelOverrides.isEnabled)
    #expect(decoded.switcherNotes.contains(where: { $0.contains("switchers.parallel.minimizedMode") }))
    #expect(decoded.switcherNotes.contains(where: { $0.contains("switchers.parallel.enabled") }))
  }

  @Test
  func parallelEnabledInheritReadsAsOnWithNote() throws {
    let decoded = try #require(decode(
      #"{"version": 1, "switchers": {"parallel": {"enabled": "inherit"}}}"#
    ).successValue)

    #expect(decoded.config.parallelOverrides.isEnabled)
    #expect(decoded.switcherNotes.contains(where: { $0.contains("switchers.parallel.enabled") }))
  }

  @Test
  func topLevelInheritInvalidatesTheFile() {
    #expect(decode(#"{"version": 1, "windowScope": "inherit"}"#).failureValue == .invalidValue(key: "windowScope"))
  }

  @Test
  func misplacedSectionKeysInvalidateTheFile() {
    #expect(decode(#"{"version": 1, "switchers": {"windowScope": "allApps"}}"#)
      .failureValue == .invalidValue(key: "switchers.windowScope"))
    #expect(decode(#"{"version": 1, "switchers": {"main": {"enabled": false}}}"#)
      .failureValue == .invalidValue(key: "switchers.main.enabled"))
    #expect(decode(#"{"version": 1, "switchers": {"parallel": {"bogus": 1}}}"#)
      .failureValue == .invalidValue(key: "switchers.parallel.bogus"))
    #expect(decode(#"{"version": 1, "switchers": 1}"#)
      .failureValue == .invalidValue(key: "switchers"))
    #expect(decode(#"{"version": 1, "switchers": {"main": 1}}"#)
      .failureValue == .invalidValue(key: "switchers.main"))
    #expect(decode(#"{"version": 1, "switchers": {"parallel": 1}}"#)
      .failureValue == .invalidValue(key: "switchers.parallel"))
  }

  @Test
  func sharedKeysInSectionsAreIgnoredWithNotes() throws {
    let shared: [(key: String, spelled: String)] = [
      ("appearanceMode", #""appearanceMode": "dark""#),
      ("romajiScope", #""romajiScope": "kana""#),
      ("launchAtLogin", #""launchAtLogin": true"#),
      ("saveLogsToDisk", #""saveLogsToDisk": false"#),
      ("updateCheckEnabled", #""updateCheckEnabled": true"#),
      ("updateChannel", #""updateChannel": "beta""#),
      ("exclusions", #""exclusions": [{"app": "x", "titlePattern": "y"}]"#),
      ("shortcutMemoryLength", #""shortcutMemoryLength": 3"#),
      ("keybindings", #""keybindings": {"commit": [{"keyCode": 36, "modifiers": []}]}"#),
      ("sampleCount", #""sampleCount": 2"#),
      ("stopMonitorEvery", #""stopMonitorEvery": 3"#),
      ("rowOrder", #""rowOrder": []"#),
      ("groupNames", #""groupNames": {"1": "Work"}"#),
      ("groupAssignments", #""groupAssignments": []"#),
    ]
    let mainEntries = shared.map(\.spelled).joined(separator: ", ")
    let parallelEntries = shared.map(\.spelled).joined(separator: ", ")
    let decoded = try #require(decode(
      #"{"version": 1, "shortcutMemoryLength": 4, "switchers": {"main": {\#(mainEntries)}, "parallel": {\#(parallelEntries)}}}"#
    ).successValue)
    let values = SettingsValues.effective(from: decoded.config)

    #expect(values.shortcutMemoryLength == 4)
    #expect(values.mainSwitcher.displayModes == .defaults)
    for key in shared.map(\.key) {
      #expect(decoded.switcherNotes.contains(
        "switchers.main.\(key) is shared by both switchers; write it at the top level"
      ), "for main.\(key)")
      #expect(decoded.switcherNotes.contains(
        "switchers.parallel.\(key) is shared by both switchers; write it at the top level"
      ), "for parallel.\(key)")
    }
  }

  @Test
  func retiredKeyInSectionsIsIgnoredWithNote() throws {
    let decoded = try #require(decode(
      #"{"version": 1, "switchers": {"main": {"logLevel": "debug"}, "parallel": {"logLevel": "debug"}}}"#
    ).successValue)

    #expect(decoded.switcherNotes.contains("switchers.main.logLevel is no longer used and was ignored"))
    #expect(decoded.switcherNotes.contains("switchers.parallel.logLevel is no longer used and was ignored"))
  }

  @Test
  func invalidMainFallsBackToTopLevel() throws {
    let decoded = try #require(decode(
      #"{"version": 1, "minimizedMode": "hide", "switchers": {"main": {"minimizedMode": "bogus"}}}"#
    ).successValue)
    let values = SettingsValues.effective(from: decoded.config)

    #expect(values.mainSwitcher.displayModes.minimized == .hide)
    #expect(decoded.switcherNotes.contains(where: {
      $0.contains("switchers.main.minimizedMode") && $0.contains("top-level key")
    }))
  }

  @Test
  func invalidMainWithoutTopLevelFallsBackToDefault() throws {
    let decoded = try #require(decode(
      #"{"version": 1, "switchers": {"main": {"minimizedMode": "bogus"}}}"#
    ).successValue)
    let values = SettingsValues.effective(from: decoded.config)

    #expect(values.mainSwitcher.displayModes.minimized == .separateAtBottom)
    #expect(decoded.switcherNotes.contains(where: {
      $0.contains("switchers.main.minimizedMode") && $0.contains("the default")
    }))
  }

  @Test
  func mainSpellsOnlyNonDefaults() throws {
    var values = SettingsValues.defaults
    values.windowScope = .frontApp
    values.displayModes.minimized = .show
    let text = try encode(values, diskHasSections: false, changed: true)

    #expect(text.contains(#""switchers": {"#))
    #expect(text.contains(#""main": {"#))
    #expect(text.contains(#""minimizedMode": "show""#))
    #expect(text.contains(#""windowScope": "frontApp""#))
    #expect(!text.contains(#""windowScope": "allApps""#))
    // The spelled items leave the top level: no duplicate keys.
    #expect(text.components(separatedBy: "\"minimizedMode\"").count == 2)
    #expect(text.components(separatedBy: "\"windowScope\"").count == 2)

    let reread = try #require(decode(text).successValue)
    let reloaded = SettingsValues.effective(from: reread.config)
    #expect(reloaded.mainSwitcher == values.mainSwitcher)
  }

  @Test
  func everySwitcherItemSurvivesSaveAndLoad() throws {
    var values = SettingsValues.defaults
    values.windowScope = .frontApp
    values.displayModes = DisplayModes(
      otherSpace: .hide,
      hiddenApp: .show,
      minimized: .hide,
      fullscreen: .separateAtBottom,
      windowlessApp: .show
    )
    values.grouping.placements = [
      .otherSpace: .withinGroup,
      .hiddenApp: .withinGroup,
      .minimized: .withinGroup,
      .fullscreen: .withinGroup,
      .windowlessApp: .withinGroup,
    ]
    values.parallelOverrides = ParallelOverrides(
      windowScope: .own(.allApps),
      otherSpaceMode: .own(.separateAtBottom),
      hiddenAppMode: .own(.hide),
      minimizedMode: .own(.show),
      fullscreenMode: .own(.hide),
      windowlessAppMode: .own(.separateAtBottom),
      otherSpacePlacement: .own(.endOfList),
      hiddenAppPlacement: .own(.endOfList),
      minimizedPlacement: .own(.endOfList),
      fullscreenPlacement: .own(.endOfList),
      windowlessAppPlacement: .own(.endOfList),
      isEnabled: false
    )
    let text = try encode(values, diskHasSections: false, changed: true)

    let reread = try #require(decode(text).successValue)
    let reloaded = SettingsValues.effective(from: reread.config)
    #expect(reloaded.mainSwitcher == values.mainSwitcher)
    #expect(reloaded.parallelOverrides == values.parallelOverrides)
    #expect(reloaded.parallelSwitcher == values.parallelSwitcher)
  }

  @Test
  func panelLookKeysInSectionsAreIgnoredWithNotes() throws {
    let entries = Self.sharedPanelKeys.map(\.spelled).joined(separator: ", ")
    let decoded = try #require(decode(
      #"{"version": 1, "textScale": 1.25, "showDelayMs": 150, "grouping": "bySpace", "#
        + #""switchers": {"main": {\#(entries)}, "parallel": {\#(entries)}}}"#
    ).successValue)
    let values = SettingsValues.effective(from: decoded.config)

    #expect(values.textScale == .large)
    #expect(values.showDelayMs == 150)
    #expect(values.grouping.mode == .bySpace)
    #expect(values.displayTarget == .primary)
    #expect(values.fuzzyMatchEnabled)
    #expect(values.parallelOverrides == .defaults)
    for key in Self.sharedPanelKeys.map(\.key) {
      #expect(decoded.switcherNotes.contains(
        "switchers.main.\(key) is shared by both switchers; write it at the top level"
      ), "for main.\(key)")
      #expect(decoded.switcherNotes.contains(
        "switchers.parallel.\(key) is shared by both switchers; write it at the top level"
      ), "for parallel.\(key)")
    }
  }

  @Test
  func panelLookKeysStayTopLevelWhenSectioned() throws {
    var values = SettingsValues.defaults
    values.textScale = .large
    values.showDelayMs = 150
    values.grouping.mode = .bySpace
    values.hintsMode = .numbers
    values.windowScope = .frontApp
    let text = try encode(values, diskHasSections: false, changed: true)

    #expect(text.contains(#""main": {"#))
    #expect(text.contains(#""windowScope": "frontApp""#))
    let config = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    #expect(config["textScale"] as? Double == 1.25)
    #expect(config["showDelayMs"] as? Double == 150)
    #expect(config["grouping"] as? String == "bySpace")
    #expect(config["hintsMode"] as? String == "numbers")
    let main = try #require((config["switchers"] as? [String: Any])?["main"] as? [String: Any])
    #expect(Set(main.keys) == ["windowScope"])
  }

  @Test
  func parallelWithOnlySharedKeysSpellsNothing() throws {
    let decoded = try #require(decode(
      #"{"version": 1, "switchers": {"parallel": {"displayTarget": "cursor"}}}"#
    ).successValue)
    let values = SettingsValues.effective(from: decoded.config)

    #expect(AppConfiguration.spelledParallelSection(values.parallelOverrides).isEmpty)
    let text = try encode(values, diskHasSections: false, changed: false)
    #expect(!text.contains("\"switchers\""))
  }

  @Test
  func unrelatedSaveKeepsTopLevelShape() throws {
    var values = SettingsValues.defaults
    values.exclusions = [ExclusionEntry(app: "x", titlePattern: "y")]
    let text = try encode(values, diskHasSections: false, changed: false)

    #expect(!text.contains("\"switchers\""))
    #expect(text.contains("\"exclusions\""))
  }

  @Test
  func topLevelItemMovesToMainOnSave() throws {
    let decoded = try #require(decode(
      #"{"version": 1, "minimizedMode": "hide", "switchers": {"parallel": {"minimizedMode": "show"}}}"#
    ).successValue)
    let values = SettingsValues.effective(from: decoded.config)
    // The disk holds sections while the values were loaded section-less
    // in shape: saving an unrelated change keeps the sectioned shape and
    // moves the top-level item into main.
    let text = try encode(values, diskHasSections: true, changed: false)

    #expect(text.contains(#""main": {"#))
    #expect(text.contains(#""minimizedMode": "hide""#))
    #expect(text.components(separatedBy: "\"minimizedMode\"").count == 3)
  }

  @Test
  func handAddedSectionsKeptOnUnrelatedSave() throws {
    let decoded = try #require(decode(
      #"{"version": 1, "switchers": {"parallel": {"minimizedMode": "show"}}}"#
    ).successValue)
    var values = SettingsValues.effective(from: decoded.config)
    values.exclusions = [ExclusionEntry(app: "x", titlePattern: "y")]
    let text = try encode(values, diskHasSections: true, changed: false)

    #expect(text.contains(#""parallel": {"#))
    #expect(text.contains(#""minimizedMode": "show""#))
    #expect(text.contains("\"exclusions\""))
  }

  @Test
  func missingDiskWithDefaultParallelWritesTopLevel() throws {
    let text = try encode(SettingsValues.defaults, diskHasSections: false, changed: false)

    #expect(!text.contains("\"switchers\""))
  }

  @Test
  func parallelInheritAloneSpellsSwitchers() throws {
    var values = SettingsValues.defaults
    values.parallelOverrides.windowScope = .follow
    let text = try encode(values, diskHasSections: false, changed: false)

    #expect(text.contains(#""parallel": {"#))
    #expect(text.contains(#""windowScope": "inherit""#))
  }

  @Test
  func disabledParallelSurvivesReplacement() throws {
    var values = SettingsValues.defaults
    values.parallelOverrides.isEnabled = false
    values.parallelOverrides.minimizedMode = .own(.show)
    // The second save of an invalid-file replacement carries no change:
    // the values already equal the live ones, and the disk is still
    // invalid. The spelled parallel keys alone keep the sectioned shape.
    let text = try encode(values, diskHasSections: false, changed: false)

    #expect(text.contains(#""enabled": false"#))
    #expect(text.contains(#""minimizedMode": "show""#))
    let reread = try #require(decode(text).successValue)
    let reloaded = SettingsValues.effective(from: reread.config)
    #expect(reloaded.parallelOverrides.isEnabled == false)
    #expect(reloaded.parallelSwitcher.displayModes.minimized == .show)
  }

  @Test
  func schemaParity() throws {
    let schema = try schemaDocument()
    let properties = try #require(schema["properties"] as? [String: Any])
    let switchers = try #require(properties["switchers"] as? [String: Any])
    #expect(switchers["additionalProperties"] as? Bool == false)
    let sections = try #require(switchers["properties"] as? [String: Any])
    let main = try #require((sections["main"] as? [String: Any])?["properties"] as? [String: Any])
    let parallel = try #require((sections["parallel"] as? [String: Any])?["properties"] as? [String: Any])
    let fileKeys = Set(AppConfiguration.knownKeys).subtracting(["version", "switchers"])
    #expect(Set(main.keys) == fileKeys)
    #expect(Set(parallel.keys) == fileKeys.union(["enabled"]))
    let listKeys: Set = [
      "windowScope",
      "otherSpaceMode",
      "hiddenAppMode",
      "minimizedMode",
      "fullscreenMode",
      "windowlessAppMode",
      "otherSpacePlacement",
      "hiddenAppPlacement",
      "minimizedPlacement",
      "fullscreenPlacement",
      "windowlessAppPlacement",
    ]
    #expect(AppConfiguration.switcherPanelKeys == listKeys)
    let current = { (section: [String: Any]) in
      Set(section.compactMap { key, fragment in
        (fragment as? [String: Any])?["deprecated"] as? Bool == true ? nil : key
      })
    }
    #expect(current(main) == listKeys)
    #expect(current(parallel) == listKeys.union(["enabled"]))
  }

  @Test
  func schemaParallelAcceptsInherit() throws {
    let schema = try schemaDocument()
    let properties = try #require(schema["properties"] as? [String: Any])
    let switchers = try #require(properties["switchers"] as? [String: Any])
    let sections = try #require(switchers["properties"] as? [String: Any])
    let main = try #require((sections["main"] as? [String: Any])?["properties"] as? [String: Any])
    let parallel = try #require((sections["parallel"] as? [String: Any])?["properties"] as? [String: Any])
    let mainScope = try #require(main["windowScope"] as? [String: Any])
    #expect(mainScope["oneOf"] == nil)
    let parallelScope = try #require(parallel["windowScope"] as? [String: Any])
    let options = try #require(parallelScope["oneOf"] as? [Any])
    #expect(options.count == 2)
    #expect(options.contains(where: { ($0 as? [String: Any])?["const"] as? String == "inherit" }))
    let enabled = try #require(parallel["enabled"] as? [String: Any])
    #expect(enabled["type"] as? String == "boolean")
    #expect((sections["parallel"] as? [String: Any])?["additionalProperties"] as? Bool == false)
  }

  // MARK: Private

  /// The panel's look, place, delay, gestures, ordering, matching, and
  /// grouping: shared by both switchers, so a section ignores them.
  private static let sharedPanelKeys: [(key: String, spelled: String)] = [
    ("resultOrder", #""resultOrder": "score""#),
    ("fuzzyMatchEnabled", #""fuzzyMatchEnabled": false"#),
    ("listWindowsOnAllSpaces", #""listWindowsOnAllSpaces": true"#),
    ("grouping", #""grouping": "manual""#),
    ("groupCount", #""groupCount": 3"#),
    ("groupHeadingStyle", #""groupHeadingStyle": "name""#),
    ("displayTarget", #""displayTarget": "cursor""#),
    ("panelWidth", #""panelWidth": 1.2"#),
    ("panelRows", #""panelRows": 12"#),
    ("textScale", #""textScale": 1.0"#),
    ("showDelayMs", #""showDelayMs": 0"#),
    ("hintsMode", #""hintsMode": "numbers""#),
    ("numberJump", #""numberJump": true"#),
    ("numberReorder", #""numberReorder": true"#),
    ("numberScope", #""numberScope": "allRows""#),
    ("hoverSelect", #""hoverSelect": true"#),
    ("scrollSelect", #""scrollSelect": true"#),
  ]

  private func decode(_ text: String) -> Result<DecodedConfiguration, ConfigDecodeError> {
    AppConfiguration.decode(Data(text.utf8))
  }

  private func encode(
    _ values: SettingsValues,
    diskHasSections: Bool,
    changed: Bool
  ) throws -> String {
    let config = values.configuration(
      version: 1,
      sampleCount: nil,
      stopMonitorEverySeconds: nil,
      diskHasSwitcherSections: diskHasSections,
      switcherSettingsChanged: changed
    )
    return try #require(String(bytes: AppConfiguration.encode(config), encoding: .utf8))
  }

  private func schemaDocument() throws -> [String: Any] {
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("config")
      .appendingPathComponent("config-schema.json")
    let data = try Data(contentsOf: url)
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

}
