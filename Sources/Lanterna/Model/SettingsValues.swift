/// What the settings UI shows and changes, as one value.
///
/// A UI-layer snapshot of the eight user-facing settings. Persistence and
/// validation stay with `ValidConfiguration`; this only carries the live
/// values between the window and the application delegate.
struct SettingsValues: Equatable, Sendable {

  // MARK: Internal

  /// The values for a missing or invalid file: follow the system, park
  /// the special kinds as usual, match kanji readings as well, stay
  /// off the login items.
  static let defaults = SettingsValues(
    appearanceMode: .system,
    displayModes: .defaults,
    romajiScope: .kanaKanji,
    updateCheckEnabled: false,
    updateChannel: .stable,
    launchAtLogin: false,
    saveLogsToDisk: true,
    exclusions: [],
    shortcutMemoryLength: 5,
    fuzzyMatchEnabled: true,
    resultOrder: .mru,
    textScale: .standard,
    displayTarget: .primary,
    hoverSelect: false,
    scrollSelect: false,
    numberJump: false,
    numberReorder: false,
    numberScope: .windows,
    rowOrder: .none,
    panelWidth: .standard,
    showDelayMs: nil,
    windowScope: .allApps,
    grouping: GroupingPolicy(),
    keyBindings: .defaults,
    keyBindingSection: nil,
    loadedKeyBindings: .defaults
  )

  var appearanceMode: AppearanceMode
  var displayModes: DisplayModes
  var romajiScope: RomajiScope
  /// Whether Lanterna checks for newer releases. Absent in the file means off.
  var updateCheckEnabled: Bool
  /// Which releases the check covers. Absent in the file means stable only.
  var updateChannel: UpdateChannel
  /// Whether Lanterna starts at login. Absent in the file means off.
  var launchAtLogin: Bool
  /// Whether each launch's log lines are kept on disk. Absent in the file
  /// means on.
  var saveLogsToDisk: Bool
  /// The raw exclusion entries. Empty means no exclusions.
  var exclusions: [ExclusionEntry]
  /// How many characters of a query the shortcut memory covers. Absent
  /// in the file means 5. 0 means off.
  var shortcutMemoryLength: Int
  /// Whether subsequence queries match as well as substrings. Absent in
  /// the file means on.
  var fuzzyMatchEnabled: Bool
  /// The ordering the narrowed rows draw in. Absent in the file means
  /// recent use first.
  var resultOrder: SearchOrdering
  /// The panel text and icon scale step. Absent in the file means
  /// the standard step, the base, unscaled sizes.
  var textScale: TextScaleLevel
  /// Which display the panel opens on. Absent in the file means
  /// the menu-bar display.
  var displayTarget: DisplayTarget
  /// Whether hovering a row moves the selection. Absent in the file
  /// means off.
  var hoverSelect: Bool
  /// Whether scrolling moves the selection. Absent in the file
  /// means off.
  var scrollSelect: Bool
  /// Whether holding a modifier and pressing a row number jumps to
  /// that row. Absent in the file means off.
  var numberJump: Bool
  /// Whether moving the selected row by key works in grouped lists.
  /// Absent in the file means off.
  var numberReorder: Bool
  /// Which rows row numbers cover. Absent in the file means window
  /// rows alone.
  var numberScope: NumberScope
  /// The hand-arranged row orders shadowing the drawn order. Absent
  /// in the file means no overrides.
  var rowOrder: ManualRowOrder
  /// The panel width step. Absent in the file means the standard
  /// step, the current width.
  var panelWidth: PanelWidth
  /// The panel show delay in milliseconds. Nil means off.
  var showDelayMs: Double?
  /// Which applications' rows each appearance starts on. Absent in the
  /// file means every application.
  var windowScope: WindowScope
  /// How the list groups its rows. Absent in the file means one list,
  /// with every parked section at the end.
  var grouping: GroupingPolicy
  /// The resolved key bindings. Never partial: absent in the file
  /// means all defaults.
  var keyBindings: KeyBindingTable
  /// The section as spelled in the file, kept so an unrelated save
  /// does not drop a customization that lost resolution.
  var keyBindingSection: [KeyBindingAction: [RawKeyBinding]]?
  /// The table as loaded, for telling an untouched round trip apart
  /// from an edited table.
  var loadedKeyBindings: KeyBindingTable

  /// The values for one run: present keys win, absent keys mean
  /// the defaults.
  static func effective(from config: ValidConfiguration) -> SettingsValues {
    SettingsValues(
      appearanceMode: AppearanceMode.effective(from: config),
      displayModes: DisplayModes.effective(from: config),
      romajiScope: RomajiScope.effective(from: config),
      updateCheckEnabled: config.updateCheckEnabled ?? false,
      updateChannel: UpdateChannel(rawValue: config.updateChannel ?? "stable") ?? .stable,
      launchAtLogin: config.launchAtLogin ?? false,
      saveLogsToDisk: config.saveLogsToDisk ?? true,
      exclusions: config.exclusions ?? [],
      shortcutMemoryLength: config.shortcutMemoryLength ?? 5,
      fuzzyMatchEnabled: config.fuzzyMatchEnabled ?? true,
      resultOrder: SearchOrdering.effective(from: config),
      textScale: TextScaleLevel.effective(from: config),
      displayTarget: DisplayTarget.effective(from: config),
      hoverSelect: config.hoverSelect ?? false,
      scrollSelect: config.scrollSelect ?? false,
      numberJump: config.numberJump ?? false,
      numberReorder: config.numberReorder ?? false,
      numberScope: NumberScope.effective(from: config),
      rowOrder: ManualRowOrder(entries: config.rowOrder),
      panelWidth: PanelWidth.effective(from: config),
      showDelayMs: ShowDelay.effective(config.showDelayMs).value,
      windowScope: config.windowScope ?? .allApps,
      grouping: GroupingPolicy(
        mode: config.grouping ?? .none,
        placements: config.subgroupPlacements,
        groupCount: config.groupCount ?? 1,
        headingStyle: config.groupHeadingStyle ?? .number,
        names: config.groupNames,
        assignments: config.groupAssignments
      ),
      keyBindings: config.keyBindings,
      keyBindingSection: config.keyBindingSection,
      loadedKeyBindings: config.keyBindings
    )
  }

  /// The validated form for saving. The version and the debug keys ride
  /// along from the caller, so a save never drops what the UI hides.
  func configuration(
    version: Int,
    sampleCount: Int?,
    stopMonitorEverySeconds: Int?
  ) -> ValidConfiguration {
    var config = ValidConfiguration(
      version: version,
      sampleCount: sampleCount,
      stopMonitorEverySeconds: stopMonitorEverySeconds
    )
    config.appearanceMode = appearanceMode
    config.otherSpaceMode = displayModes.otherSpace
    config.hiddenAppMode = displayModes.hiddenApp
    config.minimizedMode = displayModes.minimized
    config.fullscreenMode = displayModes.fullscreen
    config.windowlessAppMode = displayModes.windowlessApp
    config.romajiScope = romajiScope
    config.launchAtLogin = launchAtLogin
    config.updateCheckEnabled = updateCheckEnabled
    config.updateChannel = updateChannel.rawValue
    // Empty stays absent, so clearing the list removes the key.
    config.exclusions = exclusions.isEmpty ? nil : exclusions
    // Defaults stay absent, so a later default change reaches saved files.
    let defaults = SettingsValues.defaults
    if saveLogsToDisk != defaults.saveLogsToDisk {
      config.saveLogsToDisk = saveLogsToDisk
    }
    if shortcutMemoryLength != defaults.shortcutMemoryLength {
      config.shortcutMemoryLength = shortcutMemoryLength
    }
    if fuzzyMatchEnabled != defaults.fuzzyMatchEnabled {
      config.fuzzyMatchEnabled = fuzzyMatchEnabled
    }
    if resultOrder != defaults.resultOrder {
      config.resultOrder = resultOrder.rawValue
    }
    // Standard stays absent, so the scaffold keeps reading as standard.
    if textScale != .standard {
      config.textScale = textScale.factor
    }
    if displayTarget != defaults.displayTarget {
      config.displayTarget = displayTarget
    }
    if panelWidth != .standard {
      config.panelWidth = panelWidth.factor
    }
    if hoverSelect != defaults.hoverSelect {
      config.hoverSelect = hoverSelect
    }
    if scrollSelect != defaults.scrollSelect {
      config.scrollSelect = scrollSelect
    }
    if numberJump != defaults.numberJump {
      config.numberJump = numberJump
    }
    if numberReorder != defaults.numberReorder {
      config.numberReorder = numberReorder
    }
    if numberScope != defaults.numberScope {
      config.numberScope = numberScope
    }
    // Absent stays absent, so clearing the order removes the key.
    if rowOrder != .none {
      config.rowOrder = rowOrder.entries()
    }
    // Off stays absent, so a later default change reaches saved files.
    if let showDelayMs, showDelayMs > 0 {
      config.showDelayMs = showDelayMs
    }
    if windowScope != defaults.windowScope {
      config.windowScope = windowScope
    }
    if grouping.mode != .none {
      config.grouping = grouping.mode
    }
    config.subgroupPlacements = grouping.placements.filter { $0.value != .endOfList }
    if grouping.groupCount != 1 {
      config.groupCount = grouping.groupCount
    }
    if grouping.headingStyle != .number {
      config.groupHeadingStyle = grouping.headingStyle
    }
    config.groupNames = grouping.names.filter { !$0.value.isEmpty }
    config.groupAssignments = Self.savedAssignments(grouping.assignments)
    config.keyBindings = keyBindings
    if keyBindings == loadedKeyBindings {
      config.keyBindingSection = keyBindingSection
    } else {
      config.keyBindingSection = Self.customizedSection(keyBindings)
    }
    return config
  }

  // MARK: Private

  /// The assignments for saving: rows with a bundle identifier, trimmed,
  /// the first of each identifier ignoring case, in the order shown. A
  /// row the editor shows as already assigned is left out here.
  private static func savedAssignments(_ assignments: [GroupAssignment]) -> [GroupAssignment] {
    var seen = Set<String>()
    return assignments.compactMap { entry in
      let trimmed = GroupAssignment.trimmed(entry.bundleID)
      guard !trimmed.isEmpty, seen.insert(GroupAssignment.matchKey(trimmed)).inserted else { return nil }
      return GroupAssignment(bundleID: trimmed, group: entry.group)
    }
  }

  /// The customized section for saving: actions differing from their
  /// defaults, as the file spells them. Empty actions and an empty
  /// section read as absent, so defaults never reach the disk.
  private static func customizedSection(
    _ table: KeyBindingTable
  ) -> [KeyBindingAction: [RawKeyBinding]]? {
    let customized = KeyBindingAction.allCases.filter { action in
      let keys = table[action]
      return !keys.isEmpty && keys != KeyBindingTable.defaults[action]
    }
    guard !customized.isEmpty else { return nil }
    return Dictionary(uniqueKeysWithValues: customized.map { action in
      (action, table[action].map {
        RawKeyBinding(keyCode: Int($0.keyCode), modifiers: $0.modifierWords)
      })
    })
  }

}
