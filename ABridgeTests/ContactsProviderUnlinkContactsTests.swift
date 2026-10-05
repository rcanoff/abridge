@testable import ABridge
import Contacts
import Foundation
import Testing

@Suite("ContactsProviderUnlinkContacts")
struct ContactsProviderUnlinkContactsTests {
    private static let contactReadKeys: Set<String> = [
        "identifier",
        "contact_type",
        "given_name",
        "family_name",
        "middle_name",
        "name_prefix",
        "name_suffix",
        "nickname",
        "organization_name",
        "department_name",
        "job_title",
        "phonetic_given_name",
        "phonetic_middle_name",
        "phonetic_family_name",
        "phonetic_organization_name",
        "previous_family_name",
        "note",
        "image_data_available",
        "image_data",
        "thumbnail_image_data",
        "birthday",
        "non_gregorian_birthday",
        "phone_numbers",
        "email_addresses",
        "postal_addresses",
        "url_addresses",
        "contact_relations",
        "social_profiles",
        "instant_message_addresses",
        "dates",
    ]

    @Test
    @MainActor
    func unlinkContactsReturnsFaithfulPayload() throws {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .authorized
        let contact = ContactsTestSupport.makeRichContact()
        mockStore.contacts = [contact]
        let provider = ContactsProvider(store: mockStore)

        let payloadJson = #"{"contact_identifier":"\#(contact.identifier)"}"#
        let response = provider.handle(operation: "unlink_contacts", payloadJson: payloadJson)

        #expect(response.ok == true)

        let data = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let unlinked = try #require(decoded)

        #expect(Set(unlinked.keys) == Self.contactReadKeys)
        #expect(unlinked["identifier"] as? String == contact.identifier)
        #expect(mockStore.contacts.count == 1)
    }

    @Test
    @MainActor
    func unlinkContactsUnknownIdentifierReturnsInvalidArguments() {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .authorized
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "unlink_contacts",
            payloadJson: #"{"contact_identifier":"missing"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("Unknown contact_identifier") == true)
    }

    @Test
    @MainActor
    func unlinkContactsPermissionDeniedWhenUnauthorized() {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .denied
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "unlink_contacts",
            payloadJson: #"{"contact_identifier":"contact-42"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
        #expect(response.errorJson?.contains("Contacts write access not granted") == true)
    }

    @Test
    @MainActor
    func unlinkContactsUnlinkingUnavailableReturnsContactsError() {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .authorized
        mockStore.unlinkingUnavailable = true
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "unlink_contacts",
            payloadJson: #"{"contact_identifier":"contact-42"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("contacts_error") == true)
        #expect(response.errorJson?.contains("no public Contacts framework unlink API") == true)
    }

    @Test
    @MainActor
    func unlinkContactsPermissionDeniedWithLimitedAuthorization() throws {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = try #require(CNAuthorizationStatus(rawValue: 4))
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "unlink_contacts",
            payloadJson: #"{"contact_identifier":"contact-42"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
    }
}
