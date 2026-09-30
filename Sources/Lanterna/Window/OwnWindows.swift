import AppKit

// MARK: - OwnWindows

/// Windows of this process the switcher lists, so an open settings,
/// guide, or version window is a keystroke away.
///
/// The enumerator only reads regular applications, and this process is
/// an accessory: without this source its own windows never become rows.
/// The floating panel itself is never listed: switching to the panel
/// would be switching to the list, not through it. Rows built here
/// travel the ordinary commit path; activating this process and raising
/// one of its windows needs no special case.
enum OwnWindows {
  /// One own window considered for listing, read off `NSApp`.
  struct Prospect: Equatable, Sendable {
    /// The window-server id, as `NSWindow.windowNumber` reports it.
    var number: Int
    var title: String
    var isTitled: Bool
    var isVisible: Bool
    var isMiniaturized: Bool
    /// True for the switcher panel, which must never list itself.
    var isPanel: Bool
    /// Whether the window is on the active Space, backing other-Space placement.
    var isOnActiveSpace: Bool
  }

  /// This process as a row owner: who the rows name and picture.
  struct Owner {
    var processIdentifier: pid_t
    var appName: String
    var bundleIdentifier: String?
    var isHidden: Bool
    var icon: NSImage
  }

  /// The prospects on screen now: titled, visible, non-panel windows
  /// of this process. Closed windows and the panel stay out.
  @MainActor
  static func currentProspects() -> [Prospect] {
    NSApp.windows.compactMap { window in
      guard window.isVisible, window.windowNumber > 0 else { return nil }
      let prospect = Prospect(
        number: window.windowNumber,
        title: window.title,
        isTitled: window.styleMask.contains(.titled),
        isVisible: window.isVisible,
        isMiniaturized: window.isMiniaturized,
        isPanel: window is SwitcherPanel,
        isOnActiveSpace: window.isOnActiveSpace
      )
      guard isListable(prospect) else { return nil }
      return prospect
    }
  }

  /// Whether a prospect becomes a row.
  static func isListable(_ prospect: Prospect) -> Bool {
    prospect.isTitled && prospect.isVisible && !prospect.isPanel
  }

  /// This process now, read off the running app.
  @MainActor
  static func currentOwner() -> Owner {
    Owner(
      processIdentifier: getpid(),
      appName: displayName(
        bundleName: Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String,
        processName: ProcessInfo.processInfo.processName,
        processIdentifier: getpid()
      ),
      bundleIdentifier: Bundle.main.bundleIdentifier,
      isHidden: NSApp.isHidden,
      icon: NSApp.applicationIconImage ?? AppIconResolver.placeholder
    )
  }

  /// Rows for the prospects, carrying this process as their owner.
  ///
  /// Own windows never go natively fullscreen, so that fact reads false
  /// the way missing information does elsewhere; Space placement follows
  /// the active-Space reading, negated into the row flag: never hiding,
  /// only placing.
  static func items(prospects: [Prospect], owner: Owner) -> [WindowItem] {
    prospects.filter(isListable).map { prospect in
      WindowItem(
        id: WindowItem.Identifier(windowID: CGWindowID(prospect.number)),
        ownerProcessIdentifier: owner.processIdentifier,
        appName: owner.appName,
        bundleIdentifier: owner.bundleIdentifier,
        windowTitle: prospect.title,
        kind: .standard,
        isMinimized: prospect.isMiniaturized,
        isHidden: owner.isHidden,
        isOnOtherSpace: !prospect.isOnActiveSpace,
        icon: owner.icon
      )
    }
  }

  /// This process as the rows name it: the bundle name, the process
  /// name, and only then the pid fallback the enumerator uses.
  static func displayName(
    bundleName: String?,
    processName: String,
    processIdentifier: pid_t
  ) -> String {
    if let bundleName, !bundleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return bundleName
    }
    if !processName.isEmpty {
      return processName
    }
    return "pid \(processIdentifier)"
  }
}

extension WindowListSnapshot {
  /// The snapshot with this process's rows appended.
  ///
  /// The counts move with the rows so the diagnostics line stays
  /// honest: one more application looked at, only when it brought
  /// windows.
  func includingOwnWindows(_ own: [WindowItem]) -> WindowListSnapshot {
    WindowListSnapshot(
      items: items + own,
      applicationCount: applicationCount + (own.isEmpty ? 0 : 1),
      gatheringDuration: gatheringDuration,
      skipped: skipped,
      droppedWithoutID: droppedWithoutID,
      gatheredAt: gatheredAt
    )
  }
}
