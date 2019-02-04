
#import <Foundation/Foundation.h>

#import "TKRTanker+Private.h"
#import "TKRUtils+Private.h"

#include <tanker.h>

#include <objc/runtime.h>

// https://stackoverflow.com/a/15707096/4116453
#define AntiARCRetain(value)                              \
  void* retained##value = (__bridge_retained void*)value; \
  (void)retained##value

@implementation TKRTanker (Private)

// http://nshipster.com/associated-objects/
@dynamic cTanker;
@dynamic events;

- (void)setCTanker:(void*)value
{
  objc_setAssociatedObject(self, @selector(cTanker), ptrToNumber(value), OBJC_ASSOCIATION_RETAIN);
}

- (void*)cTanker
{
  return numberToPtr(objc_getAssociatedObject(self, @selector(cTanker)));
}

- (void)setEvents:(NSMutableArray*)events
{
  objc_setAssociatedObject(self, @selector(events), events, OBJC_ASSOCIATION_RETAIN);
}

- (NSMutableArray*)events
{
  return objc_getAssociatedObject(self, @selector(events));
}

- (void)encryptDataFromDataImpl:(nonnull NSData*)clearData
                        options:(nonnull TKREncryptionOptions*)options
              completionHandler:(nonnull void (^)(PtrAndSizePair*, NSError*))handler
{
  uint64_t encrypted_size = tanker_encrypted_size(clearData.length);
  uint8_t* encrypted_buffer = (uint8_t*)malloc((unsigned long)encrypted_size);

  TKRAdapter adapter = ^(NSNumber* ptrValue, NSError* err) {
    // Force clearData to be retained until the tanker_future is done
    // to avoid reading a dangling pointer
    AntiARCRetain(clearData);

    if (err)
    {
      free(encrypted_buffer);
      handler(nil, err);
      return;
    }
    // So, why don't we use NSMutableData? It looks perfect for the job!
    //
    // NSMutableData is broken, every *WithNoCopy functions will copy and free the buffer you give to
    // it. In addition, giving freeWhenDone:YES will cause a double free and crash the program. We could create
    // the NSMutableData upfront and carry the internal pointer around, but it is not possible to retrieve the
    // pointer and tell NSMutableData to not free it anymore.
    //
    // So let's return a uintptr_t...
    PtrAndSizePair* hack = [[PtrAndSizePair alloc] init];
    hack.ptrValue = (uintptr_t)encrypted_buffer;
    hack.ptrSize = (NSUInteger)encrypted_size;
    handler(hack, nil);
  };

  if (!encrypted_buffer)
  {
    handler(nil, createNSError("could not allocate encrypted buffer", TKRErrorOther));
    return;
  }
  tanker_encrypt_options_t encryption_options = TANKER_ENCRYPT_OPTIONS_INIT;

  NSError* err = nil;
  char** user_ids = convertStringstoCStrings(options.shareWithUsers, &err);
  if (err)
  {
    handler(nil, err);
    return;
  }
  char** group_ids = convertStringstoCStrings(options.shareWithGroups, &err);
  if (err)
  {
    freeCStringArray(user_ids, options.shareWithUsers.count);
    handler(nil, err);
    return;
  }
  encryption_options.recipient_uids = (char const* const*)user_ids;
  encryption_options.nb_recipient_uids = (uint32_t)options.shareWithUsers.count;
  encryption_options.recipient_gids = (char const* const*)group_ids;
  encryption_options.nb_recipient_gids = (uint32_t)options.shareWithGroups.count;
  tanker_future_t* encrypt_future = tanker_encrypt((tanker_t*)self.cTanker,
                                                   encrypted_buffer,
                                                   (uint8_t const*)clearData.bytes,
                                                   clearData.length,
                                                   &encryption_options);
  tanker_future_t* resolve_future =
      tanker_future_then(encrypt_future, (tanker_future_then_t)&resolvePromise, (__bridge_retained void*)adapter);
  tanker_future_destroy(encrypt_future);
  tanker_future_destroy(resolve_future);
  freeCStringArray(user_ids, options.shareWithUsers.count);
  freeCStringArray(group_ids, options.shareWithGroups.count);
}

- (void)decryptDataFromDataImpl:(NSData*)cipherData
                        options:(TKRDecryptionOptions*)options
              completionHandler:(nonnull void (^)(PtrAndSizePair*, NSError*))handler
{
  uint8_t const* encrypted_buffer = (uint8_t const*)cipherData.bytes;
  uint64_t encrypted_size = cipherData.length;

  __block uint8_t* decrypted_buffer = nil;
  __block uint64_t decrypted_size = 0;

  TKRAdapter adapter = ^(NSNumber* ptrValue, NSError* err) {
    // Force cipherData to be retained until the tanker_future is done
    // to avoid reading a dangling pointer
    AntiARCRetain(cipherData);

    if (err)
    {
      free(decrypted_buffer);
      handler(nil, err);
      return;
    }
    PtrAndSizePair* hack = [[PtrAndSizePair alloc] init];
    hack.ptrValue = (uintptr_t)decrypted_buffer;
    hack.ptrSize = (NSUInteger)decrypted_size;
    handler(hack, nil);
  };

  tanker_expected_t* expected_decrypted_size = tanker_decrypted_size(encrypted_buffer, encrypted_size);
  decrypted_size = (uint64_t)unwrapAndFreeExpected(expected_decrypted_size);

  decrypted_buffer = (uint8_t*)malloc((unsigned long)decrypted_size);
  if (!decrypted_buffer)
  {
    handler(nil, createNSError("could not allocate decrypted buffer", TKRErrorOther));
    return;
  }
  tanker_decrypt_options_t opts = TANKER_DECRYPT_OPTIONS_INIT;
  opts.timeout = options.timeout * 1000;
  tanker_future_t* decrypt_future =
      tanker_decrypt((tanker_t*)self.cTanker, decrypted_buffer, encrypted_buffer, encrypted_size, &opts);
  // ensures cipherText lives while the promise does by telling ARC to retain it
  tanker_future_t* resolve_future =
      tanker_future_then(decrypt_future, (tanker_future_then_t)&resolvePromise, (__bridge_retained void*)adapter);
  tanker_future_destroy(decrypt_future);
  tanker_future_destroy(resolve_future);
}

- (nullable NSNumber*)setEvent:(nonnull NSNumber*)evt
                   callbackPtr:(nonnull NSNumber*)callbackPtr
                       handler:(nonnull TKRAbstractEventHandler)handler
                         error:(NSError* _Nullable* _Nonnull)error
{
  tanker_expected_t* connect_expected = tanker_event_connect((tanker_t*)self.cTanker,
                                                             (enum tanker_event)evt.integerValue,
                                                             (tanker_event_callback_t)numberToPtr(callbackPtr),
                                                             (__bridge_retained void*)handler);

  *error = getOptionalFutureError(connect_expected);
  if (*error)
    return nil;
  void* ptr = unwrapAndFreeExpected(connect_expected);
  NSNumber* ptrConnectionValue = [NSNumber numberWithUnsignedLongLong:(uintptr_t)ptr];
  [self.events addObject:ptrConnectionValue];
  return ptrConnectionValue;
}

- (void)disconnectEventConnection:(nonnull NSNumber*)ptrConnectionValue
{
  [self.events removeObject:ptrConnectionValue];
  tanker_connection_t* connection = (tanker_connection_t*)numberToPtr(ptrConnectionValue);
  tanker_expected_t* disconnect_expected = tanker_event_disconnect((tanker_t*)self.cTanker, connection);
  unwrapAndFreeExpected(disconnect_expected);
}

@end
