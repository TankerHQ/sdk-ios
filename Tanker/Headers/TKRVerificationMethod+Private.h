#import <Foundation/Foundation.h>

#import <Tanker/TKRVerificationMethod.h>

@interface TKRVerificationMethod ()

@property(readwrite) TKRVerificationMethodType type;
@property(nonnull, readwrite) NSString* email;
@property(nonnull, readwrite) NSString* phoneNumber;
@property(nonnull, readwrite) NSString* preverifiedEmail;
@property(nonnull, readwrite) NSString* preverifiedPhoneNumber;
@property(nonnull, readwrite) NSString* oidcProviderID;
@property(nonnull, readwrite) NSString* oidcProviderDisplayName;

@end
