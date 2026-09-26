import ApplicationServices
@testable import Lanterna
import Testing

/// A box so scripted answers can be recorded through sendable closures.
private final class ScriptBox: @unchecked Sendable {
    struct Script {
        var children: [ObjectIdentifier: [AXUIElement]] = [:]
        var strings: [ObjectIdentifier: [String: String]] = [:]
        var pressResults: [ObjectIdentifier: AXError] = [:]
        var pressed: [AXUIElement] = []
    }

    var script: Script
    init(_ script: Script) {
        self.script = script
    }
}

/// A box so scripted terminations cross into sendable closures.
private final class TerminationBox: @unchecked Sendable {
    var terminated = false
}

/// A scripted application: answers what terminating and hiding come to.
private struct FakeControllableApplication: ControllableApplication {
    let terminateAnswer: @Sendable () -> Bool
    let hideAnswer: @Sendable () -> Bool
    init(terminate: @escaping @Sendable () -> Bool, hide: @escaping @Sendable () -> Bool) {
        terminateAnswer = terminate
        hideAnswer = hide
    }

    func terminate() -> Bool {
        terminateAnswer()
    }

    func hide() -> Bool {
        hideAnswer()
    }
}

/// A box so scripted minimize writes cross into sendable closures.
private final class MinimizeBox: @unchecked Sendable {
    let window = AXUIElementCreateApplication(1)
    var writes: [(AXUIElement, Bool)] = []
}

/// A box so scripted elements cross into sendable closures.
private final class ElementBox: @unchecked Sendable {
    let windows: [AXUIElement]
    let windowIDs: [ObjectIdentifier: CGWindowID]
    init(windows: [AXUIElement], windowIDs: [ObjectIdentifier: CGWindowID]) {
        self.windows = windows
        self.windowIDs = windowIDs
    }
}

struct WindowOperationTests {
    private func target(windowID: CGWindowID = 7, pid: pid_t = 123) -> ActivationTarget {
        ActivationTarget(
            id: WindowItem.Identifier(windowID: windowID),
            ownerProcessIdentifier: pid,
            appName: "TextEdit",
            displayTitle: "Untitled"
        )
    }

    private func closer(
        script: ScriptBox.Script,
        windows: [AXUIElement],
        windowIDs: [ObjectIdentifier: CGWindowID],
        listError: AXError = .success
    ) -> (LiveWindowCloser, ScriptBox) {
        let box = ScriptBox(script)
        let elements = ElementBox(windows: windows, windowIDs: windowIDs)
        let made = LiveWindowCloser(
            copyWindows: { _ in (listError, elements.windows) },
            copyWindowID: { element in
                (.success, elements.windowIDs[ObjectIdentifier(element)] ?? 0)
            },
            copyChildren: { element in
                (.success, box.script.children[ObjectIdentifier(element)])
            },
            attributeString: { element, name in
                (.success, box.script.strings[ObjectIdentifier(element)]?[name])
            },
            press: { element in
                box.script.pressed.append(element)
                return box.script.pressResults[ObjectIdentifier(element)] ?? .success
            }
        )
        return (made, box)
    }

    /// The close button one level down is pressed, and nothing else is.
    @Test func pressingTheCloseButtonClosesTheWindow() {
        let window = AXUIElementCreateApplication(1)
        let button = AXUIElementCreateApplication(2)
        let script = ScriptBox.Script(
            children: [ObjectIdentifier(window): [button]],
            strings: [
                ObjectIdentifier(button): [
                    kAXRoleAttribute as String: "AXButton",
                    kAXSubroleAttribute as String: "AXCloseButton",
                ],
            ],
            pressResults: [ObjectIdentifier(button): .success]
        )
        let (made, box) = closer(
            script: script, windows: [window],
            windowIDs: [ObjectIdentifier(window): 7]
        )
        #expect(made.closeWindow(target()) == nil)
        #expect(box.script.pressed.count == 1)
    }

    /// No close button means a failure, not a silent pass.
    @Test func aWindowWithNoCloseButtonFails() {
        let window = AXUIElementCreateApplication(1)
        let script = ScriptBox.Script(children: [ObjectIdentifier(window): []])
        let (made, _) = closer(
            script: script, windows: [window],
            windowIDs: [ObjectIdentifier(window): 7]
        )
        #expect(made.closeWindow(target()) != nil)
    }

    /// A refused press is a failure carrying the error.
    @Test func aRefusedPressFails() {
        let window = AXUIElementCreateApplication(1)
        let button = AXUIElementCreateApplication(2)
        let script = ScriptBox.Script(
            children: [ObjectIdentifier(window): [button]],
            strings: [
                ObjectIdentifier(button): [
                    kAXRoleAttribute as String: "AXButton",
                    kAXSubroleAttribute as String: "AXCloseButton",
                ],
            ],
            pressResults: [ObjectIdentifier(button): .failure]
        )
        let (made, _) = closer(
            script: script, windows: [window],
            windowIDs: [ObjectIdentifier(window): 7]
        )
        #expect(made.closeWindow(target()) == .other(reason: "error -25200"))
    }

    /// Minimizing writes the flag, and a refused write is a failure.
    @Test func minimizingWritesTheFlag() {
        let box = MinimizeBox()
        let minimizer = LiveWindowMinimizer(
            copyWindows: { _ in (.success, [box.window]) },
            copyWindowID: { _ in (.success, 7) },
            setMinimized: { element, minimized in
                box.writes.append((element, minimized))
                return .success
            }
        )
        #expect(minimizer.minimizeWindow(target()) == nil)
        #expect(box.writes.count == 1)
        #expect(box.writes.first?.1 == true)
    }

    @Test func aRefusedMinimizeFails() {
        let minimizer = LiveWindowMinimizer(
            copyWindows: { _ in (.success, []) },
            copyWindowID: { _ in (.success, 0) },
            setMinimized: { _, _ in .failure }
        )
        #expect(minimizer.minimizeWindow(target()) == .windowGone)
    }

    /// A target no application still lists is gone, not broken.
    @Test func aMissingTargetIsWindowGone() {
        let (made, _) = closer(script: ScriptBox.Script(), windows: [], windowIDs: [:])
        #expect(made.closeWindow(target()) == .windowGone)
    }

    /// Quitting asks the application to terminate, and a missing one is
    /// gone rather than broken.
    @Test func quittingTerminatesTheApplication() {
        let box = TerminationBox()
        let quitter = LiveApplicationQuitter(findApplication: { _ in
            FakeControllableApplication(terminate: {
                box.terminated = true
                return true
            }, hide: { true })
        })
        #expect(quitter.quitApplication(processIdentifier: 123) == nil)
        #expect(box.terminated)
    }

    @Test func quittingAMissingApplicationIsGone() {
        let quitter = LiveApplicationQuitter(findApplication: { _ in nil })
        #expect(quitter.quitApplication(processIdentifier: 123) == .applicationGone)
    }

    /// Hiding hides the application, and a refusal is a failure.
    @Test func hidingHidesTheApplication() {
        let box = TerminationBox()
        let hider = LiveApplicationHider(findApplication: { _ in
            FakeControllableApplication(terminate: { true }, hide: {
                box.terminated = true
                return true
            })
        })
        #expect(hider.hideApplication(processIdentifier: 123) == nil)
        #expect(box.terminated)
    }

    @Test func aRefusedHideFails() {
        let hider = LiveApplicationHider(findApplication: { _ in
            FakeControllableApplication(terminate: { true }, hide: { false })
        })
        #expect(hider.hideApplication(processIdentifier: 123) != nil)
    }

    @Test func theFourOperationsAreDistinct() {
        let operations: [WindowOperation] = [
            .closeWindow, .quitApplication, .hideApplication, .minimizeWindow,
        ]
        #expect(Set(operations).count == 4)
    }

    @Test func eachOperationHasItsLogName() {
        #expect(WindowOperation.closeWindow.logName == "close")
        #expect(WindowOperation.quitApplication.logName == "quit")
        #expect(WindowOperation.hideApplication.logName == "hide")
        #expect(WindowOperation.minimizeWindow.logName == "minimize")
    }
}
