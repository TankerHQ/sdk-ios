
#import <Foundation/Foundation.h>

#import "TKRChunkEncryptor.h"
#import "TKRDecryptionOptions.h"
#import "TKREncryptionOptions.h"
#import "TKRTanker.h"

#import <PromiseKit/fwd.h>

@interface TKRChunkEncryptor (Private)

// We must retain the TKRTanker object.
@property TKRTanker* tanker;
@property void* cChunkEncryptor;

+ (nonnull PMKPromise<TKRChunkEncryptor*>*)chunkEncryptorWithTKRTanker:(nonnull TKRTanker*)tanker
                                                                  seal:(nullable NSData*)seal
                                                               options:(nullable TKRDecryptionOptions*)options;

- (nonnull PMKPromise<NSData*>*)encryptDataFromDataImpl:(nonnull NSData*)clearData atIndex:(NSUInteger)index;
- (nonnull PMKPromise<NSData*>*)decryptDataFromDataImpl:(nonnull NSData*)cipherData atIndex:(NSUInteger)index;

- (nonnull PMKPromise<NSData*>*)sealImplWithOptions:(nonnull TKREncryptionOptions*)options;

@end
