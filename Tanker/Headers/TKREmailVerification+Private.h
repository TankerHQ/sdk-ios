
#import <Foundation/Foundation.h>

@interface TKREmailVerification : NSObject

+ (nonnull TKREmailVerification*)emailVerificationFromEmail:(nonnull NSString*)email
                                           verificationCode:(nonnull NSString*)code;

@property(nonnull, readonly) NSString* email;
@property(nonnull, readonly) NSString* verificationCode;

@end
