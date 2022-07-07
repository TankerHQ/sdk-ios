#import <Tanker/TKREncryptionOptions.h>

@implementation TKREncryptionOptions

+ (instancetype)options
{
  TKREncryptionOptions* opts = [[self alloc] init];
  opts.shareWithUsers = @[];
  opts.shareWithGroups = @[];
  opts.shareWithSelf = true;
  opts.paddingStep = [TKRPadding automatic];
  return opts;
}

@end
