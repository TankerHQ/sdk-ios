#import <Foundation/Foundation.h>

#import "TKRVerificationKey.h"

/*!
 @brief TKRVerification
 */
@interface TKRVerification : NSObject

+ (nonnull TKRVerification*)verificationFromVerificationKey:(nonnull TKRVerificationKey*)key;
+ (nonnull TKRVerification*)verificationFromEmail:(nonnull NSString*)email verificationCode:(nonnull NSString*)code;
+ (nonnull TKRVerification*)verificationFromPassphrase:(nonnull NSString*)passphrase;
+ (nonnull TKRVerification*)verificationFromOIDCIDToken:(nonnull NSString*)oidcIDToken;

@end
