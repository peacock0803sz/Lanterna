import AppKit
import Foundation
@testable import Lanterna
import Logging
import Testing

// MARK: - ApplicationReopenerTests

/// What asking the workspace to open an application does, and what the
/// answer does.
///
/// No live application is ever asked: the lookup and the opening are both
/// scripted, and the completion is held and called by hand rather than
/// waited out. What is pinned is which call goes out with which settings,
/// that nothing is waited for, and that a late failure is a line of its own.
@MainActor
struct ApplicationReopenerTests {

  // MARK: Internal

  /// No bundle means no opening: bringing the application forward is the
  /// whole switch, and the note says so.
  @Test
  func withoutABundleNothingOpens() {
    let script = ScriptedReopen(application: nil)
    let reopener = script.reopener()

    #expect(reopener.reopen(processIdentifier: 4242) == .skippedNoBundle)
    #expect(script.findPIDs == [4242])
    #expect(script.opened.isEmpty)
  }

  /// A found application without a bundle still opens nothing.
  @Test
  func withAnApplicationButNoBundleNothingOpens() {
    let script = ScriptedReopen(application: ScriptedReopenable(bundleURL: nil))
    let reopener = script.reopener()

    #expect(reopener.reopen(processIdentifier: 4242) == .skippedNoBundle)
    #expect(script.opened.isEmpty)
  }

  /// A bundle is opened once, asked to come forward without a new
  /// instance or a recent item, and the take does not wait for it.
  @Test
  func withABundleTheOpenCallGoesOutUnwaited() {
    let script = ScriptedReopen(application: ScriptedReopenable(bundleURL: Self.bundleURL))
    let reopener = script.reopener()

    #expect(reopener.reopen(processIdentifier: 4242) == .requested)
    #expect(script.findPIDs == [4242])
    #expect(script.opened.count == 1)
    #expect(script.opened.first?.url == Self.bundleURL)
    #expect(script.opened.first?.activates == true)
    #expect(script.opened.first?.createsNewApplicationInstance == false)
    #expect(script.opened.first?.addsToRecentItems == false)
    #expect(script.lines.isEmpty)
  }

  /// A late failure is a line of its own, naming the application the way
  /// the rows do and carrying who it was.
  @Test
  func aLateFailureIsItsOwnNoticeLine() {
    let script = ScriptedReopen(application: ScriptedReopenable(bundleURL: Self.bundleURL))
    let reopener = script.reopener()

    #expect(reopener.reopen(processIdentifier: 4242) == .requested)
    #expect(script.lines.isEmpty)
    script.complete(with: Self.failure("the operation could not be completed"))

    #expect(script.lines.count == 1)
    #expect(script.lines.first?.level == .notice)
    #expect(script.lines.first?.message == "reopen of Safari failed (the operation could not be completed)")
    #expect(script.lines.first?.context["pid"] == .int(4242))
    #expect(script.lines.first?.context["bundle"] == .string("com.apple.Safari"))
  }

  /// A failure reason spanning lines still prints as one line.
  @Test
  func aMultilineReasonPrintsAsOneLine() {
    let script = ScriptedReopen(application: ScriptedReopenable(bundleURL: Self.bundleURL))
    let reopener = script.reopener()

    _ = reopener.reopen(processIdentifier: 4242)
    script.complete(with: Self.failure("first\nsecond"))

    #expect(script.lines.first?.message == "reopen of Safari failed (first second)")
  }

  /// An application name spanning lines still prints as one line.
  @Test
  func aMultilineNamePrintsAsOneLine() {
    let script = ScriptedReopen(
      application: ScriptedReopenable(bundleURL: Self.bundleURL, localizedName: "Sa\nfari")
    )
    let reopener = script.reopener()

    _ = reopener.reopen(processIdentifier: 4242)
    script.complete(with: Self.failure("the operation could not be completed"))

    #expect(script.lines.first?.message == "reopen of Sa fari failed (the operation could not be completed)")
  }

  /// A success answers nothing: the take already said what it did.
  @Test
  func aSuccessWritesNothing() {
    let script = ScriptedReopen(application: ScriptedReopenable(bundleURL: Self.bundleURL))
    let reopener = script.reopener()

    _ = reopener.reopen(processIdentifier: 4242)
    script.complete(with: nil)

    #expect(script.lines.isEmpty)
  }

  // MARK: Private

  private static let bundleURL = URL(fileURLWithPath: "/Applications/Safari.app")

  private static func failure(_ message: String) -> any Error {
    NSError(domain: "LanternaTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }

}

// MARK: - ScriptedReopenable

/// A found application, scripted: the bundle answers, the names read the
/// way the rows name them.
private struct ScriptedReopenable: ReopenableApplication {
  let bundleURL: URL?
  var localizedName: String? = "Safari"

  var executableURL: URL? {
    nil
  }

  var bundleIdentifier: String? {
    "com.apple.Safari"
  }
}

// MARK: - ScriptedReopen

/// Scripted answers for the opener, recording every call.
///
/// The completion is held rather than awaited: the test calls it by hand,
/// so no suite waits on how busy the machine is.
// swiftlint:disable:next no_unchecked_sendable - test-only; driven synchronously on the main actor
private final class ScriptedReopen: @unchecked Sendable {

  // MARK: Lifecycle

  init(application: (any ReopenableApplication)?) {
    self.application = application
  }

  // MARK: Internal

  struct Opening {
    let url: URL
    let activates: Bool
    let createsNewApplicationInstance: Bool
    let addsToRecentItems: Bool
  }

  private(set) var findPIDs = [pid_t]()
  private(set) var opened = [Opening]()
  private(set) var lines = [LogLine]()

  func reopener() -> ApplicationReopener {
    ApplicationReopener(
      findApplication: { [self] pid in
        findPIDs.append(pid)
        return application
      },
      openApplication: { [self] url, configuration, completion in
        opened.append(Opening(
          url: url,
          activates: configuration.activates,
          createsNewApplicationInstance: configuration.createsNewApplicationInstance,
          addsToRecentItems: configuration.addsToRecentItems
        ))
        if let completion {
          heldCompletions.append(completion)
        }
      },
      writeLine: { [self] in lines.append($0) }
    )
  }

  func complete(with error: (any Error)?) {
    precondition(!heldCompletions.isEmpty, "no pending reopen completion")
    let completion = heldCompletions.removeFirst()
    completion(error)
  }

  // MARK: Private

  private let application: (any ReopenableApplication)?
  private var heldCompletions = [@Sendable (Error?) -> Void]()

}
