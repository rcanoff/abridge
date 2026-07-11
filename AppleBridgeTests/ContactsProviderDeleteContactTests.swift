@testable import AppleBridge
import Contacts
import Foundation
import Testing

@Suite("ContactsProviderDeleteContact")
struct ContactsProviderDeleteContactTests {
    @Test
    @MainActor
    func deleteContactReturnsIdentifierEnvelope() {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .authorized
        let contact = ContactsTestSupport.makeRichContact()
        mockStore.contacts = [contact]
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "delete_contact",
            payloadJson: #"{"contact_identifier":"\#(contact.identifier)"}"#
        )

        #expect(response.ok == true)
        #expect(response.payloadJson.contains("\"contact_identifier\":\"\(contact.identifier)\""))
        #expect(!response.payloadJson.contains("\"given_name\""))
        #expect(mockStore.contacts.isEmpty)
    }

    @Test
    @MainActor
    func deleteContactUnknownContactIdentifierReturnsInvalidArguments() {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .authorized
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "delete_contact",
            payloadJson: #"{"contact_identifier":"missing"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("Unknown contact_identifier") == true)
    }

    @Test
    @MainActor
    func deleteContactMissingContactIdentifierReturnsInvalidArguments_schemaOwnedByRust() {
        #expect(SchemaTrustedPayload.requiredString([:], "x") == "")
    }

    @Test
    @MainActor
    func deleteContactPermissionDeniedWhenUnauthorized() {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .denied
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "delete_contact",
            payloadJson: #"{"contact_identifier":"contact-1"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
        #expect(response.errorJson?.contains("Contacts write access not granted") == true)
    }

    @Test
    @MainActor
    func deleteContactPermissionDeniedWithLimitedAuthorization() throws {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = try #require(CNAuthorizationStatus(rawValue: 4))
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "delete_contact",
            payloadJson: #"{"contact_identifier":"contact-1"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
    }
}
