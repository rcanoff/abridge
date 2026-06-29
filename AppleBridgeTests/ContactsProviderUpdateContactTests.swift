@testable import AppleBridge
import Contacts
import Foundation
import Testing

@Suite("ContactsProviderUpdateContact")
struct ContactsProviderUpdateContactTests {
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
    func updateContactReturnsFaithfulPayload() throws {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .authorized
        let contact = ContactsTestSupport.makeRichContact()
        mockStore.contacts = [contact]
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "update_contact",
            payloadJson: #"{"contact_identifier":"\#(contact.identifier)","given_name":"Janet"}"#
        )

        #expect(response.ok == true)

        let data = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let updated = try #require(decoded)

        #expect(Set(updated.keys) == Self.contactReadKeys)
        #expect(updated["identifier"] as? String == contact.identifier)
        #expect(updated["given_name"] as? String == "Janet")
        #expect(updated["family_name"] as? String == "Doe")
    }

    @Test
    @MainActor
    func updateContactClearsNullableFieldWithNull() throws {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .authorized
        let contact = ContactsTestSupport.makeRichContact()
        mockStore.contacts = [contact]
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "update_contact",
            payloadJson: #"{"contact_identifier":"\#(contact.identifier)","note":null}"#
        )

        #expect(response.ok == true)

        let data = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let updated = try #require(decoded)

        #expect(updated["note"] as? String == "")
    }

    @Test
    @MainActor
    func updateContactLeavesAbsentFieldsUnchanged() throws {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .authorized
        let contact = ContactsTestSupport.makeRichContact()
        mockStore.contacts = [contact]
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "update_contact",
            payloadJson: #"{"contact_identifier":"\#(contact.identifier)","job_title":"Principal Engineer"}"#
        )

        #expect(response.ok == true)

        let data = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let updated = try #require(decoded)

        #expect(updated["job_title"] as? String == "Principal Engineer")
        #expect(updated["given_name"] as? String == "Jane")
        #expect(updated["note"] as? String == "VIP")
    }

    @Test
    @MainActor
    func updateContactMissingContactIdentifierReturnsInvalidArguments() {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .authorized
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "update_contact",
            payloadJson: #"{"given_name":"Jane"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("contact_identifier is required") == true)
    }

    @Test
    @MainActor
    func updateContactUnknownContactIdentifierReturnsInvalidArguments() {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .authorized
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "update_contact",
            payloadJson: #"{"contact_identifier":"missing","given_name":"Jane"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("Unknown contact_identifier") == true)
    }

    @Test
    @MainActor
    func updateContactPermissionDeniedWhenUnauthorized() {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .denied
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "update_contact",
            payloadJson: #"{"contact_identifier":"contact-1","given_name":"Jane"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
    }

    @Test
    @MainActor
    func updateContactPermissionDeniedWithLimitedAuthorization() throws {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = try #require(CNAuthorizationStatus(rawValue: 4))
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "update_contact",
            payloadJson: #"{"contact_identifier":"contact-1","given_name":"Jane"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
    }
}
