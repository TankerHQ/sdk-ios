#import "TKREmailVerification+Private.h"
#import "TKRVerification+Private.h"
#import "TKRVerificationMethodType.h"

@implementation TKRVerification

+ (nonnull TKRVerification*)verificationFromVerificationKey:(TKRVerificationKey*)key
{
  TKRVerification* ret = [[TKRVerification alloc] init];
  ret.type = TKRVerificationMethodTypeVerificationKey;
  ret.verificationKey = key;
  return ret;
}

+ (nonnull TKRVerification*)verificationFromEmail:(NSString*)email verificationCode:(NSString*)code
{
  TKRVerification* ret = [[TKRVerification alloc] init];
  ret.type = TKRVerificationMethodTypeEmail;
  ret.email = [TKREmailVerification emailVerificationFromEmail:email verificationCode:code];
  return ret;
}

+ (nonnull TKRVerification*)verificationFromPassphrase:(NSString*)passphrase
{
  TKRVerification* ret = [[TKRVerification alloc] init];
  ret.type = TKRVerificationMethodTypePassphrase;
  ret.passphrase = passphrase;
  return ret;
}

+ (nonnull TKRVerification*)verificationFromOIDCIDToken:(NSString*)oidcIDToken
{
  TKRVerification* ret = [[TKRVerification alloc] init];
  ret.type = TKRVerificationMethodTypeOIDCIDToken;
  ret.oidcIDToken = oidcIDToken;
  return ret;
}

@end
