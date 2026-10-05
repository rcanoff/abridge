@preconcurrency import Contacts
import Foundation

extension ContactsDeserialization {
    static func applyScalarFields(from dictionary: [String: Any], to contact: CNMutableContact) throws {
        if dictionary.keys.contains("contact_type") {
            contact.contactType = try contactType(from: dictionary["contact_type"])
        }

        try applyOptionalStringField("given_name", from: dictionary, set: { contact.givenName = $0 })
        try applyOptionalStringField("family_name", from: dictionary, set: { contact.familyName = $0 })
        try applyOptionalStringField("middle_name", from: dictionary, set: { contact.middleName = $0 })
        try applyOptionalStringField("name_prefix", from: dictionary, set: { contact.namePrefix = $0 })
        try applyOptionalStringField("name_suffix", from: dictionary, set: { contact.nameSuffix = $0 })
        try applyOptionalStringField("nickname", from: dictionary, set: { contact.nickname = $0 })
        try applyOptionalStringField("organization_name", from: dictionary, set: { contact.organizationName = $0 })
        try applyOptionalStringField("department_name", from: dictionary, set: { contact.departmentName = $0 })
        try applyOptionalStringField("job_title", from: dictionary, set: { contact.jobTitle = $0 })
        try applyOptionalStringField("phonetic_given_name", from: dictionary, set: { contact.phoneticGivenName = $0 })
        try applyOptionalStringField("phonetic_middle_name", from: dictionary, set: { contact.phoneticMiddleName = $0 })
        try applyOptionalStringField("phonetic_family_name", from: dictionary, set: { contact.phoneticFamilyName = $0 })
        try applyOptionalStringField(
            "phonetic_organization_name",
            from: dictionary,
            set: { contact.phoneticOrganizationName = $0 }
        )
        try applyOptionalStringField("previous_family_name", from: dictionary, set: { contact.previousFamilyName = $0 })
        // Note: writing `note` without com.apple.developer.contacts.notes fails on live CNSaveRequest
        // (Cocoa 134092). Live store maps that error; mock stores still accept note for fidelity tests.
        try applyOptionalStringField("note", from: dictionary, set: { contact.note = $0 })

        if dictionary.keys.contains("image_data") {
            contact.imageData = try optionalData(dictionary["image_data"])
        }
    }

    static func applyOptionalStringField(
        _ key: String,
        from dictionary: [String: Any],
        set: (String) -> Void
    ) throws {
        guard dictionary.keys.contains(key) else { return }
        try set(optionalString(dictionary[key]) ?? "")
    }

    static func contactType(from value: Any?) throws -> CNContactType {
        guard let string = try optionalString(value) else {
            return .person // schema enum; offline default
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

    static func optionalData(_ value: Any?) throws -> Data? {
        guard let string = try optionalString(value) else { return nil }
        guard let data = Data(base64Encoded: string) else {
            throw ContactsProviderError.invalidArguments("image data must be valid base64")
        }
        return data
    }
}
