import Carbon.HIToolbox
import Testing
@testable import Lanterna

// MARK: - ParallelHotkeyTests

/// The parallel invocations behind Carbon registrations: what the table
/// spells them as, and what the system-shortcut discipline leaves alone.
@MainActor
struct ParallelHotkeyTests {

  @Test
  func bindingsIncludeParallelInvocations() {
    let bindings = HotkeyBinding.bindings(for: .defaults)
    let parallel = bindings.filter {
      $0.combination == .parallelForward || $0.combination == .parallelReverse
    }
    #expect(parallel.count == 2)
    let forward = parallel.first { $0.combination == .parallelForward }
    #expect(forward?.keyCode == UInt32(kVK_Tab))
    #expect(forward?.carbonModifiers == UInt32(optionKey))
    #expect(forward?.name == "Opt+Tab")
    let reverse = parallel.first { $0.combination == .parallelReverse }
    #expect(reverse?.keyCode == UInt32(kVK_Tab))
    #expect(reverse?.carbonModifiers == UInt32(optionKey | shiftKey))
    #expect(reverse?.name == "Shift+Opt+Tab")
  }

  @Test
  func fullRegistrationReadsWithoutFailure() {
    let outcome = HotkeyRegistrationOutcome(
      registered: HotkeyCombination.all,
      failures: []
    )
    #expect(!outcome.isTotalFailure)
    #expect(outcome.logLevel == .info)
    #expect(outcome.summaryLine.contains("Opt+Tab (parallel)"))
  }

  @Test
  func systemShortcutsLeaveParallelAlone() {
    #expect(SystemSwitcherShortcuts.systemCounterparts == [.forward, .reverse, .filter])
  }

  @Test
  func switchedOffParallelAsksForNoBindings() {
    let bindings = HotkeyBinding.bindings(for: .defaults, parallelEnabled: false)
    #expect(bindings.allSatisfy { $0.combination.switcher == .main })
    #expect(bindings.map(\.combination) == [.forward, .reverse, .filter])
  }

  @Test
  func unrequestedCombinationsReadAsQuiet() {
    let outcome = HotkeyRegistrationOutcome(
      registered: [.forward, .reverse, .filter],
      failures: [],
      unrequested: [.parallelForward, .parallelReverse]
    )
    #expect(!outcome.isTotalFailure)
    #expect(outcome.logLevel == .info)
    #expect(outcome.summaryLine == "registered Cmd+Tab (main), Shift+Cmd+Tab (main), Cmd+Space (main)")
  }

}
