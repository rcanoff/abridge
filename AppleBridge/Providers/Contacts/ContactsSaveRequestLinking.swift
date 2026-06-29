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
    private static let linkSelector = Selector(("linkContact:toContact:"))

    static var isAvailable: Bool {
        CNSaveRequest.instancesRespond(to: linkSelector)
    }

    static func link(
        from contact: CNMutableContact,
        to unifiedContact: CNMutableContact,
        in saveRequest: CNSaveRequest
    ) throws {
        guard isAvailable, saveRequest.responds(to: linkSelector) else {
            throw ContactsProviderError.linkingUnavailable
        }

        guard let result = saveRequest.perform(linkSelector, with: contact, with: unifiedContact)?
            .takeUnretainedValue() as? NSNumber
        else {
            throw ContactsProviderError.contactsError("Contacts framework rejected the link request")
        }

        guard result.boolValue else {
            throw ContactsProviderError.contactsError("Contacts framework rejected the link request")
        }
    }
}
