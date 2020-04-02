
#import "TKREncryptionSession.h"
#import "TKRUtils+Private.h"

@interface TKREncryptionSession (Private)

@property(nonnull) void* cSession;

- (void)encryptDataImpl:(nonnull NSData*)clearData
      completionHandler:(nonnull void (^)(PtrAndSizePair* _Nullable, NSError* _Nullable err))handler;

@end
