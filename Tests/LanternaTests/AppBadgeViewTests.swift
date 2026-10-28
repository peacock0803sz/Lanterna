import AppKit
@testable import Lanterna
import SwiftUI
import Testing

// MARK: - AppBadgeViewTests

/// The badge keeps to its own size at every text scale: a badge stretched
/// to the room it is offered would centre itself away from the icon.
@MainActor
struct AppBadgeViewTests {

  // MARK: Internal

  /// A one-letter badge is a round dot as tall as it is wide, not a capsule
  /// spread across the room around it.
  @Test(arguments: TextScaleLevel.allCases)
  func aShortWordIsAsWideAsItIsTall(level: TextScaleLevel) {
    let size = fittingSize(.text("!"), level: level)
    let height = scaled(12, level)
    #expect(abs(size.height - height) <= 1)
    #expect(abs(size.width - height) <= 1)
  }

  /// Wording is cut short, so a long word stays beside its icon.
  @Test(arguments: TextScaleLevel.allCases)
  func aLongWordStopsAtItsWidth(level: TextScaleLevel) {
    let size = fittingSize(.text("Downloading"), level: level)
    #expect(size.width <= scaled(20, level) + 2 * scaled(3, level) + 1)
  }

  /// Counts are drawn whole, so a longer count makes a wider badge.
  @Test(arguments: TextScaleLevel.allCases)
  func aLongerCountIsWider(level: TextScaleLevel) {
    #expect(fittingSize(.count(999), level: level).width > fittingSize(.count(3), level: level).width)
  }

  // MARK: Private

  /// The size the badge takes when offered far more room than it needs,
  /// the way the row's overlay offers it the whole icon and beyond.
  private func fittingSize(_ badge: AppBadge, level: TextScaleLevel) -> CGSize {
    NSHostingController(rootView: AppBadgeView(badge: badge, textScale: level))
      .sizeThatFits(in: CGSize(width: 400, height: 400))
  }

  private func scaled(_ base: Double, _ level: TextScaleLevel) -> Double {
    (base * level.factor).rounded()
  }

}
