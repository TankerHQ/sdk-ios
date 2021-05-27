#import <Foundation/Foundation.h>

#import <Tanker/TKRStatus.h>

@class TKRVerificationKey;
@class TKRVerificationMethod;
@class TKRAttachResult;
@class TKREncryptionSession;
@class TKRLogEntry;

/*!
 @typedef TKRStartHandler
 @brief Block which will be called when starting.

 @param status the TKRStatus
 @param err the error which occurred, or nil.
 */
typedef void (^TKRStartHandler)(TKRStatus status, NSError* _Nullable err);

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
 @typedef TKRIdentityVerificationHandler
 @brief Block which may be called with a session token string.

 @param sessionToken the token, or nil if none was requested or if an error occurred.
 @param err the error which occurred, or nil.
 */
typedef void (^TKRIdentityVerificationHandler)(NSString* _Nullable sessionToken,
                                               NSError* _Nullable err);

/*!
 @typedef TKRVerificationKeyHandler
 @brief Block which will be called with a string.

 @param key the unlock key, or nil if an error occurred.
 @param err the error which occurred, or nil.
 */
typedef void (^TKRVerificationKeyHandler)(TKRVerificationKey* _Nullable key,
                                          NSError* _Nullable err);

/*!
 @typedef TKRVerificationMethodsHandler
 @brief Block which will be called with a list of verification methods.

 @param methods a list of verification methods, or nil if an error occurred.
 @param err the error which occurred, or nil.
 */
typedef void (^TKRVerificationMethodsHandler)(
    NSArray<TKRVerificationMethod*>* _Nullable methods, NSError* _Nullable err);

/*!
 @typedef TKRAttachResultHandler
 @brief Block which will be called with a TKRAttachResult*.

 @param result the result of attachProvisionalIdentity, or nil.
 @param err the error which occurred, or nil.
 */
typedef void (^TKRAttachResultHandler)(TKRAttachResult* _Nullable result,
                                       NSError* _Nullable err);

/*!
 @typedef TKRInputStreamHandler
 @brief Block called with an NSInputStream*

 @param stream the stream, or nil
 @param err the error which occurred, or nil
 */
typedef void (^TKRInputStreamHandler)(NSInputStream* _Nullable stream,
                                      NSError* _Nullable err);

/*!
 @typedef TKREncryptionSessionHandler
 @brief Block which will be called with a TKREncryptionSession*.

 @param session the encryption session, or nil if an error occurred.
 @param err the error which occurred, or nil.
 */
typedef void (^TKREncryptionSessionHandler)(
    TKREncryptionSession* _Nullable session, NSError* _Nullable err);

typedef void (^TKRLogHandler)(TKRLogEntry* _Nonnull entry);
