#import "TKRDecryptionOptions.h"

#import "tanker/tanker.h"

@implementation TKRDecryptionOptions

+ (instancetype)defaultOptions
{
  TKRDecryptionOptions* opts = [[self alloc] init];
  opts.timeout = TANKER_DECRYPT_DEFAULT_TIMEOUT / 1000;
  return opts;
}

@end
