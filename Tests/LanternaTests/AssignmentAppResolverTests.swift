@testable import Lanterna
import Testing

// MARK: - AssignmentAppResolverTests

/// The note under one group assignment row: found and running, found but
/// not running, not found, or already assigned by an earlier row.
@MainActor
struct AssignmentAppResolverTests {

  // MARK: Internal

  @Test
  func aRunningInstalledAppReadsByNameAndIdentifier() {
    let note = resolve("com.apple.Safari", running: ["com.apple.safari"])
    #expect(note == .found(name: "Safari", bundleIdentifier: "com.apple.Safari"))
    #expect(note.text == "Safari · com.apple.Safari")
    #expect(!note.isProblem)
  }

  @Test
  func anInstalledAppThatIsNotRunningSaysSo() {
    let note = resolve("com.apple.Safari", running: [])
    #expect(note.text == "Safari · not running")
    #expect(!note.isProblem)
  }

  /// Only the exact identifier is looked up: the text is never read as a
  /// pattern the way an exclusion's app field is.
  @Test
  func anUnknownIdentifierIsNotFoundAndNeverMatchedAsAPattern() {
    let note = resolve("Saf.*", running: ["com.apple.safari"])
    #expect(note == .missing)
    #expect(note.text == "No app found for this bundle ID")
    #expect(note.isProblem)
  }

  /// A row repeating an earlier row's identifier, in any case, is already
  /// assigned whatever the lookup would say.
  @Test
  func aRepeatedIdentifierIsAlreadyAssigned() {
    let earlier = [GroupAssignment(bundleID: "COM.APPLE.SAFARI", group: 2)]
    let note = AssignmentAppResolver.note(
      for: "com.apple.Safari",
      earlier: earlier,
      installed: installed,
      isRunning: { _ in true }
    )
    #expect(note == .alreadyAssigned)
    #expect(note.text == "Already assigned")
  }

  @Test
  func aBlankRowSaysNothingYet() {
    #expect(resolve("  ", running: []) == .blank)
    #expect(AssignmentNote.blank.text.isEmpty)
  }

  // MARK: Private

  private func installed(_ bundleID: String) -> ResolvedExclusionApp? {
    if bundleID.lowercased() == "com.apple.safari" {
      ResolvedExclusionApp(name: "Safari", bundleIdentifier: "com.apple.Safari")
    } else {
      nil
    }
  }

  private func resolve(_ bundleID: String, running: Set<String>) -> AssignmentNote {
    AssignmentAppResolver.note(
      for: bundleID,
      earlier: [],
      installed: installed,
      isRunning: { running.contains($0.lowercased()) }
    )
  }

}
