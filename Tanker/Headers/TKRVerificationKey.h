
#import <Foundation/Foundation.h>

/*!
 @brief TKRVerificationKey

 @description A simple data structure holding a verification key as NSString in a value field.

 @see generateVerificationKey
 */
@interface TKRVerificationKey : NSObject

/*!
 @description value of the verification key
 */
@property(readonly, nonnull) NSString* value;

/*!
 @description create a new verification key from a value
 */
+ (nonnull TKRVerificationKey*)verificationKeyFromValue:(nonnull NSString*)value;
@end
