import ApplicationServices
import PrivateAPIs
import Synchronization

// MARK: - WindowElementResolver

/// Turns a shown row back into its accessibility element.
///
/// Shared by the switcher-shaped operations: switching, closing and
/// minimizing. The target is what the appearance showed, so it is looked up
/// in the owning application's window list and never in a fresher list of
/// rows. One derivation of resolving for all three, so a row gone missing
/// reads the same way in each.
///
/// With the setting on, a target the list lacks is also looked for by probing
/// the application's element ids, because the list leaves out windows on
/// Spaces no display is showing.
struct WindowElementResolver: Sendable {

  // MARK: Lifecycle

  /// The defaults talk to the real accessibility API. Tests replace them,
  /// because which answer an application gives is precisely the behaviour
  /// being specified and no real application can be asked to give one.
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
    probesOtherSpaces: @escaping @Sendable () -> Bool = { false },
    probeWindows: @escaping @Sendable (pid_t, CGWindowID?, ContinuousClock.Instant) -> [ProbedWindow] = {
      WindowProbe.windows(of: $0, stoppingAt: $1, until: $2)
    },
    now: @escaping @Sendable () -> ContinuousClock.Instant = { .now }
  ) {
    self.createApplication = createApplication
    self.setMessagingTimeout = setMessagingTimeout
    self.copyWindows = copyWindows
    self.copyWindowID = copyWindowID
    self.probesOtherSpaces = probesOtherSpaces
    self.probeWindows = probeWindows
    self.now = now
  }

  // MARK: Internal

  /// What resolving came to. Apart from the outcome so a missing row stays
  /// distinct from a failed read all the way to the wording.
  enum Resolution {
    case element(AXUIElement)
    case failure(ActivationFailure)
  }

  static let messagingTimeout: Float = 1.0
  /// Answers slower than this are waits, not refusals. Half the messaging
  /// timeout leaves a wide margin on both sides; borrowed from the reader,
  /// which draws the same line for the same code.
  static let unreachableAnswerCeiling = Duration.milliseconds(500)
  /// How long the probe may look for a target the list lacks. Resolving runs
  /// on the main actor, so this is how long a press can hang on it.
  static let otherSpaceProbeLimit = Duration.milliseconds(500)

  /// Slow `cannotComplete` answers are waits, fast ones refusals.
  func waitedSince(_ instant: ContinuousClock.Instant) -> Bool {
    now() - instant >= Self.unreachableAnswerCeiling
  }

  /// Arms one element with the messaging timeout. Costs no round trip.
  func prepare(_ element: AXUIElement) -> Bool {
    setMessagingTimeout(element, Self.messagingTimeout) == .success
  }

  func resolve(_ target: ActivationTarget) -> Resolution {
    let application = createApplication(target.ownerProcessIdentifier)
    guard setMessagingTimeout(application, Self.messagingTimeout) == .success else {
      return .failure(.applicationGone)
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
        return .failure(.other(reason: "malformed answer"))
      }
      elements = rawElements

    case .noValue:
      // No open windows, which the reader reads as an empty list: a
      // target of this application is gone rather than erroneous.
      elements = []

    default:
      return .failure(listFailure(for: windowsError, since: sentAt))
    }
    if let found = firstMatch(in: elements, for: target) {
      return found
    }
    return otherSpaceElement(for: target) ?? .failure(.windowGone)
  }

  /// What a failed list read means. Apart so resolving stays readable:
  /// the ceiling judges one message, whichever message it was.
  func listFailure(for error: AXError, since sentAt: ContinuousClock.Instant) -> ActivationFailure {
    switch error {
    case .cannotComplete:
      waitedSince(sentAt) ? .timedOut : .applicationGone
    case .apiDisabled:
      .other(reason: "permission missing")
    case .invalidUIElement:
      .applicationGone
    case let error:
      .other(reason: "error \(error.rawValue)")
    }
  }

  // MARK: Private

  private enum ElementMatch {
    case match
    case skip
    case abort(ActivationFailure)
  }

  private let createApplication: @Sendable (pid_t) -> AXUIElement
  private let setMessagingTimeout: @Sendable (AXUIElement, Float) -> AXError
  private let copyWindows: @Sendable (AXUIElement) -> (AXError, [AXUIElement]?)
  private let copyWindowID: @Sendable (AXUIElement) -> (AXError, CGWindowID)
  private let probesOtherSpaces: @Sendable () -> Bool
  private let probeWindows: @Sendable (pid_t, CGWindowID?, ContinuousClock.Instant) -> [ProbedWindow]
  private let now: @Sendable () -> ContinuousClock.Instant

  /// The target's element when it is on a Space no display is showing. The
  /// list leaves such windows out, and a row for one may be on screen.
  /// Nil with the setting off, which leaves the list's answer as it was.
  private func otherSpaceElement(for target: ActivationTarget) -> Resolution? {
    guard probesOtherSpaces(), let windowID = target.id.windowID else {
      return nil
    }
    let deadline = now() + Self.otherSpaceProbeLimit
    let found = probeWindows(target.ownerProcessIdentifier, windowID, deadline)
      .first { $0.windowID == windowID && prepare($0.element) }
    return found.map { .element($0.element) }
  }

  /// The first element that is the target, or the abort that ended the look.
  /// Nil when none is.
  private func firstMatch(in elements: [AXUIElement], for target: ActivationTarget) -> Resolution? {
    for element in elements {
      switch match(element, to: target) {
      case .match:
        return .element(element)
      case .skip:
        continue
      case .abort(let failure):
        return .failure(failure)
      }
    }
    return nil
  }

  /// One element against the target. Most elements are somebody else's row
  /// and are skipped; an answer about the application aborts the whole
  /// resolve instead. Anything else unreadable is skipped too: an element
  /// that cannot be told apart cannot condemn the take, and a target never
  /// matched is windowGone.
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
      return .abort(waitedSince(attemptAt) ? .timedOut : .applicationGone)
    case .apiDisabled:
      return .abort(.other(reason: "permission missing"))
    default:
      return .skip
    }
  }

}

// MARK: - OtherSpacesSetting

/// The "windows on all desktops" setting as the long-lived switchers read it.
///
/// The switcher, closer and minimizer are built once while the setting
/// changes live, so each asks this at the time of use. A lock rather than the
/// main actor, because the resolver they share is not isolated to it.
final class OtherSpacesSetting: Sendable {

  // MARK: Lifecycle

  init(isOn: Bool) {
    value = Mutex(isOn)
  }

  // MARK: Internal

  var isOn: Bool {
    get { value.withLock { $0 } }
    set { value.withLock { $0 = newValue } }
  }

  // MARK: Private

  private let value: Mutex<Bool>

}
