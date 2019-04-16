
#import <AvailabilityMacros.h>
#import <Foundation/Foundation.h>

#import "TKRAuthenticationMethods.h"
#import "TKRCompletionHandlers.h"
#import "TKREncryptionOptions.h"
#import "TKREvents.h"
#import "TKRShareOptions.h"
#import "TKRSignInOptions.h"
#import "TKRTankerOptions.h"
#import "TKRUnlockKey.h"
#import "TKRUnlockMethods.h"
#import "TKRUnlockOptions.h"

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

// MARK: Instance methods

/*!
 @brief Register a handler called when the current device is revoked.

 @discussion The handler will be called as soon as the device is revoked.

 @param handler This block will be called without any argument, and will be run on a background queue.

 @return an event handler id.
 */
- (nonnull NSNumber*)connectDeviceRevokedHandler:(nonnull TKRDeviceRevokedHandler)handler;
/*!
 @brief Register a handler called when new devices have been unlocked for the current user since their last connection.

 @discussion The handler will be called as soon as the device is unlocked or new devices
             have been unlocked for the current user since his last connection

 @param handler This block will be called without any argument, and will be run on a background queue.

 @return an event handler id.
 */
- (nonnull NSNumber*)connectDeviceCreatedHandler:(nonnull TKRDeviceCreatedHandler)handler;
/*!
 @brief Check if the current user has already registered an unlock key.

 @discussion If @NO is passed to the completion handler, you can call registerUnlockWithOptions or
 generateAndRegisterUnlockKey.

 @param handler the block called with either @YES or @NO.
*/
- (void)isUnlockAlreadySetUpWithCompletionHandler:(nonnull TKRBooleanHandler)handler;

/*!
 @brief Check if the current user has already registered an unlock method out of password and email.

 @discussion If NO is returned, you can call registerUnlock.

 @param err output error parameter.

 @return YES if any method has been registered, NO otherwise.
 */
- (BOOL)hasRegisteredUnlockMethodsWithError:(NSError* _Nullable* _Nonnull)err;

/*!
 @brief Check if the current user has registered the given unlock method.

 @discussion If NO is returned, you can call registerUnlockWithOptions to register the corresponding
 method.

 @param method unlock method to check.
 @param err output error parameter.

 @return YES if the method has been registered, NO otherwise.
 */
- (BOOL)hasRegisteredUnlockMethod:(TKRUnlockMethods)method error:(NSError* _Nullable* _Nonnull)err;

/*!
 @brief Get the list of the registered unlock methods.

 @param err output error parameter.

 @return a list of registered unlock methods, represented as NSNumber*, or nil if an error occurs.
 */
- (nullable NSArray<NSNumber*>*)registeredUnlockMethodsWithError:(NSError* _Nullable* _Nonnull)err;

/*!
 @brief Register one or more unlock methods

 @param handler the block called with a NSError*, or nil.
 */
- (void)registerUnlockWithOptions:(nonnull TKRUnlockOptions*)options completionHandler:(TKRErrorHandler)handler;

/*!
 @brief Sign up to Tanker

 @param identity a previously registered Tanker identity.
 @param handler the block called with the sign-up result.
 */
- (void)signUpWithIdentity:(nonnull NSString*)identity completionHandler:(nonnull TKRSignUpHandler)handler;

/*!
 @brief Sign up to Tanker and set authentication methods

 @param identity a previously registered Tanker identity.
 @param methods authentication methods to set up.
 @param handler the block called with the sign-up result.
 */
- (void)signUpWithIdentity:(nonnull NSString*)identity
     authenticationMethods:(nonnull TKRAuthenticationMethods*)methods
         completionHandler:(nonnull TKRSignUpHandler)handler;

/*!
 @brief Sign in to Tanker

 @param identity a previously registered Tanker identity.
 @param options sign-in options.
 @param handler the block called with the sign-in result.
 */
- (void)signInWithIdentity:(nonnull NSString*)identity
                   options:(nonnull TKRSignInOptions*)options
         completionHandler:(nonnull TKRSignInHandler)handler;

/*!
 @brief Sign in to Tanker

 @param identity a previously registered Tanker identity.
 @param handler the block called with the sign-in result.
 */
- (void)signInWithIdentity:(nonnull NSString*)identity completionHandler:(nonnull TKRSignInHandler)handler;

/*!
 @brief returns true if Tanker is open
 */
- (BOOL)isOpen;

/*!
 @brief Retrieve the current device id.

 @param handler the block called with the device id.

 @pre Status is TKRStatusOpen.
 */
- (void)deviceIDWithCompletionHandler:(nonnull TKRDeviceIDHandler)handler;

/*!
 @brief Sign out of Tanker.

 @discussion Perform Tanker cleanup actions.

 @param handler the block called with a NSError*, or nil.

 @post Status is TKRStatusClosed
*/
- (void)signOutWithCompletionHandler:(nonnull TKRErrorHandler)handler;

/*!
 @brief Create a unlock key that can be used to validate devices.

 @discussion A new unlock key is created each time.

 @param handler the block called with the unlock key, or nil.
 */
- (void)generateAndRegisterUnlockKeyWithCompletionHandler:(nonnull TKRUnlockKeyHandler)handler;

/*!
 @brief Encrypt a string and share it with the user's registered devices.

 @discussion The string will be converted to UTF-8 before encryption.
 There are no requirements on Unicode Normalization Form (NFC/NFD/NFKC/NFKD).

 @param clearText The string to encrypt.
 @param handler the block called with the encrypted data.
 */
- (void)encryptDataFromString:(nonnull NSString*)clearText completionHandler:(nonnull TKREncryptedDataHandler)handler;

/*!
 @brief Encrypt a string, using customized options.

 @discussion The string will be converted to UTF-8 before encryption.
 There are no requirements on Unicode Normalization Form (NFC/NFD/NFKC/NFKD).

 @param clearText The string to encrypt.
 @param options Custom encryption options.
 @param handler the block called with the encrypted data.
 */
- (void)encryptDataFromString:(nonnull NSString*)clearText
                      options:(nonnull TKREncryptionOptions*)options
            completionHandler:(nonnull TKREncryptedDataHandler)handler;

/*!
 @brief Encrypt data and share it with the user's registered devices.

 @discussion equivalent to calling encryptDataFromString:options: with default options.

 @param clearData data to encrypt.
 @param handler the block called with the encrypted data.
 */
- (void)encryptDataFromData:(nonnull NSData*)clearData completionHandler:(nonnull TKREncryptedDataHandler)handler;

/*!
 @brief Encrypt data, using customized options.

 @param clearData data to encrypt.
 @param options custom encryption options.
 @param handler the block called with the encrypted data.
 */
- (void)encryptDataFromData:(nonnull NSData*)clearData
                    options:(nonnull TKREncryptionOptions*)options
          completionHandler:(nonnull TKREncryptedDataHandler)handler;

/*!
 @brief Decrypt encrypted data as a string.

 @discussion equivalent to calling decryptStringFromData:options: with default options.

 @param cipherText encrypted data to decrypt.
 @param handler the block called with the decrypted string.

 @pre @a cipherText was returned by encryptDataFromString.
 */
- (void)decryptStringFromData:(nonnull NSData*)cipherText completionHandler:(nonnull TKRDecryptedStringHandler)handler;

/*!
 @brief Decrypt encrypted data.

 @discussion equivalent to calling decryptDataFromData:options: with default options.

 @param cipherData encrypted data to decrypt.
 @param handler the block called with the decrypted data.

 @pre @a cipherText was returned by encryptDataFromData.
 */
- (void)decryptDataFromData:(nonnull NSData*)cipherData completionHandler:(nonnull TKRDecryptedDataHandler)handler;

/*!
 @brief Get the encrypted resource ID.

 @param cipherData encrypted data.
 @param error output error parameter.

 @return the resource id.
 */
- (nullable NSString*)resourceIDOfEncryptedData:(nonnull NSData*)cipherData error:(NSError* _Nullable* _Nonnull)error;

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
 @param identities the users to add to the group.
 @param handler the block called with a NSError, or nil.
 */
- (void)updateMembersOfGroup:(nonnull NSString*)groupId
             identitiesToAdd:(nonnull NSArray<NSString*>*)identities
           completionHandler:(nonnull TKRErrorHandler)handler;

/*!
 @brief Share multiple encrypted resources to multiple users.

 @param resourceIDs resource IDs to share.
 @param options recipient identities and group IDs to share with.
 @param handler the block called with a NSError, or nil.

 @pre @a resourceIDs must contain resource IDs retrieved with the resourceIDOfEncryptedData method.
 @a userIDs must contain valid user IDs.

 If one of those parameters are empty, the method has no effect.
 */
- (void)shareResourceIDs:(nonnull NSArray<NSString*>*)resourceIDs
                 options:(nonnull TKRShareOptions*)options
       completionHandler:(nonnull TKRErrorHandler)handler;

/*!
 @brief Revoke a device from its deviceId

 @discussion The handler being called with nil does not mean that the device has been revoked yet. You have to use the
 TKRDeviceRevokedHandler.

 @param deviceId device ID to revoke.
 @param handler the block called with a NSError, or nil.

 @pre @a deviceId must be the ID of one of the current user's devices.
 */
- (void)revokeDevice:(nonnull NSString*)deviceId completionHandler:(nonnull TKRErrorHandler)handler;

- (void)dealloc;

// MARK: Properties

/// Options with which the TKR object was initialized.
@property(nonnull, readonly) TKRTankerOptions* options;

@end
