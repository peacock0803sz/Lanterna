import AppKit
import CoreGraphics
@testable import Lanterna
import Testing

// MARK: - ActivationPolicyPresenterTests

/// Both switchers take through the same switches.
///
/// The policy rides the presenter rather than either switcher, so a main
/// take and a parallel take hand the same value over, whatever the
/// parallel switcher's own settings say. Wired by the shared commit path,
/// so this pins the structure rather than new behaviour.
@MainActor
struct ActivationPolicyPresenterTests {

  @Test
  func mainAndParallelCommitsHandTheSameSwitchesOver() {
    let policy = ActivationPolicy(reopensWindowlessApps: true, raisesOnlyChosenWindow: true)

    let main = Fixture(entryCount: 12, closesOnCommandRelease: true)
    main.presenter.activationPolicy = policy
    main.presenter.handleHotkey(.forward, deliveryDelay: nil)
    main.presenter.handleCommandRelease()
    #expect(main.switcher.policies == [policy])

    let rows = [
      WindowItem(
        id: WindowItem.Identifier(windowID: 101),
        ownerProcessIdentifier: 4242,
        appName: "TextEdit",
        bundleIdentifier: nil,
        windowTitle: "Untitled",
        kind: .standard,
        isMinimized: false,
        icon: NSImage(size: NSSize(width: 1, height: 1))
      )
    ]
    let parallel = Fixture(
      store: WindowListStore(fixed: rows),
      windows: rows,
      closesOnCommandRelease: true,
      commandIsHeld: false,
      heldModifiers: .maskAlternate
    )
    parallel.presenter.keyCommands.frontmostProcessIdentifier = { 4242 }
    parallel.presenter.activationPolicy = policy
    parallel.presenter.parallelSwitcher = SwitcherSettings(
      windowScope: .frontApp,
      displayModes: .defaults,
      subgroupPlacements: [:]
    )
    parallel.presenter.handleHotkey(.parallelForward, deliveryDelay: nil)
    parallel.presenter.handleOptionRelease()
    #expect(parallel.switcher.policies == [policy])
  }

}
