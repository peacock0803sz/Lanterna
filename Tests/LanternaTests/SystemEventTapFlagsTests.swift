import CoreGraphics
@testable import Lanterna
import Testing

/// Which modifier changes count as Command being let go.
///
/// Pairs of states rather than single states, because that is the whole
/// question: a `.flagsChanged` carrying no `.maskCommand` is either Command
/// coming up or some other modifier moving with Command already up, and the
/// two must not come out the same.
///
/// This is the only place that question is asked. The judgement sits below
/// `EventTapControlling`, so `FakeEventTap` cannot reach it: every other test
/// in the suite starts from "the tap said Command was released" and so takes
/// the answer as given.
struct SystemEventTapFlagsTests {
    @Test func lettingGoOfCommandAloneIsARelease() {
        #expect(SystemEventTap.shouldReportRelease(previous: .maskCommand, current: []))
    }

    @Test func lettingGoOfCommandWhileShiftStaysDownIsARelease() {
        #expect(
            SystemEventTap.shouldReportRelease(
                previous: [.maskShift, .maskCommand],
                current: .maskShift
            )
        )
    }

    /// The case that must never commit. Command is already up, and Shift going
    /// down carries no `.maskCommand` — which is exactly what a real release
    /// looks like to anything reading `current` alone.
    @Test func pressingShiftWithCommandAlreadyUpIsNotARelease() {
        #expect(!SystemEventTap.shouldReportRelease(previous: [], current: .maskShift))
    }

    /// The other half of the same prohibition, and the one a state-reading
    /// judgement fails most obviously: nothing but Shift moved, and it moved
    /// in the direction a release moves.
    @Test func lettingGoOfShiftAloneIsNotARelease() {
        #expect(!SystemEventTap.shouldReportRelease(previous: .maskShift, current: []))
    }

    /// Swapping hands. `.maskCommand` stays set while either Command is down,
    /// so no edge appears and the case needs no code of its own.
    @Test func lettingGoOfOneCommandWhileTheOtherIsHeldIsNotARelease() {
        #expect(
            !SystemEventTap.shouldReportRelease(
                previous: .maskCommand,
                current: .maskCommand
            )
        )
    }

    @Test func pressingCommandIsNotARelease() {
        #expect(!SystemEventTap.shouldReportRelease(previous: [], current: .maskCommand))
    }

    /// Option and Control are covered by the same clause as Shift, and the
    /// spec names all three. Asserting them keeps a later change that special-
    /// cases one modifier from passing on the strength of the Shift cases
    /// alone.
    @Test(arguments: [CGEventFlags.maskAlternate, .maskControl, .maskAlphaShift])
    func anotherModifierMovingWithCommandUpIsNeverARelease(other: CGEventFlags) {
        #expect(!SystemEventTap.shouldReportRelease(previous: [], current: other))
        #expect(!SystemEventTap.shouldReportRelease(previous: other, current: []))
    }

    /// The same modifiers moving while Command is held must not commit
    /// either: the user is still holding the panel open.
    @Test(arguments: [CGEventFlags.maskAlternate, .maskControl, .maskShift])
    func anotherModifierMovingWithCommandHeldIsNeverARelease(other: CGEventFlags) {
        #expect(
            !SystemEventTap.shouldReportRelease(
                previous: .maskCommand,
                current: [.maskCommand, other]
            )
        )
        #expect(
            !SystemEventTap.shouldReportRelease(
                previous: [.maskCommand, other],
                current: .maskCommand
            )
        )
    }

    /// Real flags arrive with bits this feature does not read —
    /// `maskNonCoalesced` is on every event, and the device-dependent bits
    /// say which side of the keyboard was used. The judgement must ignore all
    /// of them, or a release would be missed for riding on a real keyboard.
    @Test func bitsOutsideTheModifiersDoNotChangeTheAnswer() {
        let noise = CGEventFlags(rawValue: 0x100)
        #expect(
            SystemEventTap.shouldReportRelease(
                previous: [.maskCommand, noise],
                current: noise
            )
        )
        #expect(
            !SystemEventTap.shouldReportRelease(
                previous: noise,
                current: [.maskShift, noise]
            )
        )
    }
}
