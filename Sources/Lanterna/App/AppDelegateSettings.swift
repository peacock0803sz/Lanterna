import AppKit
import Logging

/// Settings changes, split out when the delegate reached the file-length
/// limit. Launch keeps the handles; everything a change touches hangs
/// off them here.
extension AppDelegate {

  // MARK: Internal

  /// What the skipped-exclusions line carries beside its wording.
  var invalidExclusionContext: [String: ContextValue] {
    var context: [String: ContextValue] = ["issue": .string("invalid exclusion entries")]
    if let configFileURL {
      context["path"] = .string(configFileURL.path)
    }
    return context
  }

  /// Opens the settings window on the current values.
  ///
  /// Reopening takes a fresh snapshot: the window edits a copy, and
  /// every edit applies through the single path, so the screen and
  /// the file cannot drift apart. Confirmation and failure notices
  /// for saves join with the persistence work; until then the outcome
  /// only decides what reaches the disk.
  func openSettings() {
    // Close the held window first so reopening leaves exactly one.
    settingsWindow?.close()
    let window = SettingsWindow(
      values: currentValues,
      version: DisplayedVersion(full: AppVersion.full),
      permissionState: launchPermissionState,
      opener: SystemSettings.open,
      appearanceMode: currentValues.appearanceMode,
      onCheckNow: { [weak self] in self?.runUpdateCheck() },
      diagnostics: makeDiagnosticsDisplay(),
      launchSummary: Diagnostics.launchSummary,
      onChange: { [weak self] values in
        guard let self else { return }
        switch applySettings(values, replacingInvalidFile: false) {
        case .saved:
          break
        case .needsConfirmation:
          confirmInvalidFileReplacement(for: values)
        case .failed(let reason):
          noticeSaveFailure(reason: reason)
        }
        settingsWindow?.appearance = values.appearanceMode.nsAppearance
      }
    )
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    settingsWindow = window
  }

  /// Runs one manual update check from the General tab.
  ///
  /// The check runs off the panel paths: nothing here touches panel
  /// timing, and a failure stays a line in the General tab and in the
  /// diagnostics. The run never writes the settings file.
  func runUpdateCheck() {
    guard currentValues.updateCheckEnabled else { return }
    let channel = currentValues.updateChannel
    guard let display = settingsWindow?.checkDisplay else { return }
    guard !display.isChecking else { return }
    display.isChecking = true
    display.resultText = nil
    Task { [weak self, display] in
      let result = await UpdateCheck.perform(
        channel: channel,
        currentVersion: AppVersion.short,
        fetcher: LiveReleaseFetcher()
      )
      await MainActor.run { [weak self, display] in
        self?.finishUpdateCheck(result, channel: channel, display: display)
      }
    }
  }

  /// Compiles the exclusion entries and hands the rules to the panel
  /// and the presenter, so both judge the same rows out. Changed rules
  /// apply at once; unreadable entries are reported and skipped.
  func refreshExclusions(from entries: [ExclusionEntry]) {
    let compiled = WindowExclusion.compile(entries)
    panel?.exclusionRules = compiled.rules
    presenter?.exclusionRules = compiled.rules
    if compiled.invalid > 0 {
      Diagnostics.writeLine(LogLine(
        .info,
        .config,
        "ignored \(compiled.invalid) invalid exclusion entries",
        context: invalidExclusionContext
      ))
    }
  }

  /// Builds the panel and its presenter together, so the two judge the
  /// same rows out from the first appearance on.
  func makePanelAndPresenter(windowList: WindowListStore) -> (SwitcherPanel, PanelPresenter) {
    let compiled = WindowExclusion.compile(options.exclusionEntries)
    if compiled.invalid > 0 {
      Diagnostics.writeLine(LogLine(
        .info,
        .config,
        "ignored \(compiled.invalid) invalid exclusion entries",
        context: invalidExclusionContext
      ))
    }
    let panel = SwitcherPanel(
      displayModes: options.displayModes,
      exclusionRules: compiled.rules,
      appearanceMode: options.appearanceMode,
      searchSettings: options.searchSettings,
      textScale: options.textScale
    )
    let presenter = PanelPresenter(
      surface: panel,
      store: windowList,
      displayModes: options.displayModes,
      exclusionRules: compiled.rules,
      searchSettings: options.searchSettings,
      keyBindings: options.keyBindings,
      closesOnCommandRelease: { [weak self] in self?.monitor?.isMonitoring ?? false },
      switcher: OwnWindowSwitcher(wrapped: LiveWindowSwitcher())
    )
    presenter.windowScope = currentValues.windowScope
    return (panel, presenter)
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
    let checkContextChanged = values.updateCheckEnabled != currentValues.updateCheckEnabled
      || values.updateChannel != currentValues.updateChannel
    let exclusionsChanged = values.exclusions != currentValues.exclusions
    let keyBindingsChanged = values.keyBindings != currentValues.keyBindings
    let previousValues = currentValues
    currentValues = values
    if checkContextChanged {
      settingsWindow?.checkDisplay.resultText = nil
    }
    panel?.displayModes = values.displayModes
    panel?.appearance = values.appearanceMode.nsAppearance
    panel?.textScale = values.textScale
    let searchSettings = SearchSettings(
      fuzzyMatchEnabled: values.fuzzyMatchEnabled,
      shortcutMemoryLength: values.shortcutMemoryLength,
      ordering: values.resultOrder
    )
    panel?.searchSettings = searchSettings
    presenter?.displayModes = values.displayModes
    presenter?.searchSettings = searchSettings
    presenter?.windowScope = values.windowScope
    // Recompile exclusions only when the entries changed, so unrelated
    // tweaks leave the panel and presenter rules alone.
    if exclusionsChanged {
      refreshExclusions(from: values.exclusions)
    }
    // Reclaims the invocation keys and hands the panel the new
    // table, so a change answers at once; the save below keeps it.
    let valuesForSave = appliedKeyBindingValues(
      values,
      previous: previousValues,
      changed: keyBindingsChanged
    )
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
    // Keeps the login item with the toggle, apart from the save: the
    // change is live before the file catches up, and the next launch
    // heals whatever drift is left. A failure stays a diagnostics line.
    if
      let report = LaunchAtLogin.sync(
        desired: values.launchAtLogin,
        service: LaunchAtLogin.liveIfBundled()
      )
    {
      Diagnostics.writeLine(LogLine(report.level, .config, report.line))
    }
    return saveSettings(valuesForSave, replacingInvalidFile: replacingInvalidFile)
  }

  // MARK: Private

  /// Shows one finished check: the General tab always hears about it,
  /// and only a newer release also gets a dialog with a way to the
  /// releases page.
  private func finishUpdateCheck(
    _ result: UpdateCheckResult,
    channel: UpdateChannel,
    display: UpdateCheckDisplay
  ) {
    Diagnostics.writeLine(LogLine(.info, .config, UpdateCheck.diagnosticsLine(result, channel: channel)))
    guard settingsWindow?.checkDisplay === display else { return }
    display.isChecking = false
    switch result {
    case .found(let version, let pageURL):
      display.resultText = "A newer release (\(version)) is published."
      guard let window = settingsWindow else { return }
      let alert = NSAlert()
      alert.messageText = "A newer Lanterna release is available"
      alert.informativeText = "Version \(version) is published. "
        + "Downloading stays a manual step."
      alert.addButton(withTitle: "Open Releases")
      alert.addButton(withTitle: "Later")
      alert.beginSheetModal(for: window) { response in
        if response == .alertFirstButtonReturn {
          _ = SystemSettings.open(pageURL)
        }
      }

    case .upToDate:
      display.resultText = "Lanterna is up to date."

    case .failed(let reason):
      display.resultText = "The check did not finish (\(reason))."
    }
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
        if case .failed(let reason) = self?.applySettings(values, replacingInvalidFile: true) {
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

  /// The values to save after attempting the keybinding change. A total
  /// failure keeps the previous table live and on disk, so the panel
  /// still opens; partial failures keep the new table with warnings.
  private func appliedKeyBindingValues(
    _ values: SettingsValues,
    previous: SettingsValues,
    changed: Bool
  ) -> SettingsValues {
    guard changed else { return values }
    guard didApplyKeyBindings(values.keyBindings, previous: previous.keyBindings) else {
      return values
    }
    currentValues.keyBindings = previous.keyBindings
    currentValues.keyBindingSection = previous.keyBindingSection
    currentValues.loadedKeyBindings = previous.loadedKeyBindings
    var restored = values
    restored.keyBindings = previous.keyBindings
    restored.keyBindingSection = previous.keyBindingSection
    restored.loadedKeyBindings = previous.loadedKeyBindings
    return restored
  }

  /// Writes the current values to the file, keeping the debug keys
  /// the UI hides. Split out when `applySettings` stood at the
  /// length limit.
  private func saveSettings(
    _ values: SettingsValues,
    replacingInvalidFile: Bool
  ) -> SettingsSaveOutcome {
    guard let configFileURL else {
      return .failed(reason: "cannot resolve directory")
    }
    let preserved = preservedConfiguration()
    let config = values.configuration(
      version: AppConfiguration.currentVersion,
      sampleCount: preserved?.sampleCount,
      stopMonitorEverySeconds: preserved?.stopMonitorEverySeconds
    )
    return SettingsSaver.save(
      config,
      to: configFileURL,
      replacingInvalidFile: replacingInvalidFile
    )
  }

  /// Reclaims the invocation keys and hands the panel the new table.
  /// Answers whether the new table went live: a total failure keeps
  /// everything previous and puts the old keys back, so the panel
  /// still opens. Split out when `applySettings` stood at the
  /// length limit.
  private func didApplyKeyBindings(_ bindings: KeyBindingTable, previous: KeyBindingTable) -> Bool {
    hotkeys?.unregister()
    // The panel takes the table even with no manager, so a missing
    // manager never blocks what the panel shows.
    if hotkeys == nil {
      presenter?.keyBindings = bindings
      return true
    }
    guard let hotkeys else { return true }
    // The system's shortcuts come back first, so a combination the new
    // table no longer holds is not left switched off; the disable below
    // then takes only what the new table claimed.
    let restoreFailures = SystemSwitcherShortcuts.restore()
    if let line = SystemSwitcherShortcuts.summaryLine(restoring: restoreFailures) {
      Diagnostics.writeLine(LogLine(.warning, .hotkey, line))
    }
    let outcome = hotkeys.register(bindings: HotkeyBinding.bindings(for: bindings))
    Diagnostics.writeLine(LogLine(outcome.logLevel, .hotkey, outcome.summaryLine))
    for detail in hotkeys.refusedDetails {
      Diagnostics.writeLine(LogLine(.warning, .hotkey, detail))
    }
    // The panel takes the new table only once something answers for
    // it: a total failure keeps the previous table, which still opens.
    guard !outcome.isTotalFailure else {
      Diagnostics.writeLine(LogLine(.error, .hotkey, "new keybindings registered nothing; keeping the previous table"))
      hotkeys.unregister()
      let recovery = hotkeys.register(bindings: HotkeyBinding.bindings(for: previous))
      Diagnostics.writeLine(LogLine(recovery.logLevel, .hotkey, recovery.summaryLine))
      return false
    }
    presenter?.keyBindings = bindings
    let disabling = SystemSwitcherShortcuts.disable(outcome.registered)
    if let line = SystemSwitcherShortcuts.summaryLine(disabling: disabling) {
      Diagnostics.writeLine(LogLine(.warning, .hotkey, line))
    }
    return true
  }

  /// The debug keys the settings UI hides, as the disk file holds them.
  ///
  /// Anything unreadable means nothing to preserve: an invalid file is
  /// about to be confirmed away or rebuilt, and a missing one was never
  /// going to supply them.
  /// The on-disk configuration the settings window does not manage, read
  /// back so saving from the window does not drop it: the debug count and
  /// period, and the log level, which lives in the file alone.
  private func preservedConfiguration() -> ValidConfiguration? {
    guard
      let configFileURL,
      let data = try? Data(contentsOf: configFileURL),
      case .success(let decoded) = AppConfiguration.decode(data)
    else { return nil }
    return decoded.config
  }

}
