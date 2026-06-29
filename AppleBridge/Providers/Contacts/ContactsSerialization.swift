@preconcurrency import Contacts
import Foundation

enum ContactsSerialization {
    static func contactJSONObject(from contact: CNContact) -> [String: Any] {
        [
            "identifier": contact.identifier,
            "contact_type": contactTypeString(contact.contactType),
            "given_name": contact.givenName,
            "family_name": contact.familyName,
            "middle_name": contact.middleName,
            "name_prefix": contact.namePrefix,
            "name_suffix": contact.nameSuffix,
            "nickname": contact.nickname,
            "organization_name": contact.organizationName,
            "department_name": contact.departmentName,
            "job_title": contact.jobTitle,
            "phonetic_given_name": contact.phoneticGivenName,
            "phonetic_middle_name": contact.phoneticMiddleName,
            "phonetic_family_name": contact.phoneticFamilyName,
            "phonetic_organization_name": contact.phoneticOrganizationName,
            "previous_family_name": contact.previousFamilyName,
            "note": contact.note,
            "image_data_available": contact.imageDataAvailable,
            "image_data": base64String(from: contact.imageData),
            "thumbnail_image_data": base64String(from: contact.thumbnailImageData),
            "birthday": dateComponentsJSONObject(from: contact.birthday),
            "non_gregorian_birthday": dateComponentsJSONObject(from: contact.nonGregorianBirthday),
            "phone_numbers": labeledValueArrayJSONObject(from: contact.phoneNumbers, map: phoneNumberJSONObject),
            "email_addresses": labeledValueArrayJSONObject(
                from: contact.emailAddresses,
                map: { jsonValueString($0 as String) }
            ),
            "postal_addresses": labeledValueArrayJSONObject(
                from: contact.postalAddresses,
                map: postalAddressJSONObject
            ),
            "url_addresses": labeledValueArrayJSONObject(
                from: contact.urlAddresses,
                map: { jsonValueString($0 as String) }
            ),
            "contact_relations": labeledValueArrayJSONObject(
                from: contact.contactRelations,
                map: contactRelationJSONObject
            ),
            "social_profiles": labeledValueArrayJSONObject(from: contact.socialProfiles, map: socialProfileJSONObject),
            "instant_message_addresses": labeledValueArrayJSONObject(
                from: contact.instantMessageAddresses,
                map: instantMessageAddressJSONObject
            ),
            "dates": labeledValueArrayJSONObject(
                from: contact.dates,
                map: { dateComponentsJSONObject(from: $0 as DateComponents) }
            ),
        ]
    }

    static func jsonString(from object: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object)
        guard let string = String(data: data, encoding: .utf8) else {
            throw ContactsProviderError.serializationFailed
        }
        return string
    }

    // MARK: - Nested types

    private static func phoneNumberJSONObject(from phoneNumber: CNPhoneNumber) -> [String: Any] {
        [
            "string_value": phoneNumber.stringValue,
        ]
    }

    private static func postalAddressJSONObject(from address: CNPostalAddress) -> [String: Any] {
        [
            "street": address.street,
            "sub_locality": address.subLocality,
            "city": address.city,
            "sub_administrative_area": address.subAdministrativeArea,
            "state": address.state,
            "postal_code": address.postalCode,
            "country": address.country,
            "iso_country_code": address.isoCountryCode,
        ]
    }

    private static func contactRelationJSONObject(from relation: CNContactRelation) -> [String: Any] {
        [
            "name": relation.name,
        ]
    }

    private static func socialProfileJSONObject(from profile: CNSocialProfile) -> [String: Any] {
        [
            "url_string": profile.urlString,
            "username": profile.username,
            "user_identifier": profile.userIdentifier,
            "service": profile.service,
        ]
    }

    private static func instantMessageAddressJSONObject(from address: CNInstantMessageAddress) -> [String: Any] {
        [
            "username": address.username,
            "service": address.service,
        ]
    }

    private static func labeledValueArrayJSONObject<Value>(
        from values: [CNLabeledValue<Value>],
        map: (Value) -> Any
    ) -> [[String: Any]] {
        values.map { labeledValueJSONObject(from: $0, map: map) }
    }

    private static func labeledValueJSONObject<Value>(
        from labeledValue: CNLabeledValue<Value>,
        map: (Value) -> Any
    ) -> [String: Any] {
        [
            "label": jsonValue(labeledValue.label),
            "identifier": labeledValue.identifier,
            "value": map(labeledValue.value),
        ]
    }

    private static func dateComponentsJSONObject(from components: DateComponents?) -> Any {
        guard let components else { return NSNull() }

        var payload: [String: Any] = [
            "year": jsonValue(components.year),
            "month": jsonValue(components.month),
            "day": jsonValue(components.day),
            "hour": jsonValue(components.hour),
            "minute": jsonValue(components.minute),
            "second": jsonValue(components.second),
            "nanosecond": jsonValue(components.nanosecond),
            "weekday": jsonValue(components.weekday),
            "weekday_ordinal": jsonValue(components.weekdayOrdinal),
            "quarter": jsonValue(components.quarter),
            "week_of_month": jsonValue(components.weekOfMonth),
            "week_of_year": jsonValue(components.weekOfYear),
            "year_for_week_of_year": jsonValue(components.yearForWeekOfYear),
            "is_leap_month": jsonValue(components.isLeapMonth),
            "time_zone": jsonValue(components.timeZone?.identifier),
        ]

        if let calendar = components.calendar {
            payload["calendar"] = foundationCalendarJSONObject(from: calendar)
        } else {
            payload["calendar"] = NSNull()
        }

        return payload
    }

    private static func foundationCalendarJSONObject(from calendar: Calendar) -> [String: Any] {
        [
            "identifier": EventKitSerialization.calendarIdentifierString(calendar.identifier),
            "locale": jsonValue(calendar.locale?.identifier),
            "time_zone": calendar.timeZone.identifier,
            "first_weekday": calendar.firstWeekday,
            "minimum_days_in_first_week": calendar.minimumDaysInFirstWeek,
        ]
    }

    // MARK: - Encoding helpers

    private static func jsonValue(_ string: String?) -> Any {
        string ?? NSNull()
    }

    private static func jsonValueString(_ string: String) -> Any {
        string
    }

    private static func jsonValue(_ number: Int?) -> Any {
        number ?? NSNull()
    }

    private static func jsonValue(_ number: Bool?) -> Any {
        number ?? NSNull()
    }

    private static func base64String(from data: Data?) -> Any {
        guard let data else { return NSNull() }
        return data.base64EncodedString()
    }

    private static func contactTypeString(_ type: CNContactType) -> String {
        switch type {
        case .person:
            "person"
        case .organization:
            "organization"
        @unknown default:
            "unknown"
        }
    }
}
