
#import <Foundation/Foundation.h>

/*!
 @brief Options used when registering unlock methods.

 @discussion Each field is optional.
 */
@interface TKRUnlockOptions : NSObject

/*!
 @brief Password to set or NULL
 */
@property NSString* password;

/*!
 @brief E-mail to set or NULL
 */
@property NSString* email;

/*!
 @brief Create a TKRUnlockOptions with default values.
 */
+ (instancetype)defaultOptions;

@end
