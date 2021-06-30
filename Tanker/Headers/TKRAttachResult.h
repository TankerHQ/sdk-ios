#import <Foundation/Foundation.h>

#import <Tanker/TKRStatus.h>
#import <Tanker/TKRVerificationMethod.h>

@interface TKRAttachResult : NSObject

@property(readonly) TKRStatus status;
@property(readonly, nullable) TKRVerificationMethod* method;

@end
