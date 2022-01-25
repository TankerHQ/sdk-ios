
#import <Foundation/Foundation.h>

#import <Tanker/TKRAsyncStreamReader+Private.h>
#import <Tanker/TKRTanker.h>
#import <Tanker/Utils/TKRUtils.h>

typedef void (^TKRAbstractEventHandler)(void* _Nonnull);

void completeStreamEncrypt(TKRAsyncStreamReader* _Nonnull reader,
                           tanker_future_t* _Nonnull streamFut,
                           TKRInputStreamHandler _Nonnull handler);

NSError* _Nullable convertSharingOptions(TKRSharingOptions* _Nonnull opts, void* _Nonnull c_opts);
NSError* _Nullable convertEncryptionOptions(TKREncryptionOptions* _Nonnull opts, void* _Nonnull c_opts);

@interface TKRTanker (Private)

@property(nonnull) void* cTanker;

- (void)encryptDataImpl:(nonnull NSData*)clearData
                options:(nonnull TKREncryptionOptions*)options
      completionHandler:(nonnull void (^)(TKRPtrAndSizePair* _Nullable, NSError* _Nullable err))handler;

- (void)decryptDataImpl:(nonnull NSData*)encryptedData
      completionHandler:(nonnull void (^)(TKRPtrAndSizePair* _Nullable, NSError* _Nullable err))handler;

@end
