
#import <Tanker/TKREncryptionSession.h>
#import <Tanker/Utils/TKRUtils.h>

@interface TKREncryptionSession (Private)

@property(nonnull) void* cSession;

- (void)encryptDataImpl:(nonnull NSData*)clearData
      completionHandler:(nonnull void (^)(TKRPtrAndSizePair* _Nullable, NSError* _Nullable err))handler;

@end
