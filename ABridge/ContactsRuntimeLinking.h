#import <Contacts/Contacts.h>
#import <Foundation/Foundation.h>

void ABLinkContactToContact(
    CNSaveRequest *saveRequest,
    CNMutableContact *contact,
    CNMutableContact *unifiedContact
);
BOOL ABContactLinkingIsAvailable(void);