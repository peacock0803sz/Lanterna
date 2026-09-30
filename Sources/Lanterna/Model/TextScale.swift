import Foundation

// MARK: - TextScaleLevel

/// The panel text and icon scale in five steps.
///
/// The configuration file spells one of the five multiplier decimals;
/// the settings slider spells the matching index. Both meet here, so
/// validation and display share one table instead of two.
enum TextScaleLevel: Int, CaseIterable, Equatable, Sendable {
  case small = 0
  case smallMedium = 1
  case standard = 2
  case largeMedium = 3
  case large = 4

  // MARK: Lifecycle

  /// The step a multiplier spells, when it spells one.
  ///
  /// Only the five table values count, within a small tolerance for
  /// the decimal round trip. Anything else is not a step but a bad
  /// value, and the caller falls back instead of guessing.
  init?(factor: Double) {
    for level in Self.allCases where abs(level.factor - factor) < 1e-9 {
      self = level
      return
    }
    return nil
  }

  // MARK: Internal

  /// The multiplier each step stands for. Standard means the base,
  /// unscaled sizes; nothing else moves when it is chosen.
  var factor: Double {
    switch self {
    case .small: 0.85
    case .smallMedium: 0.93
    case .standard: 1.0
    case .largeMedium: 1.12
    case .large: 1.25
    }
  }

  /// The row height this step draws, in whole points.
  var scaledRowHeight: Double {
    (36 * factor).rounded()
  }

  /// The panel width this step draws, in whole points.
  var scaledWidth: Double {
    (Double(PanelMetrics.width) * factor).rounded()
  }
}

extension TextScaleLevel {
  /// The step one run uses: a spelled step wins, anything missing
  /// means the standard step, the base, unscaled sizes.
  static func effective(from config: ValidConfiguration) -> TextScaleLevel {
    config.textScale.flatMap(TextScaleLevel.init(factor:)) ?? .standard
  }
}
