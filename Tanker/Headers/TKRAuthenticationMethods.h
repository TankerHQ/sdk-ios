#import <Foundation/Foundation.h>

/*!
 @brief Tanker authentication methods
 
 @discussion Each field is optional.
 */
@interface TKRAuthenticationMethods : NSObject

/*!
 @brief Password
 
 @discussion If set, it will be required later on to validate new devices.
 */
@property NSString* password;

/*!
 @brief Current user's email address
 
 @discussion If set, an email will be sent to it to validate new devices.
 */
@property NSString* email;

/*!
 @brief Create an empty TKRAuthenticationMethods with every field set to nil.
 */
+ (instancetype)methods;

@end
