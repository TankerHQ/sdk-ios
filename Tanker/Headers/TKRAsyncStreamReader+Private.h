
#import <Foundation/Foundation.h>

#include <Tanker/ctanker/stream.h>

void readInput(uint8_t* _Nonnull out,
               int64_t n,
               tanker_stream_read_operation_t* _Nonnull op,
               void* _Nonnull additional_data);

@interface TKRAsyncStreamReader : NSObject <NSStreamDelegate>

+ (nullable instancetype)readerWithStream:(nonnull NSInputStream*)stream;
- (nullable instancetype)initWithStream:(nonnull NSInputStream*)stream;
- (void)performRead:(nonnull uint8_t*)out
          maxLength:(int64_t)len
      readOperation:(nonnull tanker_stream_read_operation_t*)op;

@property(nonnull) NSInputStream* stream;
@property(nullable) uint8_t* cOut;
@property int64_t cSize;
@property(nullable) tanker_stream_read_operation_t* cOp;

@end
