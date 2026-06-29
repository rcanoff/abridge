@testable import AppleBridge
import Contacts
import Foundation
import Testing

@Suite("ContactsProviderCreateContact")
struct ContactsProviderCreateContactTests {
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
    func createContactReturnsFaithfulPayload() throws {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .authorized
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "create_contact",
            payloadJson: #"{"container_identifier":"container-1","given_name":"Jane","family_name":"Doe"}"#
        )

        #expect(response.ok == true)

        let data = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let contact = try #require(decoded)

        #expect(Set(contact.keys) == Self.contactReadKeys)
        #expect((contact["identifier"] as? String)?.isEmpty == false)
        #expect(contact["given_name"] as? String == "Jane")
        #expect(contact["family_name"] as? String == "Doe")
    }

    @Test
    @MainActor
    func createContactAppliesOptionalFields() throws {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .authorized
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "create_contact",
            payloadJson: #"""
            {
              "container_identifier": "container-1",
              "organization_name": "Acme",
              "job_title": "Engineer",
              "phone_numbers": [
                {
                  "label": "home",
                  "value": { "string_value": "+1-555-0100" }
                }
              ]
            }
            """#
        )

        #expect(response.ok == true)
        #expect(response.payloadJson.contains("Acme"))
        #expect(response.payloadJson.contains("Engineer"))
        #expect(response.payloadJson.contains("+1-555-0100"))
    }

    @Test
    @MainActor
    func createContactMissingContainerIdentifierReturnsInvalidArguments() {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .authorized
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "create_contact",
            payloadJson: #"{"given_name":"Jane"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("container_identifier is required") == true)
    }

    @Test
    @MainActor
    func createContactMissingNameReturnsInvalidArguments() {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .authorized
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "create_contact",
            payloadJson: #"{"container_identifier":"container-1"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(
            response.errorJson?.contains(
                "At least one of given_name, family_name, or organization_name is required"
            ) == true
        )
    }

    @Test
    @MainActor
    func createContactWhitespaceOnlyNameReturnsInvalidArguments() {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .authorized
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "create_contact",
            payloadJson: #"{"container_identifier":"container-1","given_name":"   "}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
    }

    @Test
    @MainActor
    func createContactUnknownContainerReturnsInvalidArguments() {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .authorized
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "create_contact",
            payloadJson: #"{"container_identifier":"missing","given_name":"Jane"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("Unknown container_identifier") == true)
    }

    @Test
    @MainActor
    func createContactPermissionDeniedWhenUnauthorized() {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .denied
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "create_contact",
            payloadJson: #"{"container_identifier":"container-1","given_name":"Jane"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
    }

    @Test
    @MainActor
    func createContactPermissionDeniedWithLimitedAuthorization() throws {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = try #require(CNAuthorizationStatus(rawValue: 4))
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "create_contact",
            payloadJson: #"{"container_identifier":"container-1","given_name":"Jane"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
    }

    @Test
    @MainActor
    func createContactAcceptsOrganizationNameOnly() throws {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .authorized
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "create_contact",
            payloadJson: #"{"container_identifier":"container-1","organization_name":"Acme Corp"}"#
        )

        #expect(response.ok == true)
        #expect(response.payloadJson.contains("Acme Corp"))
    }
}