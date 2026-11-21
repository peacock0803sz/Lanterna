import CoreGraphics
import Foundation

/// The result of one pass over every listable application.
///
/// A pass produces one of these and `WindowListStore` holds the newest, so a
/// press takes a list that is already gathered rather than waiting for one.
/// The panel is handed the rows as an array when it is shown, which is why a
/// pass finishing while the panel is up replaces what is held without
/// disturbing what is on screen.
struct WindowListSnapshot {

  // MARK: Lifecycle

  /// `assert` rather than `precondition`: a duplicated id is loud in debug
  /// builds and under test, but a doubled row must never take the panel
  /// down in release.
  init(
    items: [WindowItem],
    applicationCount: Int,
    gatheringDuration: Duration,
    skipped: [SkippedApplication],
    droppedWithoutID: Int,
    gatheredAt: ContinuousClock.Instant,
    spacesUnread: Bool = false,
    otherSpacesCutShort: Int = 0,
    missingOtherSpaceWindows: [MissingOtherSpace] = []
  ) {
    assert(Set(items.map(\.id)).count == items.count, "window ids must be unique")
    self.spacesUnread = spacesUnread
    self.otherSpacesCutShort = otherSpacesCutShort
    self.missingOtherSpaceWindows = missingOtherSpaceWindows
    self.items = items
    self.applicationCount = applicationCount
    self.gatheringDuration = gatheringDuration
    self.skipped = skipped
    self.droppedWithoutID = droppedWithoutID
    self.gatheredAt = gatheredAt
  }

  // MARK: Internal

  /// An application whose read failed. Named in the diagnostics line so a
  /// missing application is explained rather than silently absent. The
  /// owner travels along so the sweep can tell a skipped application from
  /// a gone window: absence from a list that never looked is not absence.
  struct SkippedApplication {
    let name: String
    let reason: ReadFailure
    let processIdentifier: pid_t
  }

  /// Windows the window server keeps on a hidden Space for one application
  /// that the read did not settle. The name is the one the panel shows.
  struct MissingOtherSpace: Equatable {
    let name: String
    let processIdentifier: pid_t
    let windowIDs: Set<CGWindowID>
  }

  /// Grouped by application in process-identifier order, and within an
  /// application in window-id order.
  let items: [WindowItem]
  /// Every application the pass looked at, including the skipped ones.
  let applicationCount: Int
  /// From the start of the pass, before applications are collected, to the
  /// assembled list: everything the panel waited for.
  let gatheringDuration: Duration
  let skipped: [SkippedApplication]
  let droppedWithoutID: Int
  /// When this pass started observing. The sweep spares records newer
  /// than this: a snapshot that predates a use could not have observed it.
  let gatheredAt: ContinuousClock.Instant
  /// Whether the pass found no Space any display is showing, so grouping
  /// by Space would have nothing to go on. Said on the summary line.
  let spacesUnread: Bool
  /// How many applications ended their look for windows on other Spaces
  /// early, so a missing row there is explained.
  let otherSpacesCutShort: Int
  /// The applications whose windows on hidden Spaces were not all settled,
  /// in process order.
  let missingOtherSpaceWindows: [MissingOtherSpace]

  // When this pass finished assembling. The sweep spares records newer
  // than this: a snapshot that predates a use could not have observed it.

  /// The owners a pass failed to read. Records for these stay put when
  /// sweeping: their rows are missing because the look missed, not
  /// because the windows closed.
  var skippedOwners: Set<pid_t> {
    Set(skipped.map(\.processIdentifier))
  }

  /// The windows left missing on hidden Spaces, keyed as recent-use records.
  /// Their rows are absent because the look did not reach them, not because
  /// they closed, so the sweep keeps their records for the pass that does.
  var sparedRecords: Set<MRUKey> {
    Set(missingOtherSpaceWindows.flatMap { missing in
      missing.windowIDs.map {
        MRUKey(id: WindowItem.Identifier(windowID: $0), ownerProcessIdentifier: missing.processIdentifier)
      }
    })
  }

  /// The one line written after a pass. Counts, timings, and the names of
  /// applications skipped or with windows elsewhere not found — never a
  /// window title. Rows on another
  /// Space are counted only when there are some, so a pass with every
  /// window in view reads as it always has.
  var summaryLine: String {
    var line = "listed \(items.count) windows from \(applicationCount) applications "
      + "in \(Diagnostics.millisecondsText(gatheringDuration)) ms"
    let onOtherSpace = items.count(where: \.isOnOtherSpace)
    if onOtherSpace > 0 {
      line += "; \(onOtherSpace) on other Spaces"
    }
    if !skipped.isEmpty {
      let reasons = skipped.map { "\($0.name) (\($0.reason))" }
      line += "; skipped " + reasons.joined(separator: ", ")
    }
    if droppedWithoutID > 0 {
      line += "; dropped \(droppedWithoutID) elements without a window id"
    }
    if spacesUnread {
      line += "; Spaces unread"
    }
    if otherSpacesCutShort > 0 {
      line += "; other Spaces cut short in \(otherSpacesCutShort) applications"
    }
    // Last, so the clauses before it read as they always have.
    if !missingOtherSpaceWindows.isEmpty {
      let counts = missingOtherSpaceWindows.map { "\($0.name) (\($0.windowIDs.count))" }
      line += "; not found on other Spaces: " + counts.joined(separator: ", ")
    }
    return line
  }

}
