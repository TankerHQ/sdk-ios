#import <Foundation/Foundation.h>

#import <Tanker/Storage/TKRDatastoreOnConflict.h>

@interface TKRDatastore : NSObject

+ (nullable TKRDatastore*)datastoreWithPersistentPath:(nonnull NSString*)persistentPath
                                            cachePath:(nonnull NSString*)cachePath
                                                error:(NSError* _Nullable* _Nonnull)err;

- (instancetype _Nullable)initWithPersistentPath:(nonnull NSString*)persistentPath
                                       cachePath:(nonnull NSString*)cachePath
                                           error:(NSError* _Nullable* _Nonnull)err;

- (nullable NSError*)nuke;
- (void)close;

- (nullable NSError*)cacheValues:(nonnull NSDictionary<NSData*, NSData*>*)keyValues
                      onConflict:(TKRDatastoreOnConflict)action;
// missing keys will use NSNull as a placeholder
- (nonnull NSArray<id>*)findCacheValuesWithKeys:(nonnull NSArray<NSData*>*)keys error:(NSError* _Nullable* _Nonnull)err;

- (nullable NSError*)setSerializedDevice:(nonnull NSData*)serializedDevice;
- (nullable NSData*)serializedDeviceWithError:(NSError* _Nullable* _Nonnull)err;

- (void)dealloc;

@end
