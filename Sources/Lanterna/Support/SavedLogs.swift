import Foundation

/// This run's saved launches: where they live, this launch's file, and
/// switching the saving on and off.
///
/// Made once at launch, after the settings are read and before the panel
/// can run, so creating the file and trimming old ones stay off the paths
/// with a time budget.
@MainActor
final class SavedLogs {

  // MARK: Lifecycle

  /// The three closures reach the process's diagnostics store; tests pass
  /// a store of their own.
  init(
    store: LaunchLogStore,
    launch: LaunchID = Diagnostics.currentLaunch,
    version: String = AppVersion.full,
    attach: @escaping @MainActor (LaunchLogWriter) -> Void = { Diagnostics.attachSavedLog($0) },
    detach: @escaping @MainActor () -> Void = { Diagnostics.detachSavedLog() },
    decline: @escaping @MainActor () -> Void = { Diagnostics.declineSaving() }
  ) {
    self.store = store
    self.launch = launch
    self.version = version
    self.attach = attach
    self.detach = detach
    self.decline = decline
  }

  // MARK: Internal

  let store: LaunchLogStore
  /// This launch as the mirror names it.
  let launch: LaunchID

  /// This launch's file, once made.
  private(set) var currentFile: URL?

  /// This launch as its file names it: the same as `launch` unless the
  /// name was taken and a `-N` was added.
  private(set) var fileLaunch: LaunchID?

  /// Whether this launch's lines are going to its file.
  private(set) var isSaving = false

  /// The folder for the build that is running, under the user's
  /// Application Support. Nil when that cannot be resolved.
  static func live() -> SavedLogs? {
    guard
      let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
      let executable = Bundle.main.executableURL
    else { return nil }
    let origin = LogOrigin.of(executable: executable)
    return SavedLogs(store: LaunchLogStore(directory: LaunchLogStore.directory(applicationSupport: support, origin: origin)))
  }

  /// Deletes every launch saved before this one. This launch's file stays.
  func deleteEarlierLaunches() {
    store.deleteAll(except: fileLaunch ?? launch)
  }

  /// Settles saving for the launch: with `saving`, makes this launch's
  /// file and starts saving to it, the lines written so far first; without
  /// it, saves nothing until switched on. Then trims the oldest launches.
  func start(saving: Bool) {
    if saving {
      startSaving()
    } else {
      decline()
    }
    store.prune(keeping: fileLaunch ?? launch)
  }

  /// Switches saving on or off while the app runs. Off closes the file,
  /// and with `deletingSaved` removes every saved launch, this one's too.
  /// On again appends to this launch's file from then on, making it anew
  /// with its header when it is gone; the lines from while it was off
  /// stay out of it.
  func setSaving(_ saving: Bool, deletingSaved: Bool = false) {
    if saving {
      guard !isSaving else { return }
      if let writer {
        do {
          try writer.reopen()
          attach(writer)
          isSaving = true
        } catch {
          reportCannotSave(error)
        }
      } else {
        startSaving()
      }
    } else {
      detach()
      isSaving = false
      if deletingSaved {
        store.deleteAll(except: nil)
      }
    }
  }

  // MARK: Private

  private let version: String
  private let attach: @MainActor (LaunchLogWriter) -> Void
  private let detach: @MainActor () -> Void
  private let decline: @MainActor () -> Void
  private var writer: LaunchLogWriter?

  /// Makes this launch's file and attaches it. A file that cannot be made
  /// leaves one line saying so, and the launch carries on unsaved.
  private func startSaving() {
    do {
      let made = try store.create(for: launch, version: version)
      fileLaunch = made.launch
      currentFile = made.url
      let writer = try LaunchLogWriter(url: made.url, header: header(for: made.launch))
      self.writer = writer
      attach(writer)
      isSaving = true
    } catch {
      decline()
      reportCannotSave(error)
    }
  }

  private func reportCannotSave(_ error: any Error) {
    Diagnostics.writeLine(LogLine(
      .warning,
      .logs,
      "logs: could not create the saved log; this launch is not saved (\(error.localizedDescription))",
      context: ["path": .string(store.directory.path), "issue": .string(error.localizedDescription)]
    ))
  }

  private func header(for launch: LaunchID) -> String {
    LaunchLogCoding.header(
      launch: launch,
      version: version,
      utcOffsetSeconds: store.timeZone.secondsFromGMT(for: launch.startedAt)
    )
  }

}
