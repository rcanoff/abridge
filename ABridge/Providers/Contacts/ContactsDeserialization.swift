@preconcurrency import Contacts
import Foundation

enum ContactsDeserialization {
    static func mutableContact(from dictionary: [String: Any]) throws -> CNMutableContact {
        let contact = CNMutableContact()
        try applyWritableFields(from: dictionary, to: contact)
        return contact
    }

    static func applyWritableFields(from dictionary: [String: Any], to contact: CNMutableContact) throws {
        try applyScalarFields(from: dictionary, to: contact)
        try applyCollectionFields(from: dictionary, to: contact)
    }

    static func optionalString(_ value: Any?) throws -> String? {
        guard let value else { return nil }
        if value is NSNull {
            return nil
        }
        guard let string = value as? String else {
            throw ContactsProviderError.invalidArguments("Expected string or null")
        }
        return string
    }

    static func optionalInt(_ value: Any?) throws -> Int? {
        guard let value else { return nil }
        if value is NSNull {
            return nil
        }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                throw ContactsProviderError.invalidArguments("Expected integer or null")
            }
            guard isIntegralNumber(number) else {
                throw ContactsProviderError.invalidArguments("Expected integer or null")
            }
            return number.intValue
        }
        if value is Bool {
            throw ContactsProviderError.invalidArguments("Expected integer or null")
        }
        if let int = value as? Int {
            return int
        }
        throw ContactsProviderError.invalidArguments("Expected integer or null")
    }

    static func optionalBool(_ value: Any?) throws -> Bool? {
        guard let value else { return nil }
        if value is NSNull {
            return nil
        }
        guard let bool = value as? Bool else {
            throw ContactsProviderError.invalidArguments("Expected boolean or null")
        }
        return bool
    }

    static func isIntegralNumber(_ number: NSNumber) -> Bool {
        let double = number.doubleValue
        return double.rounded() == double
    }
}
