import Foundation
@testable import Lanterna
import Testing

struct TextScaleTests {
  @Test
  func fiveStepsCoverSmallToLarge() {
    #expect(TextScaleLevel.allCases.count == 5)
    #expect(TextScaleLevel.standard.factor == 1.0)
    let factors = TextScaleLevel.allCases.map(\.factor)
    #expect(factors == [0.85, 0.93, 1.0, 1.12, 1.25])
    #expect(factors == factors.sorted())
  }

  @Test
  func factorMapsBackToItsStep() {
    for level in TextScaleLevel.allCases {
      #expect(TextScaleLevel(factor: level.factor) == level, "for \(level.factor)")
    }
  }

  @Test
  func integerOneMatchesOnePointOh() {
    #expect(TextScaleLevel(factor: 1) == .standard)
  }

  @Test
  func offStepValuesMapToNothing() {
    for factor in [0.0, 0.9, 1.1, 1.2, 2.0, -1.0] {
      #expect(TextScaleLevel(factor: factor) == nil, "for \(factor)")
    }
  }

  /// The decimal round trip stays inside the tolerance, while twice
  /// the tolerance is already off step.
  @Test
  func standardToleranceBoundary() {
    #expect(TextScaleLevel(factor: 1.0 + 5e-10) == .standard)
    #expect(TextScaleLevel(factor: 1.0 - 5e-10) == .standard)
    #expect(TextScaleLevel(factor: 1.0 + 2e-9) == nil)
    #expect(TextScaleLevel(factor: 1.0 - 2e-9) == nil)
  }

  @Test
  func scaledRowHeightRoundsToWholePoints() {
    #expect(TextScaleLevel.standard.scaledRowHeight == 36)
    #expect(TextScaleLevel.large.scaledRowHeight == 45)
    for level in TextScaleLevel.allCases {
      #expect(level.scaledRowHeight == (36 * level.factor).rounded())
    }
  }

  @Test
  func scaledWidthRoundsToWholePoints() {
    #expect(TextScaleLevel.small.scaledWidth == 612)
    #expect(TextScaleLevel.smallMedium.scaledWidth == 670)
    #expect(TextScaleLevel.standard.scaledWidth == 720)
    #expect(TextScaleLevel.largeMedium.scaledWidth == 806)
    #expect(TextScaleLevel.large.scaledWidth == 900)
    for level in TextScaleLevel.allCases {
      #expect(level.scaledWidth == (Double(PanelMetrics.width) * level.factor).rounded())
    }
  }
}
