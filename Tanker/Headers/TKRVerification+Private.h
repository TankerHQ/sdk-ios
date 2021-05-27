#import <Tanker/TKREmailVerification+Private.h>
#import <Tanker/TKRVerification.h>
#import <Tanker/TKRVerificationMethodType.h>

@interface TKRVerification (Private)

@property TKRVerificationMethodType type;

@property NSString* passphrase;
@property TKRVerificationKey* verificationKey;
@property TKREmailVerification* email;
@property NSString* oidcIDToken;

@property id valuePrivate;

@end
