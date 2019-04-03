
#import "PromiseKit/Promise.h"
#import "TKRChunkEncryptor+Private.h"
#import "TKRTanker+Private.h"
#import "TKRUtils+Private.h"

#include <objc/runtime.h>
#include <stdint.h>
#include <stdlib.h>
#include <tanker.h>

// I prefer not to expose it in a private header, hence the copy
#define AntiARCRetain(value)                              \
  void* retained##value = (__bridge_retained void*)value; \
  (void)retained##value

@implementation TKRChunkEncryptor (Private)

@dynamic tanker;
@dynamic cChunkEncryptor;

// MARK: Voodoo associated objects methods

- (void)setTanker:(TKRTanker*)value
{
  objc_setAssociatedObject(self, @selector(tanker), value, OBJC_ASSOCIATION_RETAIN);
}

- (TKRTanker*)tanker
{
  return objc_getAssociatedObject(self, @selector(tanker));
}

- (void)setCChunkEncryptor:(void*)value
{
  objc_setAssociatedObject(self, @selector(cChunkEncryptor), ptrToNumber(value), OBJC_ASSOCIATION_RETAIN);
}

- (void*)cChunkEncryptor
{
  return numberToPtr(objc_getAssociatedObject(self, @selector(cChunkEncryptor)));
}

// MARK: Class methods
+ (nonnull PMKPromise*)chunkEncryptorWithTKRTanker:(nonnull TKRTanker*)tanker
                                              seal:(nullable NSData*)seal
                                           options:(nullable TKRDecryptionOptions*)options
{
  return [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
           tanker_future_t* chunk_encryptor_future = nil;
           if (!seal)
             chunk_encryptor_future = tanker_make_chunk_encryptor(tanker.cTanker);
           else
           {
             tanker_decrypt_options_t opts = TANKER_DECRYPT_OPTIONS_INIT;
             opts.timeout = options.timeout * 1000;
             chunk_encryptor_future =
                 tanker_make_chunk_encryptor_from_seal(tanker.cTanker, seal.bytes, seal.length, &opts);
           }
           tanker_future_t* resolve_future = tanker_future_then(
               chunk_encryptor_future, (tanker_future_then_t)&resolvePromise, (__bridge_retained void*)resolve);
           tanker_future_destroy(chunk_encryptor_future);
           tanker_future_destroy(resolve_future);
         }]
      .then(^(NSNumber* ptrValue) {
        AntiARCRetain(seal);
        tanker_chunk_encryptor_t* chunk_encryptor = numberToPtr(ptrValue);
        TKRChunkEncryptor* ret = [[TKRChunkEncryptor alloc] init];
        ret.tanker = tanker;
        ret.cChunkEncryptor = chunk_encryptor;
        return ret;
      });
}

// MARK: Instance methods
- (nonnull PMKPromise*)encryptDataFromDataImpl:(nonnull NSData*)clearData atIndex:(NSUInteger)index
{
  uint64_t encrypted_size = tanker_chunk_encryptor_encrypted_size(clearData.length);
  uint8_t* encrypted_buffer = (uint8_t*)malloc((unsigned long)encrypted_size);

  return
      [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
        if (!encrypted_buffer)
        {
          [NSException raise:NSMallocException format:@"could not allocate %lu bytes", (unsigned long)encrypted_size];
        }
        tanker_future_t* chunk_encrypt_future = tanker_chunk_encryptor_encrypt_at(
            self.cChunkEncryptor, encrypted_buffer, clearData.bytes, clearData.length, index);
        tanker_future_t* resolve_future = tanker_future_then(
            chunk_encrypt_future, (tanker_future_then_t)&resolvePromise, (__bridge_retained void*)resolve);
        tanker_future_destroy(chunk_encrypt_future);
        tanker_future_destroy(resolve_future);
      }]
          .catch(^(NSError* err) {
            free(encrypted_buffer);
            // let users write a .catch continuation by returning the NSError.
            return err;
          })
          .then(^{
            AntiARCRetain(clearData);

            PtrAndSizePair* hack = [[PtrAndSizePair alloc] init];
            hack.ptrValue = (uintptr_t)encrypted_buffer;
            hack.ptrSize = (NSUInteger)encrypted_size;
            return hack;
          });
}

- (nonnull PMKPromise*)sealImplWithOptions:(nonnull TKREncryptionOptions*)options
{
  uint64_t seal_size = tanker_chunk_encryptor_seal_size(self.cChunkEncryptor);
  __block uint8_t* seal_buffer = (uint8_t*)malloc(seal_size);
  return [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
           tanker_encrypt_options_t encryption_options = TANKER_ENCRYPT_OPTIONS_INIT;

           char** user_ids = convertStringstoCStrings(options.shareWithUsers);
           char** group_ids = convertStringstoCStrings(options.shareWithGroups);

           encryption_options.recipient_uids = (char const* const*)user_ids;
           encryption_options.nb_recipient_uids = (uint32_t)options.shareWithUsers.count;
           encryption_options.recipient_gids = (char const* const*)group_ids;
           encryption_options.nb_recipient_gids = (uint32_t)options.shareWithGroups.count;
           tanker_future_t* seal_future =
               tanker_chunk_encryptor_seal(self.cChunkEncryptor, seal_buffer, &encryption_options);
           tanker_future_t* resolve_future =
               tanker_future_then(seal_future, (tanker_future_then_t)&resolvePromise, (__bridge_retained void*)resolve);
           tanker_future_destroy(seal_future);
           tanker_future_destroy(resolve_future);
         }]
      .catch(^(NSError* err) {
        free(seal_buffer);
        return err;
      })
      .then(^{
        PtrAndSizePair* hack = [[PtrAndSizePair alloc] init];
        hack.ptrValue = ptrToNumber(seal_buffer).unsignedLongValue;
        hack.ptrSize = seal_size;
        return hack;
      });
}

- (nonnull PMKPromise*)decryptDataFromDataImpl:(nonnull NSData*)cipherData atIndex:(NSUInteger)index
{
  // declare here to be available in then/catch blocks.
  uint8_t const* encrypted_buffer = (uint8_t const*)cipherData.bytes;
  uint64_t encrypted_size = cipherData.length;

  __block uint8_t* decrypted_buffer = nil;
  __block uint64_t decrypted_size = 0;

  return
      [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
        tanker_expected_t* expected_decrypted_size =
            tanker_chunk_encryptor_decrypted_size(encrypted_buffer, encrypted_size);
        decrypted_size = (uint64_t)unwrapAndFreeExpected(expected_decrypted_size);

        decrypted_buffer = (uint8_t*)malloc((unsigned long)decrypted_size);
        if (!decrypted_buffer)
        {
          [NSException raise:NSMallocException format:@"could not allocate %lu bytes", (unsigned long)decrypted_size];
        }

        tanker_future_t* decrypt_chunk_future = tanker_chunk_encryptor_decrypt(
            self.cChunkEncryptor, decrypted_buffer, encrypted_buffer, encrypted_size, index);
        tanker_future_t* resolve_future = tanker_future_then(
            decrypt_chunk_future, (tanker_future_then_t)&resolvePromise, (__bridge_retained void*)resolve);
        tanker_future_destroy(decrypt_chunk_future);
        tanker_future_destroy(resolve_future);
      }]
          .catch(^(NSError* err) {
            if (decrypted_buffer)
              free(decrypted_buffer);
            return err;
          })
          .then(^{
            AntiARCRetain(cipherData);

            PtrAndSizePair* hack = [[PtrAndSizePair alloc] init];
            hack.ptrValue = (uintptr_t)decrypted_buffer;
            hack.ptrSize = (NSUInteger)decrypted_size;
            return hack;
          });
}

@end
