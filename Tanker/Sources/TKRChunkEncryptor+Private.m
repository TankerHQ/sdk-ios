
#import "TKRChunkEncryptor+Private.h"
#import "TKRError.h"
#import "TKRTanker+Private.h"
#import "TKRUtils+Private.h"

#include <objc/runtime.h>
#include <stdint.h>
#include <stdlib.h>
#include "ctanker.h"

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
+ (void)chunkEncryptorWithTKRTanker:(nonnull TKRTanker*)tanker
                               seal:(nullable NSData*)seal
                            options:(nullable TKRDecryptionOptions*)options
                  completionHandler:(nonnull void (^)(TKRChunkEncryptor*, NSError*))handler
{
  tanker_future_t* chunk_encryptor_future = nil;
  if (!seal)
    chunk_encryptor_future = tanker_make_chunk_encryptor(tanker.cTanker);
  else
  {
    tanker_decrypt_options_t opts = TANKER_DECRYPT_OPTIONS_INIT;
    opts.timeout = options.timeout * 1000;
    chunk_encryptor_future = tanker_make_chunk_encryptor_from_seal(tanker.cTanker, seal.bytes, seal.length, &opts);
  }

  TKRAdapter adapter = ^(NSNumber* ptrValue, NSError* err) {
    // Need to retain the seal to avoid reading a dangling pointer in the C code.
    AntiARCRetain(seal);
    if (err)
    {
      handler(nil, err);
      return;
    }
    tanker_chunk_encryptor_t* chunk_encryptor = numberToPtr(ptrValue);
    TKRChunkEncryptor* ret = [[TKRChunkEncryptor alloc] init];
    ret.tanker = tanker;
    ret.cChunkEncryptor = chunk_encryptor;
    handler(ret, nil);
  };
  tanker_future_t* resolve_future = tanker_future_then(
      chunk_encryptor_future, (tanker_future_then_t)&resolvePromise, (__bridge_retained void*)adapter);
  tanker_future_destroy(chunk_encryptor_future);
  tanker_future_destroy(resolve_future);
}

// MARK: Instance methods
- (void)encryptDataFromDataImpl:(nonnull NSData*)clearData
                        atIndex:(NSUInteger)index
              completionHandler:(nonnull void (^)(PtrAndSizePair*, NSError*))handler
{
  uint64_t encrypted_size = tanker_chunk_encryptor_encrypted_size(clearData.length);
  uint8_t* encrypted_buffer = (uint8_t*)malloc((unsigned long)encrypted_size);

  if (!encrypted_buffer)
  {
    runOnMainQueue(^{
      handler(nil, createNSError("could not allocate encrypted buffer", TKRErrorOther));
    });
    return;
  }

  TKRAdapter adapter = ^(NSNumber* ptrValue, NSError* err) {
    if (err)
    {
      free(encrypted_buffer);
      handler(nil, err);
      return;
    }
    PtrAndSizePair* hack = [[PtrAndSizePair alloc] init];
    hack.ptrValue = ptrToNumber(encrypted_buffer).unsignedLongValue;
    hack.ptrSize = encrypted_size;
    handler(hack, nil);
  };
  tanker_future_t* chunk_encrypt_future = tanker_chunk_encryptor_encrypt_at(
      self.cChunkEncryptor, encrypted_buffer, clearData.bytes, clearData.length, index);
  tanker_future_t* resolve_future =
      tanker_future_then(chunk_encrypt_future, (tanker_future_then_t)&resolvePromise, (__bridge_retained void*)adapter);
  tanker_future_destroy(chunk_encrypt_future);
  tanker_future_destroy(resolve_future);
}

- (void)sealImplWithOptions:(nonnull TKREncryptionOptions*)options
          completionHandler:(nonnull void (^)(PtrAndSizePair*, NSError*))handler
{
  uint64_t seal_size = tanker_chunk_encryptor_seal_size(self.cChunkEncryptor);
  uint8_t* seal_buffer = (uint8_t*)malloc(seal_size);

  if (!seal_buffer)
  {
    runOnMainQueue(^{
      handler(nil, createNSError("could not allocate seal buffer", TKRErrorOther));
    });
    return;
  }

  TKRAdapter adapter = ^(NSNumber* ptrValue, NSError* err) {
    if (err)
    {
      free(seal_buffer);
      handler(nil, err);
      return;
    }
    PtrAndSizePair* hack = [[PtrAndSizePair alloc] init];
    hack.ptrValue = ptrToNumber(seal_buffer).unsignedLongValue;
    hack.ptrSize = seal_size;
    handler(hack, nil);
  };

  tanker_encrypt_options_t encryption_options = TANKER_ENCRYPT_OPTIONS_INIT;

  NSError* err = nil;
  char** user_ids = convertStringstoCStrings(options.shareWithUsers, &err);
  if (err)
  {
    runOnMainQueue(^{
      handler(nil, err);
    });
    return;
  }
  char** group_ids = convertStringstoCStrings(options.shareWithGroups, &err);
  if (err)
  {
    freeCStringArray(user_ids, options.shareWithUsers.count);
    runOnMainQueue(^{
      handler(nil, err);
    });
    return;
  }
  encryption_options.recipient_uids = (char const* const*)user_ids;
  encryption_options.nb_recipient_uids = (uint32_t)options.shareWithUsers.count;
  encryption_options.recipient_gids = (char const* const*)group_ids;
  encryption_options.nb_recipient_gids = (uint32_t)options.shareWithGroups.count;
  tanker_future_t* seal_future = tanker_chunk_encryptor_seal(self.cChunkEncryptor, seal_buffer, &encryption_options);
  tanker_future_t* resolve_future =
      tanker_future_then(seal_future, (tanker_future_then_t)&resolvePromise, (__bridge_retained void*)adapter);
  tanker_future_destroy(seal_future);
  tanker_future_destroy(resolve_future);
  freeCStringArray(user_ids, options.shareWithUsers.count);
  freeCStringArray(group_ids, options.shareWithGroups.count);
}

- (void)decryptDataFromDataImpl:(nonnull NSData*)cipherData
                        atIndex:(NSUInteger)index
              completionHandler:(nonnull void (^)(PtrAndSizePair*, NSError*))handler
{
  // declare here to be available in then/catch blocks.
  uint8_t const* encrypted_buffer = (uint8_t const*)cipherData.bytes;
  uint64_t encrypted_size = cipherData.length;

  tanker_expected_t* expected_decrypted_size = tanker_chunk_encryptor_decrypted_size(encrypted_buffer, encrypted_size);
  uint64_t decrypted_size = (uint64_t)unwrapAndFreeExpected(expected_decrypted_size);

  uint8_t* decrypted_buffer = (uint8_t*)malloc((unsigned long)decrypted_size);
  if (!decrypted_buffer)
  {
    runOnMainQueue(^{
      handler(nil, createNSError("could not allocate decrypted buffer", TKRErrorOther));
    });
    return;
  }

  TKRAdapter adapter = ^(NSNumber* ptrValue, NSError* err) {
    if (err)
    {
      free(decrypted_buffer);
      handler(nil, err);
      return;
    }
    PtrAndSizePair* hack = [[PtrAndSizePair alloc] init];
    hack.ptrValue = ptrToNumber(decrypted_buffer).unsignedLongValue;
    hack.ptrSize = decrypted_size;
    handler(hack, nil);
  };

  tanker_future_t* decrypt_chunk_future =
      tanker_chunk_encryptor_decrypt(self.cChunkEncryptor, decrypted_buffer, encrypted_buffer, encrypted_size, index);
  tanker_future_t* resolve_future =
      tanker_future_then(decrypt_chunk_future, (tanker_future_then_t)&resolvePromise, (__bridge_retained void*)adapter);
  tanker_future_destroy(decrypt_chunk_future);
  tanker_future_destroy(resolve_future);
}

@end
