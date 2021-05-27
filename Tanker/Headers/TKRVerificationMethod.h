#import <Foundation/Foundation.h>

#import <Tanker/TKRVerificationKey.h>
#import <Tanker/TKRVerificationMethodType.h>

@interface TKRVerificationMethod : NSObject

@property(readonly) TKRVerificationMethodType type;

/*!
 @brief email address

 @pre type == TKRVerificationMethodTypeEmail
 */
@property(nonnull, readonly) NSString* email;

@end
