#import "ContactsSafeAccess.h"

NSString *_Nullable ABContactSafeNote(CNContact *contact) {
    if (contact == nil) {
        return nil;
    }
    @try {
        if (![contact isKeyAvailable:CNContactNoteKey]) {
            return nil;
        }
        return contact.note;
    } @catch (NSException *exception) {
        // Protected note property without com.apple.developer.contacts.notes.
        return nil;
    }
}
