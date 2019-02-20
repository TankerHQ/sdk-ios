#import <Foundation/Foundation.h>

/*!
 @brief Options used when decrypting resources.

 @discussion Each field is optional.
 */
@interface TKRDecryptionOptions : NSObject

/*!
 @brief Time (in seconds) after which Tanker will timeout.
 */
@property NSTimeInterval timeout;

/*!
 @brief Create a TKRDecryptionOptions with default values.

 @discussion The values are those that Tanker uses if no options are provided:
 - timeout = 10
 */
+ (instancetype)defaultOptions;

@end
