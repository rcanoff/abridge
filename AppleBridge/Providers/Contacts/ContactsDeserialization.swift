@preconcurrency import Contacts
import Foundation

enum ContactsDeserialization {
    static func mutableContact(from dictionary: [String: Any]) throws -> CNMutableContact {
        let contact = CNMutableContact()
        try applyWritableFields(from: dictionary, to: contact)
        return contact
    }

    static func applyWritableFields(from dictionary: [String: Any], to contact: CNMutableContact) throws {
        if dictionary.keys.contains("contact_type") {
            contact.contactType = try contactType(from: dictionary["contact_type"])
        }

        try applyOptionalStringField("given_name", from: dictionary, to: contact, set: { contact.givenName = $0 })
        try applyOptionalStringField("family_name", from: dictionary, to: contact, set: { contact.familyName = $0 })
        try applyOptionalStringField("middle_name", from: dictionary, to: contact, set: { contact.middleName = $0 })
        try applyOptionalStringField("name_prefix", from: dictionary, to: contact, set: { contact.namePrefix = $0 })
        try applyOptionalStringField("name_suffix", from: dictionary, to: contact, set: { contact.nameSuffix = $0 })
        try applyOptionalStringField("nickname", from: dictionary, to: contact, set: { contact.nickname = $0 })
        try applyOptionalStringField(
            "organization_name",
            from: dictionary,
            to: contact,
            set: { contact.organizationName = $0 }
        )
        try applyOptionalStringField(
            "department_name",
            from: dictionary,
            to: contact,
            set: { contact.departmentName = $0 }
        )
        try applyOptionalStringField("job_title", from: dictionary, to: contact, set: { contact.jobTitle = $0 })
        try applyOptionalStringField(
            "phonetic_given_name",
            from: dictionary,
            to: contact,
            set: { contact.phoneticGivenName = $0 }
        )
        try applyOptionalStringField(
            "phonetic_middle_name",
            from: dictionary,
            to: contact,
            set: { contact.phoneticMiddleName = $0 }
        )
        try applyOptionalStringField(
            "phonetic_family_name",
            from: dictionary,
            to: contact,
            set: { contact.phoneticFamilyName = $0 }
        )
        try applyOptionalStringField(
            "phonetic_organization_name",
            from: dictionary,
            to: contact,
            set: { contact.phoneticOrganizationName = $0 }
        )
        try applyOptionalStringField(
            "previous_family_name",
            from: dictionary,
            to: contact,
            set: { contact.previousFamilyName = $0 }
        )
        try applyOptionalStringField("note", from: dictionary, to: contact, set: { contact.note = $0 })

        if dictionary.keys.contains("image_data") {
            contact.imageData = try optionalData(dictionary["image_data"])
        }
        if dictionary.keys.contains("thumbnail_image_data") {
            contact.thumbnailImageData = try optionalData(dictionary["thumbnail_image_data"])
        }
        if dictionary.keys.contains("birthday") {
            contact.birthday = try dateComponents(from: dictionary["birthday"])
        }
        if dictionary.keys.contains("non_gregorian_birthday") {
            contact.nonGregorianBirthday = try dateComponents(from: dictionary["non_gregorian_birthday"])
        }
        if dictionary.keys.contains("phone_numbers") {
            contact.phoneNumbers = try phoneNumbers(from: dictionary["phone_numbers"])
        }
        if dictionary.keys.contains("email_addresses") {
            contact.emailAddresses = try labeledStrings(from: dictionary["email_addresses"], field: "email_addresses")
        }
        if dictionary.keys.contains("postal_addresses") {
            contact.postalAddresses = try postalAddresses(from: dictionary["postal_addresses"])
        }
        if dictionary.keys.contains("url_addresses") {
            contact.urlAddresses = try labeledStrings(from: dictionary["url_addresses"], field: "url_addresses")
        }
        if dictionary.keys.contains("contact_relations") {
            contact.contactRelations = try contactRelations(from: dictionary["contact_relations"])
        }
        if dictionary.keys.contains("social_profiles") {
            contact.socialProfiles = try socialProfiles(from: dictionary["social_profiles"])
        }
        if dictionary.keys.contains("instant_message_addresses") {
            contact.instantMessageAddresses = try instantMessageAddresses(
                from: dictionary["instant_message_addresses"]
            )
        }
        if dictionary.keys.contains("dates") {
            contact.dates = try labeledDateComponents(from: dictionary["dates"])
        }
    }

    static func optionalString(_ value: Any?) throws -> String? {
        guard let value else { return nil }
        if value is NSNull { return nil }
        guard let string = value as? String else {
            throw ContactsProviderError.invalidArguments("Expected string or null")
        }
        return string
    }

    static func optionalInt(_ value: Any?) throws -> Int? {
        guard let value else { return nil }
        if value is NSNull { return nil }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                throw ContactsProviderError.invalidArguments("Expected integer or null")
            }
            guard isIntegralNumber(number) else {
                throw ContactsProviderError.invalidArguments("Expected integer or null")
            }
            return number.intValue
        }
        if value is Bool { throw ContactsProviderError.invalidArguments("Expected integer or null") }
        if let int = value as? Int { return int }
        throw ContactsProviderError.invalidArguments("Expected integer or null")
    }

    static func optionalBool(_ value: Any?) throws -> Bool? {
        guard let value else { return nil }
        if value is NSNull { return nil }
        guard let bool = value as? Bool else {
            throw ContactsProviderError.invalidArguments("Expected boolean or null")
        }
        return bool
    }

    static func dateComponents(from value: Any?) throws -> DateComponents? {
        guard let value else { return nil }
        if value is NSNull { return nil }
        guard let dictionary = value as? [String: Any] else {
            throw ContactsProviderError.invalidArguments("date components must be an object or null")
        }

        var components = DateComponents()
        components.era = try optionalInt(dictionary["era"])
        components.year = try optionalInt(dictionary["year"])
        components.month = try optionalInt(dictionary["month"])
        components.day = try optionalInt(dictionary["day"])
        components.hour = try optionalInt(dictionary["hour"])
        components.minute = try optionalInt(dictionary["minute"])
        components.second = try optionalInt(dictionary["second"])
        components.nanosecond = try optionalInt(dictionary["nanosecond"])
        components.weekday = try optionalInt(dictionary["weekday"])
        components.weekdayOrdinal = try optionalInt(dictionary["weekday_ordinal"])
        components.quarter = try optionalInt(dictionary["quarter"])
        components.weekOfMonth = try optionalInt(dictionary["week_of_month"])
        components.weekOfYear = try optionalInt(dictionary["week_of_year"])
        components.yearForWeekOfYear = try optionalInt(dictionary["year_for_week_of_year"])
        components.isLeapMonth = try optionalBool(dictionary["is_leap_month"])

        if let timeZoneValue = dictionary["time_zone"] {
            if timeZoneValue is NSNull {
                components.timeZone = nil
            } else if let identifier = timeZoneValue as? String {
                guard let timeZone = TimeZone(identifier: identifier) else {
                    throw ContactsProviderError.invalidArguments("time_zone must be a valid timezone identifier")
                }
                components.timeZone = timeZone
            } else {
                throw ContactsProviderError.invalidArguments("time_zone must be a string or null")
            }
        }

        if let calendarValue = dictionary["calendar"] {
            if calendarValue is NSNull {
                components.calendar = nil
            } else if let calendarDictionary = calendarValue as? [String: Any] {
                components.calendar = try foundationCalendar(from: calendarDictionary)
            } else {
                throw ContactsProviderError.invalidArguments("calendar must be an object or null")
            }
        }

        return components
    }

    // MARK: - Private helpers

    private static func applyOptionalStringField(
        _ key: String,
        from dictionary: [String: Any],
        to contact: CNMutableContact,
        set: (String) -> Void
    ) throws {
        guard dictionary.keys.contains(key) else { return }
        set(try optionalString(dictionary[key]) ?? "")
    }

    private static func contactType(from value: Any?) throws -> CNContactType {
        guard let string = try optionalString(value) else {
            throw ContactsProviderError.invalidArguments("contact_type must be a string")
        }
        switch string {
        case "person":
            return .person
        case "organization":
            return .organization
        default:
            throw ContactsProviderError.invalidArguments("contact_type must be person or organization")
        }
    }

    private static func optionalData(_ value: Any?) throws -> Data? {
        guard let string = try optionalString(value) else { return nil }
        guard let data = Data(base64Encoded: string) else {
            throw ContactsProviderError.invalidArguments("image data must be valid base64")
        }
        return data
    }

    private static func phoneNumbers(from value: Any?) throws -> [CNLabeledValue<CNPhoneNumber>] {
        try labeledValues(from: value, field: "phone_numbers") { valueDictionary in
            guard let stringValue = valueDictionary["string_value"] as? String else {
                throw ContactsProviderError.invalidArguments("phone_numbers value requires string_value")
            }
            return CNPhoneNumber(stringValue: stringValue)
        }
    }

    private static func postalAddresses(from value: Any?) throws -> [CNLabeledValue<CNPostalAddress>] {
        try labeledValues(from: value, field: "postal_addresses") { valueDictionary in
            let address = CNMutablePostalAddress()
            address.street = try optionalString(valueDictionary["street"]) ?? ""
            address.subLocality = try optionalString(valueDictionary["sub_locality"]) ?? ""
            address.city = try optionalString(valueDictionary["city"]) ?? ""
            address.subAdministrativeArea = try optionalString(valueDictionary["sub_administrative_area"]) ?? ""
            address.state = try optionalString(valueDictionary["state"]) ?? ""
            address.postalCode = try optionalString(valueDictionary["postal_code"]) ?? ""
            address.country = try optionalString(valueDictionary["country"]) ?? ""
            address.isoCountryCode = try optionalString(valueDictionary["iso_country_code"]) ?? ""
            return address
        }
    }

    private static func labeledStrings(from value: Any?, field: String) throws -> [CNLabeledValue<NSString>] {
        try labeledValues(from: value, field: field) { valueObject in
            guard let string = valueObject as? String else {
                throw ContactsProviderError.invalidArguments("\(field) values must be strings")
            }
            return string as NSString
        }
    }

    private static func contactRelations(from value: Any?) throws -> [CNLabeledValue<CNContactRelation>] {
        try labeledValues(from: value, field: "contact_relations") { valueDictionary in
            guard let name = valueDictionary["name"] as? String else {
                throw ContactsProviderError.invalidArguments("contact_relations value requires name")
            }
            return CNContactRelation(name: name)
        }
    }

    private static func socialProfiles(from value: Any?) throws -> [CNLabeledValue<CNSocialProfile>] {
        try labeledValues(from: value, field: "social_profiles") { valueDictionary in
            CNSocialProfile(
                urlString: try optionalString(valueDictionary["url_string"]),
                username: try optionalString(valueDictionary["username"]),
                userIdentifier: try optionalString(valueDictionary["user_identifier"]),
                service: try optionalString(valueDictionary["service"])
            )
        }
    }

    private static func instantMessageAddresses(
        from value: Any?
    ) throws -> [CNLabeledValue<CNInstantMessageAddress>] {
        try labeledValues(from: value, field: "instant_message_addresses") { valueDictionary in
            guard let username = valueDictionary["username"] as? String else {
                throw ContactsProviderError.invalidArguments(
                    "instant_message_addresses value requires username"
                )
            }
            guard let service = valueDictionary["service"] as? String else {
                throw ContactsProviderError.invalidArguments(
                    "instant_message_addresses value requires service"
                )
            }
            return CNInstantMessageAddress(username: username, service: service)
        }
    }

    private static func labeledDateComponents(from value: Any?) throws -> [CNLabeledValue<NSDateComponents>] {
        try labeledValues(from: value, field: "dates") { valueObject in
            guard let components = try dateComponents(from: valueObject) else {
                throw ContactsProviderError.invalidArguments("dates values must be date component objects")
            }
            return components as NSDateComponents
        }
    }

    private static func labeledValues<Value>(
        from value: Any?,
        field: String,
        mapValue: ([String: Any]) throws -> Value
    ) throws -> [CNLabeledValue<Value>] where Value: NSObjectProtocol {
        try labeledValues(from: value, field: field) { valueObject in
            guard let valueDictionary = valueObject as? [String: Any] else {
                throw ContactsProviderError.invalidArguments("\(field) values must be objects")
            }
            return try mapValue(valueDictionary)
        }
    }

    private static func labeledValues<Value>(
        from value: Any?,
        field: String,
        mapValue: (Any) throws -> Value
    ) throws -> [CNLabeledValue<Value>] {
        guard let value else { return [] }
        if value is NSNull { return [] }
        guard let array = value as? [[String: Any]] else {
            throw ContactsProviderError.invalidArguments("\(field) must be an array")
        }

        return try array.map { entry in
            guard entry.keys.contains("value") else {
                throw ContactsProviderError.invalidArguments("\(field) entries require value")
            }
            let label = try optionalString(entry["label"])
            let mappedValue = try mapValue(entry["value"] as Any)
            if let identifier = try optionalString(entry["identifier"]) {
                return CNLabeledValue(label: label, identifier: identifier, value: mappedValue)
            }
            return CNLabeledValue(label: label, value: mappedValue)
        }
    }

    private static func foundationCalendar(from dictionary: [String: Any]) throws -> Calendar {
        var calendar = Calendar.current
        if dictionary.keys.contains("identifier") {
            if dictionary["identifier"] is NSNull {
                throw ContactsProviderError.invalidArguments("calendar identifier must be a string or null")
            }
            guard let identifierString = dictionary["identifier"] as? String,
                  let identifier = calendarIdentifier(from: identifierString)
            else {
                throw ContactsProviderError.invalidArguments("calendar identifier must be a valid calendar identifier")
            }
            calendar = Calendar(identifier: identifier)
        }
        if let localeIdentifier = try optionalString(dictionary["locale"]) {
            calendar.locale = Locale(identifier: localeIdentifier)
        }
        if let timeZoneIdentifier = try optionalString(dictionary["time_zone"]) {
            guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else {
                throw ContactsProviderError.invalidArguments("calendar time_zone must be a valid timezone identifier")
            }
            calendar.timeZone = timeZone
        }
        if let firstWeekday = try optionalInt(dictionary["first_weekday"]) {
            calendar.firstWeekday = firstWeekday
        }
        if let minimumDays = try optionalInt(dictionary["minimum_days_in_first_week"]) {
            calendar.minimumDaysInFirstWeek = minimumDays
        }
        return calendar
    }

    private static func isIntegralNumber(_ number: NSNumber) -> Bool {
        let double = number.doubleValue
        return double.rounded() == double
    }

    private static let calendarIdentifierLookup: [String: Calendar.Identifier] = [
        "gregorian": .gregorian,
        "buddhist": .buddhist,
        "chinese": .chinese,
        "coptic": .coptic,
        "ethiopic_amete_mihret": .ethiopicAmeteMihret,
        "ethiopic_amete_alem": .ethiopicAmeteAlem,
        "hebrew": .hebrew,
        "iso8601": .iso8601,
        "indian": .indian,
        "islamic": .islamic,
        "islamic_civil": .islamicCivil,
        "islamic_tabular": .islamicTabular,
        "islamic_umm_al_qura": .islamicUmmAlQura,
        "japanese": .japanese,
        "persian": .persian,
        "republic_of_china": .republicOfChina,
        "bangla": .bangla,
        "gujarati": .gujarati,
        "kannada": .kannada,
        "malayalam": .malayalam,
        "marathi": .marathi,
        "odia": .odia,
        "tamil": .tamil,
        "telugu": .telugu,
        "vikram": .vikram,
        "dangi": .dangi,
        "vietnamese": .vietnamese,
    ]

    private static func calendarIdentifier(from string: String) -> Calendar.Identifier? {
        calendarIdentifierLookup[string]
    }
}