import SwiftUI

// MARK: - AppBadgeView

/// The red badge laid over a row's icon, drawn the way the Dock draws it
/// so it reads as the same badge.
///
/// Sized from the text scale like the icon under it. Counts are never cut
/// short, since they were already rounded to fit; only wording is, so a
/// long word stays beside its icon instead of running over the title.
struct AppBadgeView: View {

  // MARK: Internal

  let badge: AppBadge
  var textScale = TextScaleLevel.standard

  var body: some View {
    switch badge {
    case .mark:
      Circle()
        .fill(Color.red)
        .frame(width: height, height: height)

    case .count,
         .text:
      // Sized to its own wording, not to the icon it sits on: a badge
      // stretched to whatever room it is offered would centre itself in
      // that room instead of keeping to the icon's corner.
      Text(badge.displayText)
        .font(.system(size: scaled(9), weight: .bold))
        .foregroundStyle(.white)
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(maxWidth: badge.isCount ? nil : scaled(20))
        .padding(.horizontal, scaled(3))
        .frame(minWidth: height, minHeight: height, maxHeight: height)
        .background(Capsule().fill(Color.red))
        .fixedSize()
    }
  }

  // MARK: Private

  private var height: Double {
    scaled(12)
  }

  /// One scaled point size: the base size times the step, in whole points.
  private func scaled(_ base: Double) -> Double {
    (base * textScale.factor).rounded()
  }

}

extension AppBadge {
  /// Whether the badge is a count, which is drawn whole.
  fileprivate var isCount: Bool {
    if case .count = self {
      return true
    }
    return false
  }
}
