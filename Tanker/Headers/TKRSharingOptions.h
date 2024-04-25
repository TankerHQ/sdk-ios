#import <Foundation/Foundation.h>

/*!
 @brief Options used when sharing resources.

 @discussion Each field is optional.
 */
NS_SWIFT_NAME(SharingOptions)
@interface TKRSharingOptions : NSObject

/*!
 @brief Recipient public identities to share with

 @discussion If set, must contain registered user IDs (or be empty).
 */
@property NSArray<NSString*>* shareWithUsers;

/*!
 @brief Group IDs to share with

 @discussion If set, must contain registered group IDs (or be empty).
 */
@property NSArray<NSString*>* shareWithGroups;

/*!
 @brief Create a TKRSharingOptions with empty values.
 */
+ (instancetype)options;

@end
