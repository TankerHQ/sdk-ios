
#import <Foundation/Foundation.h>

#import "PromiseKit/Promise.h"
#import "TKRChunkEncryptor+Private.h"
#import "TKRError.h"
#import "TKRUtils+Private.h"

#include <stdint.h>
#include <stdlib.h>

#include <tanker/chunk_encryptor.h>

static NSData* convertToNSData(PtrAndSizePair* hack)
{
  uint8_t* buffer = (uint8_t*)((uintptr_t)hack.ptrValue);
  return [NSData dataWithBytesNoCopy:buffer length:hack.ptrSize freeWhenDone:YES];
}

static uint64_t* convertIndexesToPointer(NSArray* indexes)
{
  uint64_t* c_indexes = (uint64_t*)malloc(sizeof(uint64_t) * indexes.count);
  for (int i = 0; i < indexes.count; ++i)
    c_indexes[i] = [indexes[i] unsignedLongLongValue];
  return c_indexes;
}

@implementation TKRChunkEncryptor

// MARK: Instance methods

- (nonnull PMKPromise<NSData*>*)encryptDataFromData:(nonnull NSData*)clearData atIndex:(NSUInteger)index
{
  return [self encryptDataFromDataImpl:clearData atIndex:index].then(^(PtrAndSizePair* hack) {
    return convertToNSData(hack);
  });
}

- (nonnull PMKPromise<NSData*>*)encryptDataFromString:(nonnull NSString*)clearText atIndex:(NSUInteger)index
{
  return [self encryptDataFromData:convertStringToData(clearText) atIndex:index];
}

- (nonnull PMKPromise<NSData*>*)encryptDataFromData:(nonnull NSData*)clearData
{
  return [self encryptDataFromData:clearData atIndex:self.count];
}

- (nonnull PMKPromise<NSData*>*)encryptDataFromString:(nonnull NSString*)clearText
{
  return [self encryptDataFromData:convertStringToData(clearText)];
}

- (nonnull PMKPromise*)removeAtIndexes:(nonnull NSArray<NSNumber*>*)indexes
{
  __block uint64_t* c_indexes = convertIndexesToPointer(indexes);

  return
      [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
        tanker_future_t* remove_future = tanker_chunk_encryptor_remove(self.cChunkEncryptor, c_indexes, indexes.count);
        tanker_future_t* resolve_future =
            tanker_future_then(remove_future, (tanker_future_then_t)&resolvePromise, (__bridge_retained void*)resolve);
        tanker_future_destroy(remove_future);
        tanker_future_destroy(resolve_future);
      }]
          .catch(^(NSError* err) {
            free(c_indexes);
            return err;
          })
          .then(^{
            free(c_indexes);
          });
}

- (nonnull PMKPromise<NSString*>*)decryptStringFromData:(nonnull NSData*)cipherText atIndex:(NSUInteger)index
{
  return [self decryptDataFromDataImpl:cipherText atIndex:index].then(^(PtrAndSizePair* hack) {
    uint8_t* decrypted_buffer = (uint8_t*)((uintptr_t)hack.ptrValue);

    return [[NSString alloc] initWithBytesNoCopy:decrypted_buffer
                                          length:hack.ptrSize
                                        encoding:NSUTF8StringEncoding
                                    freeWhenDone:YES];
  });
}

- (nonnull PMKPromise<NSData*>*)decryptDataFromData:(nonnull NSData*)cipherText atIndex:(NSUInteger)index
{
  return [self decryptDataFromDataImpl:cipherText atIndex:index].then(^(PtrAndSizePair* hack) {
    return convertToNSData(hack);
  });
}

- (nonnull PMKPromise<NSData*>*)seal
{
  return [self sealWithOptions:[TKREncryptionOptions defaultOptions]];
}

- (nonnull PMKPromise<NSData*>*)sealWithOptions:(nonnull TKREncryptionOptions*)options
{
  return [self sealImplWithOptions:options].then(^(PtrAndSizePair* hack) {
    return convertToNSData(hack);
  });
}

- (void)dealloc
{
  tanker_expected_t* destroy_expected = tanker_chunk_encryptor_destroy(self.cChunkEncryptor);
  tanker_future_destroy(destroy_expected);
  self.tanker = nil;
}

// MARK: Properties
- (NSUInteger)count
{
  return tanker_chunk_encryptor_chunk_count(self.cChunkEncryptor);
}

@end
