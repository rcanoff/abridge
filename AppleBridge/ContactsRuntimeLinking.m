#import "ContactsRuntimeLinking.h"

#import <objc/message.h>

static SEL ABLinkContactSelector(void) {
    return NSSelectorFromString(@"linkContact:toContact:");
}

BOOL ABContactLinkingIsAvailable(void) {
    return [CNSaveRequest instancesRespondToSelector:ABLinkContactSelector()];
}

void ABLinkContactToContact(
    CNSaveRequest *saveRequest,
    CNMutableContact *contact,
    CNMutableContact *unifiedContact
) {
    SEL selector = ABLinkContactSelector();
    if (![saveRequest respondsToSelector:selector]) {
        return;
    }

    typedef void (*ABLinkContactIMP)(id, SEL, CNMutableContact *, CNMutableContact *);
    ((ABLinkContactIMP)objc_msgSend)(saveRequest, selector, contact, unifiedContact);
}