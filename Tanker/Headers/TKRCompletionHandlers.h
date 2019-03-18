#import <Foundation/Foundation.h>

#import "TKRSignInResult.h"

@class TKRUnlockKey;

/*!
 @typedef TKRSignUpHandler
 @brief Block which will be called when signing up.

 @param result the sign-up result (as an NSNumber*), or nil if an error
 occurred.
 @param err the error which occurred, or nil.
 */
typedef void (^TKRSignUpHandler)(NSNumber* _Nullable result,
                                 NSError* _Nullable err);

/*!
 @typedef TKRSignInHandler
 @brief Block which will be called when signing in.

 @param result the sign-in result (as an NSNumber*), or nil if an error
 occurred.
 @param err the error which occurred, or nil.
 */
typedef void (^TKRSignInHandler)(NSNumber* _Nullable result,
                                 NSError* _Nullable err);

/*!
 @typedef TKREncryptedDataHandler
 @brief Block which will be called when data has been encrypted.

 @param encryptedData the encrypted data, or nil if an error occurred.
 @param err the error which occurred, or nil.
 */
typedef void (^TKREncryptedDataHandler)(NSData* _Nullable encryptedData,
                                        NSError* _Nullable err);

/*!
 @typedef TKRDecryptedDataHandler
 @brief Block which will be called when data has been decrypted.

 @param decryptedData the decrypted data, or nil if an error occurred.
 @param err the error which occurred, or nil.
 */
typedef void (^TKRDecryptedDataHandler)(NSData* _Nullable decryptedData,
                                        NSError* _Nullable err);

/*!
 @typedef TKRDecryptedStringHandler
 @brief Block which will be called when a string has been decrypted.

 @param decryptedString the string data, or nil if an error occurred.
 @param err the error which occurred, or nil.
 */
typedef void (^TKRDecryptedStringHandler)(NSString* _Nullable decryptedString,
                                          NSError* _Nullable err);

/*!
 @typedef TKRBooleanHandler
 @brief Block which will be called with either @YES or @NO.

 @param boolean either @YES or @NO.
 @param err the error which occurred, or nil.
 */
typedef void (^TKRBooleanHandler)(NSNumber* _Nullable boolean,
                                  NSError* _Nullable err);

/*!
 @typedef TKRErrorHandler
 @brief Block which will be called with a NSError*, or nil.

 @param err the error which occurred, or nil.
 */
typedef void (^TKRErrorHandler)(NSError* _Nullable err);

/*!
 @typedef TKRDeviceIDHandler
 @brief Block which will be called with a device ID.

 @param deviceID the deviceID, or nil if an error occurred.
 @param err the error which occurred, or nil.
 */
typedef void (^TKRDeviceIDHandler)(NSString* _Nullable deviceID,
                                   NSError* _Nullable err);

/*!
 @typedef TKRGroupIDHandler
 @brief Block which will be called with a group ID.

 @param groupID the group ID, or nil if an error occurred.
 @param err the error which occurred, or nil.
 */
typedef void (^TKRGroupIDHandler)(NSString* _Nullable groupID,
                                  NSError* _Nullable err);

/*!
 @typedef TKRUnlockKeyHandler
 @brief Block which will be called with a string.

 @param key the unlock key, or nil if an error occurred.
 @param err the error which occurred, or nil.
 */
typedef void (^TKRUnlockKeyHandler)(TKRUnlockKey* _Nullable key,
                                    NSError* _Nullable err);
