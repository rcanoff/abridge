@preconcurrency import Contacts
import Foundation

enum ContactsKeyDescriptors {
    nonisolated(unsafe) static let all: [CNKeyDescriptor] = [
        CNContactIdentifierKey as CNKeyDescriptor,
        CNContactTypeKey as CNKeyDescriptor,
        CNContactGivenNameKey as CNKeyDescriptor,
        CNContactFamilyNameKey as CNKeyDescriptor,
        CNContactMiddleNameKey as CNKeyDescriptor,
        CNContactNamePrefixKey as CNKeyDescriptor,
        CNContactNameSuffixKey as CNKeyDescriptor,
        CNContactNicknameKey as CNKeyDescriptor,
        CNContactOrganizationNameKey as CNKeyDescriptor,
        CNContactDepartmentNameKey as CNKeyDescriptor,
        CNContactJobTitleKey as CNKeyDescriptor,
        CNContactPhoneticGivenNameKey as CNKeyDescriptor,
        CNContactPhoneticMiddleNameKey as CNKeyDescriptor,
        CNContactPhoneticFamilyNameKey as CNKeyDescriptor,
        CNContactPhoneticOrganizationNameKey as CNKeyDescriptor,
        CNContactPreviousFamilyNameKey as CNKeyDescriptor,
        CNContactBirthdayKey as CNKeyDescriptor,
        CNContactNonGregorianBirthdayKey as CNKeyDescriptor,
        CNContactNoteKey as CNKeyDescriptor,
        CNContactImageDataKey as CNKeyDescriptor,
        CNContactThumbnailImageDataKey as CNKeyDescriptor,
        CNContactImageDataAvailableKey as CNKeyDescriptor,
        CNContactPhoneNumbersKey as CNKeyDescriptor,
        CNContactEmailAddressesKey as CNKeyDescriptor,
        CNContactPostalAddressesKey as CNKeyDescriptor,
        CNContactUrlAddressesKey as CNKeyDescriptor,
        CNContactDatesKey as CNKeyDescriptor,
        CNContactInstantMessageAddressesKey as CNKeyDescriptor,
        CNContactRelationsKey as CNKeyDescriptor,
        CNContactSocialProfilesKey as CNKeyDescriptor,
    ]
}

@MainActor
protocol ContactsStoreing {
    func contactsAuthorizationStatus() -> CNAuthorizationStatus
    func fetchContacts(containerIdentifier: String?) throws -> [CNContact]
    func fetchGroups(containerIdentifier: String?) throws -> [CNGroup]
    func fetchContact(identifier: String) throws -> CNContact?
    func searchContacts(
        name: String?,
        emailAddress: String?,
        phoneNumber: String?,
        containerIdentifier: String?
    ) throws -> [CNContact]
    func createContact(in containerIdentifier: String, contact: CNMutableContact) throws -> CNContact
    func createGroup(in containerIdentifier: String, name: String) throws -> CNGroup
    func updateGroup(identifier: String, fields: [String: Any]) throws -> CNGroup
    func updateContact(identifier: String, fields: [String: Any]) throws -> CNContact
    func deleteContact(identifier: String) throws
    func deleteGroup(identifier: String) throws
}
