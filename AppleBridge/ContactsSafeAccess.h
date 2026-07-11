#import <Contacts/Contacts.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Returns the contact note, or nil if the key is unavailable / protected (no notes entitlement).
/// Accessing `CNContact.note` without the Contacts Notes entitlement raises NSException and aborts.
FOUNDATION_EXPORT NSString *_Nullable ABContactSafeNote(CNContact *contact);

NS_ASSUME_NONNULL_END
