
#import "TKRAsyncStreamReader+Private.h"
#import "TKRUtils+Private.h"

void readInput(uint8_t* _Nonnull out, int64_t n, tanker_stream_read_operation_t* _Nonnull op, void* _Nonnull additional_data)
{
  // do not __bridge_transfer now, this method will be called numerous times
  TKRAsyncStreamReader* reader = (__bridge typeof(TKRAsyncStreamReader*))additional_data;

  // dispatch on main queue since streams are scheduled on it
  runOnMainQueue(^{
    if (reader.stream.hasBytesAvailable)
      [reader performRead:out maxLength:n readOperation:op];
    else
    {
      if (reader.stream.streamStatus == NSStreamStatusClosed)
      {
        if (reader.stream.streamError)
          tanker_stream_read_operation_finish(op, -1);
        else
          tanker_stream_read_operation_finish(op, 0);
        // now we can release the reader created in encryptStream/decryptStream
        (void)(__bridge_transfer TKRAsyncStreamReader*) additional_data;
      }
      reader.cOut = out;
      reader.cSize = n;
      reader.cOp = op;
    }
  });
}

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
  // Two possible cases:
  // - If Tanker asks for data when there is no bytes available, it sets cOp/cOut and we'll read it in this function
  // later on.
  // - If there is data available but Tanker did not ask for input yet, we do nothing here and when Tanker reads,
  // the readInput function (TKRTanker.m) will call performRead
  //
  // Precondition: There is always at most one read operation at the same time.
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
