#import <Contacts/Contacts.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CNSaveRequest (AppleBridgeContactLinking)

/// Links one contact into a unified destination when the runtime selector exists.
/// Returns NO when the selector is absent or the framework rejects the link.
- (BOOL)ab_linkContact:(CNMutableContact *)contact toContact:(CNMutableContact *)unifiedContact;

@end

BOOL ABCNSaveRequestContactLinkingIsAvailable(void);

NS_ASSUME_NONNULL_END