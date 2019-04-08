
#import <Foundation/Foundation.h>

#import "TKRTanker.h"
#import "TKRUtils+Private.h"

typedef void (^TKRAbstractEventHandler)(void*);

@interface TKRTanker (Private)

@property void* cTanker;
@property NSMutableArray* events;
@property NSMutableDictionary* callbacks;

- (void)encryptDataFromDataImpl:(nonnull NSData*)clearData
                        options:(nonnull TKREncryptionOptions*)options
              completionHandler:(nonnull void (^)(PtrAndSizePair*, NSError* err))handler;

- (void)decryptDataFromDataImpl:(nonnull NSData*)cipherData
              completionHandler:(nonnull void (^)(PtrAndSizePair*, NSError* err))handler;

- (nullable NSNumber*)setEvent:(nonnull NSNumber*)event
                   callbackPtr:(nonnull NSNumber*)callbackPtr
                       handler:(nonnull TKRAbstractEventHandler)handler
                         error:(NSError* _Nullable* _Nonnull)error;

- (void)disconnectEventConnection:(nonnull NSNumber*)connection;

@end
