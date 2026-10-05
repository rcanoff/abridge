@preconcurrency import Contacts
import Foundation

extension ContactsDeserialization {
    static func applyCollectionFields(from dictionary: [String: Any], to contact: CNMutableContact) throws {
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

    static func phoneNumbers(from value: Any?) throws -> [CNLabeledValue<CNPhoneNumber>] {
        try labeledValues(from: value, field: "phone_numbers") { valueDictionary in
            guard let stringValue = valueDictionary["string_value"] as? String else {
                throw ContactsProviderError.invalidArguments("phone_numbers value requires string_value")
            }
            return CNPhoneNumber(stringValue: stringValue)
        }
    }

    static func postalAddresses(from value: Any?) throws -> [CNLabeledValue<CNPostalAddress>] {
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

    static func labeledStrings(from value: Any?, field: String) throws -> [CNLabeledValue<NSString>] {
        guard let value else { return [] }
        if value is NSNull { return [] }
        guard let array = value as? [[String: Any]] else {
            throw ContactsProviderError.invalidArguments("\(field) must be an array")
        }

        return try array.map { entry in
            guard entry.keys.contains("value") else {
                throw ContactsProviderError.invalidArguments("\(field) entries require value")
            }
            guard let string = entry["value"] as? String else {
                throw ContactsProviderError.invalidArguments("\(field) values must be strings")
            }
            let label = try optionalString(entry["label"])
            return CNLabeledValue(label: label, value: string as NSString)
        }
    }

    static func contactRelations(from value: Any?) throws -> [CNLabeledValue<CNContactRelation>] {
        try labeledValues(from: value, field: "contact_relations") { valueDictionary in
            guard let name = valueDictionary["name"] as? String else {
                throw ContactsProviderError.invalidArguments("contact_relations value requires name")
            }
            return CNContactRelation(name: name)
        }
    }

    static func socialProfiles(from value: Any?) throws -> [CNLabeledValue<CNSocialProfile>] {
        try labeledValues(from: value, field: "social_profiles") { valueDictionary in
            try CNSocialProfile(
                urlString: optionalString(valueDictionary["url_string"]),
                username: optionalString(valueDictionary["username"]),
                userIdentifier: optionalString(valueDictionary["user_identifier"]),
                service: optionalString(valueDictionary["service"])
            )
        }
    }

    static func instantMessageAddresses(
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

    static func labeledDateComponents(from value: Any?) throws -> [CNLabeledValue<NSDateComponents>] {
        try labeledValues(from: value, field: "dates") { valueDictionary in
            guard let components = try dateComponents(from: valueDictionary) else {
                throw ContactsProviderError.invalidArguments("dates values must be date component objects")
            }
            return components as NSDateComponents
        }
    }

    static func labeledValues<Value: NSObjectProtocol>(
        from value: Any?,
        field: String,
        mapValue: ([String: Any]) throws -> Value
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
            guard let valueDictionary = entry["value"] as? [String: Any] else {
                throw ContactsProviderError.invalidArguments("\(field) values must be objects")
            }
            let label = try optionalString(entry["label"])
            let mappedValue = try mapValue(valueDictionary)
            return CNLabeledValue(label: label, value: mappedValue)
        }
    }
}
