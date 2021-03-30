
#import <Foundation/Foundation.h>

/*!
 @brief Options used when verifying your identity.
 */
@interface TKRVerificationOptions : NSObject

/*!
 @brief Request a session token (defaults to false)
 */
@property bool withSessionToken;

/*!
 @brief Create a TKRVerificationOptions with default values.
 */
+ (instancetype)options;

@end
