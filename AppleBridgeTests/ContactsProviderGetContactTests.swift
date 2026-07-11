@testable import AppleBridge
import Contacts
import Foundation
import Testing

@Suite("ContactsProviderGetContact")
struct ContactsProviderGetContactTests {
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
    func getContactReturnsFaithfulContactShapeMatchingListContacts() throws {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .authorized
        let contact = ContactsTestSupport.makeRichContact()
        mockStore.contacts = [contact]
        let provider = ContactsProvider(store: mockStore)

        let getResponse = provider.handle(
            operation: "get_contact",
            payloadJson: #"{"contact_identifier":"\#(contact.identifier)"}"#
        )
        #expect(getResponse.ok == true)

        let listResponse = provider.handle(operation: "list_contacts", payloadJson: "{}")
        #expect(listResponse.ok == true)

        let getData = try #require(getResponse.payloadJson.data(using: .utf8))
        let getDecoded = try JSONSerialization.jsonObject(with: getData)
        let getContact = try #require(getDecoded as? [String: Any])

        let listData = try #require(listResponse.payloadJson.data(using: .utf8))
        let listDecoded = try JSONSerialization.jsonObject(with: listData) as? [[String: Any]]
        let listContact = try #require(listDecoded?.first)

        #expect(Set(getContact.keys) == Self.contactReadKeys)
        #expect(Set(getContact.keys) == Set(listContact.keys))
        #expect(getContact["identifier"] as? String == contact.identifier)
        #expect(getContact["given_name"] as? String == "Jane")
    }

    @Test
    @MainActor
    func getContactReturnsPermissionDeniedWhenUnauthorized() {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .denied
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "get_contact",
            payloadJson: #"{"contact_identifier":"contact-42"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
    }

    @Test
    @MainActor
    func getContactSucceedsWithLimitedAuthorization() throws {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = try #require(CNAuthorizationStatus(rawValue: 4))
        let contact = ContactsTestSupport.makeRichContact()
        mockStore.contacts = [contact]
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "get_contact",
            payloadJson: #"{"contact_identifier":"\#(contact.identifier)"}"#
        )

        #expect(response.ok == true)
        #expect(response.payloadJson.contains("Jane"))
    }

    @Test
    @MainActor
    func getContactMissingContactIdentifierReturnsInvalidArguments_schemaOwnedByRust() {
        #expect(SchemaTrustedPayload.requiredString([:], "x") == "")
    }

    @Test
    @MainActor
    func getContactUnknownContactIdentifierReturnsInvalidArguments() {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .authorized
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "get_contact",
            payloadJson: #"{"contact_identifier":"missing"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("Unknown contact_identifier") == true)
    }
}
