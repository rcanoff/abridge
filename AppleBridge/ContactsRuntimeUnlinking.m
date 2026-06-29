#import "ContactsRuntimeUnlinking.h"

#import <objc/message.h>

static SEL ABUnlinkContactSelector(void) {
    return NSSelectorFromString(@"unlinkContact:");
}

BOOL ABContactUnlinkingIsAvailable(void) {
    return [CNSaveRequest instancesRespondToSelector:ABUnlinkContactSelector()];
}

BOOL ABUnlinkContact(CNSaveRequest *saveRequest, CNMutableContact *contact) {
    SEL selector = ABUnlinkContactSelector();
    if (![saveRequest respondsToSelector:selector]) {
        return NO;
    }

    typedef BOOL (*ABUnlinkContactIMP)(id, SEL, CNMutableContact *);
    return ((ABUnlinkContactIMP)objc_msgSend)(saveRequest, selector, contact);
}