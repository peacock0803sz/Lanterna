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
            version: DisplayedVersion(full: AppVersion.full),
            permissionState: launchPermissionState,
            opener: SystemSettings.open,
            appearanceMode: currentValues.appearanceMode,
            onChange: { [weak self] values in
                guard let self else { return }
                switch self.applySettings(values, replacingInvalidFile: false) {
                case .saved:
                    break
                case .needsConfirmation:
                    self.confirmInvalidFileReplacement(for: values)
                case let .failed(reason):
                    self.noticeSaveFailure(reason: reason)
                }
                self.settingsWindow?.appearance = values.appearanceMode.nsAppearance
            }
        )
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        settingsWindow = window
    }

    /// Asks before replacing an invalid settings file.
    ///
    /// The change is already live when this runs; only the file waits.
    /// Approval saves the current values over the invalid file, while
    /// cancelling leaves the disk alone for this run.
    private func confirmInvalidFileReplacement(for values: SettingsValues) {
        guard let window = settingsWindow else { return }
        let alert = NSAlert()
        alert.messageText = "Replace invalid settings file?"
        alert.informativeText =
            "The settings file on disk is invalid. Replacing it discards the current file contents."
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn {
                if case let .failed(reason) = self?.applySettings(values, replacingInvalidFile: true) {
                    self?.noticeSaveFailure(reason: reason)
                }
            }
        }
    }

    /// Tells the user a save failed without touching anything.
    ///
    /// The live values stay as applied; only the disk falls behind, so
    /// the notice is informational and the next change tries again.
    private func noticeSaveFailure(reason: String) {
        guard let window = settingsWindow else { return }
        let alert = NSAlert()
        alert.messageText = "Could not save settings"
        alert.informativeText =
            "The settings file could not be written (\(reason)). The change applies for this run only."
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window) { _ in }
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
        let scopeChanged = values.romajiScope != currentValues.romajiScope
        currentValues = values
        panel?.displayModes = values.displayModes
        panel?.appearance = values.appearanceMode.nsAppearance
        presenter?.displayModes = values.displayModes
        guideWindows?.update(appearanceMode: values.appearanceMode)
        // Reopening rebuilds the engine, so only a scope change pays
        // for it. Appearance and display tweaks leave matching alone.
        if scopeChanged {
            _ = RomajiMatcher.open(
                scope: values.romajiScope,
                dictionaryDirectory: lanternaDirectory,
                tableDirectory: tableDirectory
            )
        }
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
