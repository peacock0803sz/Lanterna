import ApplicationServices
import Foundation
@testable import Lanterna
import Testing

// MARK: - WindowElementResolverTests

/// When resolving goes beyond the application's own window list: only with
/// the setting on, only for a target the list lacks, and only as far as the
/// probe finds it.
struct WindowElementResolverTests {

  // MARK: Internal

  @Test
  func withTheSettingOffTheProbeIsNeverAskedAndTheTargetIsGone() {
    let peer = ScriptedProbe(probed: [7])
    let resolution = peer.resolver(probing: false).resolve(target(windowID: 7))

    #expect(failure(of: resolution) == .windowGone)
    #expect(peer.calls.isEmpty)
  }

  @Test
  func aTargetTheListHoldsIsNotProbedFor() {
    let peer = ScriptedProbe(listed: [7], probed: [7])
    let resolution = peer.resolver(probing: true).resolve(target(windowID: 7))

    #expect(element(of: resolution).map { CFEqual($0, peer.elements[7]) } == true)
    #expect(peer.calls.isEmpty)
  }

  @Test
  func aTargetOnlyTheProbeFindsIsResolvedToItsElement() {
    let peer = ScriptedProbe(probed: [5, 7])
    let resolution = peer.resolver(probing: true).resolve(target(windowID: 7))

    #expect(element(of: resolution).map { CFEqual($0, peer.elements[7]) } == true)
  }

  @Test
  func aTargetTheProbeMissesIsGone() {
    let peer = ScriptedProbe(probed: [5, 6])
    let resolution = peer.resolver(probing: true).resolve(target(windowID: 7))

    #expect(failure(of: resolution) == .windowGone)
    #expect(peer.calls.count == 1)
  }

  /// The probe is told whom to look for and when to stop, so a press never
  /// waits longer than the limit on the main actor.
  @Test
  func theProbeIsHandedTheTargetAndAShortDeadline() {
    let peer = ScriptedProbe(probed: [7])
    _ = peer.resolver(probing: true).resolve(target(windowID: 7, pid: 321))

    #expect(peer.calls.count == 1)
    #expect(peer.calls.first?.pid == 321)
    #expect(peer.calls.first?.target == 7)
    #expect(peer.calls.first?.deadline == peer.startedAt + WindowElementResolver.otherSpaceProbeLimit)
  }

  /// The probe returns every window it finds, so the same id may come back
  /// twice. The first is the one taken.
  @Test
  func twoProbedEntriesWithOneIDResolveToTheFirst() {
    let peer = ScriptedProbe(probed: [])
    peer.probed = [peer.window(7, as: 7), peer.window(8, as: 7)]
    let resolution = peer.resolver(probing: true).resolve(target(windowID: 7))

    #expect(element(of: resolution).map { CFEqual($0, peer.elements[7]) } == true)
  }

  /// The resolver is built once and the setting changes live, so the answer
  /// follows the setting at the time of use.
  @Test
  func theSettingIsReadAtTheTimeOfUse() {
    let setting = OtherSpacesSetting(isOn: false)
    let peer = ScriptedProbe(probed: [7])
    let resolver = peer.resolver(probing: { setting.isOn })

    #expect(failure(of: resolver.resolve(target(windowID: 7))) == .windowGone)
    setting.isOn = true
    #expect(element(of: resolver.resolve(target(windowID: 7))) != nil)
    setting.isOn = false
    #expect(failure(of: resolver.resolve(target(windowID: 7))) == .windowGone)
  }

  // MARK: Private

  private func target(windowID: CGWindowID, pid: pid_t = 4242) -> ActivationTarget {
    ActivationTarget(
      id: WindowItem.Identifier(windowID: windowID),
      ownerProcessIdentifier: pid,
      appName: "TextEdit",
      displayTitle: "Untitled"
    )
  }

  private func element(of resolution: WindowElementResolver.Resolution) -> AXUIElement? {
    if case .element(let element) = resolution {
      return element
    }
    return nil
  }

  private func failure(of resolution: WindowElementResolver.Resolution) -> ActivationFailure? {
    if case .failure(let failure) = resolution {
      return failure
    }
    return nil
  }

}

// MARK: - ScriptedProbe

/// An application whose list and probe answer from tables, recording each
/// probe. Window ids index `elements`, so a test names windows by id.
// swiftlint:disable:next no_unchecked_sendable - test-only; synchronous scripted answers, never shared
private final class ScriptedProbe: @unchecked Sendable {

  // MARK: Lifecycle

  init(listed: [CGWindowID] = [], probed: [CGWindowID]) {
    self.listed = listed
    self.probed = []
    self.probed = probed.map { ProbedWindow(element: elements[$0]!, windowID: $0) }
  }

  // MARK: Internal

  let startedAt = ContinuousClock.now
  let elements: [CGWindowID: AXUIElement] = Dictionary(
    uniqueKeysWithValues: (0 ..< 10).map { (CGWindowID($0), AXUIElementCreateApplication(pid_t(9200 + $0))) }
  )
  /// What the probe answers with.
  var probed: [ProbedWindow]
  private(set) var calls = [(pid: pid_t, target: CGWindowID?, deadline: ContinuousClock.Instant)]()

  /// The element named `element`, reporting `id` as its window id.
  func window(_ element: CGWindowID, as id: CGWindowID) -> ProbedWindow {
    ProbedWindow(element: elements[element]!, windowID: id)
  }

  func resolver(probing: Bool) -> WindowElementResolver {
    resolver(probing: { probing })
  }

  func resolver(probing: @escaping @Sendable () -> Bool) -> WindowElementResolver {
    WindowElementResolver(
      copyWindows: { [self] _ in (.success, listed.compactMap { elements[$0] }) },
      copyWindowID: { [self] element in
        guard let id = elements.first(where: { CFEqual($0.value, element) })?.key else {
          return (.illegalArgument, 0)
        }
        return (.success, id)
      },
      probesOtherSpaces: probing,
      probeWindows: { [self] pid, target, deadline in
        calls.append((pid, target, deadline))
        return probed
      },
      now: { [startedAt] in startedAt }
    )
  }

  // MARK: Private

  private let listed: [CGWindowID]

}
