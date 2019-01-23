
#import <Foundation/Foundation.h>

#import "TKRChunkEncryptor.h"
#import "TKRDecryptionOptions.h"
#import "TKREncryptionOptions.h"
#import "TKRTanker.h"
#import "TKRUtils+Private.h"

@interface TKRChunkEncryptor (Private)

// We must retain the TKRTanker object.
@property TKRTanker* tanker;
@property void* cChunkEncryptor;

+ (void)chunkEncryptorWithTKRTanker:(nonnull TKRTanker*)tanker
                               seal:(nullable NSData*)seal
                            options:(nullable TKRDecryptionOptions*)options
                  completionHandler:(nonnull void (^)(TKRChunkEncryptor*, NSError*))handler;

- (void)encryptDataFromDataImpl:(nonnull NSData*)clearData
                        atIndex:(NSUInteger)index
              completionHandler:(nonnull void (^)(PtrAndSizePair*, NSError*))handler;

- (void)decryptDataFromDataImpl:(nonnull NSData*)cipherData
                        atIndex:(NSUInteger)index
              completionHandler:(nonnull void (^)(PtrAndSizePair*, NSError*))handler;

- (void)sealImplWithOptions:(nonnull TKREncryptionOptions*)options
          completionHandler:(nonnull void (^)(PtrAndSizePair*, NSError*))handler;

@end
