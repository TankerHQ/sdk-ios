#import <Foundation/Foundation.h>

#import <PromiseKit/PromiseKit.h>

@interface TKRTestAsyncStreamReader : NSObject <NSStreamDelegate>

- (PMKPromise<NSData*>*)readAll:(NSInputStream*)aStream;

@end
