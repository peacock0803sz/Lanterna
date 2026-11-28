import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Testing
@testable import Lanterna

/// One row of the named owner, so the scope decides which rows stay.
@MainActor
private func parallelRow(
  _ windowID: CGWindowID,
  owner: pid_t,
  app: String,
  title: String,
  minimized: Bool = false
) -> WindowItem {
  WindowItem(
    id: WindowItem.Identifier(windowID: windowID),
    ownerProcessIdentifier: owner,
    appName: app,
    bundleIdentifier: nil,
    windowTitle: title,
    kind: .standard,
    isMinimized: minimized,
    icon: NSImage(size: NSSize(width: 1, height: 1))
  )
}

// MARK: - ParallelPresenterTests

/// The parallel switcher opens the same panel on its own settings: the
/// front application alone, with the scope toggle kept to the showing.
@MainActor
struct ParallelPresenterTests {

  // MARK: Internal

  @Test
  func parallelOpensOnTheFrontApplicationAlone() {
    let fixture = twoAppFixture(front: safari)
    fixture.presenter.handleHotkey(.parallelForward, deliveryDelay: nil)

    #expect(fixture.surface.isPresented)
    let shown = fixture.surface.presentedLists.last ?? []
    #expect(shown.count == 3)
    #expect(shown.allSatisfy { $0.ownerProcessIdentifier == safari })
    #expect(fixture.surface.scopeBands.last.flatMap { $0 } != nil)
  }

  @Test
  func mainOpensOnEveryApplication() {
    let fixture = twoAppFixture(front: safari)
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)

    let shown = fixture.surface.presentedLists.last ?? []
    #expect(shown.count == 5)
    #expect(fixture.surface.scopeBands.last.flatMap { $0 } == nil)
  }

  @Test
  func scopeToggleAppliesToTheShowingAlone() {
    let fixture = twoAppFixture(front: safari)
    fixture.presenter.handleHotkey(.parallelForward, deliveryDelay: nil)
    _ = fixture.presenter.handleKeyStroke(PanelKeystroke(
      keyCode: UInt16(kVK_ANSI_Slash),
      modifiers: .command,
      isARepeat: false
    ))

    #expect(fixture.surface.updatedLists.last?.count == 5)
    fixture.presenter.modifierFlagsChanged([])
    fixture.presenter.handleOptionRelease()
    #expect(!fixture.surface.isPresented)

    fixture.presenter.handleHotkey(.parallelForward, deliveryDelay: nil)
    let reopened = fixture.surface.presentedLists.last ?? []
    #expect(reopened.count == 3)
    #expect(reopened.allSatisfy { $0.ownerProcessIdentifier == safari })
  }

  @Test
  func parallelReverseWalksBackwards() {
    let fixture = twoAppFixture(front: safari)
    fixture.presenter.handleHotkey(.parallelForward, deliveryDelay: nil)
    let rows = twoAppRows()
    #expect(fixture.surface.presentedSelections.last == rows[1].id)
    fixture.presenter.handleHotkey(.parallelReverse, deliveryDelay: nil)

    #expect(fixture.surface.isPresented)
    #expect(fixture.surface.presentedLists.count == 1)
    #expect(fixture.surface.shownSelections.last == rows[0].id)
  }

  @Test
  func optionPressWithoutCommandOpens() {
    let fixture = twoAppFixture(front: safari, commandIsHeld: false, heldModifiers: .maskAlternate)
    fixture.presenter.handleHotkey(.parallelForward, deliveryDelay: nil)

    #expect(fixture.surface.isPresented)
  }

  @Test
  func optionReleaseCommitsAnOptionOpenedPanel() {
    let fixture = twoAppFixture(front: safari, commandIsHeld: false, heldModifiers: .maskAlternate)
    fixture.presenter.handleHotkey(.parallelForward, deliveryDelay: nil)

    #expect(fixture.surface.isPresented)
    fixture.presenter.handleOptionRelease()
    #expect(!fixture.surface.isPresented)
    #expect(fixture.log.lines.contains(where: { $0.hasPrefix("committed ") }))
  }

  @Test
  func commandReleaseCommitsNothingWhileOptionIsHeld() {
    let fixture = twoAppFixture(front: safari, commandIsHeld: false, heldModifiers: .maskAlternate)
    fixture.presenter.handleHotkey(.parallelForward, deliveryDelay: nil)

    #expect(fixture.surface.isPresented)
    fixture.presenter.handleCommandRelease()
    #expect(fixture.surface.isPresented)
    #expect(!fixture.log.lines.contains(where: { $0.hasPrefix("committed ") }))
  }

  @Test
  func commandReleaseAfterOptionReleaseCommits() {
    let fixture = twoAppFixture(front: safari, heldModifiers: [.maskCommand, .maskAlternate])
    fixture.presenter.handleHotkey(.parallelForward, deliveryDelay: nil)

    #expect(fixture.surface.isPresented)
    fixture.presenter.modifierFlagsChanged([.maskCommand])
    fixture.presenter.handleOptionRelease()
    #expect(fixture.surface.isPresented)
    #expect(!fixture.log.lines.contains(where: { $0.hasPrefix("committed ") }))
    fixture.presenter.modifierFlagsChanged([])
    fixture.presenter.handleCommandRelease()
    #expect(!fixture.surface.isPresented)
    #expect(fixture.log.lines.contains(where: { $0.hasPrefix("committed ") }))
  }

  @Test
  func filteringOptionReleaseCommitsNothing() {
    let fixture = twoAppFixture(front: safari, heldModifiers: .maskAlternate)
    fixture.presenter.handleHotkey(.parallelForward, deliveryDelay: nil)
    fixture.presenter.switchToFiltering()
    fixture.presenter.handleOptionRelease()

    #expect(fixture.surface.isPresented)
    #expect(!fixture.log.lines.contains(where: { $0.hasPrefix("committed ") }))
  }

  @Test(.timeLimit(.minutes(1)))
  func optionHeldPanelSurvivesTheReleaseWatch() async {
    let fixture = twoAppFixture(front: safari, commandIsHeld: false, heldModifiers: .maskAlternate)
    fixture.presenter.handleHotkey(.parallelForward, deliveryDelay: nil)

    #expect(fixture.surface.isPresented)
    let askedAtThePress = fixture.optionHold.askCount
    // Whichever comes first: a watch that asks about the wrong key takes
    // the panel down without ever asking about Option, and waiting on the
    // asks alone would then wait for good.
    let landed = FirstToLand()
    fixture.surface.onDismiss = { landed.signal() }
    Task {
      await fixture.optionHold.waitUntilAsked(times: askedAtThePress + 3)
      landed.signal()
    }
    await landed.wait()
    await settle()
    #expect(fixture.surface.isPresented)
    #expect(fixture.surface.dismissCount == 0)
  }

  @Test
  func delayedOptionReleaseCommitsWithoutShowing() async {
    let rows = interleavedRows()
    let switcher = FakeWindowSwitcher()
    let waiting = waitingPresenter(rows: rows, switcher: switcher)
    waiting.presenter.handleHotkey(.parallelForward, deliveryDelay: nil)

    #expect(waiting.presenter.pendingShow.isWaiting)
    waiting.presenter.handleOptionRelease()
    await settle()
    #expect(waiting.surface.presentedLists.isEmpty)
    #expect(waiting.log.lines.contains(where: { $0.hasPrefix("committed ") }))
    #expect(switcher.targets.map(\.id) == [rows[2].id])
  }

  @Test
  func delayedParallelTapAfterMainAppearanceKeepsTheFrontApplication() async {
    let rows = interleavedRows()
    let switcher = FakeWindowSwitcher()
    let waiting = waitingPresenter(rows: rows, switcher: switcher)
    waiting.presenter.showDelayMs = nil
    waiting.commandHold.isHeld = true
    waiting.presenter.handleHotkey(.forward, deliveryDelay: nil)
    #expect(waiting.surface.isPresented)
    waiting.presenter.handleCommandRelease()
    await settle()
    #expect(switcher.targets.map(\.id) == [rows[1].id])

    waiting.commandHold.isHeld = false
    waiting.presenter.showDelayMs = 150
    waiting.presenter.handleHotkey(.parallelForward, deliveryDelay: nil)
    #expect(waiting.presenter.pendingShow.isWaiting)
    waiting.presenter.handleOptionRelease()
    await settle()
    #expect(waiting.surface.presentedLists.count == 1)
    #expect(switcher.targets.map(\.id) == [rows[1].id, rows[2].id])
  }

  @Test
  func delayedMainTapAfterParallelAppearanceKeepsEveryApplication() async {
    let rows = interleavedRows()
    let switcher = FakeWindowSwitcher()
    let waiting = waitingPresenter(rows: rows, switcher: switcher)
    waiting.presenter.showDelayMs = nil
    waiting.presenter.handleHotkey(.parallelForward, deliveryDelay: nil)
    #expect(waiting.surface.isPresented)
    waiting.presenter.modifierFlagsChanged([])
    waiting.presenter.handleOptionRelease()
    await settle()
    #expect(switcher.targets.map(\.id) == [rows[2].id])

    waiting.commandHold.isHeld = true
    waiting.optionHold.isHeld = false
    waiting.presenter.showDelayMs = 150
    waiting.presenter.handleHotkey(.forward, deliveryDelay: nil)
    #expect(waiting.presenter.pendingShow.isWaiting)
    waiting.presenter.handleCommandRelease()
    await settle()
    #expect(waiting.surface.presentedLists.count == 1)
    #expect(switcher.targets.map(\.id) == [rows[2].id, rows[0].id])
  }

  @Test
  func otherInvocationMovesSelectionWithoutOpeningSecond() {
    let fixture = twoAppFixture(front: safari)
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    let rows = twoAppRows()
    #expect(fixture.surface.presentedSelections.last == rows[1].id)
    fixture.presenter.handleHotkey(.parallelForward, deliveryDelay: nil)

    #expect(fixture.surface.isPresented)
    #expect(fixture.surface.presentedLists.count == 1)
    #expect(fixture.surface.shownSelections.last == rows[2].id)
  }

  @Test
  func mainPressMovesParallelSelectionTheSameWay() {
    let fixture = twoAppFixture(front: safari)
    fixture.presenter.handleHotkey(.parallelForward, deliveryDelay: nil)
    let rows = twoAppRows()
    #expect(fixture.surface.presentedSelections.last == rows[1].id)
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)

    #expect(fixture.surface.isPresented)
    #expect(fixture.surface.presentedLists.count == 1)
    #expect(fixture.surface.shownSelections.last == rows[2].id)
  }

  @Test
  func filteringOtherInvocationHides() {
    let fixture = twoAppFixture(front: safari)
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    fixture.presenter.switchToFiltering()
    fixture.presenter.handleHotkey(.parallelForward, deliveryDelay: nil)

    #expect(!fixture.surface.isPresented)
    #expect(fixture.surface.presentedLists.count == 1)
  }

  @Test
  func otherInvocationWithoutMonitorHides() {
    let fixture = twoAppFixture(front: safari, closesOnCommandRelease: false)
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    fixture.presenter.handleHotkey(.parallelForward, deliveryDelay: nil)

    #expect(!fixture.surface.isPresented)
    #expect(fixture.surface.presentedLists.count == 1)
  }

  @Test
  func delayedOtherPressKeepsTheFirstPressSettings() async {
    let waiting = waitingPresenter()
    waiting.presenter.handleHotkey(.parallelForward, deliveryDelay: nil)
    waiting.commandHold.isHeld = true
    waiting.presenter.handleHotkey(.forward, deliveryDelay: nil)
    waiting.sleep.open()
    await settle()

    let shown = waiting.surface.presentedLists.last ?? []
    #expect(shown.count == 3)
    #expect(shown.allSatisfy { $0.ownerProcessIdentifier == safari })
    #expect(waiting.surface.shownSelections.count == 1)
    waiting.presenter.handleOptionRelease()
    #expect(!waiting.surface.isPresented)
    #expect(waiting.log.lines.contains(where: { $0.hasPrefix("committed ") }))
  }

  @Test
  func sharedDelayHoldsBothSwitchers() async {
    let main = waitingPresenter()
    main.commandHold.isHeld = true
    main.presenter.handleHotkey(.forward, deliveryDelay: nil)
    #expect(main.surface.presentedLists.isEmpty)
    #expect(main.presenter.pendingShow.isWaiting)

    let parallel = waitingPresenter()
    parallel.presenter.handleHotkey(.parallelForward, deliveryDelay: nil)
    #expect(parallel.surface.presentedLists.isEmpty)
    #expect(parallel.presenter.pendingShow.isWaiting)
    parallel.sleep.open()
    await settle()
    #expect(parallel.surface.presentedLists.count == 1)
  }

  @Test
  func otherSwitcherPressJoinsTheWait() async {
    let waiting = waitingPresenter()
    waiting.presenter.handleHotkey(.parallelForward, deliveryDelay: nil)
    #expect(waiting.presenter.pendingShow.isWaiting)
    #expect(waiting.surface.presentedLists.isEmpty)
    waiting.commandHold.isHeld = true
    waiting.presenter.handleHotkey(.forward, deliveryDelay: nil)
    #expect(waiting.surface.presentedLists.isEmpty)
    #expect(waiting.presenter.pendingShow.isWaiting)
    waiting.sleep.open()
    await settle()
    #expect(waiting.surface.presentedLists.count == 1)
    let shown = waiting.surface.presentedLists.last ?? []
    #expect(shown.count == 3)
    #expect(shown.allSatisfy { $0.ownerProcessIdentifier == safari })
    #expect(waiting.surface.shownSelections.count == 1)
  }

  @Test
  func firstListWaitDropsTheOtherPress() async {
    let fake = heldTwoAppGather()
    let fixture = Fixture(
      store: WindowListStore(gather: fake.gather, writeLine: { _ in }),
      commandIsHeld: false,
      heldModifiers: .maskAlternate
    )
    fixture.presenter.keyCommands.frontmostProcessIdentifier = { safari }
    fixture.presenter.handleHotkey(.parallelForward, deliveryDelay: nil)
    await fake.waitUntilCalled()
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    fake.finish()
    await settle()

    #expect(fixture.surface.presentedLists.count == 1)
    let shown = fixture.surface.presentedLists.last ?? []
    #expect(shown.count == 3)
    #expect(shown.allSatisfy { $0.ownerProcessIdentifier == safari })
  }

  @Test
  func parallelPressWithNeitherKeyHeldIsTurnedAway() {
    let fixture = twoAppFixture(front: safari, commandIsHeld: false, heldModifiers: [])
    fixture.optionHold.isHeld = false
    fixture.presenter.handleHotkey(.parallelForward, deliveryDelay: nil)

    #expect(!fixture.surface.isPresented)
    #expect(fixture.surface.presentedLists.isEmpty)
    #expect(fixture.log.lines == [
      "turned away Opt+Tab (parallel); Option was already up by the time the press arrived"
    ])
  }

  @Test
  func optionReleaseCallsOffAnOptionPressWaitingForItsList() async {
    let fake = heldTwoAppGather()
    let fixture = waitingForItsFirstList(fake)
    fixture.presenter.handleHotkey(.parallelForward, deliveryDelay: nil)
    await fake.waitUntilCalled()
    fixture.presenter.handleOptionRelease()
    fake.finish()
    await settle()

    #expect(fixture.surface.presentedLists.isEmpty)
    #expect(fixture.log.lines.count == 1)
    #expect(fixture.log.lines.first?.hasPrefix("press called off ") == true)
    #expect(fixture.log.lines.first?.contains("after Option was released") == true)
  }

  @Test
  func commandReleaseLeavesAnOptionPressWaitingForItsList() async {
    let fake = heldTwoAppGather()
    let fixture = waitingForItsFirstList(fake)
    fixture.presenter.handleHotkey(.parallelForward, deliveryDelay: nil)
    await fake.waitUntilCalled()
    fixture.presenter.handleCommandRelease()
    fake.finish()
    await settle()

    #expect(fixture.surface.presentedLists.count == 1)
    #expect(fixture.surface.isPresented)
    #expect(!fixture.log.lines.contains(where: { $0.hasPrefix("press called off ") }))
  }

  @Test
  func diagnosticLinesNameTheSwitcher() {
    let main = twoAppFixture(front: safari)
    main.presenter.handleHotkey(.forward, deliveryDelay: nil)
    #expect(main.log.lines.contains(where: { $0.hasPrefix("panel shown") && $0.contains("main") }))
    main.presenter.handleCommandRelease()
    #expect(main.log.lines.contains(where: { $0.hasPrefix("committed ") && $0.contains("main") }))

    let parallel = twoAppFixture(front: safari)
    parallel.presenter.handleHotkey(.parallelForward, deliveryDelay: nil)
    #expect(parallel.log.lines.contains(where: { $0.hasPrefix("panel shown") && $0.contains("parallel") }))
    parallel.presenter.modifierFlagsChanged([])
    parallel.presenter.handleOptionRelease()
    #expect(parallel.log.lines.contains(where: { $0.hasPrefix("committed ") && $0.contains("parallel") }))

    let filter = twoAppFixture(front: safari)
    filter.presenter.handleHotkey(.filter, deliveryDelay: nil)
    #expect(filter.log.lines.contains(where: { $0.hasPrefix("panel shown") && $0.contains("main") }))
  }

  @Test
  func displayModesReachParallelAppearance() {
    let rows = [
      parallelRow(1, owner: safari, app: "Safari", title: "Front page"),
      parallelRow(2, owner: safari, app: "Safari", title: "Downloads", minimized: true),
      parallelRow(3, owner: safari, app: "Safari", title: "Reading list"),
    ]
    let parallel = Fixture(store: WindowListStore(fixed: rows), windows: rows)
    parallel.presenter.windowScope = .allApps
    parallel.presenter.displayModes.minimized = .separateAtBottom
    parallel.presenter.parallelSwitcher.windowScope = .allApps
    parallel.presenter.parallelSwitcher.displayModes.minimized = .show
    parallel.presenter.handleHotkey(.parallelForward, deliveryDelay: nil)
    #expect(parallel.surface.presentedLists.last?.map(\.id) == rows.map(\.id))

    let main = Fixture(store: WindowListStore(fixed: rows), windows: rows)
    main.presenter.windowScope = .allApps
    main.presenter.handleHotkey(.forward, deliveryDelay: nil)
    #expect(main.surface.presentedLists.last?.map(\.id) == [rows[0].id, rows[2].id, rows[1].id])
  }

  @Test
  func listItemsReachParallelAppearance() {
    var overrides = ParallelOverrides.defaults
    overrides.windowScope = .own(.allApps)
    overrides.hiddenAppMode = .own(.hide)
    overrides.fullscreenMode = .own(.separateAtBottom)
    overrides.otherSpacePlacement = .own(.withinGroup)
    overrides.minimizedPlacement = .own(.withinGroup)
    let fixture = twoAppFixture(front: safari)
    fixture.presenter.grouping.mode = .manual
    fixture.presenter.grouping.groupCount = 3
    fixture.presenter.parallelSwitcher = .parallel(main: .mainDefaults, overrides: overrides)
    fixture.presenter.handleHotkey(.parallelForward, deliveryDelay: nil)

    let applied = fixture.surface.appliedSettings.last
    #expect(applied?.displayModes.hiddenApp == .hide)
    #expect(applied?.displayModes.fullscreen == .separateAtBottom)
    #expect(applied?.displayModes.minimized == DisplayModes.defaults.minimized)
    #expect(applied?.grouping.placements[.otherSpace] == .withinGroup)
    #expect(applied?.grouping.placements[.minimized] == .withinGroup)
    #expect(applied?.grouping.placements[.hiddenApp] == .endOfList)
    #expect(applied?.grouping.mode == .manual)
    #expect(applied?.grouping.groupCount == 3)
  }

  @Test
  func mainAppearanceKeepsItsOwnPlacements() {
    var overrides = ParallelOverrides.defaults
    overrides.minimizedPlacement = .own(.withinGroup)
    let fixture = twoAppFixture(front: safari)
    fixture.presenter.grouping.mode = .manual
    fixture.presenter.parallelSwitcher = .parallel(main: fixture.presenter.mainSwitcher, overrides: overrides)
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)

    let applied = fixture.surface.appliedSettings.last
    #expect(applied?.grouping.placement(of: .minimized) == .endOfList)
    #expect(applied?.grouping.mode == .manual)
  }

  @Test
  func followTracksMainChanges() {
    let rows = [
      parallelRow(1, owner: safari, app: "Safari", title: "Front page"),
      parallelRow(2, owner: safari, app: "Safari", title: "Downloads", minimized: true),
    ]
    let fixture = Fixture(store: WindowListStore(fixed: rows), windows: rows)
    fixture.presenter.windowScope = .allApps
    fixture.presenter.displayModes.minimized = .hide
    fixture.presenter.parallelSwitcher = .parallel(
      main: fixture.presenter.mainSwitcher,
      overrides: ParallelOverrides.defaults
    )
    fixture.presenter.parallelSwitcher.windowScope = .allApps
    fixture.presenter.handleHotkey(.parallelForward, deliveryDelay: nil)
    #expect(fixture.surface.presentedLists.last?.map(\.id) == [rows[0].id])
    fixture.presenter.modifierFlagsChanged([])
    fixture.presenter.handleOptionRelease()
    #expect(!fixture.surface.isPresented)

    var owned = ParallelOverrides.defaults
    owned.minimizedMode = .own(.show)
    fixture.presenter.parallelSwitcher = .parallel(main: fixture.presenter.mainSwitcher, overrides: owned)
    fixture.presenter.parallelSwitcher.windowScope = .allApps
    fixture.presenter.handleHotkey(.parallelForward, deliveryDelay: nil)
    #expect(fixture.surface.presentedLists.last?.map(\.id) == rows.map(\.id))
  }

  @Test
  func sharedGroupingReachesParallelAppearance() {
    let rows = manualRows()
    let fixture = Fixture(store: WindowListStore(fixed: rows), windows: rows)
    fixture.presenter.grouping.mode = .manual
    fixture.presenter.grouping.assignments = [GroupAssignment(bundleID: "com.example.front", group: 2)]
    fixture.presenter.grouping.groupCount = 2
    var overrides = ParallelOverrides.defaults
    overrides.windowScope = .own(.allApps)
    fixture.presenter.parallelSwitcher = .parallel(main: fixture.presenter.mainSwitcher, overrides: overrides)
    fixture.presenter.handleHotkey(.parallelForward, deliveryDelay: nil)
    #expect(fixture.surface.presentedLists.last?.map(\.id) == [rows[2].id, rows[3].id, rows[0].id, rows[1].id])
  }

  @Test
  func sharedFuzzyMatchReachesParallelAppearance() {
    let rows = [
      parallelRow(1, owner: safari, app: "Safari", title: "Front page"),
      parallelRow(2, owner: finder, app: "Finder", title: "Documents"),
    ]
    let fixture = Fixture(store: WindowListStore(fixed: rows), windows: rows)
    fixture.presenter.searchSettings.fuzzyMatchEnabled = false
    var overrides = ParallelOverrides.defaults
    overrides.windowScope = .own(.allApps)
    fixture.presenter.parallelSwitcher = .parallel(main: .mainDefaults, overrides: overrides)
    fixture.presenter.handleHotkey(.parallelForward, deliveryDelay: nil)
    fixture.presenter.switchToFiltering()
    for character in "Frp" {
      _ = fixture.presenter.handleKeyStroke(pressForTyping(String(character)))
    }
    #expect(fixture.surface.updatedLists.last?.isEmpty == true)
  }

  @Test
  func liveMainWritesKeepParallelListing() {
    let rows = [
      parallelRow(1, owner: safari, app: "Safari", title: "Front page"),
      parallelRow(2, owner: safari, app: "Safari", title: "Downloads", minimized: true),
    ]
    let fixture = Fixture(store: WindowListStore(fixed: rows), windows: rows)
    fixture.presenter.windowScope = .allApps
    var overrides = ParallelOverrides.defaults
    overrides.windowScope = .own(.allApps)
    overrides.minimizedMode = .own(.show)
    fixture.presenter.parallelSwitcher = .parallel(main: .mainDefaults, overrides: overrides)
    fixture.presenter.handleHotkey(.parallelForward, deliveryDelay: nil)
    #expect(fixture.surface.presentedLists.last?.map(\.id) == rows.map(\.id))
    fixture.presenter.windowScope = .frontApp
    fixture.presenter.grouping = GroupingPolicy()
    fixture.presenter.displayModes.minimized = .hide
    fixture.presenter.switchToFiltering()
    for character in "Saf" {
      _ = fixture.presenter.handleKeyStroke(pressForTyping(String(character)))
    }
    #expect(fixture.surface.updatedLists.last?.map(\.id) == rows.map(\.id))
  }

  @Test
  func sharedResultOrderReachesParallelAppearance() {
    let rows = [
      parallelRow(1, owner: safari, app: "Safari", title: "a--b"),
      parallelRow(2, owner: safari, app: "Safari", title: "xab"),
    ]
    let fixture = Fixture(store: WindowListStore(fixed: rows), windows: rows)
    fixture.presenter.searchSettings.ordering = .score
    var overrides = ParallelOverrides.defaults
    overrides.windowScope = .own(.allApps)
    fixture.presenter.parallelSwitcher = .parallel(main: .mainDefaults, overrides: overrides)
    fixture.presenter.handleHotkey(.parallelForward, deliveryDelay: nil)
    fixture.presenter.switchToFiltering()
    for character in "ab" {
      _ = fixture.presenter.handleKeyStroke(pressForTyping(String(character)))
    }
    #expect(fixture.surface.updatedLists.last?.map(\.id) == [rows[1].id, rows[0].id])
  }

  @Test
  func sharedNumberScopeReachesParallelAppearance() {
    let rows = [
      parallelRow(1, owner: safari, app: "Safari", title: "Front page"),
      parallelRow(2, owner: safari, app: "Safari", title: "Downloads"),
      windowlessParallelRow(),
    ]
    let fixture = Fixture(store: WindowListStore(fixed: rows), windows: rows)
    fixture.presenter.windowScope = .allApps
    fixture.presenter.displayModes.windowlessApp = .show
    fixture.presenter.numberScope = .allRows
    var overrides = ParallelOverrides.defaults
    overrides.windowScope = .own(.allApps)
    fixture.presenter.parallelSwitcher = .parallel(main: fixture.presenter.mainSwitcher, overrides: overrides)
    fixture.presenter.handleHotkey(.parallelForward, deliveryDelay: nil)
    #expect(fixture.presenter.keyCommands.numberedRows().count == 3)
  }

  @Test
  func sharedNumberJumpReachesParallelAppearance() {
    let fixture = twoAppFixture(front: safari, heldModifiers: .maskAlternate)
    fixture.presenter.numberJump = true
    fixture.presenter.handleHotkey(.parallelForward, deliveryDelay: nil)
    #expect(fixture.surface.numberedRowOrders.last?.isEmpty == false)
  }

  @Test
  func sharedStaysSharedAcrossSwitchers() {
    let rows = manualRows()
    let fixture = Fixture(store: WindowListStore(fixed: rows), windows: rows)
    fixture.presenter.grouping.mode = .manual
    fixture.presenter.grouping.assignments = [GroupAssignment(bundleID: "com.example.front", group: 2)]
    fixture.presenter.grouping.groupCount = 2
    fixture.presenter.grouping.names = [2: "Browsing"]
    fixture.presenter.grouping.headingStyle = .name
    var overrides = ParallelOverrides.defaults
    overrides.windowScope = .own(.allApps)
    overrides.minimizedPlacement = .own(.withinGroup)
    fixture.presenter.parallelSwitcher = .parallel(main: fixture.presenter.mainSwitcher, overrides: overrides)
    fixture.presenter.handleHotkey(.parallelForward, deliveryDelay: nil)
    let parallelApplied = fixture.surface.appliedSettings.last
    #expect(parallelApplied?.grouping.mode == .manual)
    #expect(parallelApplied?.grouping.groupCount == 2)
    #expect(parallelApplied?.grouping.headingStyle == .name)
    #expect(parallelApplied?.grouping.names == [2: "Browsing"])
    #expect(parallelApplied?.grouping.assignments == [GroupAssignment(bundleID: "com.example.front", group: 2)])
    #expect(parallelApplied?.grouping.placement(of: .minimized) == .withinGroup)
    #expect(fixture.surface.presentedLists.last?.map(\.id) == [rows[2].id, rows[3].id, rows[0].id, rows[1].id])
  }

  @Test
  func switchedOffParallelPressOpensNothing() {
    let fixture = twoAppFixture(front: safari)
    fixture.presenter.parallelEnabled = false
    fixture.presenter.handleHotkey(.parallelForward, deliveryDelay: nil)

    #expect(!fixture.surface.isPresented)
    #expect(fixture.surface.presentedLists.isEmpty)
    #expect(fixture.log.lines.isEmpty)
  }

  @Test
  func switchedOffParallelPressMovesNothing() {
    let fixture = twoAppFixture(front: safari)
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    let first = fixture.surface.shownSelections.last
    fixture.presenter.parallelEnabled = false
    fixture.presenter.handleHotkey(.parallelForward, deliveryDelay: nil)

    #expect(fixture.surface.isPresented)
    #expect(fixture.surface.presentedLists.count == 1)
    #expect(fixture.surface.shownSelections.last == first)
  }

  @Test
  func mirrorsReceiveTheSameSettings() {
    let first = FakeSurface()
    let second = FakeSurface()
    let composite = MirroredPanelSurface(panels: [first, second])
    let settings = AppliedPanelSettings.resolve(
      .parallel(main: .mainDefaults, overrides: ParallelOverrides.defaults),
      sharedGrouping: GroupingPolicy()
    )
    composite.applyPanelSettings(settings)
    #expect(first.appliedSettings == [settings])
    #expect(second.appliedSettings == [settings])
  }

  // MARK: Private

  private let safari: pid_t = 100
  private let finder: pid_t = 200

  /// Five rows across two owners, with the front application injected so
  /// no window server takes part.
  private func manualRows() -> [WindowItem] {
    [
      manualRow(1, bundle: "com.example.front"),
      manualRow(2, bundle: "com.example.front"),
      manualRow(3, bundle: "com.example.previous"),
      manualRow(4, bundle: "com.example.previous"),
    ]
  }

  private func manualRow(_ windowID: CGWindowID, bundle: String) -> WindowItem {
    WindowItem(
      id: WindowItem.Identifier(windowID: windowID),
      ownerProcessIdentifier: pid_t(windowID),
      appName: "App\(windowID)",
      bundleIdentifier: bundle,
      windowTitle: "Window",
      kind: .standard,
      isMinimized: false,
      icon: NSImage(size: NSSize(width: 1, height: 1))
    )
  }

  private func windowlessParallelRow() -> WindowItem {
    WindowItem(
      id: .application(321),
      ownerProcessIdentifier: 321,
      appName: "Music",
      bundleIdentifier: "com.apple.Music",
      windowTitle: "",
      kind: .standard,
      isMinimized: false,
      icon: NSImage(size: NSSize(width: 1, height: 1))
    )
  }

  private func pressForTyping(_ characters: String) -> PanelKeystroke {
    PanelKeystroke(keyCode: UInt16(kVK_ANSI_A), modifiers: [], isARepeat: false, characters: characters)
  }

  private func twoAppRows() -> [WindowItem] {
    [
      parallelRow(1, owner: safari, app: "Safari", title: "Front page"),
      parallelRow(2, owner: safari, app: "Safari", title: "Downloads"),
      parallelRow(3, owner: safari, app: "Safari", title: "Reading list"),
      parallelRow(4, owner: finder, app: "Finder", title: "Documents"),
      parallelRow(5, owner: finder, app: "Finder", title: "Desktop"),
    ]
  }

  /// A gather that holds the two-application list until released, so a
  /// press can be left waiting for its first list.
  private func heldTwoAppGather() -> HeldGather {
    HeldGather(answer: WindowListSnapshot(
      items: twoAppRows(),
      applicationCount: 2,
      gatheringDuration: .milliseconds(12),
      skipped: [],
      droppedWithoutID: 0,
      gatheredAt: .now
    ))
  }

  /// A presenter with a monitor running and no list yet, whose press
  /// arrives as Opt+Tab does: Option down, Command up.
  private func waitingForItsFirstList(_ fake: HeldGather) -> Fixture {
    let fixture = Fixture(
      store: WindowListStore(gather: fake.gather, writeLine: { _ in }),
      closesOnCommandRelease: true,
      commandIsHeld: false,
      heldModifiers: .maskAlternate
    )
    fixture.presenter.keyCommands.frontmostProcessIdentifier = { safari }
    return fixture
  }

  /// Rows whose recent-use order puts the other application's window
  /// between the front application's, so the scope decides which row
  /// comes second.
  private func interleavedRows() -> [WindowItem] {
    [
      parallelRow(4, owner: finder, app: "Finder", title: "Documents"),
      parallelRow(1, owner: safari, app: "Safari", title: "Front page"),
      parallelRow(2, owner: safari, app: "Safari", title: "Downloads"),
      parallelRow(5, owner: finder, app: "Finder", title: "Desktop"),
      parallelRow(3, owner: safari, app: "Safari", title: "Reading list"),
    ]
  }

  /// A presenter held at its show delay, so presses and releases land
  /// while the wait is still shut. Both holds start as an Option-held
  /// press finds them: Command up, Option down.
  private func waitingPresenter(
    rows: [WindowItem]? = nil,
    switcher: FakeWindowSwitcher = FakeWindowSwitcher()
  ) -> (
    presenter: PanelPresenter,
    surface: FakeSurface,
    log: DiagnosticsLog,
    sleep: GatedSleep,
    commandHold: CommandHold,
    optionHold: CommandHold
  ) {
    let surface = FakeSurface()
    let log = DiagnosticsLog()
    let clock = SteppingClock(step: .microseconds(4800))
    let sleep = GatedSleep()
    let commandHold = CommandHold(isHeld: false)
    let optionHold = CommandHold(isHeld: true)
    let presenter = PanelPresenter(
      surface: surface,
      store: WindowListStore(fixed: rows ?? twoAppRows()),
      ownProcessIdentifier: ownProcess,
      now: clock.read,
      writeLine: log.write,
      closesOnCommandRelease: { true },
      commandIsHeld: { [commandHold] in commandHold.read() },
      optionIsHeld: { [optionHold] in optionHold.read() },
      modifierFlags: { .maskAlternate },
      commandWatchInterval: .milliseconds(1),
      keyStatusWatchInterval: .milliseconds(1),
      showDelayMs: 150,
      showDelaySleep: sleep.sleep,
      switcher: switcher
    )
    presenter.keyCommands.frontmostProcessIdentifier = { safari }
    presenter.parallelSwitcher = .parallel(main: presenter.mainSwitcher, overrides: .defaults)
    return (presenter, surface, log, sleep, commandHold, optionHold)
  }

  private func twoAppFixture(
    front: pid_t,
    commandIsHeld: Bool = true,
    heldModifiers: CGEventFlags = .maskCommand,
    closesOnCommandRelease: Bool = true
  ) -> Fixture {
    let rows = twoAppRows()
    let fixture = Fixture(
      store: WindowListStore(fixed: rows),
      windows: rows,
      closesOnCommandRelease: closesOnCommandRelease,
      commandIsHeld: commandIsHeld,
      heldModifiers: heldModifiers
    )
    fixture.presenter.keyCommands.frontmostProcessIdentifier = { front }
    return fixture
  }

}

// MARK: - FirstToLand

/// Lets a test wait on more than one thing at once and go on at the first
/// of them, so an awaited event that never comes cannot hold it past one
/// that settles the outcome.
@MainActor
private final class FirstToLand {

  // MARK: Internal

  func signal() {
    landed = true
    continuation?.resume()
    continuation = nil
  }

  func wait() async {
    guard !landed else { return }
    await withCheckedContinuation { continuation = $0 }
  }

  // MARK: Private

  private var landed = false
  private var continuation: CheckedContinuation<Void, Never>?

}
