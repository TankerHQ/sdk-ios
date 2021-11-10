#import <Foundation/Foundation.h>

#import <Tanker/TKRVerificationKey.h>
#import <Tanker/TKRVerificationMethodType.h>

@interface TKRVerificationMethod : NSObject

@property(readonly) TKRVerificationMethodType type;

/*!
 @brief email address

 @pre type == TKRVerificationMethodTypeEmail
 */
@property(nonnull, readonly) NSString* email;

/*!
 @brief phone number

 @pre type == TKRVerificationMethodTypePhoneNumber
 */
@property(nonnull, readonly) NSString* phoneNumber;

/*!
 @brief preverified email address

 @pre type == TKRVerificationMethodTypePreverifiedEmail
 */
@property(nonnull, readonly) NSString* preverifiedEmail;

/*!
 @brief preverified phone number

 @pre type == TKRVerificationMethodTypePreverifiedPhoneNumber
 */
@property(nonnull, readonly) NSString* preverifiedPhoneNumber;

@end
