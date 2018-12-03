#import "TKRShareOptions.h"

@implementation TKRShareOptions

+ (instancetype)defaultOptions
{
  TKRShareOptions* opts = [[self alloc] init];
  opts.shareWithUsers = @[];
  opts.shareWithGroups = @[];
  return opts;
}

@end
