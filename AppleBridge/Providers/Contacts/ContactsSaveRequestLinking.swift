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
        ABCNSaveRequestContactLinkingIsAvailable()
    }

    static func link(
        from contact: CNMutableContact,
        to unifiedContact: CNMutableContact,
        in saveRequest: CNSaveRequest
    ) throws {
        guard isAvailable else {
            throw ContactsProviderError.linkingUnavailable
        }

        let success = saveRequest.ab_linkContact(contact, to: unifiedContact)
        guard success else {
            throw ContactsProviderError.contactsError("Contacts framework rejected the link request")
        }
    }
}
