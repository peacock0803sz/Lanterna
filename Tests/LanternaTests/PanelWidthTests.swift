import Foundation
@testable import Lanterna
import Testing

struct PanelWidthTests {
  @Test
  func fiveStepsCoverNarrowToWide() {
    #expect(PanelWidth.allCases.count == 5)
    #expect(PanelWidth.standard.factor == 1.0)
    let factors = PanelWidth.allCases.map(\.factor)
    #expect(factors == [0.80, 0.90, 1.00, 1.15, 1.30])
    #expect(factors == factors.sorted())
  }

  @Test
  func factorMapsBackToItsStep() {
    for step in PanelWidth.allCases {
      #expect(PanelWidth(factor: step.factor) == step, "for \(step.factor)")
    }
  }

  @Test
  func integerOneMatchesStandard() {
    #expect(PanelWidth(factor: 1) == .standard)
  }

  @Test
  func offStepValuesMapToNothing() {
    for factor in [0.0, 0.85, 1.1, 1.2, 2.0, -1.0] {
      #expect(PanelWidth(factor: factor) == nil, "for \(factor)")
    }
  }

  /// The decimal round trip stays inside the tolerance, while twice
  /// the tolerance is already off step.
  @Test
  func standardToleranceBoundary() {
    #expect(PanelWidth(factor: 1.0 + 5e-10) == .standard)
    #expect(PanelWidth(factor: 1.0 - 5e-10) == .standard)
    #expect(PanelWidth(factor: 1.0 + 2e-9) == nil)
    #expect(PanelWidth(factor: 1.0 - 2e-9) == nil)
  }

  @Test
  func appliedWidthRoundsToWholePoints() {
    #expect(PanelWidth.narrowMinus.applied(to: 720) == 576)
    #expect(PanelWidth.narrow.applied(to: 720) == 648)
    #expect(PanelWidth.standard.applied(to: 720) == 720)
    #expect(PanelWidth.wide.applied(to: 720) == 828)
    #expect(PanelWidth.widePlus.applied(to: 720) == 936)
    for step in PanelWidth.allCases {
      #expect(step.applied(to: 720) == (720 * step.factor).rounded())
    }
  }
}
