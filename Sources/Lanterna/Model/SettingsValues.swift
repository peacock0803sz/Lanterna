import Logging

/// What the settings UI shows and changes, as one value.
///
/// A UI-layer snapshot of the eight user-facing settings. Persistence and
/// validation stay with `ValidConfiguration`; this only carries the live
/// values between the window and the application delegate.
struct SettingsValues: Equatable, Sendable {
    var appearanceMode: AppearanceMode
    var displayModes: DisplayModes
    var romajiScope: RomajiScope
    /// Whether Lanterna checks for newer releases. Absent in the file means off.
    var updateCheckEnabled: Bool
    /// Which releases the check covers. Absent in the file means stable only.
    var updateChannel: UpdateChannel
    /// Whether Lanterna starts at login. Absent in the file means off.
    var launchAtLogin: Bool
    /// The raw exclusion entries. Empty means no exclusions.
    var exclusions: [ExclusionEntry]
    /// How many characters of a query the shortcut memory covers. Absent
    /// in the file means 5. 0 means off.
    var shortcutMemoryLength: Int
    /// Whether subsequence queries match as well as substrings. Absent in
    /// the file means on.
    var fuzzyMatchEnabled: Bool
    /// The raw ordering word. Absent in the file means "mru". Kept as a
    /// string like the file; the enum arrives with T018.
    var resultOrder: String

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
        exclusions: [],
        shortcutMemoryLength: 5,
        fuzzyMatchEnabled: true,
        resultOrder: "mru"
    )

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
            exclusions: config.exclusions ?? [],
            shortcutMemoryLength: config.shortcutMemoryLength ?? 5,
            fuzzyMatchEnabled: config.fuzzyMatchEnabled ?? true,
            resultOrder: config.resultOrder ?? "mru"
        )
    }

    /// The validated form for saving. The version and the debug keys ride
    /// along from the caller, so a save never drops what the UI hides.
    func configuration(
        version: Int,
        sampleCount: Int?,
        stopMonitorEverySeconds: Int?,
        logLevel: Logger.Level? = nil
    ) -> ValidConfiguration {
        var config = ValidConfiguration(
            version: version,
            sampleCount: sampleCount,
            stopMonitorEverySeconds: stopMonitorEverySeconds,
            logLevel: logLevel
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
        // Empty stays absent, so clearing the list removes the key.
        config.exclusions = exclusions.isEmpty ? nil : exclusions
        config.shortcutMemoryLength = shortcutMemoryLength
        config.fuzzyMatchEnabled = fuzzyMatchEnabled
        config.resultOrder = resultOrder
        return config
    }
}
