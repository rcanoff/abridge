@testable import AppleBridge
import Contacts
import Foundation
import Testing

@Suite("ContactsDeserialization")
struct ContactsDeserializationTests {
    @Test
    func mutableContactRoundTripsRichContactScalars() throws {
        let original = ContactsTestSupport.makeRichContact()
        let json = ContactsSerialization.contactJSONObject(from: original)
        var writableJSON = json
        writableJSON.removeValue(forKey: "identifier")
        writableJSON.removeValue(forKey: "image_data_available")

        let deserialized = try ContactsDeserialization.mutableContact(from: writableJSON)

        #expect(deserialized.givenName == "Jane")
        #expect(deserialized.familyName == "Doe")
        #expect(deserialized.organizationName == "Acme")
        #expect(deserialized.note == "VIP")
        #expect(deserialized.contactType == .person)
    }

    @Test
    func mutableContactRoundTripsLabeledCollections() throws {
        let original = ContactsTestSupport.makeRichContact()
        let json = ContactsSerialization.contactJSONObject(from: original)
        var writableJSON = json
        writableJSON.removeValue(forKey: "identifier")
        writableJSON.removeValue(forKey: "image_data_available")

        let deserialized = try ContactsDeserialization.mutableContact(from: writableJSON)

        #expect(deserialized.phoneNumbers.count == 1)
        #expect(deserialized.phoneNumbers.first?.value.stringValue == "+1-555-0100")
        #expect(deserialized.emailAddresses.first?.value as? String == "jane@example.com")
        #expect(deserialized.postalAddresses.first?.value.street == "1 Infinite Loop")
        #expect(deserialized.contactRelations.first?.value.name == "John")
        #expect(deserialized.socialProfiles.first?.value.username == "jane")
        #expect(deserialized.instantMessageAddresses.first?.value.username == "jane")
        #expect(deserialized.dates.count == 1)
    }

    @Test
    func mutableContactDecodesBase64ImageData() throws {
        let imageBytes = Data([0x01, 0x02, 0x03])
        let json: [String: Any] = [
            "given_name": "Image",
            "image_data": imageBytes.base64EncodedString(),
        ]

        let contact = try ContactsDeserialization.mutableContact(from: json)

        #expect(contact.imageData == imageBytes)
    }

    @Test
    func mutableContactDecodesDateComponentsWithEra() throws {
        let json: [String: Any] = [
            "given_name": "Era",
            "birthday": [
                "era": 1,
                "year": 2026,
                "month": 6,
                "day": 28,
                "hour": NSNull(),
                "minute": NSNull(),
                "second": NSNull(),
                "nanosecond": NSNull(),
                "weekday": NSNull(),
                "weekday_ordinal": NSNull(),
                "quarter": NSNull(),
                "week_of_month": NSNull(),
                "week_of_year": NSNull(),
                "year_for_week_of_year": NSNull(),
                "is_leap_month": NSNull(),
                "time_zone": NSNull(),
                "calendar": NSNull(),
            ],
        ]

        let contact = try ContactsDeserialization.mutableContact(from: json)

        #expect(contact.birthday?.era == 1)
        #expect(contact.birthday?.year == 2026)
        #expect(contact.birthday?.month == 6)
        #expect(contact.birthday?.day == 28)
    }

    @Test
    func mutableContactRejectsInvalidContactType() {
        let json: [String: Any] = [
            "given_name": "Bad",
            "contact_type": "invalid",
        ]

        #expect(throws: ContactsProviderError.self) {
            _ = try ContactsDeserialization.mutableContact(from: json)
        }
    }

    @Test
    func mutableContactRejectsInvalidPhoneNumbersShape() {
        let json: [String: Any] = [
            "given_name": "Bad",
            "phone_numbers": "not-an-array",
        ]

        #expect(throws: ContactsProviderError.self) {
            _ = try ContactsDeserialization.mutableContact(from: json)
        }
    }

    @Test
    func mutableContactRejectsInvalidBase64ImageData() {
        let json: [String: Any] = [
            "given_name": "Bad",
            "image_data": "%%%",
        ]

        #expect(throws: ContactsProviderError.self) {
            _ = try ContactsDeserialization.mutableContact(from: json)
        }
    }
}