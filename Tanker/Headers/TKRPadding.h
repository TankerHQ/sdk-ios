
#import <Foundation/Foundation.h>

/*!
 @brief Padding control for data encryption
 */
@interface TKRPadding : NSObject

@property(nonnull, readonly) NSNumber* nativeValue;

/*!
 @brief Default option
 */
+ (nullable instancetype)automatic;

/*!
 @brief Disables padding
 */
+ (nullable instancetype)off;

/*!
 @brief Pads the data up to a multiple of value before encryption

 @param value Must be a NSNumber >= 2
 */
+ (nullable instancetype)step:(nonnull NSNumber*)value;

@end
