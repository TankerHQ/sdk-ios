
#import <Foundation/Foundation.h>

/*!
 @brief TKRUnlockKey object

 @description A simple data structure holding a unlock key as NSString in a value field.

 @see generateAndRegisterUnlockKey and unlockCurrentDeviceWithUnlockKey
 */
@interface TKRUnlockKey : NSObject

/*!
 @description value of the unlock Key
 */
@property(readonly, nonnull) NSString* value;

/*!
 @description create a new unlock key from a value
 */
+ (nonnull TKRUnlockKey*)unlockKeyFromValue:(nonnull NSString*)value;
@end
