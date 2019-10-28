#import "TKREmailVerification+Private.h"
#import "TKRVerification.h"
#import "TKRVerificationMethodType.h"

@interface TKRVerification (Private)

@property TKRVerificationMethodType type;

@property NSString* passphrase;
@property TKRVerificationKey* verificationKey;
@property TKREmailVerification* email;
@property NSString* oidcIDToken;

@property id valuePrivate;

@end
