
#import <Foundation/Foundation.h>

#import <Tanker/TKRError.h>
#import <Tanker/TKRStreamsFromNative+Private.h>
#import <Tanker/TKRTanker+Private.h>
#import <Tanker/Utils/TKRUtils.h>
#import <Tanker/TKRSwift+Private.h>

#include <Tanker/ctanker.h>

#include <objc/runtime.h>

static void releaseCPointer(void* ptr)
{
  (void)((__bridge_transfer id)ptr);
}

NSError* _Nullable convertEncryptionOptions(TKREncryptionOptions* _Nonnull opts, void* _Nonnull c_opts_ptr)
{
  NSError* err = nil;
  char** recipient_public_identities = TKR_convertStringstoCStrings(opts.shareWithUsers, &err);
  if (err)
    return err;
  char** group_ids = TKR_convertStringstoCStrings(opts.shareWithGroups, &err);
  if (err)
  {
    TKR_freeCStringArray(recipient_public_identities, opts.shareWithUsers.count);
    return err;
  }
  tanker_encrypt_options_t* c_opts = (tanker_encrypt_options_t*)c_opts_ptr;
  c_opts->share_with_users = (char const* const*)recipient_public_identities;
  c_opts->nb_users = (uint32_t)opts.shareWithUsers.count;
  c_opts->share_with_groups = (char const* const*)group_ids;
  c_opts->nb_groups = (uint32_t)opts.shareWithGroups.count;
  c_opts->share_with_self = opts.shareWithSelf;
  c_opts->padding_step = opts.paddingStep.nativeValue.unsignedIntValue;
  return nil;
}

NSError* _Nullable convertSharingOptions(TKRSharingOptions* _Nonnull opts, void* _Nonnull c_opts_ptr)
{
  NSError* err = nil;
  char** recipient_public_identities = TKR_convertStringstoCStrings(opts.shareWithUsers, &err);
  if (err)
    return err;
  char** group_ids = TKR_convertStringstoCStrings(opts.shareWithGroups, &err);
  if (err)
  {
    TKR_freeCStringArray(recipient_public_identities, opts.shareWithUsers.count);
    return err;
  }
  tanker_sharing_options_t* c_opts = (tanker_sharing_options_t*)c_opts_ptr;
  c_opts->share_with_users = (char const* const*)recipient_public_identities;
  c_opts->nb_users = (uint32_t)opts.shareWithUsers.count;
  c_opts->share_with_groups = (char const* const*)group_ids;
  c_opts->nb_groups = (uint32_t)opts.shareWithGroups.count;
  return nil;
}

void completeStreamEncrypt(TKRAsyncStreamReader* _Nonnull reader,
                           tanker_future_t* _Nonnull streamFut,
                           TKRInputStreamHandler _Nonnull handler)
{
  TKRAdapter adapter = ^(NSNumber* ptrValue, NSError* err) {
    if (err)
    {
      handler(nil, err);
      return;
    }
    tanker_stream_t* stream = TKR_numberToPtr(ptrValue);
    TKRStreamsFromNative* encryptionStream = [[TKRStreamsFromNative alloc] initWithCStream:stream asyncReader:reader];
    handler(encryptionStream, nil);
  };

  tanker_future_t* resolve_fut =
      tanker_future_then(streamFut, (tanker_future_then_t)&TKR_resolvePromise, (__bridge_retained void*)adapter);
  tanker_future_destroy(resolve_fut);
}

@implementation TKRTanker (Private)

- (void)encryptDataImpl:(nonnull NSData*)clearData
                options:(nonnull TKREncryptionOptions*)options
      completionHandler:(nonnull void (^)(TKRPtrAndSizePair* _Nullable, NSError* _Nullable))handler
{
  uint64_t encrypted_size = tanker_encrypted_size(clearData.length, options.paddingStep.nativeValue.unsignedIntValue);
  uint8_t* encrypted_buffer = (uint8_t*)malloc((unsigned long)encrypted_size);

  if (!encrypted_buffer)
  {
    handler(nil, TKR_createNSErrorWithDomain(NSPOSIXErrorDomain, ENOMEM, @"could not allocate encrypted buffer"));
    return;
  }

  TKRAdapter adapter = ^(NSNumber* ptrValue, NSError* err) {
    TKRAntiARCRelease(clearData);
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
    TKRPtrAndSizePair* hack = [[TKRPtrAndSizePair alloc] init];
    hack.ptrValue = (uintptr_t)encrypted_buffer;
    hack.ptrSize = (NSUInteger)encrypted_size;
    handler(hack, nil);
  };

  tanker_encrypt_options_t encryption_options = TANKER_ENCRYPT_OPTIONS_INIT;

  NSError* err = convertEncryptionOptions(options, &encryption_options);
  if (err)
  {
    handler(nil, err);
    return;
  }
  tanker_future_t* encrypt_future = tanker_encrypt((tanker_t*)self.cTanker,
                                                   encrypted_buffer,
                                                   (uint8_t const*)clearData.bytes,
                                                   clearData.length,
                                                   &encryption_options);
  tanker_future_t* resolve_future =
      tanker_future_then(encrypt_future, (tanker_future_then_t)&TKR_resolvePromise, (__bridge_retained void*)adapter);
  tanker_future_destroy(encrypt_future);
  tanker_future_destroy(resolve_future);
  TKR_freeCStringArray((char**)encryption_options.share_with_users, encryption_options.nb_users);
  TKR_freeCStringArray((char**)encryption_options.share_with_groups, encryption_options.nb_groups);
  // Force clearData to be retained until the tanker_future is done
  // to avoid reading a dangling pointer
  TKRAntiARCRetain(clearData);
}

- (void)decryptDataImpl:(NSData*)encryptedData
      completionHandler:(nonnull void (^)(TKRPtrAndSizePair* _Nullable, NSError* _Nullable))handler
{
  uint8_t const* encrypted_buffer = (uint8_t const*)encryptedData.bytes;
  uint64_t encrypted_size = encryptedData.length;

  __block uint8_t* decrypted_buffer = nil;
  uint64_t decrypted_size = 0;

  TKRAdapter adapter = ^(NSNumber* clearSize, NSError* err) {
    TKRAntiARCRelease(encryptedData);
    if (err)
    {
      free(decrypted_buffer);
      handler(nil, err);
      return;
    }
    TKRPtrAndSizePair* hack = [[TKRPtrAndSizePair alloc] init];
    hack.ptrValue = (uintptr_t)decrypted_buffer;
    hack.ptrSize = clearSize.unsignedLongValue;
    handler(hack, nil);
  };

  tanker_expected_t* expected_decrypted_size = tanker_decrypted_size(encrypted_buffer, encrypted_size);

  NSError* err = nil;
  decrypted_size = (uint64_t)TKR_unwrapAndFreeExpected(expected_decrypted_size, &err);
  if (err) {
    handler(nil, err);
    return;
  }

  decrypted_buffer = (uint8_t*)malloc((unsigned long)decrypted_size);
  if (!decrypted_buffer)
  {
    handler(nil, TKR_createNSErrorWithDomain(NSPOSIXErrorDomain, ENOMEM, @"could not allocate decrypted buffer"));
    return;
  }
  tanker_future_t* decrypt_future =
      tanker_decrypt((tanker_t*)self.cTanker, decrypted_buffer, encrypted_buffer, encrypted_size);
  // ensures encryptedData lives while the promise does by telling ARC to retain it
  tanker_future_t* resolve_future =
      tanker_future_then(decrypt_future, (tanker_future_then_t)&TKR_resolvePromise, (__bridge_retained void*)adapter);
  tanker_future_destroy(decrypt_future);
  tanker_future_destroy(resolve_future);
  // Force encryptedData to be retained until the tanker_future is done
  // to avoid reading a dangling pointer
  TKRAntiARCRetain(encryptedData);
}

@end
