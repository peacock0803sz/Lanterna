import Carbon.HIToolbox
@testable import Lanterna
import Testing

// MARK: - FastSearchControllerTests

/// The tap's owner: makes and takes down the tap with the settings, keeps
/// the tap's conditions current, and hands the tap's reports on.
@MainActor
struct FastSearchControllerTests {

  // MARK: Internal

  @Test
  func aTapExistsOnlyWhileAModifierIsEnabled() {
    let made = make()
    made.controller.apply(modifiers: [])
    #expect(made.tap.startCount == 0)

    made.controller.apply(modifiers: [.rightCommand, .fn])
    #expect(made.tap.startCount == 1)
    #expect(made.log.lines == ["fast search tap started for Fn, Right Command"])

    made.controller.apply(modifiers: [.fn])
    #expect(made.tap.startCount == 1)

    made.controller.apply(modifiers: [])
    #expect(made.tap.stopCount == 1)
    #expect(made.log.lines.last == "fast search tap removed; no modifier is enabled")
  }

  @Test
  func aTapThatCannotBeMadeIsReportedOncePerReason() {
    let made = make()
    made.tap.startSucceeds = false
    made.tap.accessibilityGranted = false
    made.controller.apply(modifiers: [.fn])
    made.controller.apply(modifiers: [.fn, .capsLock])

    #expect(made.log.lines == [
      "fast search is unavailable; the keyboard tap could not be created (accessibility granted: no)"
    ])
    #expect(!made.controller.isRunning)
  }

  @Test
  func conditionsFollowTheSettingsAndThePanel() {
    let made = make()
    made.controller.apply(modifiers: [.fn])
    #expect(decide(made, down: kVK_ANSI_S).verdict == .swallow)
    made.controller.box.panelClosed()
    made.controller.apply(modifiers: [])
    made.controller.apply(modifiers: [.fn])

    made.fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    #expect(decide(made, down: kVK_ANSI_A).verdict == .pass)
  }

  @Test
  func aModifierTurnedOffWhileRunningStopsStarting() {
    let kept = make()
    kept.controller.apply(modifiers: [.rightCommand, .fn])
    #expect(decide(kept, down: kVK_ANSI_S, flags: rightCommand).verdict == .swallow)

    let made = make()
    made.controller.apply(modifiers: [.rightCommand, .fn])
    made.controller.apply(modifiers: [.fn])
    #expect(made.controller.isRunning)
    #expect(decide(made, down: kVK_ANSI_S, flags: rightCommand).verdict == .pass)
  }

  @Test
  func recordingAKeyStopsSearchesFromStarting() {
    let made = make()
    made.controller.apply(modifiers: [.fn])
    made.capture.set(true)
    #expect(decide(made, down: kVK_ANSI_S).verdict == .pass)
    made.capture.set(false)
    #expect(decide(made, down: kVK_ANSI_S).verdict == .swallow)
  }

  @Test
  func reportsReachThePresenterOnlyDuringASearch() {
    let made = make()
    made.controller.apply(modifiers: [.fn])
    made.tap.send(.keystroke(letter(kVK_ANSI_A, "a")))
    made.tap.send(.release(.fn, receivedAt: .now))
    #expect(!made.fixture.surface.isPresented)

    made.tap.send(.begin(letter(kVK_ANSI_S, "s"), modifier: .fn, receivedAt: .now, deliveryDelay: nil))
    #expect(made.fixture.surface.isPresented)
    made.tap.send(.keystroke(letter(kVK_ANSI_A, "a")))
    #expect(made.fixture.presenter.keyCommands.filterSummary().query == "sa")
    made.tap.send(.release(.fn, receivedAt: .now))
    #expect(!made.fixture.surface.isPresented)
  }

  @Test
  func aLetterThatMeetsAPanelStandsTheSearchDown() {
    let made = make()
    made.controller.apply(modifiers: [.fn])
    #expect(decide(made, down: kVK_ANSI_S).verdict == .swallow)
    made.fixture.presenter.handleHotkey(.filter, deliveryDelay: nil)
    made.tap.send(.begin(letter(kVK_ANSI_S, "s"), modifier: .fn, receivedAt: .now, deliveryDelay: nil))

    #expect(!made.controller.box.isRunning)
    #expect(made.fixture.presenter.keyCommands.filterSummary().query == "s")
  }

  @Test
  func aClosedPanelSendsTheGateToWaitForTheRelease() {
    let made = make()
    made.controller.apply(modifiers: [.fn])
    _ = decide(made, down: kVK_ANSI_S)
    made.tap.send(.begin(letter(kVK_ANSI_S, "s"), modifier: .fn, receivedAt: .now, deliveryDelay: nil))
    made.fixture.presenter.fastSearchKeystroke(PanelKeystroke(keyCode: UInt16(kVK_Escape), modifiers: [], isARepeat: false))
    made.fixture.presenter.fastSearchKeystroke(PanelKeystroke(keyCode: UInt16(kVK_Escape), modifiers: [], isARepeat: false))

    #expect(!made.fixture.surface.isPresented)
    #expect(!made.controller.box.isRunning)
    #expect(decide(made, down: kVK_ANSI_F).verdict == .swallow)
  }

  @Test
  func theHealthCheckPutsASilentlyStoppedTapBack() {
    let made = make()
    made.controller.apply(modifiers: [.fn])
    made.tap.goDownSilently()
    made.controller.checkHealth()

    #expect(made.tap.enableCount == 1)
    #expect(made.log.lines.last?.hasPrefix("fast search tap was found disabled; re-enabled") == true)
  }

  @Test
  func aSystemStopIsReported() {
    let made = make()
    made.controller.apply(modifiers: [.fn])
    made.tap.reportDisabled(reenabled: true)
    made.tap.reportDisabled(reenabled: false)

    #expect(made.log.lines.suffix(2) == [
      "fast search tap was disabled by the system; re-enabled",
      "fast search tap was disabled by the system; could not re-enable it",
    ])
  }

  // MARK: Private

  private struct Made {
    let controller: FastSearchController
    let tap: FakeFastSearchTap
    let fixture: Fixture
    let log: DiagnosticsLog
    let capture: KeyCaptureActivity
  }

  private let table = KeyCharacterTable { keyCode, shift in
    let letters: [UInt16: String] = [UInt16(kVK_ANSI_S): "s", UInt16(kVK_ANSI_A): "a", UInt16(kVK_ANSI_F): "f"]
    return letters[keyCode].map { shift ? $0.uppercased() : $0 }
  }

  /// Command with the right-hand device bit, as the tap reads Right Command.
  private let rightCommand = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x10)

  private func make() -> Made {
    let tap = FakeFastSearchTap()
    let log = DiagnosticsLog()
    let capture = KeyCaptureActivity()
    let fixture = Fixture()
    let controller = FastSearchController(
      tap: tap,
      tables: KeyCharacterTableWatch(read: { [table] in table }),
      capture: capture,
      writeLine: log.write
    )
    controller.presenter = fixture.presenter
    return Made(controller: controller, tap: tap, fixture: fixture, log: log, capture: capture)
  }

  private func letter(_ keyCode: Int, _ text: String) -> PanelKeystroke {
    PanelKeystroke(keyCode: UInt16(keyCode), modifiers: [], isARepeat: false, characters: text)
  }

  private func decide(
    _ made: Made,
    down keyCode: Int,
    flags: CGEventFlags = .maskSecondaryFn
  ) -> (verdict: FastSearchVerdict, effect: FastSearchEffect?) {
    made.controller.box.decide(FastSearchEvent(kind: .keyDown, keyCode: UInt16(keyCode), flags: flags))
  }

}
