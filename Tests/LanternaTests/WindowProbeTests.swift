import ApplicationServices
import Foundation
@testable import Lanterna
import Testing

struct WindowProbeTests {

  // MARK: Internal

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

  /// Once the last window asked for turns up, no further id is tried:
  /// every id costs a round trip to the application.
  @Test
  func theSearchStopsOnceEveryTargetIsFound() {
    var looked = [UInt64]()
    let found = WindowProbe.search(
      ids: 0 ..< 10,
      stoppingAfter: [10, 11],
      until: start + .seconds(1),
      now: { start }
    ) { id in
      looked.append(id)
      return Self.window(at: id)
    }

    #expect(found.map(\.windowID) == [10, 11])
    #expect(looked.last == 5)
  }

  /// A window nobody asked for is still a window: it is returned, and the
  /// search goes on for the ones that were asked for.
  @Test
  func aWindowOutsideTheTargetsIsKeptAndDoesNotStopTheSearch() {
    var looked = [UInt64]()
    let found = WindowProbe.search(
      ids: 0 ..< 10,
      stoppingAfter: [12],
      until: start + .seconds(1),
      now: { start }
    ) { id in
      looked.append(id)
      return Self.window(at: id)
    }

    #expect(found.map(\.windowID) == [10, 11, 12])
    #expect(looked.last == 8)
  }

  /// With nothing to stop at, every id in the range is tried.
  @Test
  func anEmptyTargetSetSearchesTheWholeRange() {
    var looked = [UInt64]()
    let found = WindowProbe.search(
      ids: 0 ..< 10,
      stoppingAfter: [],
      until: start + .seconds(1),
      now: { start }
    ) { id in
      looked.append(id)
      return Self.window(at: id)
    }

    #expect(found.map(\.windowID) == [10, 11, 12])
    #expect(looked == Array(0 ..< 10))
  }

  /// The deadline ends the search with what was found so far.
  @Test
  func theDeadlineEndsTheSearchWithWhatWasFound() {
    var clock = start
    var looked = [UInt64]()
    let found = WindowProbe.search(
      ids: 0 ..< 10,
      stoppingAfter: [],
      until: start + .seconds(3),
      now: { clock }
    ) { id in
      looked.append(id)
      clock = clock.advanced(by: .seconds(1))
      return Self.window(at: id)
    }

    #expect(looked == [0, 1, 2])
    #expect(found.map(\.windowID) == [10])
  }

  // MARK: Private

  private let start = ContinuousClock.now

  /// Windows at element ids 2, 5 and 8; every other id answers nothing.
  private static func window(at id: UInt64) -> ProbedWindow? {
    let windowIDs: [UInt64: CGWindowID] = [2: 10, 5: 11, 8: 12]
    return windowIDs[id].map { ProbedWindow(element: AXUIElementCreateApplication(pid_t(9300 + $0)), windowID: $0) }
  }

}
