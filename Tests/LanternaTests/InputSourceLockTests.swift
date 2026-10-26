@testable import Lanterna
import Testing

// MARK: - FakeInputSources

/// The system's input source as the lock sees it: a current ID the test
/// scripts, and every select the lock asks for.
@MainActor
private final class FakeInputSources {

  // MARK: Lifecycle

  init(current: String?, installed: Set<String> = ["abc", "hiragana", "atok"]) {
    self.current = current
    self.installed = installed
  }

  // MARK: Internal

  var current: String?
  var installed: Set<String>
  private(set) var selects = [String]()
  private(set) var lines = [String]()

  func makeLock(target: String?) -> InputSourceLock {
    let lock = InputSourceLock(
      currentSourceID: { self.current },
      selectSource: { id in
        self.selects.append(id)
        guard self.installed.contains(id) else { return false }
        self.current = id
        return true
      },
      writeLine: { self.lines.append($0.message) }
    )
    lock.target = target
    return lock
  }

}

// MARK: - InputSourceLockTests

@MainActor
struct InputSourceLockTests {

  @Test
  func offNeverSelects() {
    let sources = FakeInputSources(current: "hiragana")
    let lock = sources.makeLock(target: nil)
    lock.engage()
    lock.release()
    #expect(sources.selects.isEmpty)
    #expect(sources.lines.isEmpty)
  }

  @Test
  func engageThenReleaseRestoresTheOriginal() {
    let sources = FakeInputSources(current: "hiragana")
    let lock = sources.makeLock(target: "abc")
    lock.engage()
    #expect(sources.current == "abc")
    lock.release()
    #expect(sources.selects == ["abc", "hiragana"])
    #expect(sources.current == "hiragana")
    #expect(sources.lines.count == 2)
    #expect(sources.lines.allSatisfy { $0.contains("abc") && $0.contains("hiragana") })
  }

  @Test
  func engagingTwiceSelectsOnceAndKeepsTheFirstOriginal() {
    let sources = FakeInputSources(current: "hiragana")
    let lock = sources.makeLock(target: "abc")
    lock.engage()
    lock.engage()
    lock.release()
    #expect(sources.selects == ["abc", "hiragana"])
    #expect(sources.current == "hiragana")
  }

  @Test
  func releasingTwiceRestoresOnce() {
    let sources = FakeInputSources(current: "hiragana")
    let lock = sources.makeLock(target: "abc")
    lock.engage()
    lock.release()
    lock.release()
    #expect(sources.selects == ["abc", "hiragana"])
  }

  @Test
  func alreadyOnTheTargetSelectsNothingAndRestoresNothing() {
    let sources = FakeInputSources(current: "abc")
    let lock = sources.makeLock(target: "abc")
    lock.engage()
    #expect(lock.state == .idle)
    lock.release()
    #expect(sources.selects.isEmpty)
    #expect(sources.lines.isEmpty)
  }

  @Test
  func aSourceTheUserPickedByHandStays() {
    let sources = FakeInputSources(current: "hiragana")
    let lock = sources.makeLock(target: "abc")
    lock.engage()
    sources.current = "atok"
    lock.engage()
    lock.release()
    #expect(sources.selects == ["abc"])
    #expect(sources.current == "atok")
    #expect(sources.lines.count == 2)
  }

  @Test
  func aSourceThatCannotBeSelectedLeavesTheLockIdleAndLogs() {
    let sources = FakeInputSources(current: "hiragana")
    let lock = sources.makeLock(target: "removed")
    lock.engage()
    #expect(lock.state == .idle)
    #expect(sources.current == "hiragana")
    #expect(sources.lines.count == 1)
    #expect(sources.lines.first?.contains("removed") == true)
    lock.release()
    #expect(sources.selects == ["removed"])
  }

  @Test
  func anUnreadableCurrentSourceForcesNothing() {
    let sources = FakeInputSources(current: nil)
    let lock = sources.makeLock(target: "abc")
    lock.engage()
    #expect(lock.state == .idle)
    #expect(sources.selects.isEmpty)
    #expect(sources.lines.count == 1)
  }

  @Test
  func aFailedRestoreKeepsTheOriginalForTheNextRelease() {
    let sources = FakeInputSources(current: "hiragana")
    let lock = sources.makeLock(target: "abc")
    lock.engage()
    sources.installed.remove("hiragana")
    lock.release()
    #expect(sources.current == "abc")
    sources.installed.insert("hiragana")
    lock.release()
    #expect(sources.current == "hiragana")
    #expect(lock.state == .idle)
  }

  @Test
  func anUnreadableSourceAtReleaseKeepsTheOriginalForTheNextRelease() {
    let sources = FakeInputSources(current: "hiragana")
    let lock = sources.makeLock(target: "abc")
    lock.engage()
    sources.current = nil
    lock.release()
    sources.current = "abc"
    lock.release()
    #expect(sources.selects == ["abc", "hiragana"])
    #expect(sources.current == "hiragana")
    #expect(lock.state == .idle)
  }

  @Test
  func turningOffWhileHoldingRestores() {
    let sources = FakeInputSources(current: "hiragana")
    let lock = sources.makeLock(target: "abc")
    lock.engage()
    lock.target = nil
    #expect(lock.state == .idle)
    #expect(sources.current == "hiragana")
    lock.release()
    #expect(sources.selects == ["abc", "hiragana"])
  }

}
