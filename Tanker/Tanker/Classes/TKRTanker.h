
#import <AvailabilityMacros.h>
#import <Foundation/Foundation.h>
#import <PromiseKit/fwd.h>

#import "TKRChunkEncryptor.h"
#import "TKRDecryptionOptions.h"
#import "TKREncryptionOptions.h"
#import "TKRShareOptions.h"
#import "TKRUnlockOptions.h"
#import "TKRUnlockMethods.h"
#import "TKREvents.h"
#import "TKRStatus.h"
#import "TKRTankerOptions.h"
#import "TKRUnlockKey.h"

#define TKRErrorDomain @"TKRErrorDomain"

/*!
 @brief Tanker object

 @description Every method returning a PMKPromise does not throw.
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

 @discussion If this method returns @NO, you can call registerUnlock or generateAndRegisterUnlockKey.

 @return a PMKPromise<NSNumber*> containing either @YES or @NO.
*/
- (nonnull PMKPromise<NSNumber*>*)isUnlockAlreadySetUp;

/*!
 @brief Check if the current user has already registered an unlock method out of password and email.

 @discussion If this method returns @NO, you can call registerUnlock.

 @return a PMKPromise<NSNumber*> containing either @YES or @NO.
 */
- (nonnull PMKPromise<NSNumber*>*)hasRegisteredUnlockMethods;

/*!
 @brief Check if the current user has registered the given unlock method.

 @discussion If this method returns @NO, you can call registerUnlock to register the corresponding method.

 @return a PMKPromise<NSNumber*> containing either @YES or @NO.
 */
- (nonnull PMKPromise<NSNumber*>*)hasRegisteredUnlockMethod:(NSUInteger)method;

/*!
 @brief Get the list of the unlock methods that have been registered.

 @return a PMKPromise<NSArray*> containing TKRUnlockMethods' values as NSNumber*.
 */
- (nonnull PMKPromise<NSArray*>*)registeredUnlockMethods;

/*!
 @brief Register one or more unlock methods

 @return a void promise.
 */
- (nonnull PMKPromise*)registerUnlock:(nonnull TKRUnlockOptions*)options;

/*!
@brief Set up a password key for the current user.

@discussion Requires Tanker status to be opened.

@param password a password to protect access to the unlock feature.

@return a void promise.
*/
- (nonnull PMKPromise*)setupUnlockWithPassword:(nonnull NSString*)password DEPRECATED_ATTRIBUTE;

/*!
 @brief Update an already existing user password

 @discussion Requires isUnlockAlreadySetUp == @YES.

 @return a void promise.
 */
- (nonnull PMKPromise*)updateUnlockPassword:(nonnull NSString*)newPassword DEPRECATED_ATTRIBUTE;

/*!
 @brief Unlock the current device with an unlock key

 @discussion Once this method returns, the current device can be open.

 @param unlockKey An unlock key returned by generateAndRegisterUnlockKey on a previously accepted device.

 @pre currentDevice.status == TKRStatusDeviceCreation

 @return a void promise.
 */
- (nonnull PMKPromise*)unlockCurrentDeviceWithUnlockKey:(nonnull TKRUnlockKey*)unlockKey;

/*!
@brief Unlock the current device using the password set up with setupUnlockWithPassword.

@param password the password used with setupUnlockWithPassword.

@return a void promise.
 */
- (nonnull PMKPromise*)unlockCurrentDeviceWithPassword:(nonnull NSString*)password;

/*!
 @brief Unlock the current device using the verification code sent to the email registered with registerUnlock.
 
 @param verificationCode the code sent to the registered email.
 
 @return a void promise.
 */
- (nonnull PMKPromise*)unlockCurrentDeviceWithVerificationCode:(nonnull NSString*)verificationCode;

/*!
 @brief Open Tanker.

 @discussion If no device exists, wait for it to be unlocked.

 @param userID The user ID.
 @param userToken The user token generated by createUserTokenWithUserID:userSecret:.

 @post Status is TKRStatusOpen. Encryption operations can be used.

 @return a void promise.
 */
- (nonnull PMKPromise*)openWithUserID:(nonnull NSString*)userID userToken:(nonnull NSString*)userToken;

/*!
 @brief Retrieve the current device id.

 @pre Status is TKRStatusOpen.

 @return a Promise<NSString*> containing the current device id.
 */
- (nonnull PMKPromise<NSString*>*)deviceID;

/*!
 @brief Close Tanker.

 @discussion Perform Tanker cleanup actions.

 @post Status is TKRStatusClosed

 @return a void promise.
*/
- (nonnull PMKPromise*)close;

/*!
 @brief Create a unlock key that can be used to validate devices.

 @discussion A new unlock key is created each time.

 @return a Promise<TKRUnlockKey*>.
 */
- (nonnull PMKPromise<TKRUnlockKey*>*)generateAndRegisterUnlockKey;

/*!
 @brief Create an empty Chunk Encryptor

 @pre Status is TKRStatusOpen
 @post the chunk encryptor is empty

 @return a Promise<TKRChunkEncryptor*>
 */
- (nonnull PMKPromise<TKRChunkEncryptor*>*)makeChunkEncryptor DEPRECATED_ATTRIBUTE;

/*!
 @brief Create a Chunk Encryptor from an existing seal.

 @discussion equivalent to calling makeChunkEncryptorFromSeal:options: with default options.

 @param seal the seal from which the Chunk Encryptor will be created.

 @pre Status is TKRStatusOpen

 @return a Promise<TKRChunkEncryptor*>
 */
- (nonnull PMKPromise<TKRChunkEncryptor*>*)makeChunkEncryptorFromSeal:(nonnull NSData*)seal DEPRECATED_ATTRIBUTE;

/*!
 @brief Create a Chunk Encryptor from an existing seal.

 @param seal the seal from which the Chunk Encryptor will be created.
 @param options Custom decryption options.

 @pre Status is TKRStatusOpen

 @return a Promise<TKRChunkEncryptor*>
 */
- (nonnull PMKPromise<TKRChunkEncryptor*>*)makeChunkEncryptorFromSeal:(nonnull NSData*)seal
                                                              options:(nonnull TKRDecryptionOptions*)options
    DEPRECATED_ATTRIBUTE;

/*!
 @brief Encrypt a string and share it with the user's registered devices.

 @discussion The string will be converted to UTF-8 before encryption.
 There are no requirements on Unicode Normalization Form (NFC/NFD/NFKC/NFKD).

 @param clearText The string to encrypt.

 @return a Promise<NSData*> containing the encrypted string.
 */
- (nonnull PMKPromise<NSData*>*)encryptDataFromString:(nonnull NSString*)clearText;

/*!
 @brief Encrypt a string, using customized options.

 @discussion The string will be converted to UTF-8 before encryption.
 There are no requirements on Unicode Normalization Form (NFC/NFD/NFKC/NFKD).

 @param clearText The string to encrypt.
 @param options Custom encryption options.

 @return a Promise<NSData*> containing the encrypted string.
 */
- (nonnull PMKPromise<NSData*>*)encryptDataFromString:(nonnull NSString*)clearText
                                              options:(nonnull TKREncryptionOptions*)options;

/*!
 @brief Encrypt data and share it with the user's registered devices.

 @discussion equivalent to calling encryptDataFromString:options: with default options.

 @param clearData data to encrypt.

 @return a Promise<NSData*> containing the encrypted data.
 */
- (nonnull PMKPromise<NSData*>*)encryptDataFromData:(nonnull NSData*)clearData;

/*!
 @brief Encrypt data, using customized options.

 @param clearData data to encrypt.
 @param options Custom encryption options.

 @return a Promise<NSData*> containing the encrypted data.
 */
- (nonnull PMKPromise<NSData*>*)encryptDataFromData:(nonnull NSData*)clearData
                                            options:(nonnull TKREncryptionOptions*)options;

/*!
 @brief Decrypt encrypted data as a string.

 @param cipherText encrypted data to decrypt.
 @param options custom decryption options.

 @pre @a cipherText was returned by encryptDataFromString or encryptDataFromString:shareWithUserIDs:.

 @return a Promise<NSString*> containing the decrypted string.
 */
- (nonnull PMKPromise<NSString*>*)decryptStringFromData:(nonnull NSData*)cipherText
                                                options:(nonnull TKRDecryptionOptions*)options;

/*!
 @brief Decrypt encrypted data as a string.

 @discussion equivalent to calling decryptStringFromData:options: with default options.

 @param cipherText encrypted data to decrypt.

 @return a Promise<NSString*> containing the decrypted string.
 */
- (nonnull PMKPromise<NSString*>*)decryptStringFromData:(nonnull NSData*)cipherText;

/*!
 @brief Decrypt encrypted data.

 @discussion equivalent to calling decryptDataFromData:options: with default options.

 @param cipherData encrypted data to decrypt.

 @pre @a cipherText was returned by encryptDataFromData or encryptDataFromData:options:

 @return a Promise<NSData*> containing the decrypted data.
 */
- (nonnull PMKPromise<NSData*>*)decryptDataFromData:(nonnull NSData*)cipherData;

/*!
 @brief Decrypt encrypted data.

 @param cipherText encrypted data to decrypt.
 @param options custom decryption options.
 @return a Promise<NSData*> containing the decrypted data.
 */
- (nonnull PMKPromise<NSData*>*)decryptDataFromData:(nonnull NSData*)cipherText
                                            options:(nonnull TKRDecryptionOptions*)options;

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

 @return the group id.
 */
- (nonnull PMKPromise<NSString*>*)createGroupWithUserIDs:(nonnull NSArray<NSString*>*)userIds;

/*!
 @brief Update a group to add the given user IDs.

 @param groupId the id of the group to update.
 @param usersToAdd the users to add to the group.

 @return a void promise.
 */
- (nonnull PMKPromise*)updateMembersOfGroup:(nonnull NSString*)groupId
                                        add:(nonnull NSArray<NSString*>*)usersToAdd;

/*!
 @brief Share multiple encrypted resources to multiple users.

 @param resourceIDs resource IDs to share.
 @param options user and group IDs to share with.

 @pre @a resourceIDs must contain resource IDs retrieved with the resourceIDOfEncryptedData method.
 @a userIDs must contain valid user IDs.

 If one of those parameters are empty, the method has no effect.
 */
- (nonnull PMKPromise*)shareResourceIDs:(nonnull NSArray<NSString*>*)resourceIDs
                                options:(nonnull TKRShareOptions*)options;

/*!
 @brief Revoke a device from its deviceId
 
 @param deviceId device ID to revoke.
 
 @pre @a deviceId must be the ID of one of the current user's devices.
 
 @return a void promise. The promise being resolved does not mean that the device has been revoked yet. You have to use the TKRDeviceRevokedHandler.
 */
- (nonnull PMKPromise*)revokeDevice:(nonnull NSString*)deviceId;

- (void)dealloc;

// MARK: Properties

/// Options with which the TKR object was initialized.
@property(nonnull, readonly) TKRTankerOptions* options;

/// Current status of the TKR object.
@property(readonly) TKRStatus status;

@end
