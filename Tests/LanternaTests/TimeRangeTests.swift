import Foundation
@testable import Lanterna
import Testing

/// The Since-this-launch range: bounded by the launch start when
/// known, open while the launch has yet to spill.
struct TimeRangeTests {

  @Test
  func sinceThisLaunchStartsAtTheLaunch() {
    var selection = TimeRangeSelection()
    selection.kind = .relativeNow
    selection.relative = .sinceLaunch
    let resolved = TimeRangeResolver.resolve(
      selection,
      now: Date(timeIntervalSince1970: 1_700_003_600),
      launchStart: Date(timeIntervalSince1970: 1_700_000_000)
    )
    #expect(resolved.startMilliseconds == 1_700_000_000_000)
    #expect(resolved.endMilliseconds == 1_700_003_600_000)
    #expect(resolved.queryTokens.count == 1)
  }

  @Test
  func sinceThisLaunchWithoutAStartStaysOpen() {
    var selection = TimeRangeSelection()
    selection.kind = .relativeNow
    selection.relative = .sinceLaunch
    let resolved = TimeRangeResolver.resolve(
      selection,
      now: Date(timeIntervalSince1970: 1_700_003_600),
      launchStart: nil
    )
    #expect(resolved.startMilliseconds == nil)
    #expect(resolved.endMilliseconds == 1_700_003_600_000)
    #expect(resolved.queryTokens.isEmpty)
  }

}
