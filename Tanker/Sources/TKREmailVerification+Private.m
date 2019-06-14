#import "TKREmailVerification+Private.h"

@interface TKREmailVerification ()

@property(nonnull, readwrite) NSString* email;
@property(nonnull, readwrite) NSString* verificationCode;

@end

@implementation TKREmailVerification

+ (nonnull TKREmailVerification*)emailVerificationFromEmail:(NSString*)email verificationCode:(NSString*)code
{
  TKREmailVerification* ret = [[TKREmailVerification alloc] init];
  ret.email = email;
  ret.verificationCode = code;
  return ret;
}

@end
