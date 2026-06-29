import Foundation

struct ApplePermissionAuthorization: Equatable {
    var remindersAuthorized: Bool
    var eventsAuthorized: Bool
    var contactsAuthorized: Bool
    var locationAuthorized: Bool
}
