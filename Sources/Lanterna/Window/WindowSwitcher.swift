import AppKit
import ApplicationServices

// MARK: - ActivationTarget

/// What a commit takes: the row it named, as identity, owner and names.
///
/// A value, not the row itself. `WindowItem` carries an `NSImage` and so is
/// neither `Equatable` nor `Sendable`, while switching needs only who owns
/// which window and what to call it on the log line. The names travel along
/// for the wording; nothing that decides is read off them.
struct ActivationTarget: Equatable, Sendable {
  let id: WindowItem.Identifier
  let ownerProcessIdentifier: pid_t
  let appName: String
  let displayTitle: String
}

// MARK: - ActivationFailure

/// Why a switch did not happen. The smallest vocabulary that tells the four
/// apart on the log line; anything else goes in `other` until it earns a case.
enum ActivationFailure: Equatable, Sendable {
  case windowGone
  case applicationGone
  case timedOut
  case other(reason: String)
}

// MARK: - ActivationOutcome

/// What trying a target came to.
enum ActivationOutcome: Equatable, Sendable {
  case switched
  case failed(ActivationFailure)
}

// MARK: - WindowSwitching

/// The one entrance the commit paths call. Takes a single target rather than
/// a list, so resolving off a fresher list at commit time has nowhere to go.
protocol WindowSwitching: Sendable {
  func switchTo(_ target: ActivationTarget) -> ActivationOutcome
}

// MARK: - LiveWindowSwitcher

/// Talks to the real accessibility API, in the order the contract pins down:
/// activate, unminimize, raise. Resolving (row to element) happens first and
/// is the shared resolver's, the way closing and minimizing resolve.
///
/// Every seam is a closure defaulting to the real call, so tests script
/// answers no live application can be asked to give. The shape follows
/// `AXApplicationWindowReader`, which separates its sends the same way.
struct LiveWindowSwitcher: WindowSwitching, Sendable {

  // MARK: Lifecycle

  /// The defaults talk to the real accessibility API. Tests replace them.
  init(
    resolver: WindowElementResolver = WindowElementResolver(),
    activateApplication: @escaping @Sendable (pid_t) -> ApplicationActivation = { pid in
      guard let application = NSRunningApplication(processIdentifier: pid) else { return .missing }
      return application.activate() ? .activated : .refused
    },
    setMinimized: @escaping @Sendable (AXUIElement, Bool) -> AXError = {
      AXUIElementSetAttributeValue($0, kAXMinimizedAttribute as CFString, $1 as CFTypeRef)
    },
    raiseWindow: @escaping @Sendable (AXUIElement) -> AXError = {
      AXUIElementPerformAction($0, kAXRaiseAction as CFString)
    },
    now: @escaping @Sendable () -> ContinuousClock.Instant = { .now }
  ) {
    self.resolver = resolver
    self.activateApplication = activateApplication
    self.setMinimized = setMinimized
    self.raiseWindow = raiseWindow
    self.now = now
  }

  // MARK: Internal

  /// How activating answered. Apart from the outcome so tests can script
  /// each without a live application.
  enum ApplicationActivation: Equatable, Sendable {
    case activated
    case missing
    case refused
  }

  func switchTo(_ target: ActivationTarget) -> ActivationOutcome {
    // An application with no window has nothing to resolve or raise:
    // bringing it forward is the whole switch.
    guard target.id.windowID != nil else {
      return activate(target).map { .failed($0) } ?? .switched
    }
    // 0. Resolve the row back to an element. Never off a fresher list:
    // the target is what the appearance showed.
    let resolved: AXUIElement
    switch resolver.resolve(target) {
    case .element(let element):
      resolved = element
    case .failure(let failure):
      return .failed(failure)
    }
    // 1. Activate first, so a hidden application is unhidden before any
    // window of it is touched.
    if let failure = activate(target) {
      return .failed(failure)
    }
    // 2. Unminimize unconditionally. Writing false where nothing is
    // minimized has no effect, which is cheaper than a round trip asking.
    if let failure = unminimize(resolved) {
      return .failed(failure)
    }
    // 3. Raise. Anything left standing here is the window to take.
    if let failure = raise(resolved) {
      return .failed(failure)
    }
    return .switched
  }

  // MARK: Private

  private let resolver: WindowElementResolver
  private let activateApplication: @Sendable (pid_t) -> ApplicationActivation
  private let setMinimized: @Sendable (AXUIElement, Bool) -> AXError
  private let raiseWindow: @Sendable (AXUIElement) -> AXError
  private let now: @Sendable () -> ContinuousClock.Instant

  private func activate(_ target: ActivationTarget) -> ActivationFailure? {
    switch activateApplication(target.ownerProcessIdentifier) {
    case .activated:
      nil
    case .missing:
      .applicationGone
    case .refused:
      .other(reason: "activation refused")
    }
  }

  /// One AX write with the timeout drawn the same way everywhere: a slow
  /// `cannotComplete` is a wait, anything fast a plain error to name.
  private func write(
    _ element: AXUIElement,
    _ action: @Sendable (AXUIElement) -> AXError
  ) -> ActivationFailure? {
    let sentAt = now()
    switch action(element) {
    case .success:
      return nil

    case .cannotComplete:
      return resolver.waitedSince(sentAt)
        ? .timedOut
        : .other(reason: "error \(AXError.cannotComplete.rawValue)")

    case let error:
      return .other(reason: "error \(error.rawValue)")
    }
  }

  private func unminimize(_ element: AXUIElement) -> ActivationFailure? {
    write(element) { setMinimized($0, false) }
  }

  private func raise(_ element: AXUIElement) -> ActivationFailure? {
    write(element, raiseWindow)
  }

}
