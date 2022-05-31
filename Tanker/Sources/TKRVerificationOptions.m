#import <Tanker/TKRVerificationOptions.h>

@implementation TKRVerificationOptions

+ (instancetype)options
{
  TKRVerificationOptions* opts = [[self alloc] init];
  opts.withSessionToken = false;
  opts.allowE2eMethodSwitch = false;
  return opts;
}

@end
