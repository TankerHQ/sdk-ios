
#import <Foundation/Foundation.h>

@interface TKRPreverifiedOIDCVerification : NSObject

+ (nonnull TKRPreverifiedOIDCVerification*)preverifiedOIDCVerificationFromSubject:(nonnull NSString*)subject
                                                                       providerID:(nonnull NSString*)providerID;

@property(nonnull, readonly) NSString* subject;
@property(nonnull, readonly) NSString* providerID;

@end
