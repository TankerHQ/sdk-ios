
#import <Foundation/Foundation.h>

@interface TKRPhoneNumberVerification : NSObject

+ (nonnull TKRPhoneNumberVerification*)phoneNumberVerificationFromPhoneNumber:(nonnull NSString*)phoneNumber
                                                             verificationCode:(nonnull NSString*)code;

@property(nonnull, readonly) NSString* phoneNumber;
@property(nonnull, readonly) NSString* verificationCode;

@end
