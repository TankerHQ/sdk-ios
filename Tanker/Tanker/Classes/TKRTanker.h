
#import <AvailabilityMacros.h>
#import <Foundation/Foundation.h>

#import "TKRChunkEncryptor.h"
#import "TKRDecryptionOptions.h"
#import "TKREncryptionOptions.h"
#import "TKREvents.h"
#import "TKRShareOptions.h"
#import "TKRStatus.h"
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

/*
 @brief get Tanker status as a string
 */
- (nonnull NSString*)statusAsString;

/*!
 @brief Register a handler called when the current device needs to be unlocked.

 @discussion The handler will not be called for the very first device. When called, you have to call one of the unlock
 methods.

 @param handler This block will be called without any argument, and will be run on a background queue.

 @return an event handler id.
 */
- (nonnull NSNumber*)connectUnlockRequiredHandler:(nonnull TKRUnlockRequiredHandler)handler;

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

 @discussion If @NO is passed to the completion handler, you can call registerUnlock or generateAndRegisterUnlockKey.

 @param handler the block called with either @YES or @NO.
*/
- (void)isUnlockAlreadySetUpWithCompletionHandler:(nonnull TKRBooleanHandler)handler;

/*!
 @brief Check if the current user has already registered an unlock method out of password and email.

 @discussion If @NO is passed to the completion handler, you can call registerUnlock.

 @param handler the block called with either @YES or @NO.
 */
- (void)hasRegisteredUnlockMethodsWithCompletionHandler:(nonnull TKRBooleanHandler)handler;

/*!
 @brief Check if the current user has registered the given unlock method.

 @discussion If @NO is passed to the completion handler, you can call registerUnlock to register the corresponding
 method.

 @param handler the block called with either @YES or @NO.
 */
- (void)hasRegisteredUnlockMethod:(NSUInteger)method completionHandler:(nonnull TKRBooleanHandler)handler;

/*!
 @brief Get the list of the registered unlock methods.

 @param handler the block called with a list of registered methods, represented as NSNumber*.
 */
- (void)registeredUnlockMethodsWithCompletionHandler:(nonnull TKRArrayHandler)handler;

/*!
 @brief Register one or more unlock methods

 @param handler the block called with a NSError*, or nil.
 */
- (void)registerUnlock:(nonnull TKRUnlockOptions*)options completionHandler:(TKRErrorHandler)handler;

/*!
@brief Set up a password key for the current user.

@discussion Requires Tanker status to be opened.

@param password a password to protect access to the unlock feature.
@param handler the block called with a NSError*, or nil.
*/
- (void)setupUnlockWithPassword:(nonnull NSString*)password
              completionHandler:(nonnull TKRErrorHandler)handler DEPRECATED_ATTRIBUTE;

/*!
 @brief Update an already existing user password

 @discussion Requires isUnlockAlreadySetUp == @YES.

 @param handler the block called with a NSError*, or nil.
 */
- (void)updateUnlockPassword:(nonnull NSString*)newPassword
           completionHandler:(nonnull TKRErrorHandler)handler DEPRECATED_ATTRIBUTE;

/*!
 @brief Unlock the current device with an unlock key

 @discussion Once this method returns, the current device can be open.

 @param unlockKey An unlock key returned by generateAndRegisterUnlockKey on a previously accepted device.
 @param handler the block called with a NSError*, or nil.

 @pre currentDevice.status == TKRStatusDeviceCreation
 */
- (void)unlockCurrentDeviceWithUnlockKey:(nonnull TKRUnlockKey*)unlockKey
                       completionHandler:(nonnull TKRErrorHandler)handler;

/*!
 @brief Unlock the current device using the password set up with setupUnlockWithPassword.

 @param password the password used with setupUnlockWithPassword.
 @param handler the block called with a NSError*, or nil.
 */
- (void)unlockCurrentDeviceWithPassword:(nonnull NSString*)password completionHandler:(nonnull TKRErrorHandler)handler;

/*!
 @brief Unlock the current device using the verification code sent to the email registered with registerUnlock.

 @param verificationCode the code sent to the registered email.
 @param handler the block called with a NSError*, or nil.
 */
- (void)unlockCurrentDeviceWithVerificationCode:(nonnull NSString*)verificationCode
                              completionHandler:(nonnull TKRErrorHandler)handler;

/*!
 @brief Open Tanker.

 @discussion If no device exists, wait for it to be unlocked.

 @param userID The user ID.
 @param userToken The user token generated by createUserTokenWithUserID:userSecret:.
 @param handler the block called with a NSError*, or nil.

 @post Status is TKRStatusOpen. Encryption operations can be used.
 */
- (void)openWithUserID:(nonnull NSString*)userID
             userToken:(nonnull NSString*)userToken
     completionHandler:(nonnull TKRErrorHandler)handler;

/*!
 @brief Retrieve the current device id.

 @param handler the block called with the device id.

 @pre Status is TKRStatusOpen.
 */
- (void)deviceIDWithCompletionHandler:(nonnull TKRStringHandler)handler;

/*!
 @brief Close Tanker.

 @discussion Perform Tanker cleanup actions.

 @param handler the block called with a NSError*, or nil.

 @post Status is TKRStatusClosed
*/
- (void)closeWithCompletionHandler:(nonnull TKRErrorHandler)handler;

/*!
 @brief Create a unlock key that can be used to validate devices.

 @discussion A new unlock key is created each time.

 @param handler the block called with the unlock key, or nil.
 */
- (void)generateAndRegisterUnlockKeyWithCompletionHandler:(nonnull TKRUnlockKeyHandler)handler;

/*!
 @brief Create an empty Chunk Encryptor

 @param handler the block called with the created chunk encryptor.

 @pre Status is TKRStatusOpen
 @post the chunk encryptor is empty
 */
- (void)makeChunkEncryptorWithCompletionHandler:(nonnull TKRChunkEncryptorHandler)handler DEPRECATED_ATTRIBUTE;

/*!
 @brief Create a Chunk Encryptor from an existing seal.

 @discussion equivalent to calling makeChunkEncryptorFromSeal:options: with default options.

 @param seal the seal from which the chunk encryptor will be created.
 @param handler the block called with the created chunk encryptor.

 @pre Status is TKRStatusOpen
 */
- (void)makeChunkEncryptorFromSeal:(nonnull NSData*)seal
                 completionHandler:(nonnull TKRChunkEncryptorHandler)handler DEPRECATED_ATTRIBUTE;

/*!
 @brief Create a Chunk Encryptor from an existing seal.

 @param seal the seal from which the Chunk Encryptor will be created.
 @param options Custom decryption options.
 @param handler the block called with the created chunk encryptor.

 @pre Status is TKRStatusOpen
 */
- (void)makeChunkEncryptorFromSeal:(nonnull NSData*)seal
                           options:(nonnull TKRDecryptionOptions*)options
                 completionHandler:(nonnull TKRChunkEncryptorHandler)handler DEPRECATED_ATTRIBUTE;

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

 @param cipherText encrypted data to decrypt.
 @param options custom decryption options.
 @param handler the block called with the decrypted string.

 @pre @a cipherText was returned by encryptDataFromString or encryptDataFromString:shareWithUserIDs:.
 */
- (void)decryptStringFromData:(nonnull NSData*)cipherText
                      options:(nonnull TKRDecryptionOptions*)options
            completionHandler:(nonnull TKRDecryptedStringHandler)handler;

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
 @brief Decrypt encrypted data.

 @param cipherText encrypted data to decrypt.
 @param options custom decryption options.
 @param handler the block called with the decrypted data.

 @pre @a cipherText was returned by encryptDataFromData.
 */
- (void)decryptDataFromData:(nonnull NSData*)cipherText
                    options:(nonnull TKRDecryptionOptions*)options
          completionHandler:(nonnull TKRDecryptedDataHandler)handler;

/*!
 @brief Get the encrypted resource ID.

 @param cipherData encrypted data.
 @param error output parameter

 @return the resource id.
 */
- (nullable NSString*)resourceIDOfEncryptedData:(nonnull NSData*)cipherData error:(NSError* _Nullable* _Nonnull)error;

/*!
 @brief Create a group with the given user IDs.

 @param userIds the users to add to the group.
 @param handler the block called with the group id.
 */
- (void)createGroupWithUserIDs:(nonnull NSArray<NSString*>*)userIds completionHandler:(nonnull TKRStringHandler)handler;

/*!
 @brief Update a group to add the given user IDs.

 @param groupId the id of the group to update.
 @param usersToAdd the users to add to the group.
 @param handler the block called with a NSError, or nil.
 */
- (void)updateMembersOfGroup:(nonnull NSString*)groupId
                         add:(nonnull NSArray<NSString*>*)usersToAdd
           completionHandler:(nonnull TKRErrorHandler)handler;

/*!
 @brief Share multiple encrypted resources to multiple users.

 @param resourceIDs resource IDs to share.
 @param options user and group IDs to share with.
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

/// Current status of the TKR object.
@property(readonly) TKRStatus status;

@end
