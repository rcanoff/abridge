@preconcurrency import Contacts
import Foundation

enum ContactsGroupDeserialization {
    static func applyWritableFields(from fields: [String: Any], to group: CNMutableGroup) throws {
        guard let nameValue = fields["name"] else { return }

        if nameValue is NSNull {
            group.name = ""
        } else if let name = nameValue as? String {
            group.name = name
        } else {
            throw ContactsProviderError.invalidArguments("name must be a string or null")
        }
    }
}