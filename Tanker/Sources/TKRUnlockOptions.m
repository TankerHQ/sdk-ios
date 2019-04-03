#import "TKRUnlockOptions.h"

@implementation TKRUnlockOptions

+ (instancetype)defaultOptions
{
  TKRUnlockOptions* opts = [[self alloc] init];
  opts.password = NULL;
  opts.email = NULL;
  return opts;
}

@end
