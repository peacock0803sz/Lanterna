import AppKit

/// Settings changes, split out when the delegate reached the file-length
/// limit. Launch keeps the handles; everything a change touches hangs
/// off them here.
extension AppDelegate {
    /// Opens the settings window on the current values.
    ///
    /// Reopening takes a fresh snapshot: the window edits a copy, and
    /// every edit applies through the single path, so the screen and
    /// the file cannot drift apart. Confirmation and failure notices
    /// for saves join with the persistence work; until then the outcome
    /// only decides what reaches the disk.
    func openSettings() {
        let window = SettingsWindow(
            values: currentValues,
            permissionState: launchPermissionState,
            opener: SystemSettings.open,
            appearanceMode: currentValues.appearanceMode,
            onChange: { [weak self] values in
                let outcome = self?.applySettings(values, replacingInvalidFile: false)
                self?.settingsWindow?.appearance = values.appearanceMode.nsAppearance
                _ = outcome
            }
        )
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        settingsWindow = window
    }

    /// Applies changed settings to the running app and saves them.
    ///
    /// Everything happens synchronously on the main thread, so a change
    /// is live before the settings control settles: there is no later
    /// pass that could leave the screen showing yesterday's values.
    /// The debug keys the UI hides are read back off the disk first, so
    /// saving never drops them.
    func applySettings(
        _ values: SettingsValues,
        replacingInvalidFile: Bool
    ) -> SettingsSaveOutcome {
        currentValues = values
        panel?.displayModes = values.displayModes
        panel?.appearance = values.appearanceMode.nsAppearance
        presenter?.displayModes = values.displayModes
        guideWindows?.update(appearanceMode: values.appearanceMode)
        _ = RomajiMatcher.open(
            scope: values.romajiScope,
            dictionaryDirectory: lanternaDirectory,
            tableDirectory: tableDirectory
        )
        guard let configFileURL else {
            return .failed(reason: "cannot resolve directory")
        }
        let (sampleCount, stopMonitorEvery) = preservedDebugKeys()
        let config = values.configuration(
            version: AppConfiguration.currentVersion,
            sampleCount: sampleCount,
            stopMonitorEverySeconds: stopMonitorEvery
        )
        return SettingsSaver.save(
            config,
            to: configFileURL,
            replacingInvalidFile: replacingInvalidFile
        )
    }

    /// The debug keys the settings UI hides, as the disk file holds them.
    ///
    /// Anything unreadable means nothing to preserve: an invalid file is
    /// about to be confirmed away or rebuilt, and a missing one was never
    /// going to supply them.
    private func preservedDebugKeys() -> (Int?, Int?) {
        guard let configFileURL,
              let data = try? Data(contentsOf: configFileURL),
              case let .success(decoded) = AppConfiguration.decode(data)
        else { return (nil, nil) }
        return (decoded.config.sampleCount, decoded.config.stopMonitorEverySeconds)
    }
}
