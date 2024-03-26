#import <Foundation/Foundation.h>

#import <Tanker/TKRVerificationKey.h>

/*!
 @brief TKRVerification
 */
@interface TKRVerification : NSObject

+ (nonnull TKRVerification*)verificationFromVerificationKey:(nonnull TKRVerificationKey*)key;
+ (nonnull TKRVerification*)verificationFromEmail:(nonnull NSString*)email verificationCode:(nonnull NSString*)code;
+ (nonnull TKRVerification*)verificationFromPassphrase:(nonnull NSString*)passphrase;
+ (nonnull TKRVerification*)verificationFromOIDCIDToken:(nonnull NSString*)oidcIDToken;
+ (nonnull TKRVerification*)verificationFromPhoneNumber:(nonnull NSString*)phoneNumber
                                       verificationCode:(nonnull NSString*)code;
+ (nonnull TKRVerification*)verificationFromPreverifiedEmail:(nonnull NSString*)preverifiedEmail;
+ (nonnull TKRVerification*)verificationFromPreverifiedPhoneNumber:(nonnull NSString*)preverifiedPhoneNumber;
+ (nonnull TKRVerification*)verificationFromPreverifiedOIDCSubject:(nonnull NSString*)subject providerID:(nonnull NSString*)providerID;
+ (nonnull TKRVerification*)verificationFromE2ePassphrase:(nonnull NSString*)e2ePassphrase;
+ (nonnull TKRVerification*)verificationFromOIDCAuthorizationCode:(nonnull NSString*)authorizationCode providerID:(nonnull NSString*)providerID state:(nonnull NSString*)state;

@end
