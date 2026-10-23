import Foundation
@testable import Lanterna
import Testing

struct WindowProbeTests {

  /// The 20 bytes the private call reads: process id, 0, the marker, then
  /// the element id, each in native byte order.
  @Test
  func theTokenHoldsPidZeroMarkerAndElementID() {
    let token = WindowProbe.token(pid: 4242, elementID: 0x0102_0304_0506_0708)

    #expect(token.count == 20)
    token.withUnsafeBytes { bytes in
      #expect(bytes.loadUnaligned(fromByteOffset: 0, as: Int32.self) == 4242)
      #expect(bytes.loadUnaligned(fromByteOffset: 4, as: Int32.self) == 0)
      #expect(bytes.loadUnaligned(fromByteOffset: 8, as: Int32.self) == 0x636F_636F)
      #expect(bytes.loadUnaligned(fromByteOffset: 12, as: UInt64.self) == 0x0102_0304_0506_0708)
    }
  }

}
