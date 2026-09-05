import ApplicationServices
import Foundation
@testable import Lanterna
import Testing

/// What the reader sends, and what it does with each answer.
///
/// Which error an application returns is the whole behaviour under test, and no
/// real application can be asked to return one, so a stand-in answers instead
/// and records every message it received.
struct AXApplicationWindowReaderMessagingTests {
    private typealias Reader = AXApplicationWindowReader

    @Test func anOrdinaryApplicationYieldsOneRecordPerWindow() {
        let application = FakeApplication(windowCount: 2)
        let read = try? application.read().get()
        #expect(read?.records == [
            WindowRecord(windowID: 100, title: "Window 0", kind: .standard, isMinimized: false),
            WindowRecord(windowID: 101, title: "Window 1", kind: .standard, isMinimized: false),
        ])
        #expect(read?.droppedWithoutID == 0)
    }

    /// A record is only as good as the casts that build it: a subrole that
    /// did not read as a string would classify every window as undetermined,
    /// and a minimized flag that did not read as a boolean would report every
    /// window as visible, with no failure to show for either.
    @Test func aRecordCarriesTheKindAndStateTheAnswersDescribe() {
        let application = FakeApplication(windowCount: 2)
        application.attributeResult = { index, name in
            guard index == 1 else { return nil }
            switch name {
            case kAXSubroleAttribute: return (.success, kAXDialogSubrole as CFString)
            case kAXMinimizedAttribute: return (.success, kCFBooleanTrue)
            default: return nil
            }
        }

        let read = try? application.read().get()
        #expect(read?.records == [
            WindowRecord(windowID: 100, title: "Window 0", kind: .standard, isMinimized: false),
            WindowRecord(windowID: 101, title: "Window 1", kind: .dialog, isMinimized: true),
        ])
    }

    /// Only an absent value is an answer; anything else means the application
    /// could not be read, and its records go with it.
    @Test(arguments: [
        (AXError.noValue, nil),
        (.attributeUnsupported, nil),
        (.cannotComplete, ReadFailure.unavailable(.cannotComplete)),
        (.apiDisabled, .permissionMissing),
        (.invalidUIElement, .unavailable(.invalidUIElement)),
        (.illegalArgument, .unavailable(.illegalArgument)),
    ])
    func anAttributeErrorEitherMeansAbsentOrDiscardsTheApplication(
        error: AXError,
        failure: ReadFailure?
    ) {
        let application = FakeApplication(windowCount: 2)
        application.attributeResult = { index, name in
            index == 1 && name == kAXTitleAttribute ? (error, nil) : nil
        }

        switch application.read() {
        case let .success(read):
            #expect(failure == nil)
            // An untitled window is still a window.
            #expect(read.records.count == 2)
            #expect(read.records.last?.title == "")
        case let .failure(reason):
            #expect(reason == failure)
        }
    }

    /// A dead or unreachable application is answered with the same code as a
    /// timeout, only at once; how long the answer took is the only way to tell
    /// which of the two it was.
    @Test(arguments: [
        (Duration.zero, ReadFailure.unavailable(.cannotComplete)),
        (Reader.unreachableAnswerCeiling - .milliseconds(1), .unavailable(.cannotComplete)),
        (Reader.unreachableAnswerCeiling, .timedOut),
        (.seconds(Double(Reader.messagingTimeout)), .timedOut),
    ])
    func aCannotCompleteAnswerIsATimeoutOnlyIfItTookLongEnough(cost: Duration, failure: ReadFailure) {
        let application = FakeApplication(windowCount: 2)
        application.attributeResult = { index, name in
            index == 1 && name == kAXTitleAttribute ? (.cannotComplete, nil) : nil
        }
        application.costOverride = { index, name in
            index == 1 && name == kAXTitleAttribute ? cost : nil
        }
        #expect(application.read() == .failure(failure))
    }

    /// A partly read application is worse than a missing one, so nothing that
    /// was already gathered survives the failure.
    @Test func aFailureDiscardsTheRecordsAlreadyGathered() {
        let application = FakeApplication(windowCount: 3)
        application.attributeResult = { index, name in
            index == 2 && name == kAXRoleAttribute ? (.cannotComplete, nil) : nil
        }
        application.costOverride = { index, name in
            index == 2 && name == kAXRoleAttribute ? .seconds(1) : nil
        }
        #expect(application.read() == .failure(.timedOut))
    }

    /// The budget is checked before every message, the id fetch included. At
    /// 400 ms a message, three go out at 0, 400 and 800 ms and the fourth is
    /// refused at 1200 ms. At 200 ms the five attribute reads land at 0
    /// through 800 ms and the id fetch falls exactly on the line, where it
    /// must be refused too: without a check of its own it would go out, and
    /// the read would end a window later with the id already fetched. At
    /// 999 ms the second message starts just under the line, the documented
    /// worst case.
    @Test(arguments: [
        (Duration.milliseconds(400), 3),
        (.milliseconds(200), 5),
        (.milliseconds(999), 2),
    ])
    func nothingIsSentOnceTheBudgetIsSpent(costPerMessage: Duration, messagesSent: Int) {
        let application = FakeApplication(windowCount: 10)
        application.costPerMessage = costPerMessage

        let messagesInOrder = [
            kAXWindowsAttribute, kAXRoleAttribute, kAXSubroleAttribute, kAXTitleAttribute, kAXMinimizedAttribute,
        ]
        #expect(application.read() == .failure(.timedOut))
        #expect(application.attributesRead == Array(messagesInOrder.prefix(messagesSent)))
        #expect(application.windowIDReads.isEmpty)
    }

    /// The API scopes a timeout to the element it was set on, so the
    /// application's covers none of its windows: each element gets its own,
    /// at `messagingTimeout`, before anything is asked of it.
    @Test func everyElementGetsItsOwnTimeoutBeforeItIsMessaged() {
        let application = FakeApplication(windowCount: 2)
        _ = application.read()

        #expect(application.preparedElements == [nil, 0, 1])
        #expect(application.preparedTimeouts == [1.0, 1.0, 1.0])
        #expect(application.messagedBeforePrepared.isEmpty)
    }

    /// The application element is prepared like any other: without its
    /// timeout the window list itself would be requested with the default.
    @Test func anApplicationWhoseTimeoutCannotBeSetIsNeverMessaged() {
        let application = FakeApplication(windowCount: 2)
        application.timeoutResult = { $0 == nil ? .cannotComplete : .success }

        #expect(application.read() == .failure(.unavailable(.cannotComplete)))
        #expect(application.attributesRead.isEmpty)
        #expect(application.preparedElements == [nil])
    }

    /// Without its timeout an element would be messaged with the multi-second
    /// default, so it is not messaged at all.
    @Test func anElementWhoseTimeoutCannotBeSetIsNeverMessaged() {
        let application = FakeApplication(windowCount: 2)
        application.timeoutResult = { $0 == 0 ? .cannotComplete : .success }

        #expect(application.read() == .failure(.unavailable(.cannotComplete)))
        #expect(application.attributesRead == [kAXWindowsAttribute])
        #expect(application.windowIDReads.isEmpty)
    }

    /// An element the rule table rules out — the Finder desktop, a font panel —
    /// is asked nothing more once its role and subrole are in. Every message
    /// is a round trip, and a failing one would discard the whole application
    /// over an element that was never going to be a row.
    @Test func anExcludedElementIsNotMessagedFurther() {
        let application = FakeApplication(windowCount: 2)
        application.attributeResult = { index, name in
            guard index == 0 else { return nil }
            switch name {
            case kAXRoleAttribute: return (.success, kAXScrollAreaRole as CFString)
            // Never sent, so it never gets the chance to fail the read.
            case kAXTitleAttribute: return (.invalidUIElement, nil)
            default: return nil
            }
        }

        let read = try? application.read().get()
        #expect(read?.records.map(\.windowID) == [101])
        #expect(read?.droppedWithoutID == 0)
        #expect(application.attributesRead(of: 0) == [kAXRoleAttribute, kAXSubroleAttribute])
        #expect(application.attributesRead(of: 1) == [
            kAXRoleAttribute, kAXSubroleAttribute, kAXTitleAttribute, kAXMinimizedAttribute,
        ])
        #expect(application.windowIDReads == [1])
    }

    /// The window id is the one answer whose absence is ordinary, whether it
    /// comes as an error or as a zero id, so it costs its own row and nothing
    /// else.
    @Test(arguments: [AXError.illegalArgument, .invalidUIElement, .success])
    func aMissingWindowIDCostsOnlyItsOwnRow(error: AXError) {
        let application = FakeApplication(windowCount: 3)
        application.windowIDResult = { $0 == 1 ? (error, 0) : nil }

        let read = try? application.read().get()
        #expect(read?.records.map(\.windowID) == [100, 102])
        #expect(read?.droppedWithoutID == 1)
    }

    /// The id fetch is a round trip like any attribute read. Read as "no id",
    /// a hang on the last window would have turned that window into a dropped
    /// element and the others into a partial list of a hung application, the
    /// outcome discarding the whole application exists to avoid.
    @Test(arguments: [
        (Duration.zero, ReadFailure.unavailable(.cannotComplete)),
        (.seconds(1), .timedOut),
    ])
    func aCannotCompleteOnTheLastWindowIDFetchEndsTheRead(cost: Duration, failure: ReadFailure) {
        let application = FakeApplication(windowCount: 3)
        application.windowIDResult = { $0 == 2 ? (.cannotComplete, 0) : nil }
        application.windowIDCostOverride = { $0 == 2 ? cost : nil }

        #expect(application.read() == .failure(failure))
    }

    /// The ceiling measures the one message, not the read so far: an instant
    /// refusal that arrives after half a second of ordinary messages is still
    /// a refusal. Measured from the start of the read instead, an application
    /// that quit would be reported as hung whenever a few messages had already
    /// gone out before the one it refused.
    @Test func aQuickRefusalLateInTheBudgetIsStillARefusal() {
        let application = FakeApplication(windowCount: 1)
        // Window list, role and subrole take 540 ms; the title is then refused
        // at once.
        application.costPerMessage = .milliseconds(180)
        application.attributeResult = { _, name in
            name == kAXTitleAttribute ? (.cannotComplete, nil) : nil
        }
        application.costOverride = { _, name in
            name == kAXTitleAttribute ? .zero : nil
        }
        #expect(application.read() == .failure(.unavailable(.cannotComplete)))
    }

    /// The id fetch shares that measurement.
    @Test func aQuickRefusalOfTheWindowIDLateInTheBudgetIsStillARefusal() {
        let application = FakeApplication(windowCount: 1)
        // The five attribute reads take 900 ms; the id fetch is then refused
        // at once.
        application.costPerMessage = .milliseconds(180)
        application.windowIDResult = { _ in (.cannotComplete, 0) }
        application.windowIDCostOverride = { _ in .zero }
        #expect(application.read() == .failure(.unavailable(.cannotComplete)))
    }

    /// Permission revoked between two messages is about this process, not about
    /// the element, so it must not be counted as a window that had no id.
    @Test func aRevokedPermissionOnTheWindowIDFetchEndsTheRead() {
        let application = FakeApplication(windowCount: 3)
        application.windowIDResult = { $0 == 2 ? (.apiDisabled, 0) : nil }

        #expect(application.read() == .failure(.permissionMissing))
    }

    /// An application with nothing open answers an empty list, which is a
    /// normal read, not a skipped application.
    @Test func anApplicationWithoutWindowsReadsSuccessfully() {
        let application = FakeApplication(windowCount: 0)
        let read = try? application.read().get()
        #expect(read?.records.isEmpty == true)
    }

    /// "No value" is accepted as nothing open too. The windows behind the fake
    /// prove that the answer, not the default, produced the empty list.
    @Test func aWindowListWithNoValueReadsAsEmpty() {
        let application = FakeApplication(windowCount: 2)
        application.attributeResult = { _, name in
            name == kAXWindowsAttribute ? (.noValue, nil) : nil
        }

        let read = try? application.read().get()
        #expect(read?.records.isEmpty == true)
        #expect(application.attributesRead == [kAXWindowsAttribute])
    }

    /// Every live application answers the window list with an array, an empty
    /// one included, so anything else is an application that cannot be read,
    /// not one that is idle. Folding it into "no windows" would count the
    /// application without a row and without a reason.
    @Test(arguments: [
        (AXError.attributeUnsupported, nil, ReadFailure.unavailable(.attributeUnsupported)),
        (.success, "oops", .malformedAnswer),
    ])
    func anAbnormalWindowListAnswerDiscardsTheApplication(
        error: AXError,
        value: String?,
        failure: ReadFailure
    ) {
        let application = FakeApplication(windowCount: 2)
        application.attributeResult = { _, name in
            name == kAXWindowsAttribute ? (error, value as CFString?) : nil
        }

        #expect(application.read() == .failure(failure))
        #expect(application.attributesRead == [kAXWindowsAttribute])
    }
}
