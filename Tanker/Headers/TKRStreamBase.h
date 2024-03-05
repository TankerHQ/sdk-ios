#import <Foundation/Foundation.h>
#import <Foundation/NSStream.h>

@interface TKRStreamBase : NSInputStream <NSStreamDelegate>
- (id)init;
- (BOOL)isOpen;
- (void)setStatus:(NSStreamStatus)aStatus;
- (void)setError:(NSError *)anError;
- (void)enqueueEvent:(NSStreamEvent)event;
@end
