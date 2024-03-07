#import <Foundation/Foundation.h>

#import <Tanker/TKRVerificationMethod.h>

typedef NS_ENUM(NSUInteger, TKRStatus);

@interface TKRAttachResult : NSObject

@property(readonly) TKRStatus status;
@property(readonly, nullable) TKRVerificationMethod* method;

@end
