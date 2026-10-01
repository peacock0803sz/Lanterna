import Foundation
@testable import Lanterna
import Testing

/// Save logs to disk switched at launch and while running: what reaches
/// this launch's file, and what Delete Saved Logs takes with it.
@MainActor
struct SavedLogsTests {

  // MARK: Internal

  @Test
  func savingFromLaunchWritesTheLinesFromTheStart() throws {
    let made = try Made()
    made.log.write(.probe("at launch"))
    made.saved.start(saving: true)
    made.log.write(.probe("later"))
    #expect(try made.messages() == ["at launch", "later"])
    #expect(made.saved.isSaving)
  }

  /// Off at launch and on later: only the lines after switching on.
  @Test
  func switchingOnLaterSkipsTheLinesFromTheStart() throws {
    let made = try Made()
    made.log.write(.probe("at launch"))
    made.saved.start(saving: false)
    #expect(made.saved.store.files().isEmpty)
    made.saved.setSaving(true)
    made.log.write(.probe("on"))
    #expect(try made.messages() == ["on"])
  }

  /// Off with Delete takes this launch's file too; on again starts it
  /// afresh under the same name.
  @Test
  func offWithDeleteAndOnAgainStartsAFreshFile() throws {
    let made = try Made()
    made.saved.start(saving: true)
    made.log.write(.probe("before"))
    let name = made.saved.currentFile?.lastPathComponent
    made.saved.setSaving(false, deletingSaved: true)
    made.log.write(.probe("while off"))
    #expect(made.saved.store.files().isEmpty)
    made.saved.setSaving(true)
    made.log.write(.probe("after"))
    #expect(made.saved.store.files().map(\.url.lastPathComponent) == [name].compactMap(\.self))
    #expect(try made.messages() == ["after"])
  }

  /// Off with Keep leaves every file, this launch's included.
  @Test
  func offWithKeepLeavesTheFiles() throws {
    let made = try Made()
    made.saved.start(saving: true)
    made.log.write(.probe("before"))
    made.saved.setSaving(false)
    made.log.write(.probe("while off"))
    made.saved.setSaving(true)
    made.log.write(.probe("after"))
    #expect(try made.messages() == ["before", "after"])
  }

  /// Off fixes the log window to this launch.
  @Test
  func offFixesTheLogWindowToThisLaunch() {
    let state = LogWindowState(readEntries: { [] })
    state.setSavingEnabled(false)
    state.scope = .allLaunches
    #expect(state.scope == .thisLaunch)
    #expect(!state.hasSavedLogs)
  }

  // MARK: Private

  @MainActor
  private struct Made {

    // MARK: Lifecycle

    init() throws {
      folder = try TemporaryFolder()
      let log = DiagnosticLogStore(launch: LogFixture.launch, emit: { _ in })
      self.log = log
      saved = SavedLogs(
        store: LaunchLogStore(directory: folder.url),
        launch: LogFixture.launch,
        version: "v0",
        attach: { log.attach($0) },
        detach: { log.detach() },
        decline: { log.declineSaving() }
      )
    }

    // MARK: Internal

    let folder: TemporaryFolder
    let log: DiagnosticLogStore
    let saved: SavedLogs

    func messages() throws -> [String] {
      let file = try #require(saved.store.files().first)
      return saved.store.read(file).entries.map(\.message)
    }

  }

}
