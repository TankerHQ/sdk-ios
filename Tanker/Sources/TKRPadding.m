#import <Tanker/TKRPadding.h>

@interface TKRPadding ()

- (nullable id)initWithValue:(nonnull NSNumber*)value;

@property (nonnull, readwrite) NSNumber* nativeValue;

@end

@implementation TKRPadding

- (nullable id)initWithValue:(nonnull NSNumber*)value
{
  if (self = [super init])
  {
    self.nativeValue = value;
  }

  return self;
}

+ (nullable instancetype)automatic
{
  return [[TKRPadding alloc] initWithValue:@0];
}

+ (nullable instancetype)off
{
  return [[TKRPadding alloc] initWithValue:@1];
}

+ (nullable instancetype)step:(nonnull NSNumber *)value
{
  if (value.integerValue < 2)
  {
    [NSException raise:NSInvalidArgumentException
                 format:@"Invalid step. The value must be >= 2."];
  }

  return [[TKRPadding alloc] initWithValue:value];
}

@end
