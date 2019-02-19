
#import <Foundation/Foundation.h>

#import "TKRCompletionHandlers.h"
#import "TKREncryptionOptions.h"

@interface TKRChunkEncryptor : NSObject

/*!
 @brief Encrypt a string and create or replace a chunk at the given index.

 @discussion If index is out of bounds, empty chunks will be inserted to fill the gap.
 To avoid this behaviour, use encryptReplaceDataFromString:atIndex:.

 The string will be converted to UTF-8 before encryption.
 There are no requirements on Unicode Normalization Form (NFC/NFD/NFKC/NFKD).

 @param clearText the string to encrypt.
 @param index the index at which to insert the chunk.
 @param handler the block which will be called with the encrypted chunk.
 */
- (void)encryptDataFromString:(nonnull NSString*)clearText
                      atIndex:(NSUInteger)index
            completionHandler:(nonnull TKREncryptedDataHandler)handler;

/*!
 @brief Encrypt data and create or replace a chunk at the given index.

 @discussion If index is out of bounds, empty chunks will be inserted to fill the gap.
 To avoid this behaviour, use encryptReplaceDataFromData:atIndex:.

 @param clearData data to encrypt.
 @param index the index at which to insert the chunk.
 @param handler the block which will be called with the encrypted chunk.
 */
- (void)encryptDataFromData:(nonnull NSData*)clearData
                    atIndex:(NSUInteger)index
          completionHandler:(nonnull TKREncryptedDataHandler)handler;

/*!
 @brief Encrypt a string and append the result in a new chunk.

 @discussion The string will be converted to UTF-8 before encryption.
 There are no requirements on Unicode Normalization Form (NFC/NFD/NFKC/NFKD).

 @param clearText the string to encrypt.
 @param handler the block which will be called with the encrypted chunk.
*/
- (void)encryptDataFromString:(nonnull NSString*)clearText completionHandler:(nonnull TKREncryptedDataHandler)handler;

/*!
 @brief Encrypt data and append the result in a new chunk.

 @param clearData data to encrypt.
 @param handler the block which will be called with the encrypted chunk.
 */
- (void)encryptDataFromData:(nonnull NSData*)clearData completionHandler:(nonnull TKREncryptedDataHandler)handler;

/*!
 @brief Remove chunks at given indexes.

 @discussion Indexes do not have to be sorted. Duplicate indexes will be discarded, only one chunk will be removed.

 Note: removing an encrypted chunk will prevent you from decrypting the data previously associated with it.
 Note: removing an encrypted chunk will not leave a gap. Previous indexes might be invalidated depending on their
 position relative to removed chunks.

 @param indexes indexes at which to remove chunks.
 @param err output parameter set when an error occurs, or set to nil.

 @pre indexes only contain in-bounds indexes.
 */
- (void)removeAtIndexes:(nonnull NSArray<NSNumber*>*)indexes error:(NSError* _Nullable* _Nonnull)err;

/*!
 @brief Decrypt an encrypted chunk and return the decrypted string.

 @param cipherText the encrypted chunk.
 @param index the index of cipherText
 @param handler the block which will be called with the decrypted chunk, as a string.

 @pre cipherText was returned by one of TKRChunkEncryptor encrypt methods.
 */
- (void)decryptStringFromData:(nonnull NSData*)cipherText
                      atIndex:(NSUInteger)index
            completionHandler:(nonnull TKRDecryptedStringHandler)handler;

/*!
 @brief Decrypt an encrypted chunk and return the decrypted data.

 @param cipherText the encrypted chunk.
 @param index the index of cipherText
 @param handler the block which will be called with the decrypted chunk.

 @pre cipherText was returned by one of TKRChunkEncryptor encrypt methods.
 */
- (void)decryptDataFromData:(nonnull NSData*)cipherText
                    atIndex:(NSUInteger)index
          completionHandler:(nonnull TKRDecryptedDataHandler)handler;

/*!
 @brief Seal the ChunkEncryptor and share the seal with the user's registered devices.

 @param handler the block which will be called with the seal.
 */
- (void)sealWithCompletionHandler:(nonnull TKRSealHandler)handler;

/*!
 @brief Seal the ChunkEncryptor, with custom options.

 @param options custom encryption options.
 @param handler the block which will be called with the seal.
 */
- (void)sealWithOptions:(nonnull TKREncryptionOptions*)options completionHandler:(nonnull TKRSealHandler)handler;

- (void)dealloc;

/// number of chunks in the encryptor
@property(readonly) NSUInteger count;

@end
