
#import <Foundation/Foundation.h>

#import "TKRTanker.h"

typedef void (^TKRAbstractEventHandler)(id);

@interface TKRTanker (Private)

@property void* cTanker;
@property NSMutableArray* events;

- (nonnull PMKPromise<NSData*>*)encryptDataFromDataImpl:(nonnull NSData*)clearData
                                                options:(nonnull TKREncryptionOptions*)options;
- (nonnull PMKPromise<NSData*>*)decryptDataFromDataImpl:(nonnull NSData*)cipherData
                                                options:(nonnull TKRDecryptionOptions*)options;

- (nullable NSNumber*)setEvent:(nonnull NSNumber*)event
                   callbackPtr:(nonnull NSNumber*)callbackPtr
                       handler:(nonnull TKRAbstractEventHandler)handler
                         error:(NSError* _Nullable* _Nonnull)error;

- (void)disconnectEventConnection:(nonnull NSNumber*)connection;

@end
