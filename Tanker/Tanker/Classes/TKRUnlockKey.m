#import "TKRTanker+Private.h"
#import "TKRUnlockKey+Private.h"
#import "TKRUtils+Private.h"
#import <PromiseKit/Promise.h>

@implementation TKRUnlockKey

@synthesize value = _value;

- (NSString*)value
{
  return self.valuePrivate;
}

+ (nonnull TKRUnlockKey*)unlockKeyFromValue:(nonnull NSString*)value
{
  TKRUnlockKey* ret = [[TKRUnlockKey alloc] init];
  ret.valuePrivate = value;
  return ret;
}

@end
