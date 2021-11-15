#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#import <Tanker/TKRTanker+Private.h>
#import <Tanker/Utils/TKRUtils.h>
#import <Tanker/TKRVerificationKey+Private.h>

@implementation TKRVerificationKey (Private)

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
