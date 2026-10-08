@testable import Lanterna
import Testing

/// Byte counts change unit at 1 KB, and at the last count that one
/// decimal KB would not round up to `1024.0 KB`.
struct ByteCountTextTests {

  @Test
  func belowOneKilobyteReadsAsWholeBytes() {
    #expect(ByteCountText.text(0) == "0 B")
    #expect(ByteCountText.text(1023) == "1023 B")
  }

  @Test
  func oneKilobyteReadsAsKilobytes() {
    #expect(ByteCountText.text(1024) == "1.0 KB")
  }

  @Test
  func justUnderTheRoundingEdgeStaysInKilobytes() {
    #expect(ByteCountText.text(1_048_524) == "1023.9 KB")
  }

  @Test
  func pastTheRoundingEdgeReadsAsMegabytes() {
    #expect(ByteCountText.text(1_048_525) == "1.0 MB")
    #expect(ByteCountText.text(1_048_576) == "1.0 MB")
  }

}
