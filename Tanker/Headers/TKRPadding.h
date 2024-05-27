
#import <Foundation/Foundation.h>

/*!
 @brief Padding control for data encryption
 */
NS_SWIFT_NAME(Padding)
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

 @param value Must be a NSUInteger >= 2
 */
+ (nullable instancetype)step:(NSUInteger)value error:(NSError * _Nonnull * _Nullable)error;

@end
