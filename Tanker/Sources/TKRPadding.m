#import <Tanker/TKRError.h>
#import <Tanker/TKRPadding.h>
#import <Tanker/Utils/TKRUtils.h>

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

+ (nullable instancetype)step:(NSUInteger)value error:(NSError **)error {
  if (value < 2) {
      *error = TKR_createNSError(TKRErrorInvalidArgument, @"Invalid step. The value must be >= 2.");
      return nil;
  }

  return [[TKRPadding alloc] initWithValue:@(value)];
}

@end
