@testable import AppleBridge
import EventKit
import Foundation
import ObjectiveC

/// Test-only seam for invitation RSVP tests. EventKit does not expose public
/// constructors for `EKParticipant`, so mock attendees use a runtime subclass
/// and associated objects on `EKEvent` (with swizzled `attendees`/`hasAttendees`).
enum EventKitMockParticipantSupport {
    private nonisolated(unsafe) static var associatedAttendeesKey: UInt8 = 0
    private nonisolated(unsafe) static var participantStatuses: [ObjectIdentifier: Int] = [:]
    private nonisolated(unsafe) static var mockParticipantClass: AnyClass?
    private nonisolated(unsafe) static var swizzlesInstalled = false
    private nonisolated(unsafe) static var originalAttendeesIMP: IMP?
    private nonisolated(unsafe) static var originalHasAttendeesIMP: IMP?
    private nonisolated(unsafe) static let stateLock = NSLock()

    private static func withLock<T>(_ body: () throws -> T) rethrows -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return try body()
    }

    static func installSwizzlesIfNeeded() {
        withLock {
            installSwizzlesIfNeededLocked()
        }
    }

    private static func installSwizzlesIfNeededLocked() {
        guard !swizzlesInstalled else { return }
        guard
            let attendeesMethod = class_getInstanceMethod(EKEvent.self, #selector(getter: EKEvent.attendees)),
            let hasAttendeesMethod = class_getInstanceMethod(EKEvent.self, #selector(getter: EKEvent.hasAttendees))
        else {
            return
        }

        originalAttendeesIMP = method_getImplementation(attendeesMethod)
        originalHasAttendeesIMP = method_getImplementation(hasAttendeesMethod)
        guard let originalAttendeesIMP, let originalHasAttendeesIMP else { return }

        let attendeesBlock: @convention(block) (EKEvent) -> [EKParticipant]? = { event in
            if let mockAttendees = objc_getAssociatedObject(event, &associatedAttendeesKey) as? [EKParticipant] {
                return mockAttendees
            }
            typealias Original = @convention(c) (EKEvent, Selector) -> [EKParticipant]?
            let original = unsafeBitCast(originalAttendeesIMP, to: Original.self)
            return original(event, #selector(getter: EKEvent.attendees))
        }

        let hasAttendeesBlock: @convention(block) (EKEvent) -> Bool = { event in
            if let mockAttendees = objc_getAssociatedObject(event, &associatedAttendeesKey) as? [EKParticipant],
               !mockAttendees.isEmpty
            {
                return true
            }
            typealias Original = @convention(c) (EKEvent, Selector) -> Bool
            let original = unsafeBitCast(originalHasAttendeesIMP, to: Original.self)
            return original(event, #selector(getter: EKEvent.hasAttendees))
        }

        method_setImplementation(attendeesMethod, imp_implementationWithBlock(attendeesBlock))
        method_setImplementation(hasAttendeesMethod, imp_implementationWithBlock(hasAttendeesBlock))
        swizzlesInstalled = true
    }

    static func makeCurrentUserAttendee(
        eventStore: EKEventStore,
        status: EKParticipantStatus = .pending
    ) -> EKParticipant {
        withLock {
            installSwizzlesIfNeededLocked()

            return makeCurrentUserAttendeeLocked(eventStore: eventStore, status: status)
        }
    }

    static func attachCurrentUserAttendee(
        to event: EKEvent,
        eventStore: EKEventStore,
        status: EKParticipantStatus = .pending
    ) {
        withLock {
            installSwizzlesIfNeededLocked()
            let attendee = makeCurrentUserAttendeeLocked(eventStore: eventStore, status: status)
            objc_setAssociatedObject(
                event,
                &associatedAttendeesKey,
                [attendee],
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }

    private static func makeCurrentUserAttendeeLocked(
        eventStore: EKEventStore,
        status: EKParticipantStatus
    ) -> EKParticipant {
        let participantClass: AnyClass = mockParticipantClassInstance()
        guard
            let allocated = (participantClass as AnyObject).perform(NSSelectorFromString("alloc"))?
            .takeUnretainedValue(),
            let participant = allocated as? EKParticipant
        else {
            fatalError("Failed to allocate mock EKParticipant")
        }

        participantStatuses[ObjectIdentifier(participant)] = status.rawValue
        participant.setValue(UUID().uuidString, forKey: "UUID")
        participant.setValue("mock-current-user@test.apple-bridge", forKey: "emailAddress")
        participant.setValue(eventStore, forKey: "owner")
        participant.setValue(URL(string: "mailto:mock-current-user@test.apple-bridge"), forKey: "URL")
        return participant
    }

    static func setParticipantStatus(_ status: EKParticipantStatus, on participant: EKParticipant) {
        withLock {
            participantStatuses[ObjectIdentifier(participant)] = status.rawValue
        }
    }

    static func currentUserAttendee(on event: EKEvent) -> EKParticipant? {
        event.attendees?.first(where: { $0.isCurrentUser })
    }

    private static func mockParticipantClassInstance() -> AnyClass {
        if let mockParticipantClass {
            return mockParticipantClass
        }

        let className = "AppleBridgeMockEKParticipant"
        if let existing = NSClassFromString(className) {
            mockParticipantClass = existing
            return existing
        }

        guard let dynamicClass = objc_allocateClassPair(EKParticipant.self, className, 0) else {
            fatalError("Failed to allocate mock EKParticipant class")
        }

        let isCurrentUserBlock: @convention(block) (AnyObject) -> Bool = { _ in true }
        class_addMethod(
            dynamicClass,
            #selector(getter: EKParticipant.isCurrentUser),
            imp_implementationWithBlock(isCurrentUserBlock),
            "B@:"
        )

        guard
            let statusMethod = class_getInstanceMethod(
                EKParticipant.self,
                #selector(getter: EKParticipant.participantStatus)
            ),
            let statusTypeEncoding = method_getTypeEncoding(statusMethod)
        else {
            fatalError("Failed to read EKParticipant.participantStatus method encoding")
        }

        let statusBlock: @convention(block) (AnyObject) -> Int = { participant in
            stateLock.lock()
            defer { stateLock.unlock() }
            return participantStatuses[ObjectIdentifier(participant)] ?? EKParticipantStatus.unknown.rawValue
        }
        class_addMethod(
            dynamicClass,
            #selector(getter: EKParticipant.participantStatus),
            imp_implementationWithBlock(statusBlock),
            statusTypeEncoding
        )

        objc_registerClassPair(dynamicClass)
        mockParticipantClass = dynamicClass
        return dynamicClass
    }
}
