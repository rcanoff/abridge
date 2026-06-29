@testable import AppleBridge
import Contacts
import Foundation
import Testing

@Suite("ContactsSerialization")
struct ContactsSerializationTests {
    private static let expectedScalarKeys: Set<String> = [
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
    ]

    private static let expectedCollectionKeys: Set<String> = [
        "phone_numbers",
        "email_addresses",
        "postal_addresses",
        "url_addresses",
        "contact_relations",
        "social_profiles",
        "instant_message_addresses",
        "dates",
    ]

    private static let dateComponentsReadKeys: Set<String> = [
        "era",
        "year",
        "month",
        "day",
        "hour",
        "minute",
        "second",
        "nanosecond",
        "weekday",
        "weekday_ordinal",
        "quarter",
        "week_of_month",
        "week_of_year",
        "year_for_week_of_year",
        "is_leap_month",
        "time_zone",
        "calendar",
    ]

    @Test
    func contactJSONObjectIncludesAllExpectedKeys() {
        let contact = ContactsTestSupport.makeRichContact()
        let json = ContactsSerialization.contactJSONObject(from: contact)

        for key in Self.expectedScalarKeys.union(Self.expectedCollectionKeys) {
            #expect(json[key] != nil, "Missing key: \(key)")
        }
    }

    @Test
    func contactJSONObjectUsesSnakeCaseKeysAndFaithfulValues() {
        let contact = ContactsTestSupport.makeRichContact()
        let json = ContactsSerialization.contactJSONObject(from: contact)

        #expect((json["identifier"] as? String)?.isEmpty == false)
        #expect(json["contact_type"] as? String == "person")
        #expect(json["given_name"] as? String == "Jane")
        #expect(json["family_name"] as? String == "Doe")
        #expect(json["organization_name"] as? String == "Acme")
        #expect(json["image_data_available"] as? Bool == false)

        let phoneNumbers = json["phone_numbers"] as? [[String: Any]]
        #expect(phoneNumbers?.count == 1)
        #expect(phoneNumbers?.first?["label"] != nil)
        #expect(phoneNumbers?.first?["identifier"] != nil)
        let phoneValue = phoneNumbers?.first?["value"] as? [String: Any]
        #expect(phoneValue?["string_value"] as? String == "+1-555-0100")

        let emails = json["email_addresses"] as? [[String: Any]]
        #expect(emails?.first?["value"] as? String == "jane@example.com")

        let postal = json["postal_addresses"] as? [[String: Any]]
        let postalValue = postal?.first?["value"] as? [String: Any]
        #expect(postalValue?["street"] as? String == "1 Infinite Loop")
        #expect(postalValue?["city"] as? String == "Cupertino")
    }

    @Test
    func contactJSONObjectEncodesNilOptionalsAsJSONNull() throws {
        let contact = CNMutableContact()
        contact.givenName = "Solo"
        let json = ContactsSerialization.contactJSONObject(from: contact)

        #expect(json["family_name"] as? String == "")
        #expect(json["image_data"] is NSNull)
        #expect(json["birthday"] is NSNull)
        #expect((json["phone_numbers"] as? [Any])?.isEmpty == true)

        let payload = try ContactsSerialization.jsonString(from: [json])
        #expect(payload.contains("null"))
    }

    @Test
    func dateComponentsJSONObjectIncludesAllRequiredKeys() {
        let contact = CNMutableContact()
        contact.givenName = "Era"
        contact.birthday = DateComponents(year: 2026, month: 6, day: 28)

        let json = ContactsSerialization.contactJSONObject(from: contact)
        guard let dateComponents = json["birthday"] as? [String: Any] else {
            Issue.record("Expected birthday date components object")
            return
        }

        #expect(Set(dateComponents.keys) == Self.dateComponentsReadKeys)
    }

    @Test
    func dateComponentsJSONObjectSerializesEraFaithfully() {
        let contact = CNMutableContact()
        contact.givenName = "Era"
        var components = DateComponents()
        components.era = 1
        components.year = 2026
        components.month = 6
        components.day = 28
        contact.birthday = components

        let json = ContactsSerialization.contactJSONObject(from: contact)
        guard let dateComponents = json["birthday"] as? [String: Any] else {
            Issue.record("Expected birthday date components object")
            return
        }

        #expect(dateComponents["era"] as? Int == 1)
    }

    @Test
    func contactJSONObjectEncodesImageDataAsBase64() {
        let contact = CNMutableContact()
        let imageBytes = Data([0x01, 0x02, 0x03])
        contact.imageData = imageBytes
        let json = ContactsSerialization.contactJSONObject(from: contact)

        #expect(json["image_data_available"] as? Bool == true)
        #expect(json["image_data"] as? String == imageBytes.base64EncodedString())
    }
}

enum ContactsTestSupport {
    static func makeRichContact() -> CNContact {
        let contact = CNMutableContact()
        applyScalarFields(to: contact)
        applyLabeledCollections(to: contact)
        contact.birthday = DateComponents(month: 3, day: 14)
        return contact
    }

    private static func applyScalarFields(to contact: CNMutableContact) {
        contact.givenName = "Jane"
        contact.familyName = "Doe"
        contact.middleName = "Q"
        contact.namePrefix = "Dr"
        contact.nameSuffix = "Jr"
        contact.nickname = "Janey"
        contact.organizationName = "Acme"
        contact.departmentName = "R&D"
        contact.jobTitle = "Engineer"
        contact.phoneticGivenName = "JAYN"
        contact.phoneticMiddleName = "KYOO"
        contact.phoneticFamilyName = "DOH"
        contact.phoneticOrganizationName = "AKMEE"
        contact.previousFamilyName = "Smith"
        contact.note = "VIP"
    }

    private static func applyLabeledCollections(to contact: CNMutableContact) {
        contact.phoneNumbers = [
            CNLabeledValue(
                label: CNLabelHome,
                value: CNPhoneNumber(stringValue: "+1-555-0100")
            ),
        ]
        contact.emailAddresses = [
            CNLabeledValue(label: CNLabelWork, value: "jane@example.com" as NSString),
        ]

        let postal = CNMutablePostalAddress()
        postal.street = "1 Infinite Loop"
        postal.city = "Cupertino"
        postal.state = "CA"
        postal.postalCode = "95014"
        postal.country = "United States"
        postal.isoCountryCode = "us"
        contact.postalAddresses = [
            CNLabeledValue(label: CNLabelHome, value: postal),
        ]
        contact.urlAddresses = [
            CNLabeledValue(label: CNLabelURLAddressHomePage, value: "https://example.com" as NSString),
        ]
        contact.contactRelations = [
            CNLabeledValue(label: CNLabelContactRelationSpouse, value: CNContactRelation(name: "John")),
        ]
        contact.socialProfiles = [
            CNLabeledValue(
                label: "Twitter",
                value: CNSocialProfile(
                    urlString: "https://x.com/jane",
                    username: "jane",
                    userIdentifier: "123",
                    service: "Twitter"
                )
            ),
        ]
        contact.instantMessageAddresses = [
            CNLabeledValue(
                label: "AIM",
                value: CNInstantMessageAddress(username: "jane", service: "AIM")
            ),
        ]
        contact.dates = [
            CNLabeledValue(
                label: CNLabelDateAnniversary,
                value: DateComponents(year: 2020, month: 6, day: 15) as NSDateComponents
            ),
        ]
    }
}
