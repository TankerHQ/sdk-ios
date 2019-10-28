
#import <Foundation/Foundation.h>

/*!
 @brief TKRVerificationMethodType
 */
typedef NS_ENUM(NSUInteger, TKRVerificationMethodType) {
  TKRVerificationMethodTypeEmail = 1,
  TKRVerificationMethodTypePassphrase,
  TKRVerificationMethodTypeVerificationKey,
  TKRVerificationMethodTypeOIDCIDToken,
};
