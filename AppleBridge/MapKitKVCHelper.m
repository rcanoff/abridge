#import "MapKitKVCHelper.h"

id _Nullable MapKitSafeValueForKey(id object, NSString *key) {
    if (object == nil || key.length == 0) {
        return nil;
    }

    @try {
        return [object valueForKey:key];
    } @catch (NSException *exception) {
        return nil;
    }
}