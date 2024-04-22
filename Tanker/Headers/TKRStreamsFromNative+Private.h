#import <Foundation/Foundation.h>

#import <Tanker/TKRAsyncStreamReader+Private.h>
#import <Tanker/TKRStreamBase.h>

#include <Tanker/ctanker/stream.h>

@interface TKRStreamsFromNative : TKRStreamBase

+ (nullable instancetype)streamsFromNativeWithCStream:(nonnull tanker_stream_t*)cstream
                                          asyncReader:(nonnull TKRAsyncStreamReader*)reader;

- (nullable instancetype)initWithCStream:(nonnull tanker_stream_t*)cstream
                             asyncReader:(nonnull TKRAsyncStreamReader*)reader;
@end
