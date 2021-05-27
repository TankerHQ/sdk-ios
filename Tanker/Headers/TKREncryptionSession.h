#import <Tanker/TKRCompletionHandlers.h>

/*!
 @brief Tanker Encryption Session object
 */
@interface TKREncryptionSession : NSObject

// MARK: Instance methods

/*!
 @brief Encrypt a string with the encryption session.

 @discussion The string will be converted to UTF-8 before encryption.
 There are no requirements on Unicode Normalization Form (NFC/NFD/NFKC/NFKD).

 @param clearText The string to encrypt.
 @param handler the block called with the encrypted data.
 */
- (void)encryptString:(nonnull NSString*)clearText completionHandler:(nonnull TKREncryptedDataHandler)handler;

/*!
 @brief Encrypt data with the encryption session.

 @param clearData data to encrypt.
 @param handler the block called with the encrypted data.
 */
- (void)encryptData:(nonnull NSData*)clearData completionHandler:(nonnull TKREncryptedDataHandler)handler;

/*!
 @brief Create an encryption stream from an input stream to be encrypted with the session.

 @param clearStream the stream to encrypt.
 @param handler the block called with the encryption stream.
 */
- (void)encryptStream:(nonnull NSInputStream*)clearStream completionHandler:(nonnull TKRInputStreamHandler)handler;

- (void)dealloc;

// MARK: Properties

/// The resource ID of the encryption session.
@property(nonnull, readonly) NSString* resourceID;

@end
