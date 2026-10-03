@testable import Lanterna
import Testing

// MARK: - ScrollAccumulatorTests

/// How scroll amounts turn into selection steps.
///
/// A wheel notch and a trackpad's momentum arrive as wildly different
/// amounts, and neither may move the choice on its own: small amounts
/// gather until they earn a step, and turning around throws the savings
/// away. What is settled here is that gathering, and only it — which way
/// a step goes and where the edge stops it belong to the caller.
struct ScrollAccumulatorTests {

  @Test
  func smallAmountsGatherIntoOneStep() {
    var gathered = ScrollAccumulator()
    #expect(gathered.advance(by: 0.4) == 0)
    #expect(gathered.advance(by: 0.4) == 0)
    #expect(gathered.advance(by: 0.4) == 1)
  }

  @Test
  func aWholeAmountStepsAtOnce() {
    var gathered = ScrollAccumulator()
    #expect(gathered.advance(by: 2.5) == 2)
  }

  @Test
  func turningAroundThrowsTheSavingsAway() {
    var gathered = ScrollAccumulator()
    #expect(gathered.advance(by: 0.6) == 0)
    #expect(gathered.advance(by: -0.6) == 0)
    #expect(gathered.advance(by: -0.6) == -1)
  }

}
