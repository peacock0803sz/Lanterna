// MARK: - FastSearchSession

/// One Fast Search, from its first letter to its panel coming down.
struct FastSearchSession {
  /// What a search did while it waited for its first list.
  enum Step {
    case keystroke(PanelKeystroke)
    case move(FastSearchMove)
  }

  let modifier: FastSearchModifier
  /// Whether the tap still reads the search as running.
  let gateIsRunning: @MainActor () -> Bool
  /// The steps typed before any list existed, replayed once one arrives.
  /// Nil once the panel is up.
  var waiting: [Step]?
  /// The wait for the first list, called off when the search ends first.
  var waitForList: Task<Void, Never>?
  /// The looking for a release the tap missed. Present while the panel is.
  var releaseWatch: UnreportedReleaseWatch?
}

// MARK: - FastSearchStart

/// What became of a search's first letter.
enum FastSearchStart: Equatable {
  /// The search started, with or without a list yet.
  case started
  /// A switcher panel was already up, so the letter went to it.
  case handedToPanel
  /// A panel was on its way, or a search was already running. The letter
  /// goes nowhere.
  case refused
}

// MARK: - PanelPresenter + Fast Search

extension PanelPresenter {

  // MARK: Internal

  /// Whether a switcher panel is up or on its way, or a search is running.
  var hasSwitcherSession: Bool {
    surface.isPresented || pendingPress.isWaiting || pendingShow.isWaiting || fastSearchSession != nil
  }

  /// Starts a search on its first letter, or hands the letter to a panel
  /// that got there first.
  ///
  /// The panel goes up already filtering, on the main switcher, without
  /// waiting out the show delay: the user is typing, and a delay would only
  /// hold the query back.
  func beginFastSearch(
    _ first: PanelKeystroke,
    modifier: FastSearchModifier,
    receivedAt: ContinuousClock.Instant,
    deliveryDelay: Duration?,
    gateIsRunning: @escaping @MainActor () -> Bool
  ) -> FastSearchStart {
    if surface.isPresented {
      _ = handleKeyStroke(first)
      return .handedToPanel
    }
    guard !hasSwitcherSession else { return .refused }
    var session = FastSearchSession(modifier: modifier, gateIsRunning: gateIsRunning)
    guard let held = store.snapshot else {
      session.waiting = [.keystroke(first)]
      fastSearchSession = session
      waitForFirstList(receivedAt: receivedAt, deliveryDelay: deliveryDelay)
      onSwitcherSessionChanged?()
      return .started
    }
    fastSearchSession = session
    open(held.items, steps: [.keystroke(first)], receivedAt: receivedAt, deliveryDelay: deliveryDelay, gathered: false)
    return .started
  }

  /// A later press of the running search.
  func fastSearchKeystroke(_ keystroke: PanelKeystroke) {
    apply(.keystroke(keystroke))
  }

  /// Tab with the search's key: moves the selection.
  func fastSearchMove(_ move: FastSearchMove) {
    apply(.move(move))
  }

  /// The search's key came up: takes the chosen row, or closes without
  /// taking anything when nothing was asked for or nothing matched.
  func fastSearchRelease(receivedAt: ContinuousClock.Instant) {
    guard let session = fastSearchSession else { return }
    if session.waiting != nil {
      wayOut.switcherIdentity = .main
      wayOut.fastSearch = session.modifier
      wayOut.recordPressCalledOff(since: receivedAt, trigger: .fastSearchRelease(session.modifier))
      endFastSearchSession()
      return
    }
    let summary = keyCommands.filterSummary()
    guard !summary.query.isEmpty else {
      wayOut.cancelOnFastSearchRelease(session.modifier, since: receivedAt)
      return
    }
    let chosen = selection.chosenID
    keyCommands.recordReleaseCommit(naming: chosen)
    wayOut.commitOnFastSearchRelease(session.modifier, naming: chosen, since: receivedAt, filter: summary)
  }

  /// The tap stopped during the search, so whether the key came up cannot
  /// be known. Closes without taking anything.
  func fastSearchInterrupted() {
    guard let session = fastSearchSession else { return }
    if session.waiting != nil {
      endFastSearchSession()
      return
    }
    wayOut.closeForAStoppedFastSearchTap(naming: selection.chosenID)
  }

  /// Ends the search with its panel, wherever the panel went.
  func endFastSearchSession() {
    guard let session = fastSearchSession else { return }
    session.waitForList?.cancel()
    session.releaseWatch?.stop()
    fastSearchSession = nil
    onFastSearchClosed?()
    onSwitcherSessionChanged?()
  }

  // MARK: Private

  private func apply(_ step: FastSearchSession.Step) {
    guard var session = fastSearchSession else { return }
    if var waiting = session.waiting {
      waiting.append(step)
      session.waiting = waiting
      fastSearchSession = session
      return
    }
    run(step)
  }

  private func run(_ step: FastSearchSession.Step) {
    switch step {
    case .keystroke(let keystroke):
      _ = handleKeyStroke(keystroke)
    case .move(.next):
      selection.moveToNext()
    case .move(.previous):
      selection.moveToPrevious()
    }
  }

  private func open(
    _ items: [WindowItem],
    steps: [FastSearchSession.Step],
    receivedAt: ContinuousClock.Instant,
    deliveryDelay: Duration?,
    gathered: Bool
  ) {
    guard var session = fastSearchSession else { return }
    session.waiting = nil
    session.waitForList = nil
    fastSearchSession = session
    show(
      items,
      for: .forward,
      deliveryDelay: deliveryDelay,
      startedAt: receivedAt,
      gatheredOnDemand: gathered,
      commitOnCommand: true,
      fastSearch: session.modifier
    )
    let modifier = session.modifier
    let watch = FastSearchReleaseWatch.make(
      modifier: modifier,
      interval: fastSearchReleaseWatchInterval,
      isPanelUp: { [weak self] in self?.surface.isPresented ?? false },
      isHeld: fastSearchKeyIsHeld,
      gateIsRunning: session.gateIsRunning,
      onUnreportedRelease: { [weak self] in
        self?.wayOut.closeForAnUnreportedFastSearchRelease(modifier, naming: self?.selection.chosenID)
      }
    )
    session.releaseWatch = watch
    fastSearchSession = session
    watch.start()
    for step in steps {
      run(step)
    }
  }

  private func waitForFirstList(receivedAt: ContinuousClock.Instant, deliveryDelay: Duration?) {
    let wait = Task { [weak self, store] in
      let items = await store.listWhenGathered()
      guard !Task.isCancelled, let self, let steps = fastSearchSession?.waiting else { return }
      open(items, steps: steps, receivedAt: receivedAt, deliveryDelay: deliveryDelay, gathered: true)
    }
    fastSearchSession?.waitForList = wait
  }

}
