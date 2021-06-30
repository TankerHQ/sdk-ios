#import <Tanker/TKRAttachResult.h>

@interface TKRAttachResult ()

@property(readwrite) TKRStatus status;
@property(nullable, readwrite) TKRVerificationMethod* method;

@end
