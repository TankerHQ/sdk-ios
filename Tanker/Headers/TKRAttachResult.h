#import <Foundation/Foundation.h>

#import <Tanker/TKRVerificationMethod.h>

typedef NS_ENUM(NSUInteger, TKRStatus);

NS_SWIFT_NAME(AttachResult)
@interface TKRAttachResult : NSObject

@property(readonly) TKRStatus status;
@property(readonly, nullable) TKRVerificationMethod* method;

@end
