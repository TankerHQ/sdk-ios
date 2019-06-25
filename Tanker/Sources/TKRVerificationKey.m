#import "TKRTanker+Private.h"
#import "TKRUtils+Private.h"
#import "TKRVerificationKey+Private.h"

@implementation TKRVerificationKey

@synthesize value = _value;

- (NSString*)value
{
  return self.valuePrivate;
}

+ (nonnull TKRVerificationKey*)verificationKeyFromValue:(nonnull NSString*)value
{
  TKRVerificationKey* ret = [[TKRVerificationKey alloc] init];
  ret.valuePrivate = value;
  return ret;
}

@end
