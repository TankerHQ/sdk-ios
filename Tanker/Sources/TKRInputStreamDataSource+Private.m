#import <Foundation/Foundation.h>

#import <Tanker/TKRError.h>
#import <Tanker/TKRInputStreamDataSource+Private.h>
#import <Tanker/TKRUtils+Private.h>

@interface TKRInputStreamDataSource ()

@property NSError* error;
@property(getter=isOpenCompleted) BOOL openCompleted;
@property BOOL hasBytesAvailable;
@property(getter=isAtEnd) BOOL atEnd;

@property(nullable) tanker_future_t* bytes_available_fut;

- (void)triggerCTankerRead;

@end

static void* signalBytesAvailable(tanker_future_t* fut, void* data)
{
  TKRInputStreamDataSource* source = (__bridge_transfer TKRInputStreamDataSource*)data;

  TKR_runOnMainQueue(^{
    if (!source.atEnd)
      source.hasBytesAvailable = YES;
  });
  return nil;
}

@implementation TKRInputStreamDataSource

+ (nullable instancetype)inputStreamDataSourceWithCStream:(nonnull tanker_stream_t*)stream
                                              asyncReader:(nonnull TKRAsyncStreamReader*)reader
{
  return [[TKRInputStreamDataSource alloc] initWithCStream:stream asyncReader:reader];
}

- (nullable instancetype)initWithCStream:(nonnull tanker_stream_t*)stream
                             asyncReader:(nonnull TKRAsyncStreamReader*)reader
{
  if (self = [super init])
  {
    self.stream = stream;
    self.reader = reader;
    self.bytes_available_fut = nil;
  }
  return self;
}

- (void)triggerCTankerRead
{
  // reading 0 will either:
  // - return immediately 0
  // - read the next chunk of input, and return 0
  // this is needed to be signaled when bytes are available
  tanker_future_t* read_fut = tanker_stream_read(self.stream, nil, 0);
  tanker_future_destroy(self.bytes_available_fut);
  self.bytes_available_fut = tanker_future_then(read_fut, &signalBytesAvailable, (__bridge_retained void*)self);
  tanker_future_destroy(read_fut);
}

- (BOOL)getBuffer:(uint8_t**)buffer length:(NSUInteger*)bufferLength
{
  return NO;
}

- (void)open
{
  self.hasBytesAvailable = NO;
  self.openCompleted = YES;
  [self triggerCTankerRead];
}

- (id)propertyForKey:(NSString*)key
{
  return nil;
}

- (NSInteger)read:(uint8_t*)buffer maxLength:(NSUInteger)maxLength
{
  // POSInputStreamLibrary errors when reading a closed stream, this function cannot be called in this state.
  assert(self.stream != nil);

  if (maxLength > NSIntegerMax)
  {
    self.error = TKR_createNSError(TKRErrorDomain, @"Attempting to read more than NSIntegerMax", TKRErrorInvalidArgument);
    return -1;
  }
  assert(self.bytes_available_fut);
  // this future is always ready when read is called due to hasBytesAvailable being set to YES.
  // when run synchronously, the thread is blocked until bytes are available
  tanker_future_wait(self.bytes_available_fut);
  tanker_future_t* read_future = tanker_stream_read(self.stream, buffer, (int64_t)maxLength);
  tanker_future_wait(read_future);
  NSError* err = TKR_getOptionalFutureError(read_future);
  if (err)
  {
    // Was it caused by the underlying input stream? If so, just keep the original error
    if (self.reader.stream.streamError)
      self.error = self.reader.stream.streamError;
    else
      self.error = err;
    return -1;
  }

  void* ptr = tanker_future_get_voidptr(read_future);
  tanker_future_destroy(read_future);
  NSInteger nbRead = (NSInteger)(intptr_t)ptr;
  self.hasBytesAvailable = NO;
  if (nbRead == 0)
  {
    tanker_future_destroy(tanker_stream_close(self.stream));
    self.stream = nil;
    self.atEnd = YES;
  }
  else
    [self triggerCTankerRead];
  return nbRead;
}

- (BOOL)setProperty:(id)property forKey:(NSString*)key
{
  return NO;
}

- (void)dealloc
{
  tanker_future_destroy(self.bytes_available_fut);
}

@end
