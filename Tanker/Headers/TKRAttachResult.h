#import <Foundation/Foundation.h>

#import "TKRStatus.h"
#import "TKRVerificationMethod.h"

@interface TKRAttachResult : NSObject

@property(readonly) TKRStatus status;
@property(readonly, nullable) TKRVerificationMethod* method;

@end
