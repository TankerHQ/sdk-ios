#import <Tanker/TKRPhoneNumberVerification+Private.h>

@interface TKRPhoneNumberVerification ()

@property(nonnull, readwrite) NSString* phoneNumber;
@property(nonnull, readwrite) NSString* verificationCode;

@end

@implementation TKRPhoneNumberVerification

+ (nonnull TKRPhoneNumberVerification*)phoneNumberVerificationFromPhoneNumber:(nonnull NSString*)number verificationCode:(nonnull NSString*)code
{
  TKRPhoneNumberVerification* ret = [[TKRPhoneNumberVerification alloc] init];
  ret.phoneNumber = number;
  ret.verificationCode = code;
  return ret;
}

@end
