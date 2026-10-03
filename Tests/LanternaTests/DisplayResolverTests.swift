import CoreGraphics
import Foundation
@testable import Lanterna
import Testing

struct DisplayResolverTests {

  // MARK: Internal

  @Test
  func cursorPointSelectsItsDisplay() {
    let resolved = resolver(cursor: CGPoint(x: 1600, y: 100)).resolve(.cursor, over: screens)
    #expect(resolved == .single(1))
  }

  @Test
  func missingCursorFallsBackToPrimary() {
    let resolved = resolver().resolve(.cursor, over: screens)
    #expect(resolved == .single(0))
  }

  @Test
  func focusedWindowPointSelectsItsDisplay() {
    let resolved = resolver(frontmostPID: 123, focusedPosition: CGPoint(x: 1600, y: 100))
      .resolve(.frontWindow, over: screens)
    #expect(resolved == .single(1))
  }

  @Test
  func missingFrontmostApplicationFallsBackToPrimary() {
    let resolved = resolver().resolve(.frontWindow, over: screens)
    #expect(resolved == .single(0))
  }

  @Test
  func applicationWithoutWindowsFallsBackToPrimary() {
    let resolved = resolver(frontmostPID: 123, focusedPosition: nil)
      .resolve(.frontWindow, over: screens)
    #expect(resolved == .single(0))
  }

  @Test
  func missingPointReportsFallback() {
    let (_, fellBack) = resolver().resolveWithFallback(.cursor, over: screens)
    #expect(fellBack)
  }

  @Test
  func placedPointReportsNoFallback() {
    let (_, fellBack) = resolver(cursor: CGPoint(x: 1600, y: 100))
      .resolveWithFallback(.cursor, over: screens)
    #expect(!fellBack)
  }

  @Test
  func primaryNeverReportsFallback() {
    let (_, fellBack) = resolver().resolveWithFallback(.primary, over: screens)
    #expect(!fellBack)
  }

  @Test
  func rearrangedScreensResolveAnew() {
    let moved = [
      DisplayInfo(frame: CGRect(x: 0, y: 0, width: 1080, height: 720), isPrimary: false),
      DisplayInfo(frame: CGRect(x: 1080, y: 0, width: 1512, height: 944), isPrimary: true),
    ]
    let resolved = resolver(cursor: CGPoint(x: 100, y: 100)).resolve(.cursor, over: moved)
    #expect(resolved == .single(0))
  }

  // MARK: Private

  private var screens: [DisplayInfo] {
    [
      DisplayInfo(frame: CGRect(x: 0, y: 0, width: 1512, height: 944), isPrimary: true),
      DisplayInfo(frame: CGRect(x: 1512, y: 0, width: 1080, height: 720), isPrimary: false),
    ]
  }

  private func resolver(
    cursor: CGPoint? = nil,
    frontmostPID: pid_t? = nil,
    focusedPosition: CGPoint? = nil
  ) -> DisplayResolver {
    DisplayResolver(
      cursor: { cursor },
      frontmostPID: { frontmostPID },
      focusedPosition: { _ in focusedPosition },
      screens: { [DisplayInfo]() }
    )
  }

}
