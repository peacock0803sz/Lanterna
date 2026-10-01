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

  init(store: LaunchLogStore, launch: LaunchID = Diagnostics.currentLaunch, version: String = AppVersion.full) {
    self.store = store
    self.launch = launch
    self.version = version
  }

  // MARK: Internal

  let store: LaunchLogStore
  /// This launch as the mirror names it.
  let launch: LaunchID

  /// This launch's file, once made.
  private(set) var currentFile: URL?

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

  /// Makes this launch's file and starts saving to it, the lines written
  /// so far first; then trims the oldest launches. A file that cannot be
  /// made leaves one line saying so, and the launch carries on unsaved.
  func start() {
    do {
      let made = try store.create(for: launch, version: version)
      fileLaunch = made.launch
      currentFile = made.url
      let writer = try LaunchLogWriter(url: made.url, header: header(for: made.launch))
      self.writer = writer
      Diagnostics.attachSavedLog(writer)
    } catch {
      Diagnostics.declineSaving()
      Diagnostics.writeLine(LogLine(
        .warning,
        .logs,
        "logs: could not create the saved log; this launch is not saved (\(error.localizedDescription))",
        context: ["path": .string(store.directory.path), "issue": .string(error.localizedDescription)]
      ))
    }
    store.prune(keeping: fileLaunch ?? launch)
  }

  // MARK: Private

  private let version: String
  private var writer: LaunchLogWriter?
  /// This launch as its file names it: the same as `launch` unless the
  /// name was taken and a `-N` was added.
  private var fileLaunch: LaunchID?

  private func header(for launch: LaunchID) -> String {
    LaunchLogCoding.header(
      launch: launch,
      version: version,
      utcOffsetSeconds: store.timeZone.secondsFromGMT(for: launch.startedAt)
    )
  }

}
