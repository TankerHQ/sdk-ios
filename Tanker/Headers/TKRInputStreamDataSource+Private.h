
#import <Foundation/Foundation.h>

#import <POSInputStreamLibrary/POSBlobInputStreamDataSource.h>
#import <Tanker/TKRAsyncStreamReader+Private.h>

#include "ctanker/stream.h"

@interface TKRInputStreamDataSource : NSObject <POSBlobInputStreamDataSource>

+ (nullable instancetype)inputStreamDataSourceWithCStream:(nonnull tanker_stream_t*)stream
                                              asyncReader:(nonnull TKRAsyncStreamReader*)reader;

- (nullable instancetype)initWithCStream:(nonnull tanker_stream_t*)stream
                             asyncReader:(nonnull TKRAsyncStreamReader*)reader;

@property(nullable) tanker_stream_t* stream;
@property(nonnull) TKRAsyncStreamReader* reader;

@end
