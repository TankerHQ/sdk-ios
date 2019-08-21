#import <Foundation/Foundation.h>

#import "TKRVerificationKey.h"
#import "TKRVerificationMethodType.h"

@interface TKRVerificationMethod : NSObject

@property(readonly) TKRVerificationMethodType type;

/*!
 @brief email address

 @pre type == TKRVerificationMethodTypeEmail
 */
@property(nonnull, readonly) NSString* email;

@end