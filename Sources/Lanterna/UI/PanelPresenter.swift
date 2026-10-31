import AppKit
import CoreGraphics
import Darwin
import Logging

// MARK: - PanelPresenter

/// Decides when the panel goes up, and writes down what each press cost.
@MainActor
final class PanelPresenter {

  // MARK: Lifecycle

  init(
    surface: any SwitcherSurface,
    store: WindowListStore,
    displayModes: DisplayModes = .defaults,
    exclusionRules: [ExclusionRule] = [],
    searchSettings: SearchSettings = SearchSettings(),
    keyBindings: KeyBindingTable = .defaults,
    ownProcessIdentifier: pid_t = getpid(),
    now: @escaping @MainActor () -> ContinuousClock.Instant = { ContinuousClock.now },
    writeLine: @escaping @MainActor (LogLine) -> Void = { Diagnostics.writeLine($0) },
    closesOnCommandRelease: @escaping @MainActor () -> Bool = { false },
    commandIsHeld: @escaping @MainActor () -> Bool = {
      CGEventSource.flagsState(.combinedSessionState).contains(.maskCommand)
    },
    optionIsHeld: @escaping @MainActor () -> Bool = {
      CGEventSource.flagsState(.combinedSessionState).contains(.maskAlternate)
    },
    modifierFlags: @escaping @MainActor () -> CGEventFlags = {
      CGEventSource.flagsState(.combinedSessionState)
    },
    commandWatchInterval: Duration = UnreportedReleaseWatch.defaultInterval,
    keyStatusWatchInterval: Duration = KeyStatusWatch.defaultInterval,
    showDelayMs: Double? = nil,
    showDelaySleep: @escaping @MainActor (Duration) async -> Void = { duration in
      try? await Task.sleep(for: duration)
    },
    invocationKeyIsDown: @escaping @MainActor (UInt16) -> Bool = { keyCode in
      CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(keyCode))
    },
    invocationRepeatTiming: @escaping @MainActor () -> InvocationKeyRepeat.Timing = {
      InvocationKeyRepeat.timing(
        initialDelay: .seconds(NSEvent.keyRepeatDelay),
        interval: .seconds(NSEvent.keyRepeatInterval)
      )
    },
    invocationRepeatSleep: @escaping @MainActor (Duration) async -> Void = { duration in
      try? await Task.sleep(for: duration)
    },
    switcher: any WindowSwitching = LiveWindowSwitcher(),
    closer: any WindowClosing = LiveWindowCloser(),
    minimizer: any WindowMinimizing = LiveWindowMinimizer(),
    tracker: MRUTracker = MRUTracker()
  ) {
    self.surface = surface
    selection = PanelSelection(surface: surface)
    self.store = store
    self.displayModes = displayModes
    self.exclusionRules = exclusionRules
    self.searchSettings = searchSettings
    self.keyBindings = keyBindings
    self.ownProcessIdentifier = ownProcessIdentifier
    self.now = now
    self.writeLine = writeLine
    self.closesOnCommandRelease = closesOnCommandRelease
    self.commandIsHeld = commandIsHeld
    self.optionIsHeld = optionIsHeld
    self.modifierFlags = modifierFlags
    self.commandWatchInterval = commandWatchInterval
    self.keyStatusWatchInterval = keyStatusWatchInterval
    self.showDelayMs = showDelayMs
    self.showDelaySleep = showDelaySleep
    self.invocationKeyIsDown = invocationKeyIsDown
    self.invocationRepeatTiming = invocationRepeatTiming
    self.invocationRepeatSleep = invocationRepeatSleep
    self.switcher = switcher
    self.closer = closer
    self.minimizer = minimizer
    self.tracker = tracker
    keyCommands.onRowOrderChanged = { [weak self] order in self?.didReorderRows(order) }
  }

  // MARK: Internal

  /// Handed on to the way out and the operations, built beside the presenter.
  let surface: any SwitcherSurface
  /// Where the rows come from: already gathered, in the ordinary case.
  let store: WindowListStore
  var displayModes: DisplayModes
  let ownProcessIdentifier: pid_t
  /// Handed on to the way out, built beside the presenter.
  let now: @MainActor () -> ContinuousClock.Instant
  let writeLine: @MainActor (LogLine) -> Void

  /// A press that arrived before any list had been gathered and is waiting
  /// for one.
  ///
  /// `lazy` for the reason the watch below is: what it waits on and what it
  /// does when the waiting is over are both this object's.
  /// The activation handling, kept beside the presenter, calls it off.
  lazy var pendingPress = PendingPressHold(
    listWhenGathered: { [store] in await store.listWhenGathered() },
    show: { [weak self] items, combination, deliveryDelay, startedAt, commitOnCommand in
      guard let self else { return }
      // A press the delay is holding owns every arrival while it
      // waits: the list joins the wait instead of opening a panel.
      if pendingShow.isWaiting {
        pendingShow.listArrived(items, gatheredOnDemand: true)
        return
      }
      show(
        items,
        for: combination,
        deliveryDelay: deliveryDelay,
        startedAt: startedAt,
        gatheredOnDemand: true,
        commitOnCommand: commitOnCommand
      )
    }
  )

  /// A press the show delay is holding off the screen.
  ///
  /// `lazy` for the reason the hold above is: what it waits out and
  /// what it does when the waiting is over are both this object's.
  /// The release and activation handling beside the presenter call it off.
  lazy var pendingShow = PendingShowHold(
    sleep: showDelaySleep,
    fire: { [weak self] waiting in
      self?.showFromDelay(waiting)
    }
  )

  /// The hold that walks the selection after Carbon's one press.
  ///
  /// `lazy` because the tick reaches back into this object, the way the
  /// show-delay hold above does.
  lazy var invocationRepeatClock = InvocationRepeatClock(
    sleep: invocationRepeatSleep,
    onTick: { [weak self] in
      self?.advanceInvocationRepeat()
    }
  )

  /// How long the key-status watch waits between looks (`KeyStatusWatch`'s
  /// number, injected so a test need not wait a real one out), handed on
  /// to the way out, which is built beside the presenter.
  let keyStatusWatchInterval: Duration

  /// The show delay in milliseconds. Nil or zero means off. Read at
  /// every press, so a change lands on the next one.
  var showDelayMs: Double?

  /// How the delay wait passes its time. Injected so a test need not
  /// wait a real one out.
  let showDelaySleep: @MainActor (Duration) async -> Void

  /// Whether the invocation key is physically down. Asked on each
  /// repeat tick. Injected because a test holds no real key.
  let invocationKeyIsDown: @MainActor (UInt16) -> Bool

  /// The user's key-repeat delay and interval, read when a hold arms.
  let invocationRepeatTiming: @MainActor () -> InvocationKeyRepeat.Timing

  /// How a hold waits between ticks. Injected so a test opens one tick.
  let invocationRepeatSleep: @MainActor (Duration) async -> Void

  /// The physical key of the invocation press now being repeated.
  var invocationRepeatKeyCode: UInt16 = 0

  /// When that key went down. Set with the key code on every press.
  var invocationRepeatPressedAt = ContinuousClock.now

  /// What commits take. Through to the way out, which owns the list the
  /// target is read off and is built beside the presenter.
  let switcher: any WindowSwitching

  /// What the close and minimize keys send, through to the operations.
  let closer: any WindowClosing
  let minimizer: any WindowMinimizing

  /// What commits and appearances consult for the order rows are drawn in,
  /// owned here so recording and sorting share one memory.
  let tracker: MRUTracker

  /// The looking that catches a release the tap never reported.
  ///
  /// `lazy` because every question it puts and the answer it gives back are
  /// this object's. One watch for the presenter's life, started and stopped
  /// the way the window list's loop is rather than made again for each panel.
  /// The way out, built beside the presenter, stops it as the panel goes.
  lazy var commandWatch = UnreportedReleaseWatch(
    interval: commandWatchInterval,
    isPanelUp: { [weak self] in self?.surface.isPresented ?? false },
    commandIsHeld: { [weak self] in self?.commitKeyIsHeld() ?? false },
    // The chosen row is read here and not inside the call, because the
    // call is what clears it. Swift settles the argument before the
    // method runs, so the order is the language's rather than a habit.
    onUnreportedRelease: { [weak self] in
      self?.wayOut.closeForAnUnreportedRelease(
        naming: self?.selection.chosenID,
        commitOnCommand: self?.commitOnCommand ?? true
      )
    }
  )

  /// The Fast Search on screen or waiting for its first list, if any.
  /// Its own steps live in `PanelPresenterFastSearch.swift`.
  var fastSearchSession: FastSearchSession?

  /// Whether a Fast Search key is down, for the release watch. Replaced
  /// by tests, which have no keyboard to read.
  var fastSearchKeyIsHeld: @MainActor (FastSearchModifier) -> Bool = { FastSearchReleaseWatch.liveIsHeld($0) }

  /// How often the Fast Search release watch looks. Shortened by tests.
  var fastSearchReleaseWatchInterval = UnreportedReleaseWatch.defaultInterval

  /// Told whenever a switcher panel goes up or comes down, and when a Fast
  /// Search starts or ends, so whoever starts Fast Search can stop starting
  /// one over a panel or another search.
  var onSwitcherSessionChanged: (@MainActor () -> Void)?

  /// Told when a Fast Search panel comes down, so the search's key can be
  /// held on without its letters reaching the application.
  var onFastSearchClosed: (@MainActor () -> Void)?

  /// Which row of the list on screen is chosen.
  ///
  /// Kept apart from the list it indexes, and the line is drawn where it is
  /// on purpose: `PanelExit` names rows, and naming is not choosing. Given
  /// up where the panel comes off the screen rather than at each way out,
  /// so no way out can be the one that forgets.
  /// That giving up is wired into the way out, built beside the presenter.
  let selection: PanelSelection

  /// Every way the panel comes off the screen, and the list it was showing
  /// while it was up.
  ///
  /// `lazy` for the reason the watch above is: what it does when the panel
  /// goes reaches back into this object.
  ///
  /// Built by a function rather than written out here, because these two
  /// name each other — the watch reports a release to the way out, and the
  /// way out stops the watch — and two `lazy` properties whose types are
  /// both left to be worked out from expressions naming the other cannot
  /// be worked out at all. A declared return type settles one of them, and
  /// the other follows. Spelling the type on the property instead would say
  /// the same thing, and the formatter would take it straight back off
  /// again as a repetition of the initialiser beside it.
  /// The operations, built beside the presenter, close the panel through it.
  lazy var wayOut = makeWayOut()

  /// What a press means to a panel that is up.
  ///
  /// `lazy` because it is handed the way out, which is itself `lazy`. It
  /// holds one appearance's input state, while the panel, the chosen row
  /// and the ways out are all this object's, so the two can share them
  /// rather than keep second copies.
  /// The way out and the operations, built beside the presenter, reach it.
  lazy var keyCommands = PanelKeyCommands(
    surface: surface,
    selection: selection,
    wayOut: wayOut,
    displayModes: displayModes,
    exclusionRules: exclusionRules,
    searchSettings: searchSettings,
    keyBindings: keyBindings,
    now: now,
    operate: { [weak self] operation, chosen in
      self?.startOperation(operation, naming: chosen)
    },
    startFiltering: { [weak self] in self?.switchToFiltering() },
    openSettings: { [weak self] in self?.onOpenSettings?() }
  )

  /// Carries out the operations on the chosen row. Made beside the
  /// presenter, so no two `lazy` properties name each other.
  lazy var operations = makeOperations()

  /// Whether hovering a row moves the selection. Read on every hover:
  /// a panel that is up keeps answering to the value from launch until
  /// the change lands.
  var hoverSelect = false

  /// Whether scrolling moves the selection. Same timing as above.
  var scrollSelect = false

  /// The commit switches every switcher shares. Read fresh at each
  /// take, so a change lands on the next commit without a restart.
  var activationPolicy = ActivationPolicy.off

  /// Whether row icons carry their application's Dock badge. Shared by
  /// both switchers and read at every appearance, so a change lands on
  /// the next one without a restart.
  var appIconBadges = false

  /// Where the Dock's badges are read from. Set by whoever owns the
  /// window list, which knows whether the rows are real.
  var badgeReader: any DockBadgeReading = LiveDockBadgeReader()

  /// Why the last unreadable Dock was written down, so the same reason is
  /// written once rather than on every appearance. Cleared by a good read.
  var lastReportedBadgeFailure: String?

  /// Where a rearranged row order goes for saving. Set by whoever
  /// owns the file; the key commands report through here.
  var onRowOrderChanged: ((ManualRowOrder) -> Void)?

  /// Where opening the settings goes. Set by whoever owns the file.
  var onOpenSettings: (@MainActor () -> Void)?

  /// The parallel switcher's resolved list settings, beside the main one.
  var parallelSwitcher = SwitcherSettings.parallel(main: .mainDefaults, overrides: .defaults)

  /// Whether the parallel invocations reach the panel at all. Carbon
  /// stops delivering them once the switch is off, so a press arriving
  /// anyway is a race between the switch and the press, and is left alone.
  var parallelEnabled = true

  /// Which switcher opened the appearance on screen, or the last one
  /// after it closes. Read by the commit and the diagnostics; each
  /// appearance sets it as it goes up.
  private(set) var activeSwitcher = SwitcherIdentity.main

  /// Taken while the panel is up, given back on every way out and at quit.
  /// The settings set its target; a change lands at the next appearance.
  let inputSourceLock = InputSourceLock()

  /// Whether a filter that narrows to one row focuses that row.
  /// On unless the setting says otherwise. A change lands on the
  /// live filter at once.
  var autoFocusSingleCandidate = true {
    didSet { keyCommands.autoFocusSingleCandidate = autoFocusSingleCandidate }
  }

  /// How long that one row has to stay one row. Tests replace the sleep.
  var singleCandidateSleep: @MainActor (Duration) async -> Void = { duration in
    try? await Task.sleep(for: duration)
  } {
    didSet { keyCommands.singleCandidateSleep = singleCandidateSleep }
  }

  /// The main switcher's resolved list settings, read off the scope,
  /// display mode, and grouping fields. Computed so they never drift
  /// apart: every staging of a legacy field lands here with it.
  var mainSwitcher: SwitcherSettings {
    SwitcherSettings(
      windowScope: windowScope,
      displayModes: displayModes,
      subgroupPlacements: grouping.placements
    )
  }

  /// Whether digits with a jump modifier name rows. Read on every
  /// press, the same timing as above.
  var numberJump = false {
    didSet {
      keyCommands.updateNumberJump(numberJump)
      pushNumberedRows()
    }
  }

  /// Whether reorder presses move rows. Same timing as above.
  var numberReorder = false {
    didSet { keyCommands.updateReorder(numberReorder) }
  }

  /// Which rows numbers name. Same timing as above.
  var numberScope = NumberScope.windows {
    didSet { keyCommands.updateNumberScope(numberScope) }
  }

  /// The hand-arranged row orders shadowing the drawn order. Same
  /// timing as the grouping below.
  var rowOrder = ManualRowOrder.none {
    didSet { keyCommands.updateRowOrder(rowOrder) }
  }

  /// The compiled exclusion rules, handed to the key commands beside
  /// the modes, so the filter and the panel judge the same rows out.
  /// A change lands on the live filter at once: settings edits apply
  /// without waiting for the next launch.
  var exclusionRules: [ExclusionRule] {
    didSet { keyCommands.updateExclusions(exclusionRules) }
  }

  /// The three search-quality settings as one value, handed to the key
  /// commands beside the modes. A change lands on the live filter at
  /// once, like the exclusion rules.
  var searchSettings = SearchSettings() {
    didSet { pushSearchSettings() }
  }

  /// Which applications' rows each appearance starts on, handed to the
  /// key commands. A panel that is up keeps its own until it closes.
  var windowScope = WindowScope.allApps {
    didSet {
      guard !surface.isPresented || activeSwitcher == .main else { return }
      keyCommands.updateWindowScope(windowScope)
    }
  }

  /// How the rows are grouped, handed to the key commands like the modes.
  /// The parked-section placements are the main switcher's; a panel the
  /// parallel switcher opened keeps its own placements over the shared
  /// rest.
  var grouping = GroupingPolicy() {
    didSet {
      keyCommands.updateGrouping(
        AppliedPanelSettings.resolve(settings(for: activeSwitcher), sharedGrouping: grouping).grouping
      )
    }
  }

  /// The resolved key bindings, handed to the key commands. A change
  /// lands on the live panel at once, like the exclusion rules.
  var keyBindings = KeyBindingTable.defaults {
    didSet { keyCommands.updateKeyBindings(keyBindings) }
  }

  /// Whether typing a letter in a switcher panel starts filtering.
  var typingStartsFiltering: Bool {
    get { keyCommands.typingStartsFiltering }
    set {
      keyCommands.typingStartsFiltering = newValue
      keyCommands.onTypedFilterStart = { [weak self] in self?.disarmInvocationRepeat() }
    }
  }

  /// Puts the panel up for a press, and takes it down again if the press
  /// found one already up and letting go of Command is not what will close
  /// it. That is three of the four states enumerated below, not only the
  /// run with no monitor.
  ///
  /// That second job is a fallback now rather than the design. One key doing
  /// both was what dismissed the panel without a second key having to be
  /// learned or claimed from the system; where letting go of Command does
  /// the dismissing, a further press moves the selection along instead,
  /// which is the keystroke the user reaches for anyway while the key is
  /// still down.
  ///
  /// Nothing here turns a Carbon press away for arriving too soon after
  /// the last one. Carbon still delivers one hotkey event per physical
  /// press. A three-second hold produced exactly one while this method
  /// could only put the panel up, so the reading cannot be a toggle
  /// racing itself. The hold is walked by the repeat clock once the
  /// panel is up, at the system repeat rate. That clock is not a second
  /// Carbon event, and a suppression window on this method would still
  /// have nothing to suppress.
  ///
  /// Synchronous on purpose. With a list already held the panel goes up in
  /// the same turn the press arrives, so the reading below starts where the
  /// press does and there is no ordering between a press and its panel to
  /// reason about.
  func handleHotkey(
    _ combination: HotkeyCombination,
    deliveryDelay: Duration?,
    heldKeyCode: UInt16? = nil
  ) {
    // Read before anything else, because both questions below are put to
    // the window server rather than answered in this process. A span begun
    // after them would leave out work this process is answerable for, and
    // would quietly shrink as anything further moved ahead of the read
    // while the figure went on reading the same. A press that is turned
    // away writes no line at all, so charging it a clock read costs
    // nothing.
    let startedAt = now()
    // A switched-off parallel switcher owns no press: Carbon stops
    // delivering its invocations with the switch, so one arriving now
    // went out before the switch did. It moves nothing and opens nothing.
    if combination.switcher == .parallel, !parallelEnabled {
      return
    }
    if surface.isPresented {
      rememberInvocationKey(combination, heldKeyCode: heldKeyCode, startedAt: startedAt, deliveryDelay: deliveryDelay)
      handlePressWhilePresented(combination, at: startedAt)
      return
    }
    // The press comes in through Carbon and the release through the tap,
    // two sources with no order between them and a measured delay on the
    // Carbon side, so a quick tap can deliver the release first and leave
    // the press arriving after the gesture it belongs to is over. Putting
    // a panel up for it would leave one on screen the user has finished
    // with, and the next Command to be let go — a bare tap, the tail of a
    // Cmd+C — would be written down as a commit of a row nobody chose.
    // Only worth asking with a monitor running: without one there is no
    // release being listened for and so none to lose, and the panel is
    // still closed by a further press.
    //
    // Asked as the press arrives and not where the panel goes up, because
    // a press held back waiting for the first list can lose its Command
    // too, and that one is already answered — the release calls the
    // pending press off. Here is what nothing else covers.
    // The commit key is what the press still holds: Carbon only fires on
    // an exact modifier match, so the held modifiers are the invocation's.
    // A main press answers Command alone, as it long has; a parallel
    // press without Command answers Option instead. With no monitor the
    // question is never put, so nothing is asked and the key stays Command.
    let commitOnCommand: Bool
    if closesOnCommandRelease() {
      let commandHeld = commandIsHeld()
      commitOnCommand = commandHeld
      let held = commandHeld || (combination.switcher == .parallel && optionIsHeld())
      guard held else {
        let key = combination.switcher == .parallel ? "Option" : "Command"
        writeLine(LogLine(
          .info,
          .panel,
          "turned away \(combination.name) (\(combination.switcher.diagnosticsName)); "
            + "\(key) was already up by the time the press arrived"
        ))
        return
      }
    } else {
      commitOnCommand = true
    }
    rememberInvocationKey(combination, heldKeyCode: heldKeyCode, startedAt: startedAt, deliveryDelay: deliveryDelay)
    // A press is already waiting for the first list and is the one that
    // will put the panel up. The panel is not up yet, so without this a
    // second press would take the same path again and two would arrive.
    // A press the delay is holding is the exception: further presses
    // join its wait instead of being turned away.
    if pendingPress.isWaiting, pendingShowHoldIsOff {
      return
    }
    if let delay = showDelay {
      holdForDelay(
        combination,
        deliveryDelay: deliveryDelay,
        startedAt: startedAt,
        delay: delay,
        commitOnCommand: commitOnCommand
      )
      return
    }
    guard let held = store.snapshot else {
      pendingPress.begin(
        combination,
        deliveryDelay: deliveryDelay,
        startedAt: startedAt,
        commitOnCommand: commitOnCommand
      )
      return
    }
    show(
      held.items,
      for: combination,
      deliveryDelay: deliveryDelay,
      startedAt: startedAt,
      gatheredOnDemand: false,
      commitOnCommand: commitOnCommand
    )
  }

  /// Hands a key press to the one place that decides what becomes of it,
  /// kept as an entry because the channel is wired to the presenter.
  func handleKeyStroke(_ keystroke: PanelKeystroke) -> PanelKeyDisposition {
    keyCommands.handle(keystroke)
  }

  /// Hands a key release to the key commands, which listen for one only
  /// while a press waits to show whether it is a letter.
  func handleKeyRelease(_ keyCode: UInt16) -> PanelKeyDisposition {
    keyCommands.handleKeyRelease(keyCode)
  }

  /// Acts on Command having been let go.
  ///
  /// The press waiting for its first list is asked about first, and the
  /// order carries weight. Such a press means the panel is not up, so
  /// asking whether it is up first would send that case down the quiet path
  /// and leave the press to arrive as a panel over whatever the user had
  /// turned to. Letting the slot go is what stops it.
  func handleCommandRelease() {
    let startedAt = now()
    if answerWaitingPress(forCommitOnCommand: true, since: startedAt) {
      return
    }
    // A Fast Search ends on its own key, read by side by its own tap; this
    // release may be the other Command key.
    guard fastSearchSession == nil else { return }
    // A press still waiting to show whether it is a letter is one: it
    // came before the release, and may be what starts the filter.
    keyCommands.flushLongPress()
    // An Option-keyed appearance ends on Command only once Option is
    // already up; while Option stays held the numbers carry on for the
    // Option release to settle.
    if !commitOnCommand, lastModifierFlags.contains(.maskAlternate) {
      return
    }
    disarmInvocationRepeat()
    keyCommands.resetNumberInput()
    guard releaseCommitsHere else { return }
    recordTypedCommit()
    wayOut.commitOnCommandRelease(naming: selection.chosenID, since: startedAt, filter: keyCommands.filterSummary())
  }

  /// Answers the tap's modifier report: remembers which modifiers
  /// are held and redraws the numbers when a jump modifier moves.
  /// The tap only reports changes, so an appearance seeds the state
  /// from the live flags it opened under.
  func modifierFlagsChanged(_ flags: CGEventFlags) {
    lastModifierFlags = flags
    pushNumberedRows()
  }

  /// Acts on Option having been let go.
  ///
  /// A press still waiting, for its first list or for the show delay,
  /// is settled first when Option is its commit key, the way Command
  /// settles its own; one keyed to Command is left for Command.
  /// While Command stays held the release does nothing and the pending
  /// number carries on for the Command release to settle; otherwise the
  /// pending number dies with the release either way, committed or not.
  /// The tap reports the flags-changed event's flags before the release
  /// itself, so the held flags read as the state that event left behind.
  func handleOptionRelease() {
    let startedAt = now()
    if answerWaitingPress(forCommitOnCommand: false, since: startedAt) {
      return
    }
    guard fastSearchSession == nil else { return }
    keyCommands.flushLongPress()
    guard !lastModifierFlags.contains(.maskCommand) else { return }
    disarmInvocationRepeat()
    keyCommands.resetNumberInput()
    guard releaseCommitsHere else { return }
    recordTypedCommit()
    wayOut.commitOnOptionRelease(naming: selection.chosenID, since: startedAt, filter: keyCommands.filterSummary())
  }

  /// Switches the presented panel into filtering, stopping the release watch.
  func switchToFiltering() {
    disarmInvocationRepeat()
    keyCommands.activateFiltering()
    commandWatch.stop()
  }

  /// Ends the hold. Safe when none is armed.
  func disarmInvocationRepeat() {
    invocationRepeatClock.cancel()
  }

  /// The one place the panel goes up, so every appearance is measured and
  /// every measurement describes an appearance.
  ///
  /// A Fast Search comes up through here as well, on the main switcher
  /// and already filtering, with no repeat of the switcher keys behind it.
  func show(
    _ windows: [WindowItem],
    for combination: HotkeyCombination,
    deliveryDelay: Duration?,
    startedAt: ContinuousClock.Instant,
    gatheredOnDemand: Bool,
    replay: [HotkeyCombination] = [],
    commitOnCommand: Bool,
    shownFromDelay: Bool = false,
    fastSearch: FastSearchModifier? = nil
  ) {
    // Kept per appearance for the releases to answer: the press sampled
    // it as it arrived, and a wait kept its first press's answer.
    self.commitOnCommand = commitOnCommand
    // The orderings below are load-bearing, and the statements they
    // hold apart are named one pair at a time.
    //
    // The list is ordered first, so everything this appearance shows,
    // names, and measures reads off one value no later refresh can move.
    //
    // The filter starts next, over the whole ordered list, and the
    // cursor and the panel open on the rows it shows: the display modes
    // narrow the list before either is fed, and the first keystroke
    // narrows what the panel was shown. What the panel is told to draw
    // is read off the cursor.
    //
    // Keys are asked for after the panel is up and before the reading:
    // a window that is not on screen cannot become the key window, and
    // a press the keyboard never reached did not finish its work.
    //
    // Handing the list to the way out is the one statement here whose
    // position is free: it has to happen before the panel can go.
    tracker.noteSnapshotObserved(store.snapshot?.gatheredAt ?? now())
    let ordered = tracker.ordered(windows, skipping: store.snapshot?.skippedOwners ?? [])
    // Each appearance reads its own switcher's list settings: the scope,
    // the display modes, and the parked-section placements seed this
    // showing alone, and the identity stays for the commit and the
    // diagnostics to name. A panel that is up keeps its own until it
    // closes; the next appearance seeds again.
    let applied = seedSwitcher(combination.switcher)
    keyCommands.beginFiltering(
      fullWindows: ordered,
      filtering: combination == .filter || fastSearch != nil,
      origin: fastSearch == nil ? .invoked : .fastSearch
    )
    let layout = keyCommands.shownLayout
    let shown = layout.rows
    selection.beginSecond(layout.rowIDs, ranking: layout.rankedRows.map(\.id))
    // Presses the delay held past the first one walk here, after the
    // choice exists to walk and before the panel reads it off.
    replayDelayedPresses(replay)
    operations.begin(windows: ordered)
    wirePointerHandlers()
    surface.applyPanelSettings(applied)
    let badgeReading = readBadgesForAppearance(startedAt: startedAt, shownFromDelay: shownFromDelay)
    surface.showBadges(Self.drawnBadges(of: badgeReading))
    noteUnreadableDock(badgeReading)
    surface.present(windows: shown, selecting: selection.chosenID, filterActive: keyCommands.isFilteringActive)
    // The tap reports changes only, so the modifiers this press
    // opened under would otherwise leave the numbers down until the
    // next change.
    lastModifierFlags = modifierFlags()
    pushNumberedRows()
    // Before the keys, so the first keystroke already arrives under the
    // forced source.
    inputSourceLock.engage()
    let becameKey = surface.takeKeys()
    wayOut.fastSearch = fastSearch
    wayOut.nowShowing(ordered, startedAt: startedAt)
    onSwitcherSessionChanged?()
    let measurement = HotkeyMeasurement(
      combination: combination,
      elapsed: now() - startedAt,
      entryCount: shown.count,
      deliveryDelay: deliveryDelay,
      gatheredOnDemand: gatheredOnDemand,
      becameKey: becameKey,
      mru: MRUSummary(firstID: layout.rankedRows.first?.id, source: tracker.newestSource),
      badgeReading: badgeReading,
      fastSearch: fastSearch
    )
    writeLine(LogLine(.info, .panel, measurement.summaryLine, context: measurement.context))

    // Only with a monitor is a release expected at all, and starting below
    // the reading is what keeps the task out of the figure. A panel that
    // opens filtering starts no watch: an invoked filter stays up when the
    // key is let go, and a Fast Search watches for its own key's release.
    // The key-status looking starts with the handover above: it lasts as
    // long as the panel does, and the way out owns both ends of that.
    if closesOnCommandRelease(), !keyCommands.isFilteringActive {
      commandWatch.start()
    }
    // No switcher key is held behind a Fast Search, so nothing repeats.
    guard fastSearch == nil else { return }
    // The reading's own figure, not a second clock read: every read
    // advances an injected clock, and the way out times from the next one.
    armInvocationRepeat(
      for: combinationToRepeat(combination, replay: replay),
      at: startedAt + measurement.elapsed
    )
  }

  // MARK: Private

  /// Whether letting go of Command is what closes the panel.
  ///
  /// Asked on every press rather than settled at launch: the answer can stop
  /// being true under the app, because the system is free to switch a tap off
  /// whenever it likes. A remembered yes would go on spending the very press
  /// that is the way out on moving the selection, leaving a panel whose only
  /// remaining keyboard exits are the cancel keys — which reach it only
  /// where it was granted key status, and which have not been measured
  /// under secure input at all. A run with no monitor answers no throughout.
  private let closesOnCommandRelease: @MainActor () -> Bool

  /// Whether Command is down on the keyboard at this instant.
  ///
  /// Injected rather than read where it is used, because a test process
  /// cannot hold a real Command key down and reading the live state inline
  /// would answer no in every test there is. The decision below turns on
  /// this answer, and a decision that cannot be put either way from a test
  /// is a decision nothing checks.
  private let commandIsHeld: @MainActor () -> Bool

  /// Whether Option is down on the keyboard at this instant.
  ///
  /// Injected for the same reason as the Command question above: the
  /// commit key of an Option-held appearance is Option, and a test
  /// process holds no real keys.
  private let optionIsHeld: @MainActor () -> Bool

  /// The modifiers held right now, read where they are used rather
  /// than decided elsewhere: a test process holds no real keys, so
  /// the live state would answer against every test there is. The
  /// numbers seed at show time is the only reader.
  private let modifierFlags: @MainActor () -> CGEventFlags

  /// The modifiers held as of the last tap report. Seeded per
  /// appearance from the live flags, because the tap only reports
  /// changes and the opening press already holds its Command or
  /// Option. The releases also read it to tell a release under the
  /// other key apart.
  private var lastModifierFlags: CGEventFlags = []

  /// How long the watch waits between looks (`UnreportedReleaseWatch`'s
  /// number, injected so a test need not wait a real one out).
  private let commandWatchInterval: Duration

  /// Whether the appearance on screen commits on Command. Sampled as
  /// its press arrived — Carbon only fires on an exact modifier match,
  /// so the held modifiers are the invocation's — and kept for the
  /// releases to answer, while a wait keeps its first press's answer.
  private var commitOnCommand = true

  /// Whether letting go of the switcher key commits: always while not
  /// filtering, and for a filter started by typing, since the key that
  /// opened the panel is still the one being held.
  private var releaseCommitsHere: Bool {
    !keyCommands.isFilteringActive || keyCommands.filterOrigin == .typed
  }

  /// The wait one press is owed, or nothing when the delay is off.
  ///
  /// Shared by both switchers. Read at every press rather than settled
  /// at launch, the way the other per-press answers are: a change lands
  /// on the next press.
  private var showDelay: Duration? {
    guard let showDelayMs, showDelayMs > 0 else { return nil }
    return .milliseconds(max(1, Int(showDelayMs.rounded())))
  }

  /// Whether the delay holds no press back: the ordinary path.
  private var pendingShowHoldIsOff: Bool {
    showDelay == nil
  }

  /// Whether a tick may still move the selection. The same pair the
  /// next Carbon press would ask before it moved rather than closed,
  /// plus the panel still being up and not filtering.
  private var invocationRepeatStillWalking: Bool {
    surface.isPresented
      && !keyCommands.isFilteringActive
      && closesOnCommandRelease()
      && commandWatch.isLooking
  }

  /// A typed filter's commit is remembered for its query, like a commit key's.
  private func recordTypedCommit() {
    guard keyCommands.isFilteringActive, keyCommands.filterOrigin == .typed else { return }
    keyCommands.recordReleaseCommit(naming: selection.chosenID)
  }

  /// Answers a release for the waits, when the wait's commit key matches
  /// the release. A wait of the other key is left for its own release,
  /// and no wait at all falls through to the panel.
  private func answerWaitingPress(
    forCommitOnCommand key: Bool,
    since startedAt: ContinuousClock.Instant
  ) -> Bool {
    if pendingShow.isWaiting {
      guard pendingShow.waitingCommitOnCommand == key else { return true }
      guard let waiting = pendingShow.take() else { return true }
      pendingPress.callOff()
      wayOut.switcherIdentity = waiting.presses.first?.switcher ?? .main
      // Never a Fast Search: those skip the waits. Cleared here because
      // no showing comes to reset what the last panel or a called-off
      // search left behind.
      wayOut.fastSearch = nil
      guard let items = waiting.items else {
        wayOut.recordPressCalledOff(since: startedAt, trigger: trigger(forCommitOnCommand: key))
        return true
      }
      // A filtering opener asks for typing, not for taking: letting go
      // answers with silence rather than a commit or a line.
      guard waiting.presses.first != .filter else { return true }
      commitWithoutShowing(
        items,
        presses: waiting.presses,
        startedAt: startedAt,
        commitOnCommand: key
      )
      return true
    }
    if pendingPress.isWaiting {
      guard pendingPress.waitingCommitOnCommand == key else { return true }
      wayOut.switcherIdentity = pendingPress.waitingSwitcher ?? .main
      wayOut.fastSearch = nil
      pendingPress.callOff()
      wayOut.recordPressCalledOff(since: startedAt, trigger: trigger(forCommitOnCommand: key))
      return true
    }
    return false
  }

  /// The trigger a silent ending is recorded by.
  private func trigger(forCommitOnCommand key: Bool) -> PanelExitMeasurement.Trigger {
    key ? .commandRelease : .optionRelease
  }

  /// Whether the commit key of the appearance on screen is still held.
  private func commitKeyIsHeld() -> Bool {
    commitOnCommand ? commandIsHeld() : optionIsHeld()
  }

  /// The resolved settings behind one switcher.
  private func settings(for switcher: SwitcherIdentity) -> SwitcherSettings {
    switch switcher {
    case .main: mainSwitcher
    case .parallel: parallelSwitcher
    }
  }

  /// Records a rearranged row order and hands it to the file owner.
  /// The key commands already answer to the new order; setting the
  /// value again only repeats the same handover.
  private func didReorderRows(_ order: ManualRowOrder) {
    rowOrder = order
    onRowOrderChanged?(order)
  }

  /// Hands the view's row gestures to the selection and the way out.
  /// Set on every appearance, so a surface grown later hears the same
  /// handlers through the sync below it.
  private func wirePointerHandlers() {
    surface.onHoverRow = { [weak self] id in
      guard let self, hoverSelect else { return }
      selection.select(id)
    }
    surface.onClickRow = { [weak self] id in
      self?.keyCommands.commitClickedRow(id)
    }
    surface.onScrollStep = { [weak self] step in
      guard let self, scrollSelect else { return }
      selection.step(by: step)
    }
  }

  /// Holds a press off the screen until its wait runs out.
  ///
  /// With a list at hand the items join the wait at once; without one
  /// the first list joins it when it arrives, through the hold above.
  private func holdForDelay(
    _ combination: HotkeyCombination,
    deliveryDelay: Duration?,
    startedAt: ContinuousClock.Instant,
    delay: Duration,
    commitOnCommand: Bool
  ) {
    if store.snapshot == nil, !pendingPress.isWaiting {
      pendingPress.begin(
        combination,
        deliveryDelay: deliveryDelay,
        startedAt: startedAt,
        commitOnCommand: commitOnCommand
      )
    }
    pendingShow.begin(
      combination,
      deliveryDelay: deliveryDelay,
      startedAt: startedAt,
      delay: delay,
      commitOnCommand: commitOnCommand
    )
    if let held = store.snapshot {
      pendingShow.listArrived(held.items, gatheredOnDemand: false)
    }
  }

  /// Puts the panel up for a press that waited out its delay.
  private func showFromDelay(_ waiting: PendingShowHold.PendingShow) {
    guard let items = waiting.items else { return }
    show(
      items,
      for: waiting.presses.first ?? .forward,
      deliveryDelay: waiting.deliveryDelay,
      startedAt: waiting.startedAt,
      gatheredOnDemand: waiting.gatheredOnDemand,
      replay: Array(waiting.presses.dropFirst()),
      commitOnCommand: waiting.commitOnCommand,
      shownFromDelay: true
    )
  }

  /// Commits a row chosen without any panel: the delay waited out its
  /// press, and letting go found the list ready.
  ///
  /// The ordering and the walking are the showing's own; only the
  /// appearing is missing.
  private func commitWithoutShowing(
    _ items: [WindowItem],
    presses: [HotkeyCombination],
    startedAt: ContinuousClock.Instant,
    commitOnCommand: Bool
  ) {
    let ordered = arrangeDelayedChoice(items, presses: presses)
    wayOut.commitSilently(
      ordered,
      naming: selection.chosenID,
      since: startedAt,
      filter: keyCommands.filterSummary(),
      trigger: trigger(forCommitOnCommand: commitOnCommand)
    )
  }

  /// Orders the rows and walks the waiting presses over them: the part
  /// of appearing the silent commit shares with showing.
  private func arrangeDelayedChoice(
    _ items: [WindowItem],
    presses: [HotkeyCombination]
  ) -> [WindowItem] {
    tracker.noteSnapshotObserved(store.snapshot?.gatheredAt ?? now())
    let ordered = tracker.ordered(items, skipping: store.snapshot?.skippedOwners ?? [])
    _ = seedSwitcher(presses.first?.switcher ?? .main)
    keyCommands.beginFiltering(fullWindows: ordered, filtering: presses.first == .filter)
    let layout = keyCommands.shownLayout
    selection.beginSecond(layout.rowIDs, ranking: layout.rankedRows.map(\.id))
    replayDelayedPresses(Array(presses.dropFirst()))
    return ordered
  }

  /// Seeds the key commands with one switcher's list settings and keeps
  /// its identity for the commit and the diagnostics to name.
  ///
  /// Shared by showing and by the silent commit, so a choice made
  /// without a panel reads the same rows that switcher's panel would
  /// have shown.
  private func seedSwitcher(_ switcher: SwitcherIdentity) -> AppliedPanelSettings {
    activeSwitcher = switcher
    wayOut.switcherIdentity = switcher
    let settings = settings(for: switcher)
    keyCommands.updateWindowScope(settings.windowScope)
    keyCommands.updateDisplayModes(settings.displayModes)
    // The placements fold into the shared grouping, so each appearance
    // groups alike and parks the kinds where its own switcher says.
    let applied = AppliedPanelSettings.resolve(settings, sharedGrouping: grouping)
    keyCommands.updateGrouping(applied.grouping)
    return applied
  }

  /// Walks waiting presses past the first over the fresh choice.
  ///
  /// Shared by showing and by the silent commit, so both replay the
  /// same presses the same way.
  private func replayDelayedPresses(_ presses: [HotkeyCombination]) {
    for press in presses {
      switch press {
      case .forward,
           .parallelForward:
        selection.moveToNext()
      case .reverse,
           .parallelReverse:
        selection.moveToPrevious()
      case .filter:
        keyCommands.activateFiltering()
      }
    }
  }

  /// A press arriving while the panel is already up. Either it moves the
  /// selection or it closes the panel, decided by two questions and the
  /// four states they make between them. Is a monitor running, and was
  /// this appearance given a watch.
  ///
  /// Both yes, and the press moves the selection: letting go of
  /// Command is what will close the panel, so this keystroke is
  /// free to mean something else.
  ///
  /// Any other pair, and the press is what closes the panel,
  /// because nothing else will. No monitor ever started, and there
  /// is no release being listened for at all. A monitor that was
  /// stopped when the panel went up left this appearance without a
  /// watch, and one that has come back since takes its idea of the
  /// modifiers from the keyboard as it finds it — a Command let go
  /// meanwhile leaves it no release to report. A monitor that has
  /// stopped since the panel went up leaves a watch still looking
  /// with nothing left to report to it.
  ///
  /// So the split is neither question on its own. The middle two
  /// states differ from the first in one of them each, and both are
  /// read again on every press because either can have changed
  /// since the last.
  private func handlePressWhilePresented(
    _ combination: HotkeyCombination,
    at startedAt: ContinuousClock.Instant
  ) {
    let pressMovesTheSelection = closesOnCommandRelease() && commandWatch.isLooking
    guard pressMovesTheSelection || combination == .filter else {
      disarmInvocationRepeat()
      wayOut.takeDown(because: combination.name)
      return
    }
    switch combination {
    case .forward,
         .parallelForward:
      selection.moveToNext()
      armInvocationRepeat(for: combination, at: startedAt)

    case .reverse,
         .parallelReverse:
      selection.moveToPrevious()
      armInvocationRepeat(for: combination, at: startedAt)

    case .filter:
      switchToFiltering()
    }
  }

  /// Pushes the numbered order to the surface, or takes the numbers
  /// down when no jump modifier is held or the switch is off. Only a
  /// panel that is up answers; a dismissed panel shows nothing either
  /// way, and the next appearance seeds its own state. While the hint
  /// mode names rows by number, the full order stays up regardless of
  /// the modifiers and of the jump switch, so the display never
  /// flickers; naming rows is display, jumping to them still needs
  /// the switch, so with the switch off no jump can happen.
  private func pushNumberedRows() {
    guard surface.isPresented else { return }
    if surface.appearanceHints == .numbers {
      surface.showNumberedRows(keyCommands.numberedRows().map(\.id))
      return
    }
    // A search held on Command or Option types its digits into the query,
    // so the numbers a held modifier brings up would name nothing.
    guard numberJump, fastSearchSession?.modifier.isCommandOrOption != true else {
      surface.showNumberedRows([])
      return
    }
    let held = lastModifierFlags.contains(.maskCommand)
      || lastModifierFlags.contains(.maskAlternate)
    surface.showNumberedRows(held ? keyCommands.numberedRows().map(\.id) : [])
  }

  /// Hands the search settings to the live key commands.
  private func pushSearchSettings() {
    keyCommands.updateSearchSettings(searchSettings)
  }

  /// Remembers which physical key this press used, so the repeat polls
  /// that key and not whatever the combination is usually bound to, and
  /// when it went down, so the hold ages from that keydown.
  private func rememberInvocationKey(
    _ combination: HotkeyCombination,
    heldKeyCode: UInt16?,
    startedAt: ContinuousClock.Instant,
    deliveryDelay: Duration?
  ) {
    // The keydown happened before Carbon handed the press over.
    invocationRepeatPressedAt = startedAt - (deliveryDelay ?? .zero)
    if let heldKeyCode {
      invocationRepeatKeyCode = heldKeyCode
    } else {
      invocationRepeatKeyCode = UInt16(truncatingIfNeeded: combination.keyCode)
    }
  }

  /// The invocation a hold should follow. A filter press anywhere in
  /// the burst leaves the panel filtering, which does not walk.
  /// Otherwise the last navigation press wins, because that is the key
  /// still down.
  private func combinationToRepeat(
    _ first: HotkeyCombination,
    replay: [HotkeyCombination]
  ) -> HotkeyCombination {
    let sequence = [first] + replay
    if sequence.contains(where: { $0.repeatRole == .filter }) {
      return .filter
    }
    return sequence.last(where: { $0.repeatRole != .filter }) ?? first
  }

  /// Arms a hold, or drops one when this press does not walk.
  private func armInvocationRepeat(
    for combination: HotkeyCombination,
    at instant: ContinuousClock.Instant
  ) {
    guard
      InvocationKeyRepeat.shouldArm(
        role: combination.repeatRole,
        panelStaysUpWalking: invocationRepeatStillWalking
      )
    else {
      disarmInvocationRepeat()
      return
    }
    let timing = invocationRepeatTiming()
    // Delivery and any show delay are already inside the time since the
    // keydown, so the first tick waits only what is left.
    let remaining = InvocationKeyRepeat.timing(
      initialDelay: timing.initialDelay - (instant - invocationRepeatPressedAt),
      interval: timing.interval
    )
    invocationRepeatClock.arm(after: remaining.initialDelay, every: remaining.interval)
  }

  /// One repeat tick. The decision is `InvocationKeyRepeat`. This only
  /// reads the keyboard and moves the selection, or drops the hold.
  private func advanceInvocationRepeat() {
    let flags = modifierFlags()
    let direction = InvocationKeyRepeat.directionWhileHeld(
      bindings: invocationRepeatBindings(),
      keyCode: invocationRepeatKeyCode,
      held: HeldModifiers(
        shift: flags.contains(.maskShift),
        control: flags.contains(.maskControl),
        option: flags.contains(.maskAlternate),
        command: flags.contains(.maskCommand)
      )
    )
    switch InvocationKeyRepeat.tick(
      keyIsDown: invocationKeyIsDown(invocationRepeatKeyCode),
      panelStillWalking: invocationRepeatStillWalking,
      direction: direction
    ) {
    case .move(.forward):
      selection.moveToNext()
    case .move(.backward):
      selection.moveToPrevious()
    case .stop:
      disarmInvocationRepeat()
    }
  }

  /// The active switcher's forward and backward invocation keys.
  private func invocationRepeatBindings() -> [InvocationKeyRepeat.Binding] {
    let pairs: [(KeyBindingAction, InvocationKeyRepeat.Direction)] =
      switch activeSwitcher {
      case .main:
        [(.show, .forward), (.showReverse, .backward)]
      case .parallel:
        [(.showParallel, .forward), (.showParallelReverse, .backward)]
      }
    return pairs.flatMap { action, direction in
      keyBindings[action].map { key in
        InvocationKeyRepeat.Binding(
          keyCode: key.keyCode,
          modifiers: HeldModifiers(
            shift: key.modifiers.contains(.shift),
            control: key.modifiers.contains(.control),
            option: key.modifiers.contains(.option),
            command: key.modifiers.contains(.command)
          ),
          direction: direction
        )
      }
    }
  }

}

// MARK: - HotkeyCombination + Repeat

extension HotkeyCombination {
  /// Which way a repeat of this invocation walks, if it walks at all.
  var repeatRole: InvocationKeyRepeat.Role {
    switch self {
    case .forward,
         .parallelForward:
      .forward
    case .reverse,
         .parallelReverse:
      .backward
    case .filter:
      .filter
    }
  }
}
