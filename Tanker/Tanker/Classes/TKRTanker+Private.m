
#import <Foundation/Foundation.h>

#import "PromiseKit.h"
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

- (nonnull PMKPromise<NSData*>*)encryptDataFromDataImpl:(nonnull NSData*)clearData
                                                options:(nonnull TKREncryptionOptions*)options
{
  uint64_t encrypted_size = tanker_encrypted_size(clearData.length);
  uint8_t* encrypted_buffer = (uint8_t*)malloc((unsigned long)encrypted_size);

  return
      [PMKPromise promiseWithAdapter:^(PMKAdapter resolve) {
        if (!encrypted_buffer)
        {
          [NSException raise:NSMallocException format:@"could not allocate %lu bytes", (unsigned long)encrypted_size];
        }

        tanker_encrypt_options_t encryption_options = TANKER_ENCRYPT_OPTIONS_INIT;

        char** user_ids = convertStringstoCStrings(options.shareWithUsers);
        char** group_ids = convertStringstoCStrings(options.shareWithGroups);

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
            tanker_future_then(encrypt_future, (tanker_future_then_t)&resolvePromise, (__bridge_retained void*)resolve);
        tanker_future_destroy(encrypt_future);
        tanker_future_destroy(resolve_future);
        for (int i = 0; i < options.shareWithUsers.count; ++i)
          free(user_ids[i]);
        free(user_ids);
        for (int i = 0; i < options.shareWithGroups.count; ++i)
          free(group_ids[i]);
        free(group_ids);
      }]
          .catch(^(NSError* err) {
            free(encrypted_buffer);
            // let users write a .catch continuation by returning the NSError.
            return err;
          })
          .then(^{
            // Force clearData to be retained until the tanker_future is done
            // to avoid reading a dangling pointer
            AntiARCRetain(clearData);
            // no need to retain userIDs since tanker will copy them.

            // See decryptDataFromDataImpl for more info on this.
            PtrAndSizePair* hack = [[PtrAndSizePair alloc] init];
            hack.ptrValue = (uintptr_t)encrypted_buffer;
            hack.ptrSize = (NSUInteger)encrypted_size;
            return hack;
          });
}

- (nonnull PMKPromise<NSData*>*)decryptDataFromDataImpl:(nonnull NSData*)cipherData
                                                options:(nonnull TKRDecryptionOptions*)options
{
  // declare here to be available in then/catch blocks.
  uint8_t const* encrypted_buffer = (uint8_t const*)cipherData.bytes;
  uint64_t encrypted_size = cipherData.length;

  __block uint8_t* decrypted_buffer = nil;
  __block uint64_t decrypted_size = 0;

  return
      [PMKPromise promiseWithAdapter:^(PMKAdapter resolve) {
        tanker_expected_t* expected_decrypted_size = tanker_decrypted_size(encrypted_buffer, encrypted_size);
        decrypted_size = (uint64_t)unwrapAndFreeExpected(expected_decrypted_size);

        decrypted_buffer = (uint8_t*)malloc((unsigned long)decrypted_size);
        if (!decrypted_buffer)
        {
          [NSException raise:NSMallocException format:@"could not allocate %lu bytes", (unsigned long)decrypted_size];
        }

        tanker_decrypt_options_t opts = TANKER_DECRYPT_OPTIONS_INIT;
        opts.timeout = options.timeout * 1000;
        tanker_future_t* decrypt_future =
            tanker_decrypt((tanker_t*)self.cTanker, decrypted_buffer, encrypted_buffer, encrypted_size, &opts);
        // ensures cipherText lives while the promise does by telling ARC to retain it
        tanker_future_t* resolve_future =
            tanker_future_then(decrypt_future, (tanker_future_then_t)&resolvePromise, (__bridge_retained void*)resolve);
        tanker_future_destroy(decrypt_future);
        tanker_future_destroy(resolve_future);
      }]
          .catch(^(NSError* err) {
            free(decrypted_buffer);
            return err;
          })
          .then(^{
            // Force cipherData to be retained until the tanker_future is done
            // to avoid reading a dangling pointer
            AntiARCRetain(cipherData);

            // So, why don't we use NSMutableData? It looks perfect for the job!
            //
            // NSMutableData is broken, every *WithNoCopy functions will copy and free the buffer you give to
            // it. In addition, giving freeWhenDone:YES will cause a double free and crash the program. We could create
            // the NSMutableData upfront and carry the internal pointer around, but it is not possible to retrieve the
            // pointer and tell NSMutableData to not free it anymore.
            //
            // So let's return a uintptr_t...
            PtrAndSizePair* hack = [[PtrAndSizePair alloc] init];
            hack.ptrValue = (uintptr_t)decrypted_buffer;
            hack.ptrSize = (NSUInteger)decrypted_size;
            return hack;
          });
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
