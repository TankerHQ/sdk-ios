#import "TKRTankerOptions+Private.h"

@implementation TKRTankerOptions

+ (instancetype)options
{
  TKRTankerOptions* opts = [[self alloc] init];
  opts.sdkType = @"client-ios";
  return opts;
}

@end
