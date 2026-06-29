#import <Contacts/Contacts.h>
#import <Foundation/Foundation.h>

void ABUnlinkContact(CNSaveRequest *saveRequest, CNMutableContact *contact);
BOOL ABContactUnlinkingIsAvailable(void);