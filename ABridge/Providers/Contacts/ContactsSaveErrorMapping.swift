import Foundation

enum ContactsSaveErrorMapping {
    /// Cocoa 134092 is raised when saving `note` without the Contacts Notes entitlement.
    static func map(_ error: Error, wroteNote: Bool) -> ContactsProviderError {
        let nsError = error as NSError
        let looksLikeNotesDenial = nsError.domain == NSCocoaErrorDomain && nsError.code == 134_092
        if wroteNote, looksLikeNotesDenial {
            return .invalidArguments(
                "note requires the Contacts Notes entitlement (com.apple.developer.contacts.notes); omit note"
            )
        }
        return .contactsError(error.localizedDescription)
    }
}
