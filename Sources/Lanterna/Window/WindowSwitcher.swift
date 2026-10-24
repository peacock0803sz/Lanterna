import AppKit
import ApplicationServices
import PrivateAPIs

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
/// taking: with both switches off the report carries the outcome alone,
/// which is the path the commit always took.
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
/// Takes the two switches as one value, read fresh at each take.
protocol WindowSwitching: Sendable {
  func switchTo(_ target: ActivationTarget, policy: ActivationPolicy) -> ActivationReport
}

extension WindowSwitching {
  /// Both switches off: the path before either existed.
  func switchTo(_ target: ActivationTarget) -> ActivationOutcome {
    switchTo(target, policy: .off).outcome
  }
}

// MARK: - LiveWindowSwitcher

/// Talks to the real accessibility API, in the order the contract pins down:
/// activate, unminimize, raise. Resolving (row to element) happens first and
/// reads nothing but the target application's own window list.
///
/// Every seam is a closure defaulting to the real call, so tests script
/// answers no live application can be asked to give. The shape follows
/// `AXApplicationWindowReader`, which separates its sends the same way.
struct LiveWindowSwitcher: WindowSwitching, Sendable {

  // MARK: Lifecycle

  /// The defaults talk to the real accessibility API. Tests replace them.
  init(
    createApplication: @escaping @Sendable (pid_t) -> AXUIElement = {
      AXUIElementCreateApplication($0)
    },
    setMessagingTimeout: @escaping @Sendable (AXUIElement, Float) -> AXError = {
      AXUIElementSetMessagingTimeout($0, $1)
    },
    copyWindows: @escaping @Sendable (AXUIElement) -> (AXError, [AXUIElement]?) = { application in
      var value: CFTypeRef?
      let error = AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value)
      return (error, value as? [AXUIElement])
    },
    copyWindowID: @escaping @Sendable (AXUIElement) -> (AXError, CGWindowID) = { element in
      var windowID: CGWindowID = 0
      let error = _AXUIElementGetWindow(element, &windowID)
      return (error, windowID)
    },
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
    self.createApplication = createApplication
    self.setMessagingTimeout = setMessagingTimeout
    self.copyWindows = copyWindows
    self.copyWindowID = copyWindowID
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

  static let messagingTimeout: Float = 1.0
  /// Answers slower than this are waits, not refusals. Half the messaging
  /// timeout leaves a wide margin on both sides; borrowed from the reader,
  /// which draws the same line for the same code.
  static let unreachableAnswerCeiling = Duration.milliseconds(500)

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
    // 0. Resolve the row back to an element, reading only the owning
    // application's list. Never a fresher list: the target is what the
    // appearance showed.
    let resolved: AXUIElement
    switch resolve(target) {
    case .element(let element):
      resolved = element
    case .failure(let outcome):
      return ActivationReport(outcome: outcome, reopen: nil, raiseAlone: nil)
    }
    // Asked to, the chosen window goes first through the suppression
    // path below, standing in for the rest of this order.
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
      return waitedSince(sentAt)
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

  /// What resolving came to. Apart from the outcome so a missing row stays
  /// distinct from a failed read all the way to the wording.
  private enum Resolution {
    case element(AXUIElement)
    case failure(ActivationOutcome)
  }

  /// One element against the target. Most elements are somebody else's row
  /// and are skipped; an answer about the application aborts the whole
  /// resolve instead. Anything else unreadable is skipped too: an element
  /// that cannot be told apart cannot condemn the take, and a target never
  /// matched is windowGone.
  private enum ElementMatch {
    case match
    case skip
    case abort(ActivationOutcome)
  }

  private let createApplication: @Sendable (pid_t) -> AXUIElement
  private let setMessagingTimeout: @Sendable (AXUIElement, Float) -> AXError
  private let copyWindows: @Sendable (AXUIElement) -> (AXError, [AXUIElement]?)
  private let copyWindowID: @Sendable (AXUIElement) -> (AXError, CGWindowID)
  private let activateApplication: @Sendable (pid_t) -> ApplicationActivation
  private let setMinimized: @Sendable (AXUIElement, Bool) -> AXError
  private let reopenApplication: @Sendable (pid_t) -> ReopenNote
  private let now: @Sendable () -> ContinuousClock.Instant

  /// Slow `cannotComplete` answers are waits, fast ones refusals. The line
  /// is the reader's: half the messaging timeout either way.
  private func waitedSince(_ instant: ContinuousClock.Instant) -> Bool {
    now() - instant >= Self.unreachableAnswerCeiling
  }

  private func resolve(_ target: ActivationTarget) -> Resolution {
    let application = createApplication(target.ownerProcessIdentifier)
    guard setMessagingTimeout(application, Self.messagingTimeout) == .success else {
      return .failure(.failed(.applicationGone))
    }
    let sentAt = now()
    let (windowsError, rawElements) = copyWindows(application)
    let elements: [AXUIElement]
    switch windowsError {
    case .success:
      // An application that answers its window list with something
      // that is not one cannot be read, and the reader's word for
      // that is kept: malformed answer.
      guard let rawElements else {
        return .failure(.failed(.other(reason: "malformed answer")))
      }
      elements = rawElements

    case .noValue:
      // No open windows, which the reader reads as an empty list: a
      // target of this application is gone rather than erroneous.
      elements = []

    default:
      return .failure(listFailure(for: windowsError, since: sentAt))
    }
    for element in elements {
      switch match(element, to: target) {
      case .match:
        return .element(element)
      case .skip:
        continue
      case .abort(let outcome):
        return .failure(outcome)
      }
    }
    return .failure(.failed(.windowGone))
  }

  /// What a failed list read means. Apart so resolving stays readable:
  /// the ceiling judges one message, whichever message it was.
  private func listFailure(for error: AXError, since sentAt: ContinuousClock.Instant) -> ActivationOutcome {
    switch error {
    case .cannotComplete:
      waitedSince(sentAt) ? .failed(.timedOut) : .failed(.applicationGone)
    case .apiDisabled:
      .failed(.other(reason: "permission missing"))
    case .invalidUIElement:
      .failed(.applicationGone)
    case let error:
      .failed(.other(reason: "error \(error.rawValue)"))
    }
  }

  private func match(_ element: AXUIElement, to target: ActivationTarget) -> ElementMatch {
    // The timeout rides with the element it protects: the setting
    // applies to the element it is made on, so every element is given
    // its own before its first message. One that cannot take it is
    // skipped like anything else unreadable.
    guard setMessagingTimeout(element, Self.messagingTimeout) == .success else {
      return .skip
    }
    let attemptAt = now()
    let (idError, windowID) = copyWindowID(element)
    switch idError {
    case .success:
      return windowID != 0 && windowID == target.id.windowID ? .match : .skip
    case .cannotComplete:
      return .abort(waitedSince(attemptAt) ? .failed(.timedOut) : .failed(.applicationGone))
    case .apiDisabled:
      return .abort(.failed(.other(reason: "permission missing")))
    default:
      return .skip
    }
  }

}
