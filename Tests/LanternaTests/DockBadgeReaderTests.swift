import ApplicationServices
import Foundation
@testable import Lanterna
import Testing

// MARK: - DockScript

/// A Dock told what to answer, call by call. Elements are application
/// elements made from made-up process numbers, so each one can be told
/// apart by the number it carries.
@MainActor
final class DockScript {

  // MARK: Internal

  struct Tile {
    var subrole: Any = "AXApplicationDockItem"
    var url: Any?
    var label: Any?
  }

  static let dockPID: pid_t = 900
  static let listPID: pid_t = 901

  var dockRunning = true
  var listChildren = [pid_t]()
  var tiles = [pid_t: Tile]()
  var running = [RunningDockApplication]()
  /// Errors to answer instead of a value, by the element asked.
  var failures = [pid_t: AXError]()
  var timeoutFailures = Set<pid_t>()
  /// How far the clock moves on each call to an element.
  var cost = Duration.zero
  /// An extra jump the clock takes on the call to one element.
  var jumps = [pid_t: Duration]()
  /// How far the clock moves when the running applications are listed.
  var listingCost = Duration.zero
  var appChildren = [listPID]

  private(set) var timeouts = [(pid: pid_t, seconds: Float)]()
  private(set) var asked = [pid_t]()

  var reader: LiveDockBadgeReader {
    LiveDockBadgeReader(
      dockProcessIdentifier: { [self] in dockRunning ? Self.dockPID : nil },
      setMessagingTimeout: { [self] element, seconds in
        let pid = pid(of: element)
        timeouts.append((pid, seconds))
        return timeoutFailures.contains(pid) ? .failure : .success
      },
      copyChildren: { [self] element in
        let pid = ask(element)
        if let failure = failures[pid] {
          return (failure, [])
        }
        let children = pid == Self.dockPID ? appChildren : pid == Self.listPID ? listChildren : []
        return (.success, children.map { AXUIElementCreateApplication($0) })
      },
      copyRole: { [self] element in
        let pid = ask(element)
        if let failure = failures[pid] {
          return (failure, nil)
        }
        return (.success, pid == Self.listPID ? "AXList" : "AXMenuBar")
      },
      copyTileAttributes: { [self] element in
        let pid = ask(element)
        if let failure = failures[pid] {
          return (failure, [])
        }
        let tile = tiles[pid] ?? Tile()
        return (.success, [tile.subrole, tile.url ?? Self.noValue, tile.label ?? Self.noValue])
      },
      runningApplications: { [self] in
        clock += listingCost
        return running
      },
      now: { [self] in clock }
    )
  }

  static func error(_ error: AXError) -> Any {
    var value = error
    return AXValueCreate(.axError, &value) as Any
  }

  func tile(_ pid: pid_t, url: String?, label: String?, subrole: String = "AXApplicationDockItem") {
    listChildren.append(pid)
    tiles[pid] = Tile(subrole: subrole, url: url.map { URL(fileURLWithPath: $0) }, label: label)
  }

  func app(_ pid: pid_t, at path: String, regular: Bool = true) {
    running.append(RunningDockApplication(
      processIdentifier: pid,
      bundleURL: URL(fileURLWithPath: path),
      isRegular: regular
    ))
  }

  // MARK: Private

  private static let noValue = error(.noValue)

  private var clock = ContinuousClock.now

  private func pid(of element: AXUIElement) -> pid_t {
    var pid: pid_t = 0
    AXUIElementGetPid(element, &pid)
    return pid
  }

  private func ask(_ element: AXUIElement) -> pid_t {
    let pid = pid(of: element)
    asked.append(pid)
    clock += cost + (jumps[pid] ?? .zero)
    return pid
  }

}

// MARK: - DockBadgeReaderTests

@MainActor
struct DockBadgeReaderTests {

  @Test
  func applicationTilesMapToTheirProcesses() {
    let dock = DockScript()
    dock.tile(910, url: "/Applications/Mail.app", label: "3")
    dock.tile(911, url: "/Applications/Slack.app", label: "•")
    dock.tile(912, url: "/Users/me/Downloads", label: "5", subrole: "AXFolderDockItem")
    dock.app(42, at: "/Applications/Mail.app")
    dock.app(43, at: "/Applications/Slack.app")

    let reading = dock.reader.read(deadline: .milliseconds(32))

    #expect(reading.outcome == .read)
    #expect(reading.badges == AppBadges(byProcess: [42: .count(3), 43: .text("•")]))
  }

  @Test
  func pathsCompareWithoutTheirTrailingSlash() {
    let dock = DockScript()
    dock.listChildren = [910]
    dock.tiles[910] = DockScript.Tile(url: URL(string: "file:///Applications/Mail.app/"), label: "3")
    dock.running = [RunningDockApplication(
      processIdentifier: 42,
      bundleURL: URL(string: "file:///Applications/Mail.app"),
      isRegular: true
    )]

    #expect(dock.reader.read(deadline: .milliseconds(32)).badges == AppBadges(byProcess: [42: .count(3)]))
  }

  @Test
  func tilesWithoutABadgeOrARunningAppStayOut() {
    let dock = DockScript()
    dock.tile(910, url: "/Applications/Mail.app", label: nil)
    dock.tile(911, url: "/Applications/Notes.app", label: "2")
    dock.app(42, at: "/Applications/Mail.app")

    let reading = dock.reader.read(deadline: .milliseconds(32))

    #expect(reading.outcome == .read)
    #expect(reading.badges == .none)
  }

  @Test
  func copiesLaunchedFromOnePlaceCannotBeToldApart() {
    let dock = DockScript()
    dock.tile(910, url: "/Applications/Mail.app", label: "3")
    dock.tile(911, url: "/Applications/Mail.app", label: "5")
    dock.tile(912, url: "/Applications/Slack.app", label: "1")
    dock.app(42, at: "/Applications/Mail.app")
    dock.app(44, at: "/Applications/Mail.app")
    dock.app(43, at: "/Applications/Slack.app")
    dock.app(45, at: "/Applications/Slack.app", regular: false)

    #expect(dock.reader.read(deadline: .milliseconds(32)).badges == AppBadges(byProcess: [43: .count(1)]))
  }

  @Test
  func noDockMeansNoBadges() {
    let dock = DockScript()
    dock.dockRunning = false

    let reading = dock.reader.read(deadline: .milliseconds(32))

    #expect(reading.outcome == .noDock)
    #expect(reading.badges == .none)
  }

  @Test
  func aDockWithoutItsTileListFails() {
    let dock = DockScript()
    dock.appChildren = [902]

    #expect(dock.reader.read(deadline: .milliseconds(32)).outcome == .failed(reason: "noDockList"))
  }

  @Test
  func anErrorFromTheDockFailsTheRead() {
    let dock = DockScript()
    dock.tile(910, url: "/Applications/Mail.app", label: "3")
    dock.app(42, at: "/Applications/Mail.app")
    dock.failures[DockScript.listPID] = .apiDisabled

    let reading = dock.reader.read(deadline: .milliseconds(32))

    #expect(reading.outcome == .failed(reason: "error -25211"))
    #expect(reading.badges == .none)
  }

  @Test
  func aTimeoutThatCannotBeSetFailsTheRead() {
    let dock = DockScript()
    dock.timeoutFailures = [DockScript.dockPID]

    #expect(dock.reader.read(deadline: .milliseconds(32)).outcome == .failed(reason: "error -25200"))
    #expect(dock.asked.isEmpty)
  }

  /// Messaging timeouts belong to one element each, so every element is
  /// given what is left of the deadline right before it is asked.
  @Test
  func eachElementIsGivenWhatIsLeftBeforeItIsAsked() {
    let dock = DockScript()
    dock.cost = .milliseconds(4)
    dock.tile(910, url: "/Applications/Mail.app", label: "3")
    dock.tile(911, url: "/Applications/Slack.app", label: nil)
    dock.app(42, at: "/Applications/Mail.app")

    _ = dock.reader.read(deadline: .milliseconds(32))

    #expect(dock.timeouts.map(\.pid) == dock.asked)
    #expect(dock.timeouts.map { Int(($0.seconds * 1000).rounded()) } == [32, 28, 24, 20, 16])
  }

  @Test
  func passingTheDeadlineDropsEverythingAndAsksNoMore() {
    let dock = DockScript()
    dock.tile(910, url: "/Applications/Mail.app", label: "3")
    dock.tile(911, url: "/Applications/Slack.app", label: "1")
    dock.app(42, at: "/Applications/Mail.app")
    dock.app(43, at: "/Applications/Slack.app")
    dock.jumps[910] = .milliseconds(40)

    let reading = dock.reader.read(deadline: .milliseconds(32))

    #expect(reading.outcome == .late)
    #expect(reading.badges == .none)
    #expect(!dock.asked.contains(911))
  }

  @Test
  func aTimeoutAtTheDeadlineIsLateNotAFailure() {
    let dock = DockScript()
    dock.tile(910, url: "/Applications/Mail.app", label: "3")
    dock.failures[910] = .cannotComplete
    dock.jumps[910] = .milliseconds(31)

    #expect(dock.reader.read(deadline: .milliseconds(32)).outcome == .late)
  }

  @Test
  func aTimeoutWellBeforeTheDeadlineIsAFailure() {
    let dock = DockScript()
    dock.tile(910, url: "/Applications/Mail.app", label: "3")
    dock.failures[910] = .cannotComplete
    dock.jumps[910] = .milliseconds(5)

    #expect(dock.reader.read(deadline: .milliseconds(32)).outcome == .failed(reason: "error -25204"))
  }

  @Test
  func aMissingLabelMeansNoBadgeAndKeepsTheOthers() {
    let dock = DockScript()
    dock.tile(910, url: "/Applications/Mail.app", label: "3")
    dock.listChildren.append(911)
    dock.tiles[911] = DockScript.Tile(
      url: URL(fileURLWithPath: "/Applications/Slack.app"),
      label: DockScript.error(.attributeUnsupported)
    )
    dock.app(42, at: "/Applications/Mail.app")
    dock.app(43, at: "/Applications/Slack.app")

    let reading = dock.reader.read(deadline: .milliseconds(32))

    #expect(reading.outcome == .read)
    #expect(reading.badges == AppBadges(byProcess: [42: .count(3)]))
  }

  @Test
  func anyOtherLabelErrorFailsTheRead() {
    let dock = DockScript()
    dock.listChildren = [910]
    dock.tiles[910] = DockScript.Tile(
      url: URL(fileURLWithPath: "/Applications/Mail.app"),
      label: DockScript.error(.cannotComplete)
    )

    #expect(dock.reader.read(deadline: .milliseconds(32)).outcome == .failed(reason: "error -25204"))
  }

  @Test
  func matchingRowsCountsInsideTheDeadline() {
    let dock = DockScript()
    dock.tile(910, url: "/Applications/Mail.app", label: "3")
    dock.app(42, at: "/Applications/Mail.app")
    dock.listingCost = .milliseconds(40)

    let reading = dock.reader.read(deadline: .milliseconds(32))

    #expect(reading.outcome == .late)
    #expect(reading.badges == .none)
  }

}
