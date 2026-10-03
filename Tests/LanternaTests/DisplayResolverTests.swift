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
    let resolved = resolver(frontmostPID: 123, focusedFrame: CGRect(x: 1500, y: 400, width: 200, height: 200))
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
    let resolved = resolver(frontmostPID: 123, focusedFrame: nil)
      .resolve(.frontWindow, over: screens)
    #expect(resolved == .single(0))
  }

  @Test
  func ownFrontmostApplicationFallsBackToPrimary() {
    let (resolved, fellBack) = resolver(
      frontmostPID: 777,
      focusedFrame: CGRect(x: 1500, y: 400, width: 200, height: 200),
      ownPID: 777
    )
    .resolveWithFallback(.frontWindow, over: screens)
    #expect(resolved == .single(0))
    #expect(fellBack)
  }

  @Test
  func otherFrontmostApplicationResolvesWithoutFallback() {
    let (resolved, fellBack) = resolver(
      frontmostPID: 123,
      focusedFrame: CGRect(x: 1500, y: 400, width: 200, height: 200),
      ownPID: 777
    )
    .resolveWithFallback(.frontWindow, over: screens)
    #expect(resolved == .single(1))
    #expect(!fellBack)
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

  @Test
  func externalDisplayAboveHoldsWindowReadInAccessibilitySpace() {
    let stacked = [
      DisplayInfo(frame: CGRect(x: 0, y: 0, width: 1512, height: 944), isPrimary: true),
      DisplayInfo(frame: CGRect(x: 0, y: 944, width: 1920, height: 1080), isPrimary: false),
    ]
    // Above the menu-bar display, accessibility y runs negative.
    let frame = CGRect(x: 100, y: -800, width: 400, height: 300)
    #expect(DisplayResolver.cocoaCentre(ofAccessibilityFrame: frame, over: stacked)
      == CGPoint(x: 300, y: 1594))
    let resolved = resolver(frontmostPID: 123, focusedFrame: frame)
      .resolve(.frontWindow, over: stacked)
    #expect(resolved == .single(1))
  }

  @Test
  func externalDisplayBelowHoldsWindowReadInAccessibilitySpace() {
    let stacked = [
      DisplayInfo(frame: CGRect(x: 0, y: 0, width: 1512, height: 944), isPrimary: true),
      DisplayInfo(frame: CGRect(x: 0, y: -1080, width: 1920, height: 1080), isPrimary: false),
    ]
    // Below the menu-bar display, accessibility y passes its height.
    let frame = CGRect(x: 100, y: 1200, width: 400, height: 300)
    #expect(DisplayResolver.cocoaCentre(ofAccessibilityFrame: frame, over: stacked)
      == CGPoint(x: 300, y: -406))
    let resolved = resolver(frontmostPID: 123, focusedFrame: frame)
      .resolve(.frontWindow, over: stacked)
    #expect(resolved == .single(1))
  }

  @Test
  func sideBySideDisplaysOfDifferentHeightsHoldWindowsReadInAccessibilitySpace() {
    // The shorter display shares the bottom edge, so in accessibility
    // space its rows start below the menu-bar display's top.
    let low = CGRect(x: 1550, y: 800, width: 100, height: 100)
    #expect(DisplayResolver.cocoaCentre(ofAccessibilityFrame: low, over: screens)
      == CGPoint(x: 1600, y: 94))
    #expect(resolver(frontmostPID: 123, focusedFrame: low).resolve(.frontWindow, over: screens)
      == .single(1))
    let top = CGRect(x: 100, y: 50, width: 200, height: 100)
    #expect(DisplayResolver.cocoaCentre(ofAccessibilityFrame: top, over: screens)
      == CGPoint(x: 200, y: 844))
    #expect(resolver(frontmostPID: 123, focusedFrame: top).resolve(.frontWindow, over: screens)
      == .single(0))
  }

  @Test
  func conversionPivotsOnTheMenuBarDisplayWhereverItIsListed() {
    let moved = [
      DisplayInfo(frame: CGRect(x: -1080, y: 0, width: 1080, height: 720), isPrimary: false),
      DisplayInfo(frame: CGRect(x: 0, y: 0, width: 1512, height: 944), isPrimary: true),
    ]
    let frame = CGRect(x: -600, y: 600, width: 200, height: 100)
    #expect(DisplayResolver.cocoaCentre(ofAccessibilityFrame: frame, over: moved)
      == CGPoint(x: -500, y: 294))
  }

  @Test
  func conversionNeedsAScreenToPivotOn() {
    let frame = CGRect(x: 0, y: 0, width: 10, height: 10)
    #expect(DisplayResolver.cocoaCentre(ofAccessibilityFrame: frame, over: []) == nil)
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
    focusedFrame: CGRect? = nil,
    ownPID: pid_t = -1
  ) -> DisplayResolver {
    DisplayResolver(
      cursor: { cursor },
      frontmostPID: { frontmostPID },
      ownPID: { ownPID },
      focusedFrame: { _ in focusedFrame },
      screens: { [DisplayInfo]() }
    )
  }

}
