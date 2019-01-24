#import <Foundation/Foundation.h>

@class TKRUnlockKey;
@class TKRChunkEncryptor;

/*!
 @typedef TKREncryptedDataHandler
 @brief Block which will be called when data has been encrypted.

 @param encryptedData the encrypted data, or nil if an error occurred.
 @param err the error which occurred, or nil.
 */
typedef void (^TKREncryptedDataHandler)(NSData* encryptedData, NSError* err);

/*!
 @typedef TKRDecryptedDataHandler
 @brief Block which will be called when data has been decrypted.

 @param decryptedData the decrypted data, or nil if an error occurred.
 @param err the error which occurred, or nil.
 */
typedef void (^TKRDecryptedDataHandler)(NSData* decryptedData, NSError* err);

/*!
 @typedef TKRDecryptedDataHandler
 @brief Block which will be called when a string has been decrypted.

 @param decryptedString the string data, or nil if an error occurred.
 @param err the error which occurred, or nil.
 */
typedef void (^TKRDecryptedStringHandler)(NSString* decryptedString,
                                          NSError* err);

/*!
 @typedef TKRSealHandler
 @brief Block which will be called when a @see TKRChunkEncryptor gets sealed.

 @param seal the seal, nil if an error occurred.
 @param err the error which occurred, or nil.
 */
typedef void (^TKRSealHandler)(NSData* seal, NSError* err);

/*!
 @typedef TKRBooleanHandler
 @brief Block which will be called with either @YES or @NO.

 @param b either @YES or NO.
 @param err the error which occurred, or nil.
 */
typedef void (^TKRBooleanHandler)(NSNumber* b, NSError* err);

/*!
 @typedef TKRArrayHandler
 @brief Block which will be called with a NSArray*.

 @param a an array containing some values.
 @param err the error which occurred, or nil.
 */
typedef void (^TKRArrayHandler)(NSArray* a, NSError* err);

/*!
 @typedef TKRArrayHandler
 @brief Block which will be called with a NSError*, or nil.

 @param err the error which occurred, or nil.
 */
typedef void (^TKRErrorHandler)(NSError* err);

/*!
 @typedef TKRStringHandler
 @brief Block which will be called with a string.

 @param str the string, or nil if an error occurred.
 @param err the error which occurred, or nil.
 */
typedef void (^TKRStringHandler)(NSString* str, NSError* err);

/*!
 @typedef TKRUnlockKeyHandler
 @brief Block which will be called with a string.

 @param key the unlock key, or nil if an error occurred.
 @param err the error which occurred, or nil.
 */
typedef void (^TKRUnlockKeyHandler)(TKRUnlockKey* key, NSError* err);

/*!
 @typedef TKRChunkEncryptorHandler
 @brief Block which will be called when a @see TKRChunkEncryptor has been
 created.

 @param chunkEncryptor the @see TKRChunkEncryptor, or nil if an error occurred.
 @param err the error which occurred, or nil.
 */
typedef void (^TKRChunkEncryptorHandler)(TKRChunkEncryptor* chunkEncryptor,
                                         NSError* err);
