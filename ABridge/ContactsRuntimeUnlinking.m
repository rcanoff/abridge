#import "ContactsRuntimeUnlinking.h"

#import <objc/message.h>

static SEL ABUnlinkContactSelector(void) {
    return NSSelectorFromString(@"unlinkContact:");
}

BOOL ABContactUnlinkingIsAvailable(void) {
    return [CNSaveRequest instancesRespondToSelector:ABUnlinkContactSelector()];
}

void ABUnlinkContact(CNSaveRequest *saveRequest, CNMutableContact *contact) {
    SEL selector = ABUnlinkContactSelector();
    if (![saveRequest respondsToSelector:selector]) {
        return;
    }

    typedef void (*ABUnlinkContactIMP)(id, SEL, CNMutableContact *);
    ((ABUnlinkContactIMP)objc_msgSend)(saveRequest, selector, contact);
}