import AppKit
import Dispatch
import Synchronization

// MARK: - WindowEnumerator

/// Turns the running applications into the list the panel draws.
///
/// Main-actor bound because the names and icons it joins onto the rows come
/// from `RunningApplicationInfo`, which is kept on the main thread. The
/// reading itself is handed to worker threads, which see nothing but process
/// identifiers.
@MainActor
struct WindowEnumerator {

  // MARK: Lifecycle

  /// `readsOtherSpaces` asks the window server, once per pass, which windows
  /// each application keeps on Spaces no display shows, and hands each read
  /// its own. It goes with the reader's own setting for the same pass.
  init(
    reader: any ApplicationWindowReading = AXApplicationWindowReader(),
    locator: any SpaceLocating = WindowServerSpaceLocator(),
    displayNames: @escaping @MainActor () -> [String: String] = Self.screenNames,
    readsOtherSpaces: Bool = false
  ) {
    self.reader = reader
    self.locator = locator
    self.displayNames = displayNames
    self.readsOtherSpaces = readsOtherSpaces
  }

  // MARK: Internal

  /// Reads every application at once and assembles the rows in a fixed order.
  ///
  /// Applications are read in parallel because the first message to a process
  /// costs far more than the rest; each application still pays its own, but
  /// in parallel those costs overlap instead of adding up, which is what
  /// keeps the pass inside its budget. Order therefore cannot come from
  /// completion: it comes from the process identifier and the window id,
  /// neither of which changes while the process or window exists, so a list
  /// of the same windows always reads the same way.
  func enumerate(
    applications: [RunningApplicationInfo],
    startedAt: ContinuousClock.Instant
  ) -> WindowListSnapshot {
    let ordered = applications.sorted { $0.processIdentifier < $1.processIdentifier }
    return assemble(
      ordered,
      Self.gather(request(for: ordered), using: reader, locator: locator),
      startedAt: startedAt
    )
  }

  /// The same pass, with the reading kept off the main thread.
  ///
  /// `read(_:using:)` blocks the thread it runs on until every application
  /// has answered, which is about a second when one of them has stopped
  /// answering. On the main thread that second is a second the panel cannot
  /// be drawn in, so the call is sent elsewhere and waited for.
  ///
  /// A global queue rather than `Task.detached`, because blocking is exactly
  /// what this work does. Swift concurrency's cooperative pool has about one
  /// thread per core and expects them to suspend rather than block; a
  /// detached task parked inside `concurrentPerform` holds those threads
  /// against everything else that wants them. A Dispatch queue is the pool
  /// that is allowed to be blocked. A `TaskGroup` was turned down for the
  /// reading itself over the same distinction.
  ///
  /// Only the identifiers cross: the names and icons stay on this side and
  /// are joined on afterwards, which is what lets `RunningApplicationInfo`
  /// remain main-actor bound.
  func enumerateOffMainThread(
    applications: [RunningApplicationInfo],
    startedAt: ContinuousClock.Instant
  ) async -> WindowListSnapshot {
    let ordered = applications.sorted { $0.processIdentifier < $1.processIdentifier }
    let request = request(for: ordered)
    let reader = reader
    let locator = locator
    let gathered = await withCheckedContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        continuation.resume(returning: Self.gather(request, using: reader, locator: locator))
      }
    }
    return assemble(ordered, gathered, startedAt: startedAt)
  }

  /// Every running application that shows in the Dock, and its windows, with
  /// the reading kept off the main thread. The refresh loop's pass.
  ///
  /// Collecting the applications stays here, on the main actor, because
  /// `NSWorkspace` and the names and icons it yields belong to the main
  /// thread. It costs a few milliseconds; the reading is the part worth
  /// moving.
  func enumerateRegularApplicationsOffMainThread() async -> WindowListSnapshot {
    // Started before the applications are collected, because resolving
    // names and icons is part of what a pass costs.
    let startedAt = ContinuousClock.now
    return await enumerateOffMainThread(
      applications: RunningApplicationInfo.regularApplications(),
      startedAt: startedAt
    )
  }

  // MARK: Private

  /// What the worker side of a pass hands back: one read per application,
  /// in input order, and the whole Space reading — which windows are on
  /// another Space or only on fullscreen Spaces, the Spaces each window
  /// is on, and the displays' layout.
  private struct Gathered: Sendable {
    let results: [Result<ApplicationRead, ReadFailure>]
    let spaces: SpaceReading
  }

  /// What crosses to the worker side: the applications in order, which of
  /// them are hidden, and whether to ask about other Spaces. Plain values,
  /// so the main-actor application infos stay behind.
  private struct ReadRequest: Sendable {
    let identifiers: [pid_t]
    let hiddenOwners: Set<pid_t>
    let readsOtherSpaces: Bool
  }

  private let reader: any ApplicationWindowReading
  private let locator: any SpaceLocating
  private let readsOtherSpaces: Bool
  /// Each display's name by its identifier, read on the main thread where
  /// the screens live.
  private let displayNames: @MainActor () -> [String: String]

  /// The names of the screens, keyed the way the window server names
  /// displays in its Space lists.
  private static func screenNames() -> [String: String] {
    var names = [String: String]()
    for screen in NSScreen.screens {
      guard
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
        let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue(),
        let text = CFUUIDCreateString(nil, uuid) as String?
      else {
        continue
      }
      names[text] = screen.localizedName
    }
    return names
  }

  /// The blocking half of a pass: the windows kept on other Spaces when
  /// asked for, the reads, then one Space query for every window they
  /// found or left missing. Shared by both paths, and run wherever the
  /// reading runs, so the window-server calls stay off the main thread
  /// whenever the reading does.
  private nonisolated static func gather(
    _ request: ReadRequest,
    using reader: any ApplicationWindowReading,
    locator: any SpaceLocating
  ) -> Gathered {
    // The pool frees this pass's Objective-C temporaries as it ends,
    // rather than whenever the pool around the caller next drains.
    autoreleasepool {
      let otherSpace = request.readsOtherSpaces ? locator.otherSpaceWindows() : OtherSpaceWindows()
      let results = read(request, expecting: otherSpace, using: reader)
      // The windows left missing are asked about too: a row standing for
      // them takes its group and fullscreen look from their Spaces.
      let windowIDs = results.flatMap { result -> [CGWindowID] in
        guard let read = try? result.get() else {
          return []
        }
        return read.records.map(\.windowID) + read.missingOtherSpaceWindows.sorted()
      }
      return Gathered(results: results, spaces: locator.reading(among: windowIDs))
    }
  }

  /// Reads all applications concurrently, one result per input position.
  ///
  /// The closure `concurrentPerform` runs is `@Sendable`, so it could not
  /// touch main-actor state whatever this function's isolation; `nonisolated`
  /// records that the function needs nothing from the main actor. The calling
  /// thread takes part in the iterations and blocks until every application
  /// has answered. Results are written to a fixed slot rather than appended,
  /// so a slow application changes when a row arrives but never where it
  /// lands.
  ///
  /// `concurrentPerform` does not overcommit: its width is roughly the active
  /// core count. One wedged application therefore costs about one second in
  /// total, but more of them wedged at once than that width serialise into
  /// waves of about a second each.
  private nonisolated static func read(
    _ request: ReadRequest,
    expecting otherSpace: OtherSpaceWindows,
    using reader: any ApplicationWindowReading
  ) -> [Result<ApplicationRead, ReadFailure>] {
    let identifiers = request.identifiers
    guard !identifiers.isEmpty else {
      return []
    }
    let slots = Mutex<[Result<ApplicationRead, ReadFailure>?]>(
      Array(repeating: nil, count: identifiers.count)
    )
    DispatchQueue.concurrentPerform(iterations: identifiers.count) { index in
      let processIdentifier = identifiers[index]
      let result = reader.read(
        processIdentifier: processIdentifier,
        otherSpaceWindows: otherSpace.windowIDs(of: processIdentifier),
        isHidden: request.hiddenOwners.contains(processIdentifier)
      )
      slots.withLock { $0[index] = result }
    }
    // Every iteration fills its own slot. Dropping an unwritten one instead
    // would misalign the results against the applications they belong to.
    return slots.withLock { $0 }.enumerated().map { index, result in
      guard let result else {
        preconditionFailure("application \(index) left its slot unwritten")
      }
      return result
    }
  }

  /// The worker side's arguments for applications already in order.
  private func request(for ordered: [RunningApplicationInfo]) -> ReadRequest {
    ReadRequest(
      identifiers: ordered.map(\.processIdentifier),
      hiddenOwners: Set(ordered.filter(\.isHidden).map(\.processIdentifier)),
      readsOtherSpaces: readsOtherSpaces
    )
  }

  /// Joins each application to its answer and lays the rows out.
  ///
  /// Shared by both paths so that moving the reading cannot quietly change
  /// the list. Main-actor bound because `RunningApplicationInfo` is: this is
  /// where the names and icons are attached.
  private func assemble(
    _ ordered: [RunningApplicationInfo],
    _ gathered: Gathered,
    startedAt: ContinuousClock.Instant
  ) -> WindowListSnapshot {
    var items = [WindowItem]()
    var windowless = [WindowItem]()
    var skipped = [WindowListSnapshot.SkippedApplication]()
    var droppedWithoutID = 0
    var otherSpacesCutShort = 0
    var missing = [WindowListSnapshot.MissingOtherSpace]()
    // The screens are asked only when there is a layout to name.
    let names = gathered.spaces.layout == nil ? [:] : displayNames()
    let grouping = SpaceGrouping(reading: gathered.spaces, displayNames: names)
    for (application, result) in zip(ordered, gathered.results) {
      switch result {
      case .failure(let reason):
        skipped.append(
          WindowListSnapshot.SkippedApplication(
            name: application.name,
            reason: reason,
            processIdentifier: application.processIdentifier
          )
        )

      case .success(let read):
        droppedWithoutID += read.droppedWithoutID
        if read.otherSpacesCutShort {
          otherSpacesCutShort += 1
        }
        if !read.missingOtherSpaceWindows.isEmpty {
          missing.append(WindowListSnapshot.MissingOtherSpace(
            name: application.name,
            processIdentifier: application.processIdentifier,
            windowIDs: read.missingOtherSpaceWindows
          ))
        }
        if let row = applicationRow(for: read, of: application, spaces: gathered.spaces, grouping: grouping) {
          windowless.append(row)
          continue
        }
        items.append(
          contentsOf: read.records
            .sorted { $0.windowID < $1.windowID }
            .map { record in
              item(
                for: record,
                of: application,
                isOnOtherSpace: gathered.spaces.onOtherSpace.contains(record.windowID),
                isFullscreenSpace: gathered.spaces.fullscreen.contains(record.windowID),
                spaceGroup: grouping.group(of: record.windowID, appName: application.name)
              )
            }
        )
      }
    }

    // After every window, by name: recency moves the ones it knows, and
    // the rest stay last in an order a reader can predict.
    windowless.sort { $0.appName.localizedStandardCompare($1.appName) == .orderedAscending }
    return WindowListSnapshot(
      items: items + windowless,
      applicationCount: ordered.count,
      gatheringDuration: ContinuousClock.now - startedAt,
      skipped: skipped,
      droppedWithoutID: droppedWithoutID,
      gatheredAt: startedAt,
      spacesUnread: gathered.spaces.displaysUnread && !items.isEmpty,
      otherSpacesCutShort: otherSpacesCutShort,
      missingOtherSpaceWindows: missing
    )
  }

  /// The row standing for the application itself when it has no window
  /// row, or nil when it has window rows or only windows dropped for want
  /// of an id.
  ///
  /// Windows on hidden Spaces the read could not reach make it a row
  /// standing for those, whatever else was dropped, unless the application
  /// answered both its main and its focused window with an explicit "no
  /// value". Otherwise, read and found empty, which is not the same as
  /// unread: only an answer of no windows at all makes the application a
  /// row. A window dropped for want of an id is still a window.
  ///
  /// An application with a window row gets no row standing for the rest:
  /// its windows elsewhere that the read could not reach have no row, and
  /// only the diagnostics line names them.
  private func applicationRow(
    for read: ApplicationRead,
    of application: RunningApplicationInfo,
    spaces: SpaceReading,
    grouping: SpaceGrouping
  ) -> WindowItem? {
    guard read.records.isEmpty else {
      return nil
    }
    if !read.missingOtherSpaceWindows.isEmpty, !read.namesNoWindow {
      return row(standingFor: application, windowsElsewhere: read.missingOtherSpaceWindows, spaces: spaces, grouping: grouping)
    }
    return read.droppedWithoutID == 0 ? row(standingFor: application) : nil
  }

  /// The row standing for windows on hidden Spaces: on another Space by
  /// definition, fullscreen only if every one of them is, and in the group
  /// of the first of their Spaces in drawing order.
  private func row(
    standingFor application: RunningApplicationInfo,
    windowsElsewhere windowIDs: Set<CGWindowID>,
    spaces: SpaceReading,
    grouping: SpaceGrouping
  ) -> WindowItem {
    WindowItem(
      id: .application(application.processIdentifier),
      ownerProcessIdentifier: application.processIdentifier,
      appName: application.name,
      bundleIdentifier: application.bundleIdentifier,
      windowTitle: "",
      kind: .standard,
      isMinimized: false,
      isHidden: application.isHidden,
      isOnOtherSpace: true,
      isFullscreen: windowIDs.allSatisfy(spaces.fullscreen.contains),
      windowsElsewhere: windowIDs.count,
      spaceGroup: windowIDs
        .compactMap { grouping.group(of: $0, appName: application.name) }
        .min { $0.order < $1.order },
      icon: application.icon
    )
  }

  /// The row for an application with no window: its name and icon, and
  /// no title.
  private func row(standingFor application: RunningApplicationInfo) -> WindowItem {
    WindowItem(
      id: .application(application.processIdentifier),
      ownerProcessIdentifier: application.processIdentifier,
      appName: application.name,
      bundleIdentifier: application.bundleIdentifier,
      windowTitle: "",
      kind: .standard,
      isMinimized: false,
      isHidden: application.isHidden,
      icon: application.icon
    )
  }

  private func item(
    for record: WindowRecord,
    of application: RunningApplicationInfo,
    isOnOtherSpace: Bool,
    isFullscreenSpace: Bool = false,
    spaceGroup: SpaceGroup? = nil
  ) -> WindowItem {
    WindowItem(
      id: WindowItem.Identifier(windowID: record.windowID),
      ownerProcessIdentifier: application.processIdentifier,
      appName: application.name,
      bundleIdentifier: application.bundleIdentifier,
      windowTitle: record.title,
      kind: record.kind,
      isMinimized: record.isMinimized,
      isHidden: application.isHidden,
      isOnOtherSpace: isOnOtherSpace,
      isFullscreen: record.isFullscreen || isFullscreenSpace,
      spaceGroup: spaceGroup,
      icon: application.icon
    )
  }

}
