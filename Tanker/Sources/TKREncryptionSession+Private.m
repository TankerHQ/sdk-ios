
#import <Tanker/TKREncryptionSession+Private.h>
#import <Tanker/Utils/TKRUtils.h>

#include <ctanker/encryptionsession.h>

#include <objc/runtime.h>

@implementation TKREncryptionSession (Private)

// http://nshipster.com/associated-objects/
@dynamic cSession;

- (void)setCSession:(void*)value
{
  objc_setAssociatedObject(self, @selector(cSession), TKR_ptrToNumber(value), OBJC_ASSOCIATION_RETAIN);
}

- (void*)cSession
{
  return TKR_numberToPtr(objc_getAssociatedObject(self, @selector(cSession)));
}

- (void)encryptDataImpl:(nonnull NSData*)clearData
      completionHandler:(nonnull void (^)(TKRPtrAndSizePair* _Nullable, NSError* _Nullable))handler
{
  uint64_t encrypted_size = tanker_encryption_session_encrypted_size(clearData.length);
  uint8_t* encrypted_buffer = (uint8_t*)malloc((unsigned long)encrypted_size);

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

  if (!encrypted_buffer)
  {
    handler(nil, TKR_createNSError(NSPOSIXErrorDomain, @"could not allocate encrypted buffer", ENOMEM));
    return;
  }

  tanker_future_t* encrypt_future = tanker_encryption_session_encrypt(
      (tanker_encryption_session_t*)self.cSession, encrypted_buffer, (uint8_t const*)clearData.bytes, clearData.length);
  tanker_future_t* resolve_future =
      tanker_future_then(encrypt_future, (tanker_future_then_t)&TKR_resolvePromise, (__bridge_retained void*)adapter);
  tanker_future_destroy(encrypt_future);
  tanker_future_destroy(resolve_future);
  // Force clearData to be retained until the tanker_future is done
  // to avoid reading a dangling pointer
  TKRAntiARCRetain(clearData);
}

@end
