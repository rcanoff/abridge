#import "ContactsSaveRequestLinking.h"

@interface CNSaveRequest (AppleBridgePrivateLinking)
- (BOOL)linkContact:(CNMutableContact *)contact toContact:(CNMutableContact *)unifiedContact;
@end

@implementation CNSaveRequest (AppleBridgeContactLinking)

- (BOOL)ab_linkContact:(CNMutableContact *)contact toContact:(CNMutableContact *)unifiedContact {
    SEL selector = @selector(linkContact:toContact:);
    if (![self respondsToSelector:selector]) {
        return NO;
    }
    return [self linkContact:contact toContact:unifiedContact];
}

@end

BOOL ABCNSaveRequestContactLinkingIsAvailable(void) {
    return [CNSaveRequest instancesRespondToSelector:@selector(linkContact:toContact:)];
}