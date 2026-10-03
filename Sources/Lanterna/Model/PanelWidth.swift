import Foundation

// MARK: - PanelWidth

/// The panel width in steps, as a factor over the text-scaled width.
///
/// The configuration file spells one of the factor decimals; the
/// settings slider spells the matching index. Both meet here, so
/// validation and display share one table instead of two. The standard
/// step leaves the text-scaled width unchanged.
enum PanelWidth: Int, CaseIterable, Equatable, Sendable {
  case narrowMinus = 0
  case narrow = 1
  case standard = 2
  case wide = 3
  case widePlus = 4

  // MARK: Lifecycle

  /// The step a factor spells, when it spells one.
  ///
  /// Only the table values count, within a small tolerance for
  /// the decimal round trip. Anything else is not a step but a bad
  /// value, and the caller falls back instead of guessing.
  init?(factor: Double) {
    for step in Self.allCases where abs(step.factor - factor) < 1e-9 {
      self = step
      return
    }
    return nil
  }

  // MARK: Internal

  /// The factor each step stands for. Standard is a factor of one, so
  /// the text-scaled width passes through unchanged.
  var factor: Double {
    switch self {
    case .narrowMinus: 0.80
    case .narrow: 0.90
    case .standard: 1.00
    case .wide: 1.15
    case .widePlus: 1.30
    }
  }

  /// The width this step draws from a text-scaled width, in whole
  /// points.
  func applied(to scaledWidth: Double) -> Double {
    (scaledWidth * factor).rounded()
  }
}

extension PanelWidth {
  /// The step one run uses: a spelled step wins, anything missing
  /// means the standard step.
  static func effective(from config: ValidConfiguration) -> PanelWidth {
    config.panelWidth.flatMap(PanelWidth.init(factor:)) ?? .standard
  }
}
