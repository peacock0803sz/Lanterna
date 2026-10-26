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

// MARK: - ActivationReport

/// What taking a target came to, beside the outcome itself.
///
/// The notes stay absent unless a switch the commit asked for changed the
/// taking: with the commit switches off the report carries the outcome
/// alone.
struct ActivationReport: Equatable, Sendable {
  let outcome: ActivationOutcome
  let reopen: ReopenNote?
  let raiseAlone: RaiseAloneNote?
}

// MARK: - ReopenNote

/// How opening a windowless application went. Only the call being taken up
/// is noted here; a failure arriving later is a line of its own.
enum ReopenNote: Equatable, Sendable {
  case requested
  case skippedNoBundle
}

// MARK: - RaiseAloneNote

/// How bringing only the chosen window forward went. The wording names the
/// procedure's own success; whether the order on screen kept still is read
/// off the screen, not off this note.
enum RaiseAloneNote: Equatable, Sendable {
  case held
  case notHeld(reason: String)
}

// MARK: - WindowSwitching

/// The one entrance the commit paths call. Takes a single target rather than
/// a list, so resolving off a fresher list at commit time has nowhere to go.
/// Takes the commit switches as one value, which the caller reads fresh at
/// each take.
protocol WindowSwitching: Sendable {
  func switchTo(_ target: ActivationTarget, policy: ActivationPolicy) -> ActivationReport
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
    reopenApplication: @escaping @Sendable (pid_t) -> ReopenNote = {
      ApplicationReopener().reopen(processIdentifier: $0)
    },
    setMain: @escaping @Sendable (AXUIElement) -> AXError = {
      AXUIElementSetAttributeValue($0, kAXMainAttribute as CFString, kCFBooleanTrue as CFTypeRef)
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
    self.reopenApplication = reopenApplication
    self.setMain = setMain
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

  let raiseWindow: @Sendable (AXUIElement) -> AXError
  let setMain: @Sendable (AXUIElement) -> AXError

  func switchTo(_ target: ActivationTarget, policy: ActivationPolicy) -> ActivationReport {
    // An application with no window has nothing to resolve or raise:
    // bringing it forward is the whole switch. Asked to, the workspace
    // is then told to reopen it, the way its Dock icon would.
    guard target.id.windowID != nil else {
      switch activate(target) {
      case .none:
        let reopen: ReopenNote? = policy.reopensWindowlessApps ? reopenApplication(target.ownerProcessIdentifier) : nil
        return ActivationReport(outcome: .switched, reopen: reopen, raiseAlone: nil)

      case .some(let failure):
        return ActivationReport(outcome: .failed(failure), reopen: nil, raiseAlone: nil)
      }
    }
    // 0. Resolve the row back to an element. Never off a fresher list:
    // the target is what the appearance showed.
    let resolved: AXUIElement
    switch resolver.resolve(target) {
    case .element(let element):
      resolved = element
    case .failure(let failure):
      return ActivationReport(outcome: .failed(failure), reopen: nil, raiseAlone: nil)
    }
    // Asked to, the chosen window goes through `switchRaiseAlone`
    // instead, which stands in for the rest of this order.
    if policy.raisesOnlyChosenWindow {
      return switchRaiseAlone(target, resolved: resolved)
    }
    // 1. Activate first, so a hidden application is unhidden before any
    // window of it is touched.
    if let failure = activate(target) {
      return ActivationReport(outcome: .failed(failure), reopen: nil, raiseAlone: nil)
    }
    // 2. Unminimize unconditionally. Writing false where nothing is
    // minimized has no effect, which is cheaper than a round trip asking.
    if let failure = unminimize(resolved) {
      return ActivationReport(outcome: .failed(failure), reopen: nil, raiseAlone: nil)
    }
    // 3. Raise. Anything left standing here is the window to take.
    if let failure = raise(resolved) {
      return ActivationReport(outcome: .failed(failure), reopen: nil, raiseAlone: nil)
    }
    return ActivationReport(outcome: .switched, reopen: nil, raiseAlone: nil)
  }

  func activate(_ target: ActivationTarget) -> ActivationFailure? {
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
  func write(
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

  func unminimize(_ element: AXUIElement) -> ActivationFailure? {
    write(element) { setMinimized($0, false) }
  }

  func raise(_ element: AXUIElement) -> ActivationFailure? {
    write(element, raiseWindow)
  }

  // MARK: Private

  private let resolver: WindowElementResolver
  private let activateApplication: @Sendable (pid_t) -> ApplicationActivation
  private let setMinimized: @Sendable (AXUIElement, Bool) -> AXError
  private let reopenApplication: @Sendable (pid_t) -> ReopenNote
  private let now: @Sendable () -> ContinuousClock.Instant

}
