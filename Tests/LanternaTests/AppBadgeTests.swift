import AppKit
@testable import Lanterna
import Testing

@MainActor
struct AppBadgeTests {

  // MARK: Internal

  @Test
  func missingOrEmptyLabelIsNoBadge() {
    #expect(AppBadge(statusLabel: nil) == nil)
    #expect(AppBadge(statusLabel: "") == nil)
  }

  @Test
  func blankLabelIsAMark() {
    #expect(AppBadge(statusLabel: " ") == .mark)
    #expect(AppBadge(statusLabel: "  ") == .mark)
  }

  @Test
  func digitsAreACount() {
    #expect(AppBadge(statusLabel: "3") == .count(3))
    #expect(AppBadge(statusLabel: " 12 ") == .count(12))
  }

  @Test
  func zeroStaysText() {
    #expect(AppBadge(statusLabel: "0") == .text("0"))
  }

  @Test
  func anythingElseIsText() {
    #expect(AppBadge(statusLabel: "!") == .text("!"))
    #expect(AppBadge(statusLabel: "New mail") == .text("New mail"))
    #expect(AppBadge(statusLabel: "3a") == .text("3a"))
    #expect(AppBadge(statusLabel: "•") == .text("•"))
  }

  @Test
  func nonASCIIDigitsAreText() {
    #expect(AppBadge(statusLabel: "３") == .text("３"))
  }

  @Test
  func countsPastThreeDigitsRoundDown() {
    #expect(AppBadge.count(999).displayText == "999")
    #expect(AppBadge.count(1000).displayText == "999+")
    #expect(AppBadge.count(123_456).displayText == "999+")
  }

  @Test
  func digitsBeyondIntStillRound() {
    let badge = AppBadge(statusLabel: "12345678901234567890")
    #expect(badge == .count(Int.max))
    #expect(badge?.displayText == "999+")
  }

  @Test
  func textAndMarkSpellAsGiven() {
    #expect(AppBadge.text("New mail").displayText == "New mail")
    #expect(AppBadge.mark.displayText == "")
  }

  @Test
  func emptyTableHasNothing() {
    #expect(AppBadges.none.badge(for: item(processIdentifier: 42)) == nil)
  }

  @Test
  func everyRowOfOneProcessSharesItsBadge() {
    let badges = AppBadges(byProcess: [42: .count(3)])
    #expect(badges.badge(for: item(processIdentifier: 42, windowID: 1)) == .count(3))
    #expect(badges.badge(for: item(processIdentifier: 42, windowID: 2)) == .count(3))
    #expect(badges.badge(for: windowless(processIdentifier: 42)) == .count(3))
    #expect(badges.badge(for: item(processIdentifier: 7)) == nil)
  }

  // MARK: Private

  private func item(processIdentifier: pid_t, windowID: CGWindowID = 1) -> WindowItem {
    WindowItem(
      id: WindowItem.Identifier(windowID: windowID),
      ownerProcessIdentifier: processIdentifier,
      appName: "Mail",
      bundleIdentifier: nil,
      windowTitle: "Inbox",
      kind: .standard,
      isMinimized: false,
      icon: NSImage()
    )
  }

  private func windowless(processIdentifier: pid_t) -> WindowItem {
    WindowItem(
      id: .application(processIdentifier),
      ownerProcessIdentifier: processIdentifier,
      appName: "Mail",
      bundleIdentifier: nil,
      windowTitle: "",
      kind: .standard,
      isMinimized: false,
      icon: NSImage()
    )
  }

}
