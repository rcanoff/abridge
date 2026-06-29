@testable import AppleBridge
import Contacts
import Foundation
import Testing

@Suite("ContactsProviderLinkContacts")
struct ContactsProviderLinkContactsTests {
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
    func linkContactsReturnsFaithfulPayload() throws {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .authorized
        let fromContact = ContactsTestSupport.makeRichContact()
        let toMutable = try #require(
            ContactsTestSupport.makeRichContact().mutableCopy() as? CNMutableContact
        )
        toMutable.givenName = "Destination"
        let toContact = toMutable as CNContact
        mockStore.contacts = [fromContact, toContact]
        let provider = ContactsProvider(store: mockStore)

        let payloadJson = #"{"from_contact_identifier":"\#(fromContact.identifier)","#
            + #""to_contact_identifier":"\#(toContact.identifier)"}"#
        let response = provider.handle(operation: "link_contacts", payloadJson: payloadJson)

        #expect(response.ok == true)

        let data = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let linked = try #require(decoded)

        #expect(Set(linked.keys) == Self.contactReadKeys)
        #expect(linked["identifier"] as? String == toContact.identifier)
        #expect(linked["given_name"] as? String == "Destination")
        #expect(mockStore.contacts.count == 1)
    }

    @Test
    @MainActor
    func linkContactsUnknownFromIdentifierReturnsInvalidArguments() {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .authorized
        let toContact = ContactsTestSupport.makeRichContact()
        mockStore.contacts = [toContact]
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "link_contacts",
            payloadJson: #"{"from_contact_identifier":"missing","to_contact_identifier":"\#(toContact.identifier)"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("Unknown from_contact_identifier") == true)
    }

    @Test
    @MainActor
    func linkContactsUnknownToIdentifierReturnsInvalidArguments() {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .authorized
        let fromContact = ContactsTestSupport.makeRichContact()
        mockStore.contacts = [fromContact]
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "link_contacts",
            payloadJson: #"{"from_contact_identifier":"\#(fromContact.identifier)","to_contact_identifier":"missing"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("Unknown to_contact_identifier") == true)
    }

    @Test
    @MainActor
    func linkContactsMissingFromIdentifierReturnsInvalidArguments() {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .authorized
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "link_contacts",
            payloadJson: #"{"to_contact_identifier":"contact-to"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("from_contact_identifier is required") == true)
    }

    @Test
    @MainActor
    func linkContactsMissingToIdentifierReturnsInvalidArguments() {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .authorized
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "link_contacts",
            payloadJson: #"{"from_contact_identifier":"contact-from"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("to_contact_identifier is required") == true)
    }

    @Test
    @MainActor
    func linkContactsEmptyFromIdentifierReturnsInvalidArguments() {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .authorized
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "link_contacts",
            payloadJson: #"{"from_contact_identifier":"   ","to_contact_identifier":"contact-to"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("from_contact_identifier must not be empty") == true)
    }

    @Test
    @MainActor
    func linkContactsSameIdentifierReturnsInvalidArguments() {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .authorized
        let contact = ContactsTestSupport.makeRichContact()
        mockStore.contacts = [contact]
        let provider = ContactsProvider(store: mockStore)

        let payloadJson = #"{"from_contact_identifier":"\#(contact.identifier)","#
            + #""to_contact_identifier":"\#(contact.identifier)"}"#
        let response = provider.handle(operation: "link_contacts", payloadJson: payloadJson)

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("must differ") == true)
    }

    @Test
    @MainActor
    func linkContactsPermissionDeniedWhenUnauthorized() {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .denied
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "link_contacts",
            payloadJson: #"{"from_contact_identifier":"contact-from","to_contact_identifier":"contact-to"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
        #expect(response.errorJson?.contains("Contacts write access not granted") == true)
    }

    @Test
    @MainActor
    func linkContactsPermissionDeniedWithLimitedAuthorization() throws {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = try #require(CNAuthorizationStatus(rawValue: 4))
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "link_contacts",
            payloadJson: #"{"from_contact_identifier":"contact-from","to_contact_identifier":"contact-to"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
    }
}
