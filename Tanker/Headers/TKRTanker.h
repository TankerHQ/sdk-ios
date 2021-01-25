
#import <AvailabilityMacros.h>
#import <Foundation/Foundation.h>

#import "TKRCompletionHandlers.h"
#import "TKREncryptionOptions.h"
#import "TKREvents.h"
#import "TKRSharingOptions.h"
#import "TKRStatus.h"
#import "TKRTankerOptions.h"
#import "TKRVerification.h"
#import "TKRVerificationKey.h"
#import "TKRVerificationMethod.h"

#define TKRErrorDomain @"TKRErrorDomain"

/*!
 @brief Tanker object
 */
@interface TKRTanker : NSObject

// MARK: Class methods
/*!
 @brief Create a TKRTanker object with options.

 @throw NSInvalidArgumentException if initialization fails.

 @param options Options needed to initialize Tanker.

 @pre Every field must be set with a valid value.

 @return an initialized TKRTanker*.

 */
+ (nonnull TKRTanker*)tankerWithOptions:(nonnull TKRTankerOptions*)options;

/*!
 @brief Get Tanker version as a string
 */
+ (nonnull NSString*)versionString;

+ (nonnull NSString*)nativeVersionString;

+ (nonnull NSString*)prehashPassword:(nonnull NSString*)password;

// MARK: Instance methods

/*!
 @brief Register a handler called when the current device is revoked.

 @discussion The handler will be called as soon as the device is revoked.

 @param handler the block called without any argument. Runs on a background queue.

 @deprecated the DeviceRevoked event is deprecated, it will be removed in the future
 */
- (void)connectDeviceRevokedHandler:(nonnull TKRDeviceRevokedHandler)handler
  DEPRECATED_MSG_ATTRIBUTE("the DeviceRevoked event is deprecated, it will be removed in the future");
;

/*!
 @brief Get the list of the registered verification methods.

 @pre status must be TKRStatusReady

 @param handler the block called with a list of registered verification methods, or an NSError*.
 */
- (void)verificationMethodsWithCompletionHandler:(nonnull TKRVerificationMethodsHandler)handler;

/*!
 @brief Register or update a verification method.

 @pre status must be TKRStatusReady

 @param verification the verification.
 @param handler the block called with an NSError*, or nil.
 */
- (void)setVerificationMethod:(nonnull TKRVerification*)verification completionHandler:(nonnull TKRErrorHandler)handler;

/*!
 @brief Start Tanker

 @pre status must be TKRStatusStopped

 @param identity a previously registered Tanker identity.
 @param handler the block called with Tanker's status.
 */
- (void)startWithIdentity:(nonnull NSString*)identity completionHandler:(nonnull TKRStartHandler)handler;

/*!
 @brief Register an identity and associate a verification method.

 @pre status must be TKRStatusIdentityRegistrationNeeded

 @param verification the verification.
 @param handler the block called with an NSError*, or nil.
 */
- (void)registerIdentityWithVerification:(nonnull TKRVerification*)verification
                       completionHandler:(nonnull TKRErrorHandler)handler;

/*!
 @brief Verify an identity

 @pre status must be TKRStatusIdentityVerificationNeeded

 @param verification the verification.
 @param handler the block called with an NSError*, or nil.
 */
- (void)verifyIdentityWithVerification:(nonnull TKRVerification*)verification
                     completionHandler:(nonnull TKRErrorHandler)handler;

/*!
 @brief Attach a provisional identity to the current user

 @pre status must be TKRStatusReady

 @param provisionalIdentity the provisional identity to attach.
 @param handler the block called with the result, or an NSError*.
 */
- (void)attachProvisionalIdentity:(nonnull NSString*)provisionalIdentity
                completionHandler:(nonnull TKRAttachResultHandler)handler;

/*!
 @brief Verify a provisional identity

 @pre status must be TKRStatusReady

 @param verification the verification.
 @param handler the block called with an NSError*, or nil.
 */
- (void)verifyProvisionalIdentityWithVerification:(nonnull TKRVerification*)verification
                                completionHandler:(nonnull TKRErrorHandler)handler;

/*!
 @brief Retrieve the current device id.

 @param handler the block called with the device id.

 @pre Status is TKRStatusReady.
 */
- (void)deviceIDWithCompletionHandler:(nonnull TKRDeviceIDHandler)handler;

/*!
 @brief Stop Tanker.

 @discussion Perform Tanker cleanup actions.

 @param handler the block called with an NSError*, or nil.

 @post Status is TKRStatusStopped
*/
- (void)stopWithCompletionHandler:(nonnull TKRErrorHandler)handler;

/*!
 @brief Create a verification key that can be used to accept devices.

 @discussion A new verification key is created each time.

 @param handler the block called with the unlock key, or nil.
 */
- (void)generateVerificationKeyWithCompletionHandler:(nonnull TKRVerificationKeyHandler)handler;

/*!
 @brief Encrypt a string and share it with the user's registered devices.

 @discussion The string will be converted to UTF-8 before encryption.
 There are no requirements on Unicode Normalization Form (NFC/NFD/NFKC/NFKD).

 @param clearText The string to encrypt.
 @param handler the block called with the encrypted data.
 */
- (void)encryptString:(nonnull NSString*)clearText completionHandler:(nonnull TKREncryptedDataHandler)handler;

/*!
 @brief Encrypt a string, using custom options.

 @discussion The string will be converted to UTF-8 before encryption.
 There are no requirements on Unicode Normalization Form (NFC/NFD/NFKC/NFKD).

 @param clearText The string to encrypt.
 @param options Custom encryption options.
 @param handler the block called with the encrypted data.
 */
- (void)encryptString:(nonnull NSString*)clearText
              options:(nonnull TKREncryptionOptions*)options
    completionHandler:(nonnull TKREncryptedDataHandler)handler;

/*!
 @brief Encrypt data and share it with the user's registered devices.

 @discussion equivalent to calling encryptString:options: with default options.

 @param clearData data to encrypt.
 @param handler the block called with the encrypted data.
 */
- (void)encryptData:(nonnull NSData*)clearData completionHandler:(nonnull TKREncryptedDataHandler)handler;

/*!
 @brief Encrypt data, using customized options.

 @param clearData data to encrypt.
 @param options custom encryption options.
 @param handler the block called with the encrypted data.
 */
- (void)encryptData:(nonnull NSData*)clearData
              options:(nonnull TKREncryptionOptions*)options
    completionHandler:(nonnull TKREncryptedDataHandler)handler;

/*!
 @brief Decrypt encrypted data as a string.

 @discussion equivalent to calling decryptStringFromData:options: with default options.

 @param encryptedData encrypted data to decrypt.
 @param handler the block called with the decrypted string.

 @pre @a encryptedData was returned by encryptString.
 */
- (void)decryptStringFromData:(nonnull NSData*)encryptedData
            completionHandler:(nonnull TKRDecryptedStringHandler)handler;

/*!
 @brief Decrypt encrypted data.

 @discussion equivalent to calling decryptData:options: with default options.

 @param encryptedData encrypted data to decrypt.
 @param handler the block called with the decrypted data.

 @pre @a encryptedData was returned by encryptData.
 */
- (void)decryptData:(nonnull NSData*)encryptedData completionHandler:(nonnull TKRDecryptedDataHandler)handler;

/*!
 @brief Get the encrypted resource ID.

 @param encryptedData encrypted data.
 @param error output error parameter.

 @return the resource id, or nil if an error occurred.
 */
- (nullable NSString*)resourceIDOfEncryptedData:(nonnull NSData*)encryptedData
                                          error:(NSError* _Nullable* _Nonnull)error;

/*!
 @brief Create a group with the given recipient identities.

 @param identities the identities to add to the group.
 @param handler the block called with the group id.
 */
- (void)createGroupWithIdentities:(nonnull NSArray<NSString*>*)identities
                completionHandler:(nonnull TKRGroupIDHandler)handler;

/*!
 @brief Update a group to add the given user IDs.

 @param groupId the id of the group to update.
 @param userIdentities the users to add to the group.
 @param handler the block called with an NSError, or nil.
 */
- (void)updateMembersOfGroup:(nonnull NSString*)groupId
                  usersToAdd:(nonnull NSArray<NSString*>*)userIdentities
           completionHandler:(nonnull TKRErrorHandler)handler;

/*!
 @brief Share multiple encrypted resources to multiple users.

 @param resourceIDs resource IDs to share.
 @param options recipient identities and group IDs to share with.
 @param handler the block called with an NSError, or nil.

 @pre @a resourceIDs must contain resource IDs retrieved with the resourceIDOfEncryptedData method.
 @a userIDs must contain valid user IDs.

 If one of those parameters are empty, the method has no effect.
 */
- (void)shareResourceIDs:(nonnull NSArray<NSString*>*)resourceIDs
                 options:(nonnull TKRSharingOptions*)options
       completionHandler:(nonnull TKRErrorHandler)handler;

/*!
 @brief Revoke a device.

 @discussion The handler being called with nil does not mean that the device has been revoked yet.
 The TKRDeviceRevokedHandler will be called once the device is revoked.

 @param deviceId device ID to revoke.
 @param handler the block called with an NSError, or nil.

 @pre @a deviceId must be the ID of one of the current user's devices.

 @deprecated revokeDevice is deprecated, it will be removed in the future
 */
- (void)revokeDevice:(nonnull NSString*)deviceId completionHandler:(nonnull TKRErrorHandler)handler
  DEPRECATED_MSG_ATTRIBUTE("revokeDevice is deprecated, it will be removed in the future");

/*!
@brief Create an encryption session without sharing it with other users or group.
*/
- (void)createEncryptionSessionWithCompletionHandler:(nonnull TKREncryptionSessionHandler)handler;

/*!
 @brief Create an encryption session shared with the given users and groups.

 @param sharingOptions recipient identities and group IDs to share with.
 */
- (void)createEncryptionSessionWithCompletionHandler:(nonnull TKREncryptionSessionHandler)handler
                                      sharingOptions:(nonnull TKRSharingOptions*)sharingOptions
  DEPRECATED_MSG_ATTRIBUTE("use createEncryptionSessionWithCompletionHandler:encryptionOptions instead");

/*!
 @brief Create an encryption session shared with the given users and groups.

 @param encryptionOptions recipient identities and group IDs to share with.
 */
- (void)createEncryptionSessionWithCompletionHandler:(nonnull TKREncryptionSessionHandler)handler
                                   encryptionOptions:(nonnull TKREncryptionOptions*)encryptionOptions;

/*!
 @brief Create an encryption stream from an input stream with customized options.

 @param clearStream the stream to encrypt.
 @param opts custom encryption options.
 @param handler the block called with the encryption stream.
 */
- (void)encryptStream:(nonnull NSInputStream*)clearStream
              options:(nonnull TKREncryptionOptions*)opts
    completionHandler:(nonnull TKRInputStreamHandler)handler;

/*!
 @brief Create an encryption stream from an input stream and share the resource it produces with the user's registered
 devices.

 @discussion equivalent to calling encryptStream:options: with default options.

 @param clearStream the stream to encrypt.
 @param handler the block called with the encryption stream.
 */
- (void)encryptStream:(nonnull NSInputStream*)clearStream completionHandler:(nonnull TKRInputStreamHandler)handler;

/*!
 @brief Create a decryption stream from an encrypted input stream

 @param encryptedStream the stream to decrypt.
 @param handler the block called with the encryption stream.
 */
- (void)decryptStream:(nonnull NSInputStream*)encryptedStream completionHandler:(nonnull TKRInputStreamHandler)handler;

- (void)dealloc;

// MARK: Properties

/// Options with which the TKRTanker object was initialized.
@property(nonnull, readonly) TKRTankerOptions* options;

/// Current Tanker status
@property(readonly) TKRStatus status;

@end
