#import <Tanker/TKRTanker+Private.h>
#import <Tanker/TKRUtils+Private.h>
#import <Tanker/TKRVerificationKey+Private.h>

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
