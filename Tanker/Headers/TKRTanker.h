
#import <AvailabilityMacros.h>
#import <Foundation/Foundation.h>

#import <Tanker/TKRCompletionHandlers.h>
#import <Tanker/TKREncryptionOptions.h>
#import <Tanker/TKRSharingOptions.h>
#import <Tanker/TKRStatus.h>
#import <Tanker/TKRTankerOptions.h>
#import <Tanker/TKRVerification.h>
#import <Tanker/TKRVerificationKey.h>
#import <Tanker/TKRVerificationMethod.h>
#import <Tanker/TKRVerificationOptions.h>

/*!
 @brief Tanker object
 */
@interface TKRTanker : NSObject

// MARK: Class methods
/*!
 @brief Create a TKRTanker object with options.

 @param options Options needed to initialize Tanker.

 @pre Every field must be set with a valid value.
 
 @result  Errors with NSInvalidArgumentException if initialization fails

 @return An initialized TKRTanker*.

 */
+ (nullable TKRTanker*)tankerWithOptions:(nonnull TKRTankerOptions*)options err:(NSError**)errResult;

/*!
 @brief Get Tanker version as a string
 */
+ (nonnull NSString*)versionString;

+ (nonnull NSString*)nativeVersionString;

+ (nonnull NSString*)prehashPassword:(nonnull NSString*)password;

+ (void)connectLogHandler:(nonnull TKRLogHandler)handler;

// MARK: Instance methods

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
 @brief Register or update a verification method.

 @pre status must be TKRStatusReady

 @param verification the verification.
 @param options extra options for identity verification
 @param handler the block called with an NSError*, or nil.
 */
- (void)setVerificationMethod:(nonnull TKRVerification*)verification
                      options:(nonnull TKRVerificationOptions*)options
            completionHandler:(nonnull TKRIdentityVerificationHandler)handler;

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
 @brief Register an identity and associate a verification method.

 @pre status must be TKRStatusIdentityRegistrationNeeded

 @param verification the verification.
 @param options extra options for identity verification
 @param handler the block called with an NSError*, or nil.
 */
- (void)registerIdentityWithVerification:(nonnull TKRVerification*)verification
                                 options:(nonnull TKRVerificationOptions*)options
                       completionHandler:(nonnull TKRIdentityVerificationHandler)handler;

/*!
 @brief Verify an identity

 @pre status must be TKRStatusIdentityVerificationNeeded

 @param verification the verification.
 @param handler the block called with an NSError*, or nil.
 */
- (void)verifyIdentityWithVerification:(nonnull TKRVerification*)verification
                     completionHandler:(nonnull TKRErrorHandler)handler;

/*!
 @brief Verify an identity

 @pre status must be TKRStatusIdentityVerificationNeeded

 @param verification the verification.
 @param options extra options for identity verification
 @param handler the block called with an NSError*, or nil.
 */
- (void)verifyIdentityWithVerification:(nonnull TKRVerification*)verification
                               options:(nonnull TKRVerificationOptions*)options
                     completionHandler:(nonnull TKRIdentityVerificationHandler)handler;

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
- (void)deviceIDWithCompletionHandler:(nonnull TKRDeviceIDHandler)handler
  DEPRECATED_MSG_ATTRIBUTE("This method is deprecated and will be removed in a future version");

/*!
 @brief Stop Tanker.

 @discussion Perform Tanker cleanup actions.

 @param handler the block called with an NSError*, or nil.

 @post Status is TKRStatusStopped
*/
- (void)stopWithCompletionHandler:(nonnull TKRErrorHandler)handler;

/*!
 @brief Create a nonce to use in Oidc authorization code flow

 @param handler the block called with the nonce.
 */
- (void)createOidcNonceWithCompletionHandler:(nonnull TKRNonceHandler)handler;

/*!
 @brief Set the nonce to use during Oidc verification
 */
- (void)setOidcTestNonce:(nonnull NSString*)nonce
       completionHandler:(nonnull TKRErrorHandler)handler;

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
 @brief Update a group to add the given users.

 @param groupId the id of the group to update.
 @param usersToAdd the users to add to the group.
 @param handler the block called with an NSError, or nil.
 */
- (void)updateMembersOfGroup:(nonnull NSString*)groupId
                  usersToAdd:(nonnull NSArray<NSString*>*)usersToAdd
           completionHandler:(nonnull TKRErrorHandler)handler;

/*!
 @brief Update a group to add and/or remove the given users.

 @param groupId the id of the group to update.
 @param usersToAdd the users to add to the group.
 @param usersToRemove the users to remove from the group.
 @param handler the block called with an NSError, or nil.
 */
- (void)updateMembersOfGroup:(nonnull NSString*)groupId
                  usersToAdd:(nonnull NSArray<NSString*>*)usersToAdd
               usersToRemove:(nonnull NSArray<NSString*>*)usersToRemove
           completionHandler:(nonnull TKRErrorHandler)handler;

/*!
 @brief Authenticates against a trusted identity provider.

 @warning Experimental: This API is exposed for testing purposes only

 @pre status must be TKRStatusIdentityRegistrationNeeded, TKRStatusIdentityVerificationNeeded or TKRStatusReady
 
 @param providerID oidc provider id of the trusted identity provider (as returned by the app managment API)
 @param cookie a cookie-list added to the authorization HTTP request (see https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Cookie)
 @param handler the block called with an NSError, or TKRVerification*.
 */
- (void)authenticateWithIDP:(NSString*)providerID
                     cookie:(NSString*)cookie
          completionHandler:(nonnull TKRAuthenticateWithIDPResultHandler)handler;

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
@brief Create an encryption session without sharing it with other users or group.
*/
- (void)createEncryptionSessionWithCompletionHandler:(nonnull TKREncryptionSessionHandler)handler;

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
