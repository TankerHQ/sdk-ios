#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#import "TKRTanker+Private.h"
#import "TKRUnlockKey+Private.h"
#import "TKRUtils+Private.h"
@implementation TKRUnlockKey (Private)

@dynamic valuePrivate;

// MARK: Voodoo associated objects methods

- (void)setValuePrivate:(NSString*)value
{
  objc_setAssociatedObject(self, @selector(valuePrivate), value, OBJC_ASSOCIATION_RETAIN);
}

- (NSString*)valuePrivate
{
  return objc_getAssociatedObject(self, @selector(valuePrivate));
}

@end
