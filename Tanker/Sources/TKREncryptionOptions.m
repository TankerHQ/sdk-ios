#import <Tanker/TKREncryptionOptions.h>

@implementation TKREncryptionOptions

+ (instancetype)options
{
  TKREncryptionOptions* opts = [[self alloc] init];
  opts.shareWithUsers = @[];
  opts.shareWithGroups = @[];
  opts.shareWithSelf = true;
  return opts;
}

@end
