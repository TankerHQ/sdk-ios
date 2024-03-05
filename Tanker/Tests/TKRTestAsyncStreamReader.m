#import "TKRTestAsyncStreamReader.h"

#import <PromiseKit/PromiseKit.h>

@interface TKRTestAsyncStreamReader ()

@property NSMutableData* buffer;
@property NSInteger totalRead;
@property PMKResolver resolver;

@end

@implementation TKRTestAsyncStreamReader

- (PMKPromise<NSData*>*)readAll:(NSInputStream*)aStream
{
  self.buffer = [NSMutableData dataWithLength:4096];
  self.totalRead = 0;
  aStream.delegate = self;
  [aStream open];
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    NSRunLoop* runLoop = [NSRunLoop currentRunLoop];
    [aStream scheduleInRunLoop:runLoop forMode:NSDefaultRunLoopMode];
    [runLoop run];
  });

  return [PMKPromise promiseWithResolver:^(PMKResolver resolver) {
    self.resolver = resolver;
  }];
}

- (void)stream:(NSStream*)aStream handleEvent:(NSStreamEvent)eventCode
{
  switch (eventCode)
  {
  case NSStreamEventHasBytesAvailable:
  {
    [self.buffer increaseLengthBy:1024 * 1024];
    NSInputStream* input = (NSInputStream*)aStream;
    NSInteger nbRead = [input read:(self.buffer.mutableBytes + self.totalRead) maxLength:1024 * 1024];
    if (nbRead < 0) {
      [aStream close];
      self.resolver(aStream.streamError);
      break;
    }
    
    self.totalRead += nbRead;
    self.buffer.length = self.totalRead;
  }
  break;
  case NSStreamEventEndEncountered:
    [aStream close];
    self.resolver(self.buffer);
    break;
  case NSStreamEventErrorOccurred:
    [aStream close];
    self.resolver(aStream.streamError);
    break;
  case NSStreamEventOpenCompleted:
    break;
  default:
    break;
  }
}

@end
