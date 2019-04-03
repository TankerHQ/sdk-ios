
#import "TKRTankerOptions+Private.h"
#import "TKRUtils+Private.h"

#import <objc/runtime.h>

@implementation TKRTankerOptions (Private)

@dynamic sdkType;

- (void)setSdkType:(NSString *)value
{
  objc_setAssociatedObject(self, @selector(sdkType), value, OBJC_ASSOCIATION_RETAIN);
}

- (NSString*)sdkType
{
  return objc_getAssociatedObject(self, @selector(sdkType));
}

@end
