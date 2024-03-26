
#import <Foundation/Foundation.h>

@interface TKROIDCAuthorizationCodeVerification : NSObject

+ (nonnull TKROIDCAuthorizationCodeVerification*)oidcAuthorizationCodeVerificationFromProviderID:(nonnull NSString*)providerID
                                                                               authorizationCode:(nonnull NSString*)authorizationCode
                                                                                           state:(nonnull NSString*)state;

@property(nonnull, readonly) NSString* providerID;
@property(nonnull, readonly) NSString* authorizationCode;
@property(nonnull, readonly) NSString* state;

@end
