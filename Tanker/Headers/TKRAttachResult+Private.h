#import <Tanker/TKRAttachResult.h>
#import <Tanker/Tanker-Swift.h>

@interface TKRAttachResult ()

@property(readwrite) TKRStatus status;
@property(nullable, readwrite) TKRVerificationMethod* method;

@end
