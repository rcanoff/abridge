#import "ContactsRuntimeLinking.h"

#import <objc/message.h>

static SEL ABLinkContactSelector(void) {
    return NSSelectorFromString(@"linkContact:toContact:");
}

BOOL ABContactLinkingIsAvailable(void) {
    return [CNSaveRequest instancesRespondToSelector:ABLinkContactSelector()];
}

BOOL ABLinkContactToContact(
    CNSaveRequest *saveRequest,
    CNMutableContact *contact,
    CNMutableContact *unifiedContact
) {
    SEL selector = ABLinkContactSelector();
    if (![saveRequest respondsToSelector:selector]) {
        return NO;
    }

    typedef BOOL (*ABLinkContactIMP)(id, SEL, CNMutableContact *, CNMutableContact *);
    return ((ABLinkContactIMP)objc_msgSend)(saveRequest, selector, contact, unifiedContact);
}