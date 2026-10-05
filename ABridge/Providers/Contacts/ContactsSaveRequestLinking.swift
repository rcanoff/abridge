@preconcurrency import Contacts
import Foundation

protocol ContactsLinkingPerforming: Sendable {
    func link(
        from contact: CNMutableContact,
        to unifiedContact: CNMutableContact,
        in saveRequest: CNSaveRequest
    ) throws
}

struct LiveContactsLinkingPerformer: ContactsLinkingPerforming {
    func link(
        from contact: CNMutableContact,
        to unifiedContact: CNMutableContact,
        in saveRequest: CNSaveRequest
    ) throws {
        try ContactsSaveRequestLinking.link(from: contact, to: unifiedContact, in: saveRequest)
    }
}

enum ContactsSaveRequestLinking {
    static var isAvailable: Bool {
        ABContactLinkingIsAvailable()
    }

    static func link(
        from contact: CNMutableContact,
        to unifiedContact: CNMutableContact,
        in saveRequest: CNSaveRequest
    ) throws {
        guard isAvailable else {
            throw ContactsProviderError.linkingUnavailable
        }

        ABLinkContactToContact(saveRequest, contact, unifiedContact)
    }
}
