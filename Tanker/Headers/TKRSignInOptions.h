#import <Foundation/Foundation.h>

#import "TKRUnlockKey.h"

/*!
 @brief Tanker sign-in options

 @discussion Each field is optional.
 */
@interface TKRSignInOptions : NSObject

/*!
 @brief Password provided during sign-up.
 */
@property NSString* password;

/*!
 @brief Verification code sent to the user's email address.
 */
@property NSString* verificationCode;

/*!
 @brief Unlock key manually generated after sign-up.
 */
@property TKRUnlockKey* unlockKey;

/*!
 @brief Create an empty TKRSignInOptions with every field set to nil.
 */
+ (instancetype)options;

@end
