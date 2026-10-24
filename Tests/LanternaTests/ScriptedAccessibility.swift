import ApplicationServices
import Foundation
@testable import Lanterna

// MARK: - ScriptedAccessibility

/// Scripted answers for the live switcher, recording every call.
///
/// Distinct elements, so a closure can tell which window it was asked about.
/// Creating one sends nothing and needs no permission.
// swiftlint:disable:next no_unchecked_sendable - test-only; synchronous scripted answers, never shared
final class ScriptedAccessibility: @unchecked Sendable {

  // MARK: Lifecycle

  init(windowCount: Int) {
    windows = (0 ..< windowCount).map { AXUIElementCreateApplication(pid_t(9101 + $0)) }
  }

  // MARK: Internal

  let application = AXUIElementCreateApplication(9000)
  let windows: [AXUIElement]

  private(set) var createPIDs = [pid_t]()
  private(set) var activatePIDs = [pid_t]()
  private(set) var minimizeValues = [Bool]()
  /// Every element given a messaging timeout, in order: the application
  /// first, then each window as it is met.
  private(set) var prepared = [ObjectIdentifier]()
  /// Every activating, unminimizing and raising call, in order, by name.
  private(set) var operationNames = [String]()
  /// The elements those calls acted upon, in the same order.
  private(set) var operated = [ObjectIdentifier]()

  var windowsError = AXError.success
  /// Answers a list that is not a list.
  var malformedList = false
  /// Answers `nil` to fall through to a successful fetch of `100 + index`.
  var idAnswers = [Int: (AXError, CGWindowID)]()
  /// The pids reopening was asked of, in order.
  private(set) var reopenPIDs = [pid_t]()
  /// What reopening answers.
  var reopenAnswer = ReopenNote.requested
  /// What making the main window answers.
  var setMainError = AXError.success
  /// What each raising answers, in order; `nil` falls through to
  /// `raiseError` above. Lets the first and the last raising fail apart.
  var raiseErrors = [AXError?]()
  var timeoutResult = AXError.success
  /// Answers `nil` to fall through to `.success`, keyed by window index.
  var prepareErrors = [Int: AXError]()
  var activateAnswer = LiveWindowSwitcher.ApplicationActivation.activated
  var writeError = AXError.success
  /// Answers `nil` to fall through to `writeError`.
  var raiseError: AXError?
  /// Time each read costs, so a timeout can be spent without waiting.
  var listCost = Duration.zero
  var idCost = Duration.zero
  var writeCost = Duration.zero

  func identity(of index: Int) -> ObjectIdentifier {
    ObjectIdentifier(windows[index])
  }

  func appIdentity() -> ObjectIdentifier {
    ObjectIdentifier(application)
  }

  func switcher() -> LiveWindowSwitcher {
    LiveWindowSwitcher(
      createApplication: { [self] pid in
        createPIDs.append(pid)
        return application
      },
      setMessagingTimeout: { [self] element, _ in
        prepared.append(ObjectIdentifier(element))
        if element === application {
          return timeoutResult
        }
        guard let index = windows.firstIndex(where: { $0 === element }) else {
          return .success
        }
        return prepareErrors[index] ?? .success
      },
      copyWindows: { [self] _ in
        clock = clock.advanced(by: listCost)
        return malformedList ? (windowsError, nil) : (windowsError, windows)
      },
      copyWindowID: { [self] element in
        guard let index = windows.firstIndex(where: { $0 === element }) else {
          return (.illegalArgument, 0)
        }
        clock = clock.advanced(by: idCost)
        return idAnswers[index] ?? (.success, CGWindowID(100 + index))
      },
      activateApplication: { [self] pid in
        operationNames.append("activate")
        activatePIDs.append(pid)
        return activateAnswer
      },
      setMinimized: { [self] element, minimized in
        operationNames.append("unminimize")
        operated.append(ObjectIdentifier(element))
        minimizeValues.append(minimized)
        clock = clock.advanced(by: writeCost)
        return writeError
      },
      reopenApplication: { [self] pid in
        operationNames.append("reopen")
        reopenPIDs.append(pid)
        return reopenAnswer
      },
      setMain: { [self] element in
        operationNames.append("setMain")
        operated.append(ObjectIdentifier(element))
        clock = clock.advanced(by: writeCost)
        return setMainError
      },
      raiseWindow: { [self] element in
        operationNames.append("raise")
        operated.append(ObjectIdentifier(element))
        clock = clock.advanced(by: writeCost)
        if !raiseErrors.isEmpty {
          return raiseErrors.removeFirst() ?? raiseError ?? writeError
        }
        return raiseError ?? writeError
      },
      now: { [self] in clock }
    )
  }

  // MARK: Private

  private var clock = ContinuousClock.now

}
