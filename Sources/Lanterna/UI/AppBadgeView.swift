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

    case .count:
      label

    case .text:
      label.frame(maxWidth: scaled(26))
    }
  }

  // MARK: Private

  private var height: Double {
    scaled(12)
  }

  private var label: some View {
    Text(badge.displayText)
      .font(.system(size: scaled(9), weight: .bold))
      .foregroundStyle(.white)
      .lineLimit(1)
      .truncationMode(.tail)
      .padding(.horizontal, scaled(3))
      .frame(minWidth: height, minHeight: height, maxHeight: height)
      .background(Capsule().fill(Color.red))
      .fixedSize(horizontal: badge.isCount, vertical: true)
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
