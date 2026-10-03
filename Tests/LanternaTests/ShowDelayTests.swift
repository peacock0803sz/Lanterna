@testable import Lanterna
import Testing

// MARK: - ShowDelayTests

struct ShowDelayTests {

  @Test
  func absentMeansOff() {
    #expect(ShowDelay.effective(nil) == (nil, nil))
  }

  @Test
  func zeroMeansOff() {
    #expect(ShowDelay.effective(0) == (nil, nil))
  }

  @Test
  func spelledWaitsWin() {
    #expect(ShowDelay.effective(150) == (150, nil))
    #expect(ShowDelay.effective(1000) == (1000, nil))
    #expect(ShowDelay.effective(275) == (275, nil))
  }

  @Test
  func pastTheMaximumClampsWithANote() {
    #expect(
      ShowDelay.effective(1001)
        == (1000, "showDelayMs is above the maximum; using 1000")
    )
  }

  @Test
  func negativeFallsBackWithANote() {
    #expect(
      ShowDelay.effective(-1)
        == (150, "showDelayMs is not a valid value; using 150")
    )
  }

  @Test
  func unreadableFallsBackWithANote() {
    #expect(
      ShowDelay.effective(Double.nan)
        == (150, "showDelayMs is not a valid value; using 150")
    )
  }

  @Test
  func positiveInfinityFallsBackWithANote() {
    #expect(
      ShowDelay.effective(Double.infinity)
        == (150, "showDelayMs is not a valid value; using 150")
    )
  }

}
