import ApplicationServices
import Foundation
@testable import Lanterna
import Testing

/// What the seam sends, and what it does with each answer.
///
/// Which error an application returns is the whole behaviour under test, and
/// no live application can be asked to return one, so a stand-in answers
/// instead. The stand-in records every call, because resolving must not be
/// skipped: the target handed over has to be the element acted upon.
///
/// The shape mirrors `FakeApplication`: an `@unchecked Sendable` peer driven
/// synchronously on one thread, with a clock the answers advance.
@MainActor
struct WindowSwitcherTests {
    private func target(windowID: CGWindowID = 101) -> ActivationTarget {
        ActivationTarget(
            id: WindowItem.Identifier(windowID: windowID),
            ownerProcessIdentifier: 4242,
            appName: "TextEdit",
            displayTitle: "Untitled",
            isMinimized: false
        )
    }

    /// A resolved element is the one acted upon, and the owning pid is the
    /// one asked about. Anything else would take a row nobody chose.
    @Test func resolvingHandsTheResolvedElementToTheOperations() {
        let peer = ScriptedAccessibility(windowCount: 2)
        let outcome = peer.switcher().switchTo(target())

        #expect(outcome == .switched)
        #expect(peer.createPIDs == [4242])
        #expect(peer.operated == [peer.identity(of: 1), peer.identity(of: 1)])
    }

    /// A missing row ends the take before anything is touched.
    @Test func anUnknownIDFailsWithoutTouchingAnything() {
        let peer = ScriptedAccessibility(windowCount: 2)
        let outcome = peer.switcher().switchTo(target(windowID: 999))

        #expect(outcome == .failed(.windowGone))
        #expect(peer.operationNames.isEmpty)
    }

    /// A slow refusal to answer is a wait.
    @Test func aSlowWindowsReadBecomesTimedOut() {
        let peer = ScriptedAccessibility(windowCount: 2)
        peer.windowsError = .cannotComplete
        peer.messageCost = .milliseconds(600)
        let outcome = peer.switcher().switchTo(target())

        #expect(outcome == .failed(.timedOut))
        #expect(peer.operationNames.isEmpty)
    }

    /// A fast refusal is about the application, not the wait.
    @Test func aFastWindowsReadBecomesApplicationGone() {
        let peer = ScriptedAccessibility(windowCount: 2)
        peer.windowsError = .cannotComplete
        let outcome = peer.switcher().switchTo(target())

        #expect(outcome == .failed(.applicationGone))
        #expect(peer.operationNames.isEmpty)
    }

    /// Which error ends a resolve, spelled out.
    @Test(arguments: [
        (AXError.apiDisabled, ActivationFailure.other(reason: "permission missing")),
        (.invalidUIElement, .applicationGone),
        (.failure, .other(reason: "error \(AXError.failure.rawValue)")),
    ])
    func aWindowsReadErrorMapsToItsOutcome(error: AXError, failure: ActivationFailure) {
        let peer = ScriptedAccessibility(windowCount: 2)
        peer.windowsError = error
        let outcome = peer.switcher().switchTo(target())

        #expect(outcome == .failed(failure))
        #expect(peer.operationNames.isEmpty)
    }

    /// No application, no take; a refusal names itself.
    @Test func aMissingApplicationIsGoneAndARefusalSaysSo() {
        let peer = ScriptedAccessibility(windowCount: 2)
        peer.activateAnswer = .missing
        #expect(peer.switcher().switchTo(target()) == .failed(.applicationGone))
        #expect(peer.operationNames == ["activate"])

        peer.activateAnswer = .refused
        #expect(peer.switcher().switchTo(target()) == .failed(.other(reason: "activation refused")))
        #expect(peer.operationNames == ["activate", "activate"])
    }

    /// A timeout that cannot even be set is about the application.
    @Test func anUnsettableTimeoutIsApplicationGone() {
        let peer = ScriptedAccessibility(windowCount: 2)
        peer.timeoutResult = .cannotComplete
        let outcome = peer.switcher().switchTo(target())

        #expect(outcome == .failed(.applicationGone))
        #expect(peer.operationNames.isEmpty)
    }
}

/// Scripted answers for the live switcher, recording every call.
///
/// Distinct elements, so a closure can tell which window it was asked about.
/// Creating one sends nothing and needs no permission.
private final class ScriptedAccessibility: @unchecked Sendable {
    let application = AXUIElementCreateApplication(9000)
    let windows: [AXUIElement]

    private(set) var createPIDs: [pid_t] = []
    /// Every activating, unminimizing and raising call, in order, by name.
    private(set) var operationNames: [String] = []
    /// The elements those calls acted upon, in the same order.
    private(set) var operated: [ObjectIdentifier] = []

    var windowsError: AXError = .success
    /// Answers `nil` to fall through to a successful fetch of `100 + index`.
    var idAnswers: [Int: (AXError, CGWindowID)] = [:]
    var timeoutResult: AXError = .success
    var activateAnswer: LiveWindowSwitcher.ApplicationActivation = .activated
    var writeError: AXError = .success
    /// Time each message costs, so a timeout can be spent without waiting.
    var messageCost: Duration = .zero

    private var clock = ContinuousClock.now

    init(windowCount: Int) {
        windows = (0 ..< windowCount).map { AXUIElementCreateApplication(pid_t(9101 + $0)) }
    }

    func identity(of index: Int) -> ObjectIdentifier {
        ObjectIdentifier(windows[index])
    }

    func switcher() -> LiveWindowSwitcher {
        LiveWindowSwitcher(
            createApplication: { [self] pid in
                createPIDs.append(pid)
                return application
            },
            setMessagingTimeout: { [self] _, _ in timeoutResult },
            copyWindows: { [self] _ in
                clock = clock.advanced(by: messageCost)
                return (windowsError, windows)
            },
            copyWindowID: { [self] element in
                guard let index = windows.firstIndex(where: { $0 === element }) else {
                    return (.illegalArgument, 0)
                }
                return idAnswers[index] ?? (.success, CGWindowID(100 + index))
            },
            activateApplication: { [self] _ in
                operationNames.append("activate")
                return activateAnswer
            },
            setMinimized: { [self] element, _ in
                operationNames.append("unminimize")
                operated.append(ObjectIdentifier(element))
                return writeError
            },
            raiseWindow: { [self] element in
                operationNames.append("raise")
                operated.append(ObjectIdentifier(element))
                return writeError
            },
            now: { [self] in clock }
        )
    }
}
