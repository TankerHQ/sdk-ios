
#import "TKRAsyncStreamReader+Private.h"

@implementation TKRAsyncStreamReader

+ (nullable instancetype)readerWithStream:(nonnull NSInputStream*)stream
{
  return [[TKRAsyncStreamReader alloc] initWithStream:stream];
}

- (nullable instancetype)initWithStream:(nonnull NSInputStream*)stream
{
  if (self = [super init])
  {
    self.stream = stream;
    self.cOp = nil;
    self.cOut = nil;
    self.cSize = 0;
  }
  return self;
}

- (void)performRead:(nonnull uint8_t*)out
          maxLength:(int64_t)len
      readOperation:(nonnull tanker_stream_read_operation_t*)op;
{
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    tanker_stream_read_operation_finish(op, [self.stream read:out maxLength:(NSUInteger)len]);
  });
}

- (void)stream:(NSStream*)aStream handleEvent:(NSStreamEvent)eventCode
{
  switch (eventCode)
  {
  // since this method and readInput (in TKRTanker.m) are run on different threads
  // we have to wait for the latter to set the c* properties before performing anything
  case NSStreamEventHasBytesAvailable:
  {
    if (self.cOp && self.cOut)
    {
      [self performRead:self.cOut maxLength:self.cSize readOperation:self.cOp];
      self.cOut = nil;
      self.cOp = nil;
      self.cSize = 0;
    }
  }
  break;
  case NSStreamEventEndEncountered:
  {
    if (self.cOp && self.cOut)
    {
      tanker_stream_read_operation_finish(self.cOp, 0);
      self.cOut = nil;
      self.cOp = nil;
      self.cSize = 0;
    }
    [aStream close];
  }
  break;
  case NSStreamEventErrorOccurred:
  {
    if (self.cOp && self.cOut)
    {
      tanker_stream_read_operation_finish(self.cOp, -1);
      self.cOut = nil;
      self.cOp = nil;
      self.cSize = 0;
    }
    [aStream close];
  }
  break;
  case NSStreamEventOpenCompleted:
    break;
  default:
    break;
  }
}

@end
