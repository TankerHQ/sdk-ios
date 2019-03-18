#import "TKRShareOptions.h"

@implementation TKRShareOptions

+ (instancetype)options
{
  TKRShareOptions* opts = [[self alloc] init];
  opts.shareWithUsers = @[];
  opts.shareWithGroups = @[];
  return opts;
}

@end
