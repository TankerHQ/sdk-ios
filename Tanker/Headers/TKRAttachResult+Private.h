#import <Tanker/TKRAttachResult.h>
#import <Tanker/TKRSwift+Private.h>

@interface TKRAttachResult ()

@property(readwrite) TKRStatus status;
@property(nullable, readwrite) TKRVerificationMethod* method;

@end
