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
    keepLogsAcrossLaunches: true,
    logRotation: .daily,
    logRetentionDays: 30,
    logDiskLimitGB: 5,
    exclusions: [],
    shortcutMemoryLength: 5,
    fuzzyMatchEnabled: true,
    resultOrder: .mru,
    textScale: .standard,
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
  /// Whether spilled archives stay on disk across launches. Absent in
  /// the file means kept.
  var keepLogsAcrossLaunches: Bool
  /// How often a launch starts a new spill file. Absent in the file
  /// means daily.
  var logRotation: LogRotation
  /// How long spill files are kept, in days. Absent in the file means
  /// thirty days.
  var logRetentionDays: Int
  /// The disk cap for spill files, in gigabytes. Absent in the file
  /// means five gigabytes.
  var logDiskLimitGB: Int
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
      keepLogsAcrossLaunches: config.keepLogsAcrossLaunches ?? true,
      logRotation: config.logRotation.flatMap(LogRotation.init(configWord:)) ?? .daily,
      logRetentionDays: config.logRetentionDays ?? 30,
      logDiskLimitGB: config.logDiskLimitGB ?? 5,
      exclusions: config.exclusions ?? [],
      shortcutMemoryLength: config.shortcutMemoryLength ?? 5,
      fuzzyMatchEnabled: config.fuzzyMatchEnabled ?? true,
      resultOrder: SearchOrdering.effective(from: config),
      textScale: TextScaleLevel.effective(from: config),
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
    config.romajiScope = romajiScope
    config.launchAtLogin = launchAtLogin
    config.updateCheckEnabled = updateCheckEnabled
    config.updateChannel = updateChannel.rawValue
    // Absent means the defaults, so defaults stay out of the file and a
    // later default change reaches saved files.
    let retentionDefaults = SettingsValues.defaults
    config.keepLogsAcrossLaunches = keepLogsAcrossLaunches == retentionDefaults.keepLogsAcrossLaunches
      ? nil
      : keepLogsAcrossLaunches
    config.logRotation = logRotation == retentionDefaults.logRotation ? nil : logRotation.configWord
    config.logRetentionDays = logRetentionDays == retentionDefaults.logRetentionDays ? nil : logRetentionDays
    config.logDiskLimitGB = logDiskLimitGB == retentionDefaults.logDiskLimitGB ? nil : logDiskLimitGB
    // Empty stays absent, so clearing the list removes the key.
    config.exclusions = exclusions.isEmpty ? nil : exclusions
    // Defaults stay absent, so a later default change reaches saved files.
    let defaults = SettingsValues.defaults
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
    config.keyBindings = keyBindings
    if keyBindings == loadedKeyBindings {
      config.keyBindingSection = keyBindingSection
    } else {
      config.keyBindingSection = Self.customizedSection(keyBindings)
    }
    return config
  }

  // MARK: Private

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
