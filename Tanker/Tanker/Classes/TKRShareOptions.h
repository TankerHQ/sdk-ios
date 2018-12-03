#import <Foundation/Foundation.h>

/*!
 @brief Options used when sharing resources.

 @discussion Each field is optional.
 */
@interface TKRShareOptions : NSObject

/*!
 @brief User IDs to share with

 @discussion If set, must contain registered user IDs (or be empty).
 */
@property NSArray<NSString*>* shareWithUsers;

/*!
 @brief Group IDs to share with

 @discussion If set, must contain registered group IDs (or be empty).
 */
@property NSArray<NSString*>* shareWithGroups;

/*!
 @brief Create a TKRShareOptions with default values.

 @discussion The values are those that Tanker uses if no options are provided:
 - shareWith = @[]
 */
+ (instancetype)defaultOptions;

@end
