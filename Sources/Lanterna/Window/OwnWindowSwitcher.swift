import AppKit
import Darwin

/// Takes this process's own rows without the accessibility API.
///
/// Rows for this process's own windows travel the ordinary commit path, but
/// the activate step of the live switcher asks `NSRunningApplication` to
/// activate, which can refuse for this accessory-policy process and fail the
/// commit before any window is raised. This decorator takes those rows
/// itself: activating this process and raising one of its windows needs no
/// such ask.
///
/// Anything owned by another process is handed to the wrapped switcher
/// untouched.
struct OwnWindowSwitcher: WindowSwitching, Sendable {

  // MARK: Lifecycle

  /// The defaults talk to the real application object. Tests replace them
  /// with a script, so no suite puts a real window on screen.
  init(
    wrapped: any WindowSwitching,
    ownProcessIdentifier: pid_t = getpid(),
    activateApp: @escaping @MainActor @Sendable (Bool) -> Bool = Self.productionActivateApp,
    showWindow: @escaping @MainActor @Sendable (CGWindowID) -> Bool = Self.productionShowWindow
  ) {
    self.wrapped = wrapped
    self.ownProcessIdentifier = ownProcessIdentifier
    self.activateApp = activateApp
    self.showWindow = showWindow
  }

  // MARK: Internal

  func switchTo(_ target: ActivationTarget) -> ActivationOutcome {
    guard target.ownerProcessIdentifier == ownProcessIdentifier else {
      return wrapped.switchTo(target)
    }
    // The commit paths that reach this are on the main actor, so this
    // arrives on the main thread and the application object below may
    // be touched. Crossing back to the main actor here documents that
    // and verifies it at runtime: assumeIsolated traps if the call ever
    // comes from elsewhere.
    guard MainActor.assumeIsolated({ activateApp(true) }) else {
      return .failed(.other(reason: "activation refused"))
    }
    guard
      let windowID = target.id.windowID,
      MainActor.assumeIsolated({ showWindow(windowID) })
    else {
      return .failed(.windowGone)
    }
    return .switched
  }

  // MARK: Private

  /// Brings this process forward, answering whether it came forward.
  /// Main actor bound like the application object it talks to, so the
  /// default below reads as one call. Activation posts no refusal of its
  /// own, so the answer is read back off the application instead.
  private static let productionActivateApp: @MainActor @Sendable (Bool) -> Bool = { ignoringOtherApps in
    NSApp.activate(ignoringOtherApps: ignoringOtherApps)
    return NSApp.isActive
  }

  /// Raises one of this process's windows, answering whether it was
  /// there. The panel never counts: switching to the list is not
  /// switching through it.
  private static let productionShowWindow: @MainActor @Sendable (CGWindowID) -> Bool = { windowID in
    guard
      let window = NSApp.windows.first(where: {
        $0.windowNumber == Int(windowID) && !($0 is SwitcherPanel)
      })
    else { return false }
    if window.isMiniaturized {
      window.deminiaturize(nil)
    }
    window.makeKeyAndOrderFront(nil)
    return true
  }

  private let wrapped: any WindowSwitching
  private let ownProcessIdentifier: pid_t
  private let activateApp: @MainActor @Sendable (Bool) -> Bool
  private let showWindow: @MainActor @Sendable (CGWindowID) -> Bool

}
