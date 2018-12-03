#import "TKREncryptionOptions.h"

@implementation TKREncryptionOptions

+ (instancetype)defaultOptions
{
  TKREncryptionOptions* opts = [[self alloc] init];
  opts.shareWithUsers = @[];
  opts.shareWithGroups = @[];
  return opts;
}

@end
