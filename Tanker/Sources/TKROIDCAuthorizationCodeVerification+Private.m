#import <Tanker/TKROIDCAuthorizationCodeVerification+Private.h>

@interface TKROIDCAuthorizationCodeVerification ()

@property(nonnull, readwrite) NSString* providerID;
@property(nonnull, readwrite) NSString* authorizationCode;
@property(nonnull, readwrite) NSString* state;

@end

@implementation TKROIDCAuthorizationCodeVerification

+ (nonnull TKROIDCAuthorizationCodeVerification*)oidcAuthorizationCodeVerificationFromProviderID:(nonnull NSString*)providerID                                                                               authorizationCode:(nonnull NSString*)authorizationCode
                                                                                           state:(nonnull NSString*)state
{
  TKROIDCAuthorizationCodeVerification* ret = [[TKROIDCAuthorizationCodeVerification alloc] init];
  ret.providerID = providerID;
  ret.authorizationCode = authorizationCode;
  ret.state = state;
  return ret;
}

@end
