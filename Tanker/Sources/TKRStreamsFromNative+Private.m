#import <Foundation/Foundation.h>
#import <Foundation/NSStream.h>
#import <objc/runtime.h>

#import <Tanker/TKRError.h>
#import <Tanker/TKRStreamsFromNative+Private.h>
#import <Tanker/Utils/TKRUtils.h>
 
@interface TKRStreamsFromNative () <NSStreamDelegate> {
  tanker_stream_t* _Nullable cstream;
  TKRAsyncStreamReader* _Nonnull reader;

  @public BOOL hasBytesAvailable;
  tanker_future_t* bytes_available_fut;
}

- (void)triggerCTankerRead;

@end

static void* finishTankerRead(tanker_future_t* fut, void* data)
{
  TKRStreamsFromNative* source = (__bridge_transfer TKRStreamsFromNative*)data;

  TKR_runOnMainQueue(^{
    if ([source streamStatus] == NSStreamStatusAtEnd)
      return;
    source->hasBytesAvailable = YES;
    [source enqueueEvent:NSStreamEventHasBytesAvailable];
  });
  return nil;
}

@implementation TKRStreamsFromNative

#pragma mark - TKRStreamsFromNative

+ (nullable instancetype)streamsFromNativeWithCStream:(nonnull tanker_stream_t*)cstream
                                          asyncReader:(nonnull TKRAsyncStreamReader*)reader
{
  return [[TKRStreamsFromNative alloc] initWithCStream:cstream asyncReader:reader];
}

- (nullable instancetype)initWithCStream:(nonnull tanker_stream_t*)cstream
                             asyncReader:(nonnull TKRAsyncStreamReader*)reader
{
  if (self = [super init])
  {
    self->cstream = cstream;
    self->reader = reader;
    self->bytes_available_fut = nil;
  }
  return self;
}

- (void)dealloc {
  tanker_future_destroy(self->bytes_available_fut);
}

- (void)triggerCTankerRead
{
  // reading 0 will either:
  // - return immediately 0
  // - read the next chunk of input, and return 0
  // this is needed to be signaled when bytes are available
  tanker_future_t* read_fut = tanker_stream_read(self->cstream, nil, 0);
  tanker_future_destroy(self->bytes_available_fut);
  self->bytes_available_fut = tanker_future_then(read_fut, &finishTankerRead, (__bridge_retained void*)self);
  tanker_future_destroy(read_fut);
}


#pragma mark - NSInputStream

- (NSInteger)read:(uint8_t *)buffer maxLength:(NSUInteger)maxLength {
  if (![self isOpen]) {
    NSLog(@"%@: Stream is not open, status %ld.", self, (long)[self streamStatus]);
    return -1;
  }
  if ([self streamStatus] == NSStreamStatusAtEnd) {
    return 0;
  }
  
  if (maxLength > NSIntegerMax)
  {
    [self setError:TKR_createNSError(TKRErrorInvalidArgument, @"Attempting to read more than NSIntegerMax")];
    return -1;
  }
  
  assert(self->bytes_available_fut);
  // this future is always ready when read is called due to hasBytesAvailable being set to YES.
  // when run synchronously, the thread is blocked until bytes are available
  tanker_future_wait(self->bytes_available_fut);
  tanker_future_t* read_future = tanker_stream_read(self->cstream, buffer, (int64_t)maxLength);
  tanker_future_wait(read_future);
  NSError* err = TKR_getOptionalFutureError(read_future);
  if (err)
  {
    // Was it caused by the underlying input stream? If so, just keep the original error
    if (self->reader.stream.streamError)
      [self setError:self->reader.stream.streamError];
    else
      [self setError:err];
    return -1;
  }

  void* ptr = tanker_future_get_voidptr(read_future);
  tanker_future_destroy(read_future);
  NSInteger nbRead = (NSInteger)(intptr_t)ptr;
  self->hasBytesAvailable = NO;
  if (nbRead == 0)
  {
    tanker_future_destroy(tanker_stream_close(self->cstream));
    self->cstream = nil;
    [self setStatus:NSStreamStatusAtEnd];
    [self enqueueEvent:NSStreamEventEndEncountered];
  }
  else
    [self triggerCTankerRead];
  return nbRead;
}

- (BOOL)hasBytesAvailable {
  if (![self isOpen]) {
    return NO;
  }
  
  return self->hasBytesAvailable;
}

#pragma mark - NSStream

- (void)open {
  if ([self streamStatus] != NSStreamStatusNotOpen) {
    NSLog(@"%@: stream already open", self);
    return;
  }
  [super open];
  
  self->hasBytesAvailable = NO;
  [self triggerCTankerRead];
}

- (void)close {
  if (![self isOpen])
    return;
  [super close];
}

@end
