#import <Tanker/TKRAsyncStreamReader+Private.h>
#import <Tanker/TKREncryptionSession+Private.h>
#import <Tanker/TKRError.h>
#import <Tanker/TKRInputStreamDataSource+Private.h>
#import <Tanker/TKRTanker+Private.h>
#import <Tanker/Utils/TKRUtils.h>

#include "ctanker/encryptionsession.h"

@implementation TKREncryptionSession

// MARK: Instance methods

- (NSString*)resourceID
{
  tanker_expected_t* resource_id_expected =
      tanker_encryption_session_get_resource_id((tanker_encryption_session_t*)self.cSession);
  char* resource_id = TKR_unwrapAndFreeExpected(resource_id_expected);
  NSString* ret = [NSString stringWithCString:resource_id encoding:NSUTF8StringEncoding];
  tanker_free_buffer(resource_id);
  return ret;
}

- (void)encryptString:(nonnull NSString*)clearText completionHandler:(nonnull TKREncryptedDataHandler)handler
{
  NSError* err = nil;
  NSData* data = TKR_convertStringToData(clearText, &err);

  if (err)
    TKR_runOnMainQueue(^{
      handler(nil, err);
    });
  else
    [self encryptData:data completionHandler:handler];
}

- (void)encryptData:(nonnull NSData*)clearData completionHandler:(nonnull TKREncryptedDataHandler)handler
{
  id adapter = ^(TKRPtrAndSizePair* hack, NSError* err) {
    if (err)
    {
      handler(nil, err);
      return;
    }
    uint8_t* encrypted_buffer = (uint8_t*)((uintptr_t)hack.ptrValue);

    NSData* ret = [NSData dataWithBytesNoCopy:encrypted_buffer length:hack.ptrSize freeWhenDone:YES];
    handler(ret, nil);
  };
  [self encryptDataImpl:clearData completionHandler:adapter];
}

- (void)dealloc
{
  tanker_future_t* close_future = tanker_encryption_session_close((tanker_encryption_session_t*)self.cSession);
  tanker_future_wait(close_future);
  tanker_future_destroy(close_future);
}

- (void)encryptStream:(nonnull NSInputStream*)clearStream completionHandler:(nonnull TKRInputStreamHandler)handler
{
  if (clearStream.streamStatus != NSStreamStatusNotOpen)
  {
    handler(nil,
            TKR_createNSError(
                TKRErrorDomain, @"Input stream status must be NSStreamStatusNotOpen", TKRErrorInvalidArgument));
    return;
  }

  TKRAsyncStreamReader* reader = [TKRAsyncStreamReader readerWithStream:clearStream];
  clearStream.delegate = reader;
  // The main run loop is the only run loop that runs automatically
  NSRunLoop* runLoop = [NSRunLoop mainRunLoop];
  [clearStream scheduleInRunLoop:runLoop forMode:NSDefaultRunLoopMode];
  [clearStream open];

  tanker_future_t* stream_fut = tanker_encryption_session_stream_encrypt((tanker_encryption_session_t*)self.cSession,
                                                                         (tanker_stream_input_source_t)&readInput,
                                                                         (__bridge_retained void*)reader);
  completeStreamEncrypt(reader, stream_fut, handler);
  tanker_future_destroy(stream_fut);
}

@end
