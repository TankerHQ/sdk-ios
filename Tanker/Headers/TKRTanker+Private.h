
#import <Foundation/Foundation.h>

#import "TKRTanker.h"
#import "TKRUtils+Private.h"

typedef void (^TKRAbstractEventHandler)(void* _Nonnull);

@interface TKRTanker (Private)

@property(nonnull) void* cTanker;
@property(nonnull) NSMutableDictionary* callbacks;

- (void)encryptDataFromDataImpl:(nonnull NSData*)clearData
                        options:(nonnull TKREncryptionOptions*)options
              completionHandler:(nonnull void (^)(PtrAndSizePair* _Nullable, NSError* _Nullable err))handler;

- (void)decryptDataFromDataImpl:(nonnull NSData*)encryptedData
              completionHandler:(nonnull void (^)(PtrAndSizePair* _Nullable, NSError* _Nullable err))handler;

- (void)setEvent:(NSUInteger)event
     callbackPtr:(nonnull NSNumber*)callbackPtr
         handler:(nonnull TKRAbstractEventHandler)handler
           error:(NSError* _Nullable* _Nonnull)error;

- (void)disconnectEvent:(NSUInteger)event;
- (void)disconnectEvents;

@end
