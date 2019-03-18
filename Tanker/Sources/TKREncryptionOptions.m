#import "TKREncryptionOptions.h"

@implementation TKREncryptionOptions

+ (instancetype)options
{
  TKREncryptionOptions* opts = [[self alloc] init];
  opts.shareWithUsers = @[];
  opts.shareWithGroups = @[];
  return opts;
}

@end
