#import <Foundation/Foundation.h>

#import <Tanker/TKRVerificationMethod.h>

@interface TKRVerificationMethod ()

@property(readwrite) TKRVerificationMethodType type;
@property(nonnull, readwrite) NSString* email;

@end
