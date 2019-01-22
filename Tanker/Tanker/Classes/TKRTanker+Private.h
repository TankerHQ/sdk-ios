
#import <Foundation/Foundation.h>

#import "PromiseKit.h"
#import "TKRTanker.h"
#import "TKRUtils+Private.h"

typedef void (^TKRAbstractEventHandler)(id);

@interface TKRTanker (Private)

@property void* cTanker;
@property NSMutableArray* events;

- (void)encryptDataFromDataImpl:(nonnull NSData*)clearData
                        options:(nonnull TKREncryptionOptions*)options
              completionHandler:(nonnull void (^)(PtrAndSizePair*, NSError* err))handler;

- (nonnull PMKPromise<NSData*>*)decryptDataFromDataImpl:(nonnull NSData*)cipherData
                                                options:(nonnull TKRDecryptionOptions*)options;

- (nullable NSNumber*)setEvent:(nonnull NSNumber*)event
                   callbackPtr:(nonnull NSNumber*)callbackPtr
                       handler:(nonnull TKRAbstractEventHandler)handler
                         error:(NSError* _Nullable* _Nonnull)error;

- (void)disconnectEventConnection:(nonnull NSNumber*)connection;

@end
