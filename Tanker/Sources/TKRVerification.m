#import <Tanker/TKREmailVerification+Private.h>
#import <Tanker/TKRPhoneNumberVerification+Private.h>
#import <Tanker/TKRVerification+Private.h>
#import <Tanker/TKRVerificationMethodType.h>

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

+ (nonnull TKRVerification*)verificationFromPhoneNumber:(NSString*)number verificationCode:(NSString*)code
{
  TKRVerification* ret = [[TKRVerification alloc] init];
  ret.type = TKRVerificationMethodTypePhoneNumber;
  ret.phoneNumber = [TKRPhoneNumberVerification phoneNumberVerificationFromPhoneNumber:number verificationCode:code];
  return ret;
}

+ (nonnull TKRVerification*)verificationFromPreverifiedEmail:(NSString*)preverifiedEmail
{
  TKRVerification* ret = [[TKRVerification alloc] init];
  ret.type = TKRVerificationMethodTypePreverifiedEmail;
  ret.preverifiedEmail = preverifiedEmail;
  return ret;
}

+ (nonnull TKRVerification*)verificationFromPreverifiedPhoneNumber:(NSString*)preverifiedPhoneNumber
{
  TKRVerification* ret = [[TKRVerification alloc] init];
  ret.type = TKRVerificationMethodTypePreverifiedPhoneNumber;
  ret.preverifiedPhoneNumber = preverifiedPhoneNumber;
  return ret;
}

+ (nonnull TKRVerification*)verificationFromE2ePassphrase:(NSString*)e2ePassphrase
{
  TKRVerification* ret = [[TKRVerification alloc] init];
  ret.type = TKRVerificationMethodTypeE2ePassphrase;
  ret.e2ePassphrase = e2ePassphrase;
  return ret;
}

+ (nonnull TKRVerification*)verificationFromPreverifiedOIDCSubject:(nonnull NSString*)subject providerID:(nonnull NSString*)providerID
{
  TKRVerification* ret = [[TKRVerification alloc] init];
  ret.type = TKRVerificationMethodTypePreverifiedOIDC;
  ret.preverifiedOIDC = [TKRPreverifiedOIDCVerification preverifiedOIDCVerificationFromSubject:subject providerID:providerID];
  return ret;
}

+ (nonnull TKRVerification*)verificationFromOIDCAuthorizationCode:(nonnull NSString*)authorizationCode providerID:(nonnull NSString*)providerID state:(nonnull NSString*)state
{
  TKRVerification* ret = [[TKRVerification alloc] init];
  ret.type = TKRVerificationMethodTypeOIDCAuthorizationCode;
  ret.oidcAuthorizationCode = [TKROIDCAuthorizationCodeVerification oidcAuthorizationCodeVerificationFromProviderID:providerID authorizationCode:authorizationCode state:state];
  return ret;
}

@end
