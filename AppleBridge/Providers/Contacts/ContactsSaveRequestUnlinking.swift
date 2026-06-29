@preconcurrency import Contacts
import Foundation

protocol ContactsUnlinkingPerforming: Sendable {
    func unlink(_ contact: CNMutableContact, in saveRequest: CNSaveRequest) throws
}

struct LiveContactsUnlinkingPerformer: ContactsUnlinkingPerforming {
    func unlink(_ contact: CNMutableContact, in saveRequest: CNSaveRequest) throws {
        try ContactsSaveRequestUnlinking.unlink(contact, in: saveRequest)
    }
}

enum ContactsSaveRequestUnlinking {
    static var isAvailable: Bool {
        ABContactUnlinkingIsAvailable()
    }

    static func unlink(_ contact: CNMutableContact, in saveRequest: CNSaveRequest) throws {
        guard isAvailable else {
            throw ContactsProviderError.unlinkingUnavailable
        }

        guard ABUnlinkContact(saveRequest, contact) else {
            throw ContactsProviderError.contactsError("Contacts framework rejected the unlink request")
        }
    }
}