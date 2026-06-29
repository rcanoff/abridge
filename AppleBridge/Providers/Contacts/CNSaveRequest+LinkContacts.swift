@preconcurrency import Contacts
import Foundation

extension CNSaveRequest {
    /// Links one contact to a unified destination contact using Contacts framework SPI.
    func link(_ contact: CNMutableContact, to unifiedContact: CNMutableContact) {
        let selector = Selector(("linkContact:toContact:"))
        _ = perform(selector, with: contact, with: unifiedContact)
    }
}
