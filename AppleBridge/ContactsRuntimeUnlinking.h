#import <Contacts/Contacts.h>
#import <Foundation/Foundation.h>

BOOL ABUnlinkContact(CNSaveRequest *saveRequest, CNMutableContact *contact);
BOOL ABContactUnlinkingIsAvailable(void);