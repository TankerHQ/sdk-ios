
#import "TKRCustomDataSource.h"

@implementation TKRCustomDataSource

+ (nullable instancetype)customDataSourceWithData:(nonnull NSData*)data
{
  return [[TKRCustomDataSource alloc] initWithData:data];
}

- (nullable instancetype)initWithData:(nonnull NSData*)data
{
  if (self = [super init])
  {
    self.willErr = NO;
    self.isSlow = NO;
    self.data = data;
    self.currentPosition = 0;
  }
  return self;
}

- (BOOL)getBuffer:(uint8_t**)buffer length:(NSUInteger*)bufferLength
{
  return NO;
}

- (void)open
{
  self.openCompleted = YES;
  if (self.isSlow)
  {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
      self.hasBytesAvailable = YES;
    });
  }
  else
    self.hasBytesAvailable = YES;
}

- (id)propertyForKey:(NSString*)key
{
  return nil;
}

- (NSInteger)read:(uint8_t*)buffer maxLength:(NSUInteger)maxLength
{
  // POSInputStreamLibrary errors when reading a closed stream, this function cannot be called in this state.
  assert(maxLength <= NSIntegerMax);
  if (self.willErr && self.currentPosition > 0)
  {
    self.error = [NSError errorWithDomain:@"TKRTestErrorDomain" code:42 userInfo:nil];
    return -1;
  }
  NSInteger remaining = self.data.length - self.currentPosition;
  NSInteger toRead = remaining < maxLength ? (remaining) : (maxLength);
  memcpy(buffer, self.data.bytes + self.currentPosition, toRead);
  self.currentPosition += toRead;
  if (self.isSlow)
  {
    self.hasBytesAvailable = NO;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
      if (self.willErr)
        self.error = [NSError errorWithDomain:@"TKRTestErrorDomain" code:42 userInfo:nil];
      else if (self.currentPosition == self.data.length)
        self.atEnd = YES;
      else
        self.hasBytesAvailable = YES;
    });
  }
  return toRead;
}

- (BOOL)setProperty:(id)property forKey:(NSString*)key
{
  return NO;
}

@end
