#import "TKRSharingOptions.h"

@implementation TKRSharingOptions

+ (instancetype)options
{
  TKRSharingOptions* opts = [[self alloc] init];
  opts.shareWithUsers = @[];
  opts.shareWithGroups = @[];
  return opts;
}

@end
