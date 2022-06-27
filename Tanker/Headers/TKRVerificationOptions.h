
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
 @brief Allow switching to and from E2E verification methods (defaults to false)
 */
@property bool allowE2eMethodSwitch;

/*!
 @brief Create a TKRVerificationOptions with default values.
 */
+ (instancetype)options;

@end
