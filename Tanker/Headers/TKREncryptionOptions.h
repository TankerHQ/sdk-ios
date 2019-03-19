
#import <Foundation/Foundation.h>

/*!
 @brief Options used when encrypting resources.

 @discussion Each field is optional.
 */
@interface TKREncryptionOptions : NSObject

/*!
 @brief Recipient public identities to share with

 @discussion If set, must contain valid public identities (or be empty).
 The current user's identity will be appended when encrypting.
 */
@property NSArray<NSString*>* shareWithUsers;

/*!
 @brief Group IDs to share with

 @discussion If set, must contain registered group IDs (or be empty).
 */
@property NSArray<NSString*>* shareWithGroups;

/*!
 @brief Create a TKREncryptionOptions with empty values.
 */
+ (instancetype)options;

@end
