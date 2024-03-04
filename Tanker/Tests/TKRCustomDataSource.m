#import <Foundation/Foundation.h>

#import "TKRCustomDataSource.h"

@interface TKRCustomDataSource () <NSStreamDelegate> {
    // Not a property to avoid clash with NSInputStream's hasBytesAvailable
    BOOL hasBytesAvailable;
}

@end

@implementation TKRCustomDataSource

+ (nullable instancetype)customDataSourceWithData:(nonnull NSData*)data
{
  return [[TKRCustomDataSource alloc] initWithData:data];
}

- (instancetype)initWithData:(nonnull NSData*)data
{
  self = [super init];
  assert(self);

  self.willErr = NO;
  self.isSlow = NO;
  self.data = data;
  self.currentPosition = 0;
  return self;
}

- (void)open
{
  if ([self streamStatus] != NSStreamStatusNotOpen) {
    NSLog(@"%@: stream already open", self);
    return;
  }
  [super open];
  
  if (self.isSlow)
  {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
      self->hasBytesAvailable = YES;
      [self enqueueEvent:NSStreamEventHasBytesAvailable];
    });
  }
  else {
    self->hasBytesAvailable = YES;
    [self enqueueEvent:NSStreamEventHasBytesAvailable];
  }
}

- (void)close {
  if (![self isOpen])
    return;
  [super close];
}

- (BOOL)hasBytesAvailable {
  if (![self isOpen]) {
    return NO;
  }
  
  return self->hasBytesAvailable;
}

- (NSInteger)read:(uint8_t*)buffer maxLength:(NSUInteger)maxLength
{
  if (![self isOpen]) {
    NSLog(@"%@: Stream is not open, status %ld.", self, (long)[self streamStatus]);
    return -1;
  }
  if ([self streamStatus] == NSStreamStatusAtEnd) {
    return 0;
  }
  
  assert(maxLength <= NSIntegerMax);
  if (self.willErr && self.currentPosition > 0)
  {
    [self setError:[NSError errorWithDomain:@"TKRTestErrorDomain" code:42 userInfo:nil]];
    return -1;
  }
  NSInteger remaining = self.data.length - self.currentPosition;
  NSInteger toRead = remaining < maxLength ? (remaining) : (maxLength);
  memcpy(buffer, self.data.bytes + self.currentPosition, toRead);
  self.currentPosition += toRead;
  if (self.isSlow)
  {
    self->hasBytesAvailable = NO;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
      if (self.willErr) {
        [self setError:[NSError errorWithDomain:@"TKRTestErrorDomain" code:42 userInfo:nil]];
      } else if (self.currentPosition == self.data.length) {
        self.atEnd = YES;
        [self setStatus:NSStreamStatusAtEnd];
        [self enqueueEvent:NSStreamEventEndEncountered];
      } else {
        self->hasBytesAvailable = YES;
        [self enqueueEvent:NSStreamEventHasBytesAvailable];
      }
    });
  }

  return toRead;
}

@end
