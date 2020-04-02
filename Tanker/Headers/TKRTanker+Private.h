
#import <Foundation/Foundation.h>

#import "TKRAsyncStreamReader+Private.h"
#import "TKRTanker.h"
#import "TKRUtils+Private.h"

typedef void (^TKRAbstractEventHandler)(void* _Nonnull);

void completeStreamEncrypt(TKRAsyncStreamReader* _Nonnull reader,
                           tanker_future_t* _Nonnull streamFut,
                           TKRInputStreamHandler _Nonnull handler);

@interface TKRTanker (Private)

@property(nonnull) void* cTanker;
@property(nonnull) NSMutableDictionary* callbacks;

- (void)encryptDataImpl:(nonnull NSData*)clearData
                options:(nonnull TKREncryptionOptions*)options
      completionHandler:(nonnull void (^)(PtrAndSizePair* _Nullable, NSError* _Nullable err))handler;

- (void)decryptDataImpl:(nonnull NSData*)encryptedData
      completionHandler:(nonnull void (^)(PtrAndSizePair* _Nullable, NSError* _Nullable err))handler;

- (void)setEvent:(NSUInteger)event
     callbackPtr:(nonnull NSNumber*)callbackPtr
         handler:(nonnull TKRAbstractEventHandler)handler
           error:(NSError* _Nullable* _Nonnull)error;

- (void)disconnectEvent:(NSUInteger)event;
- (void)disconnectEvents;

@end
