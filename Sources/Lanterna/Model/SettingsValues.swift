/// What the settings UI shows and changes, as one value.
///
/// A UI-layer snapshot of the seven user-facing settings. Persistence and
/// validation stay with `ValidConfiguration`; this only carries the live
/// values between the window and the application delegate.
struct SettingsValues: Equatable, Sendable {
    var appearanceMode: AppearanceMode
    var displayModes: DisplayModes
    var romajiScope: RomajiScope
    /// Whether Lanterna starts at login. Absent in the file means off.
    var launchAtLogin: Bool

    /// The values for a missing or invalid file: follow the system, park
    /// the special kinds as usual, match kanji readings as well, stay
    /// off the login items.
    static let defaults = SettingsValues(
        appearanceMode: .system,
        displayModes: .defaults,
        romajiScope: .kanaKanji,
        launchAtLogin: false
    )

    /// The values for one run: present keys win, absent keys mean
    /// the defaults.
    static func effective(from config: ValidConfiguration) -> SettingsValues {
        SettingsValues(
            appearanceMode: AppearanceMode.effective(from: config),
            displayModes: DisplayModes.effective(from: config),
            romajiScope: RomajiScope.effective(from: config),
            launchAtLogin: config.launchAtLogin ?? false
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
        return config
    }
}
