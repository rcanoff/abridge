#import <Contacts/Contacts.h>
#import <Foundation/Foundation.h>

BOOL ABLinkContactToContact(
    CNSaveRequest *saveRequest,
    CNMutableContact *contact,
    CNMutableContact *unifiedContact
);
BOOL ABContactLinkingIsAvailable(void);