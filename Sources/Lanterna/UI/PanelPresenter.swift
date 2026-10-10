import CoreGraphics
import Darwin
import Logging

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
    modifierFlags: @escaping @MainActor () -> CGEventFlags = {
      CGEventSource.flagsState(.combinedSessionState)
    },
    commandWatchInterval: Duration = UnreportedReleaseWatch.defaultInterval,
    keyStatusWatchInterval: Duration = KeyStatusWatch.defaultInterval,
    showDelayMs: Double? = nil,
    showDelaySleep: @escaping @MainActor (Duration) async -> Void = { duration in
      try? await Task.sleep(for: duration)
    },
    switcher: any WindowSwitching = LiveWindowSwitcher(),
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
    self.modifierFlags = modifierFlags
    self.commandWatchInterval = commandWatchInterval
    self.keyStatusWatchInterval = keyStatusWatchInterval
    self.showDelayMs = showDelayMs
    self.showDelaySleep = showDelaySleep
    self.switcher = switcher
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
    show: { [weak self] items, combination, deliveryDelay, startedAt in
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
        gatheredOnDemand: true
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

  /// What commits take. Through to the way out, which owns the list the
  /// target is read off and is built beside the presenter.
  let switcher: any WindowSwitching

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
    commandIsHeld: { [weak self] in self?.commandIsHeld() ?? false },
    // The chosen row is read here and not inside the call, because the
    // call is what clears it. Swift settles the argument before the
    // method runs, so the order is the language's rather than a habit.
    onUnreportedRelease: { [weak self] in
      self?.wayOut.closeForAnUnreportedRelease(naming: self?.selection.chosenID)
    }
  )

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

  /// Where a rearranged row order goes for saving. Set by whoever
  /// owns the file; the key commands report through here.
  var onRowOrderChanged: ((ManualRowOrder) -> Void)?

  /// Where opening the settings goes. Set by whoever owns the file.
  var onOpenSettings: (@MainActor () -> Void)?

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
    didSet { keyCommands.updateWindowScope(windowScope) }
  }

  /// How the rows are grouped, handed to the key commands like the modes.
  var grouping = GroupingPolicy() {
    didSet { keyCommands.updateGrouping(grouping) }
  }

  /// The resolved key bindings, handed to the key commands. A change
  /// lands on the live panel at once, like the exclusion rules.
  var keyBindings = KeyBindingTable.defaults {
    didSet { keyCommands.updateKeyBindings(keyBindings) }
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
  /// Nothing here turns a press away for arriving too soon after the last
  /// one. Holding the key down does not produce a stream of presses: three
  /// seconds on Cmd+Tab yielded exactly one. That was measured while this
  /// method could only put the panel up, so a repeat would have shown as a
  /// second panel rather than as a flicker, and the reading cannot be a
  /// toggle racing itself. A suppression window would have nothing to
  /// suppress, at the price of a stored instant and a threshold.
  ///
  /// Synchronous on purpose. With a list already held the panel goes up in
  /// the same turn the press arrives, so the reading below starts where the
  /// press does and there is no ordering between a press and its panel to
  /// reason about.
  func handleHotkey(_ combination: HotkeyCombination, deliveryDelay: Duration?) {
    // Read before anything else, because both questions below are put to
    // the window server rather than answered in this process. A span begun
    // after them would leave out work this process is answerable for, and
    // would quietly shrink as anything further moved ahead of the read
    // while the figure went on reading the same. A press that is turned
    // away writes no line at all, so charging it a clock read costs
    // nothing.
    let startedAt = now()
    if surface.isPresented {
      handlePressWhilePresented(combination)
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
    if closesOnCommandRelease(), !commandIsHeld() {
      writeLine(LogLine(
        .info,
        .panel,
        "turned away \(combination.name); Command was already up by the time "
          + "the press arrived"
      ))
      return
    }
    // A press is already waiting for the first list and is the one that
    // will put the panel up. The panel is not up yet, so without this a
    // second press would take the same path again and two would arrive.
    // A press the delay is holding is the exception: further presses
    // join its wait instead of being turned away.
    if pendingPress.isWaiting, pendingShowHoldIsOff {
      return
    }
    if let delay = showDelay {
      holdForDelay(combination, deliveryDelay: deliveryDelay, startedAt: startedAt, delay: delay)
      return
    }
    guard let held = store.snapshot else {
      pendingPress.begin(combination, deliveryDelay: deliveryDelay, startedAt: startedAt)
      return
    }
    show(
      held.items,
      for: combination,
      deliveryDelay: deliveryDelay,
      startedAt: startedAt,
      gatheredOnDemand: false
    )
  }

  /// Hands a key press to the one place that decides what becomes of it,
  /// kept as an entry because the channel is wired to the presenter.
  func handleKeyStroke(_ keystroke: PanelKeystroke) -> PanelKeyDisposition {
    keyCommands.handle(keystroke)
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
    keyCommands.resetNumberInput()
    if pendingShow.isWaiting {
      guard let waiting = pendingShow.take() else { return }
      pendingPress.callOff()
      guard let items = waiting.items else {
        wayOut.recordPressCalledOff(since: startedAt)
        return
      }
      // A filtering opener asks for typing, not for taking: letting go
      // answers with silence rather than a commit or a line.
      guard waiting.presses.first != .filter else { return }
      commitWithoutShowing(
        items,
        presses: waiting.presses,
        startedAt: startedAt
      )
      return
    }
    if pendingPress.isWaiting {
      pendingPress.callOff()
      wayOut.recordPressCalledOff(since: startedAt)
      return
    }
    guard !keyCommands.isFilteringActive else { return }
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
  /// Only a panel that is up answers: unlike Command, letting go of
  /// Option never calls off a press still waiting for its first list.
  /// While Command stays held the release does nothing and the pending
  /// number carries on for the Command release to settle; otherwise the
  /// pending number dies with the release either way, committed or not.
  /// The tap reports the flags-changed event's flags before the release
  /// itself, so the held flags read as the state that event left behind.
  func handleOptionRelease() {
    let startedAt = now()
    guard !lastModifierFlags.contains(.maskCommand) else { return }
    keyCommands.resetNumberInput()
    guard !keyCommands.isFilteringActive else { return }
    wayOut.commitOnOptionRelease(naming: selection.chosenID, since: startedAt, filter: keyCommands.filterSummary())
  }

  /// Switches the presented panel into filtering, stopping the release watch.
  func switchToFiltering() {
    keyCommands.activateFiltering()
    commandWatch.stop()
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

  /// The modifiers held right now, read where they are used rather
  /// than decided elsewhere: a test process holds no real keys, so
  /// the live state would answer against every test there is. The
  /// numbers seed at show time is the only reader.
  private let modifierFlags: @MainActor () -> CGEventFlags

  /// The modifiers held as of the last tap report. Seeded per
  /// appearance from the held Command, because the tap only reports
  /// changes and the opening press holds Command already. The Option
  /// release also reads it to tell a release under Command apart.
  private var lastModifierFlags: CGEventFlags = []

  /// How long the watch waits between looks (`UnreportedReleaseWatch`'s
  /// number, injected so a test need not wait a real one out).
  private let commandWatchInterval: Duration

  /// The wait one press is owed, or nothing when the delay is off.
  ///
  /// Read at every press rather than settled at launch, the way the
  /// other per-press answers are: a change lands on the next press.
  private var showDelay: Duration? {
    guard let showDelayMs, showDelayMs > 0 else { return nil }
    return .milliseconds(max(1, Int(showDelayMs.rounded())))
  }

  /// Whether the delay holds no press back: the ordinary path.
  private var pendingShowHoldIsOff: Bool {
    showDelay == nil
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
    delay: Duration
  ) {
    if store.snapshot == nil, !pendingPress.isWaiting {
      pendingPress.begin(combination, deliveryDelay: deliveryDelay, startedAt: startedAt)
    }
    pendingShow.begin(combination, deliveryDelay: deliveryDelay, startedAt: startedAt, delay: delay)
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
      replay: Array(waiting.presses.dropFirst())
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
    startedAt: ContinuousClock.Instant
  ) {
    let ordered = arrangeDelayedChoice(items, presses: presses)
    wayOut.commitSilently(
      ordered,
      naming: selection.chosenID,
      since: startedAt,
      filter: keyCommands.filterSummary()
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
    keyCommands.beginFiltering(fullWindows: ordered, filtering: presses.first == .filter)
    let layout = keyCommands.shownLayout
    selection.beginSecond(layout.rowIDs, ranking: layout.rankedRows.map(\.id))
    replayDelayedPresses(Array(presses.dropFirst()))
    return ordered
  }

  /// Walks waiting presses past the first over the fresh choice.
  ///
  /// Shared by showing and by the silent commit, so both replay the
  /// same presses the same way.
  private func replayDelayedPresses(_ presses: [HotkeyCombination]) {
    for press in presses {
      switch press {
      case .forward:
        selection.moveToNext()
      case .reverse:
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
  private func handlePressWhilePresented(_ combination: HotkeyCombination) {
    let pressMovesTheSelection = closesOnCommandRelease() && commandWatch.isLooking
    guard pressMovesTheSelection || combination == .filter else {
      wayOut.takeDown(because: combination.name)
      return
    }
    switch combination {
    case .forward:
      selection.moveToNext()
    case .reverse:
      selection.moveToPrevious()
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
    guard numberJump else {
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

  /// The one place the panel goes up, so every appearance is measured and
  /// every measurement describes an appearance.
  private func show(
    _ windows: [WindowItem],
    for combination: HotkeyCombination,
    deliveryDelay: Duration?,
    startedAt: ContinuousClock.Instant,
    gatheredOnDemand: Bool,
    replay: [HotkeyCombination] = []
  ) {
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
    keyCommands.beginFiltering(fullWindows: ordered, filtering: combination == .filter)
    let layout = keyCommands.shownLayout
    let shown = layout.rows
    selection.beginSecond(layout.rowIDs, ranking: layout.rankedRows.map(\.id))
    // Presses the delay held past the first one walk here, after the
    // choice exists to walk and before the panel reads it off.
    replayDelayedPresses(replay)
    operations.begin(windows: ordered)
    wirePointerHandlers()
    surface.present(windows: shown, selecting: selection.chosenID, filterActive: keyCommands.isFilteringActive)
    // The tap reports changes only, so the modifiers this press
    // opened under would otherwise leave the numbers down until the
    // next change.
    lastModifierFlags = modifierFlags()
    pushNumberedRows()
    let becameKey = surface.takeKeys()
    wayOut.nowShowing(ordered, startedAt: startedAt)
    let measurement = HotkeyMeasurement(
      combination: combination,
      elapsed: now() - startedAt,
      entryCount: shown.count,
      deliveryDelay: deliveryDelay,
      gatheredOnDemand: gatheredOnDemand,
      becameKey: becameKey,
      mru: MRUSummary(firstID: layout.rankedRows.first?.id, source: tracker.newestSource)
    )
    writeLine(LogLine(.info, .panel, measurement.summaryLine, context: measurement.context))

    // Only with a monitor is a release expected at all, and starting below
    // the reading is what keeps the task out of the figure. Filtering starts
    // no watch, for releases end nothing there. The key-status looking starts
    // with the handover above: it lasts as long as the panel does, and the
    // way out owns both ends of that.
    if closesOnCommandRelease(), !keyCommands.isFilteringActive {
      commandWatch.start()
    }
  }

}
