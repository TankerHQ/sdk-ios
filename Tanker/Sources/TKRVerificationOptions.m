#import <Tanker/TKRVerificationOptions.h>

@implementation TKRVerificationOptions

+ (instancetype)options
{
  TKRVerificationOptions* opts = [[self alloc] init];
  opts.withSessionToken = false;
  return opts;
}

@end
