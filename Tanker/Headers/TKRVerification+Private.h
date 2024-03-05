#import <Tanker/TKREmailVerification+Private.h>
#import <Tanker/TKRPhoneNumberVerification+Private.h>
#import <Tanker/TKRPreverifiedOIDCVerification+Private.h>
#import <Tanker/TKRVerification.h>
#import <Tanker/TKRVerificationMethodType.h>

@interface TKRVerification (Private)

@property TKRVerificationMethodType type;

@property NSString* passphrase;
@property NSString* e2ePassphrase;
@property TKRVerificationKey* verificationKey;
@property TKREmailVerification* email;
@property NSString* oidcIDToken;
@property TKRPhoneNumberVerification* phoneNumber;
@property NSString* preverifiedEmail;
@property NSString* preverifiedPhoneNumber;
@property TKRPreverifiedOIDCVerification* preverifiedOIDC;

@property id valuePrivate;

@end
