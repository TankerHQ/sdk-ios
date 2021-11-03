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
@end
