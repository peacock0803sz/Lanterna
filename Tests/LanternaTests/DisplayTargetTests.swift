import CoreGraphics
import Foundation
@testable import Lanterna
import Testing

struct DisplayTargetTests {

  // MARK: Internal

  @Test
  func primaryResolvesToTheMenuBarDisplay() {
    #expect(DisplayTarget.resolve(.primary, cursor: CGPoint(x: 1600, y: 100), focusedWindow: nil, screens: screens) == .single(0))
  }

  @Test
  func primaryFallsBackToTheFirstScreen() {
    let plain = screens.map { DisplayInfo(frame: $0.frame, isPrimary: false) }
    #expect(DisplayTarget.resolve(.primary, cursor: nil, focusedWindow: nil, screens: plain) == .single(0))
  }

  @Test
  func cursorResolvesToTheContainingDisplay() {
    #expect(DisplayTarget.resolve(.cursor, cursor: CGPoint(x: 1600, y: 100), focusedWindow: nil, screens: screens) == .single(1))
    #expect(DisplayTarget.resolve(.cursor, cursor: CGPoint(x: 100, y: 100), focusedWindow: nil, screens: screens) == .single(0))
  }

  @Test
  func missingOrOutsideCursorFallsBackToPrimary() {
    #expect(DisplayTarget.resolve(.cursor, cursor: nil, focusedWindow: nil, screens: screens) == .single(0))
    #expect(DisplayTarget
      .resolve(.cursor, cursor: CGPoint(x: -5000, y: -5000), focusedWindow: nil, screens: screens) == .single(0))
  }

  @Test
  func focusedWindowResolvesToItsDisplay() {
    #expect(DisplayTarget
      .resolve(.frontWindow, cursor: nil, focusedWindow: CGPoint(x: 1600, y: 100), screens: screens) == .single(1))
  }

  @Test
  func missingFocusedWindowFallsBackToPrimary() {
    #expect(DisplayTarget
      .resolve(.frontWindow, cursor: CGPoint(x: 1600, y: 100), focusedWindow: nil, screens: screens) == .single(0))
  }

  @Test
  func allResolvesToEveryDisplay() {
    #expect(DisplayTarget.resolve(.all, cursor: nil, focusedWindow: nil, screens: screens) == .all([0, 1]))
  }

  /// CoreGraphics counts the minimum edge as inside and the maximum
  /// edge as outside, so a point on the shared edge belongs to the
  /// display whose minimum edge it is.
  @Test
  func sharedEdgeBelongsToTheMinimumEdgeDisplay() {
    #expect(DisplayTarget.resolve(.cursor, cursor: CGPoint(x: 1512, y: 100), focusedWindow: nil, screens: screens) == .single(1))
  }

  // MARK: Private

  private var screens: [DisplayInfo] {
    [
      DisplayInfo(frame: CGRect(x: 0, y: 0, width: 1512, height: 944), isPrimary: true),
      DisplayInfo(frame: CGRect(x: 1512, y: 0, width: 1080, height: 720), isPrimary: false),
    ]
  }

}
