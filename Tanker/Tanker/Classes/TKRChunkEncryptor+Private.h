
#import <Foundation/Foundation.h>

#import "TKRChunkEncryptor.h"
#import "TKRDecryptionOptions.h"
#import "TKREncryptionOptions.h"
#import "TKRTanker.h"
#import "TKRUtils+Private.h"

#import <PromiseKit/fwd.h>

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

- (nonnull PMKPromise<NSData*>*)decryptDataFromDataImpl:(nonnull NSData*)cipherData atIndex:(NSUInteger)index;

- (nonnull PMKPromise<NSData*>*)sealImplWithOptions:(nonnull TKREncryptionOptions*)options;

@end
