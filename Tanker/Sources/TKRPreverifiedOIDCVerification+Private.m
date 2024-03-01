#import <Tanker/TKRPreverifiedOIDCVerification+Private.h>

@interface TKRPreverifiedOIDCVerification ()

@property(nonnull, readwrite) NSString* subject;
@property(nonnull, readwrite) NSString* providerID;

@end

@implementation TKRPreverifiedOIDCVerification

+ (nonnull TKRPreverifiedOIDCVerification*)preverifiedOIDCVerificationFromSubject:(nonnull NSString*)subject
                                                                       providerID:(nonnull NSString*)providerID
{
  TKRPreverifiedOIDCVerification* ret = [[TKRPreverifiedOIDCVerification alloc] init];
  ret.subject = subject;
  ret.providerID = providerID;
  return ret;
}

@end
