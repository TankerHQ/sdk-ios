
#import <Foundation/Foundation.h>

#import "PromiseKit.h"
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

- (void)encryptDataFromData:(nonnull NSData*)clearData
                    atIndex:(NSUInteger)index
          completionHandler:(nonnull TKREncryptedDataHandler)handler
{
  [self encryptDataFromDataImpl:clearData
                        atIndex:index
              completionHandler:^(PtrAndSizePair* hack, NSError* err) {
                if (err)
                  handler(nil, err);
                else
                  handler(convertToNSData(hack), nil);
              }];
}

- (void)encryptDataFromString:(nonnull NSString*)clearText
                      atIndex:(NSUInteger)index
            completionHandler:(nonnull TKREncryptedDataHandler)handler
{
  [self encryptDataFromData:convertStringToData(clearText) atIndex:index completionHandler:handler];
}

- (void)encryptDataFromData:(nonnull NSData*)clearData completionHandler:(nonnull TKREncryptedDataHandler)handler
{
  [self encryptDataFromData:clearData atIndex:self.count completionHandler:handler];
}

- (void)encryptDataFromString:(nonnull NSString*)clearText completionHandler:(nonnull TKREncryptedDataHandler)handler
{
  [self encryptDataFromData:convertStringToData(clearText) completionHandler:handler];
}

- (void)removeAtIndexes:(nonnull NSArray<NSNumber*>*)indexes error:(NSError* _Nullable* _Nonnull)err
{
  uint64_t* c_indexes = convertIndexesToPointer(indexes);
  tanker_expected_t* expected_remove = tanker_chunk_encryptor_remove(self.cChunkEncryptor, c_indexes, indexes.count);
  free(c_indexes);
  NSError* optErr = getOptionalFutureError(expected_remove);
  *err = optErr;
  tanker_future_destroy(expected_remove);
}

- (nonnull PMKPromise<NSString*>*)decryptStringFromData:(nonnull NSData*)cipherText atIndex:(NSUInteger)index
{
  return [PMKPromise promiseWithAdapter:^(PMKAdapter adapter) {
           [self decryptDataFromDataImpl:cipherText atIndex:index completionHandler:adapter];
         }]
      .then(^(PtrAndSizePair* hack) {
        uint8_t* decrypted_buffer = (uint8_t*)((uintptr_t)hack.ptrValue);

        return [[NSString alloc] initWithBytesNoCopy:decrypted_buffer
                                              length:hack.ptrSize
                                            encoding:NSUTF8StringEncoding
                                        freeWhenDone:YES];
      });
}

- (nonnull PMKPromise<NSData*>*)decryptDataFromData:(nonnull NSData*)cipherText atIndex:(NSUInteger)index
{
  return [PMKPromise promiseWithAdapter:^(PMKAdapter adapter) {
           [self decryptDataFromDataImpl:cipherText atIndex:index completionHandler:adapter];
         }]
      .then(^(PtrAndSizePair* hack) {
        return convertToNSData(hack);
      });
}

- (nonnull PMKPromise<NSData*>*)seal
{
  return [self sealWithOptions:[TKREncryptionOptions defaultOptions]];
}

- (nonnull PMKPromise<NSData*>*)sealWithOptions:(nonnull TKREncryptionOptions*)options
{
  return [PMKPromise promiseWithAdapter:^(PMKAdapter adapter) {
           [self sealImplWithOptions:options completionHandler:adapter];
         }]
      .then(^(PtrAndSizePair* hack) {
        return convertToNSData(hack);
      });
}

- (void)dealloc
{
  tanker_future_t* destroy_future = tanker_chunk_encryptor_destroy(self.cChunkEncryptor);
  tanker_future_wait(destroy_future);
  tanker_future_destroy(destroy_future);
}

// MARK: Properties
- (NSUInteger)count
{
  return tanker_chunk_encryptor_chunk_count(self.cChunkEncryptor);
}

@end
