#import "TKRTankerOptions+Private.h"

@implementation TKRTankerOptions

+ (instancetype)options
{
  TKRTankerOptions* opts = [[self alloc] init];
  opts.sdkType = @"client-ios";
  return opts;
}

- (nullable NSString*)trustchainID
{
  return _appID;
}

- (void)setTrustchainID:(nonnull NSString*)trustchainID
{
  _appID = trustchainID;
}

@end
