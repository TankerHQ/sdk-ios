
#import <Foundation/Foundation.h>

#import <PromiseKit/fwd.h>

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

 @return a Promise<NSData*> containing the encrypted chunk.
 */
- (nonnull PMKPromise<NSData*>*)encryptDataFromString:(nonnull NSString*)clearText atIndex:(NSUInteger)index;

/*!
 @brief Encrypt data and create or replace a chunk at the given index.

 @discussion If index is out of bounds, empty chunks will be inserted to fill the gap.
 To avoid this behaviour, use encryptReplaceDataFromData:atIndex:.

 @param clearData data to encrypt.
 @param index the index at which to insert the chunk.

 @return a Promise<NSData*> containing the encrypted chunk.
 */
- (nonnull PMKPromise<NSData*>*)encryptDataFromData:(nonnull NSData*)clearData atIndex:(NSUInteger)index;

/*!
 @brief Encrypt a string and append the result in a new chunk.

 @discussion The string will be converted to UTF-8 before encryption.
 There are no requirements on Unicode Normalization Form (NFC/NFD/NFKC/NFKD).

 @param clearText the string to encrypt.

 @return a Promise<NSData*> containing the encrypted chunk.
*/
- (nonnull PMKPromise<NSData*>*)encryptDataFromString:(nonnull NSString*)clearText;

/*!
 @brief Encrypt data and append the result in a new chunk.

 @param clearData data to encrypt.

 @return a Promise<NSData*> containing the encrypted chunk.
 */
- (nonnull PMKPromise<NSData*>*)encryptDataFromData:(nonnull NSData*)clearData;

/*!
 @brief Remove chunks at given indexes.

 @discussion Indexes do not have to be sorted. Duplicate indexes will be discarded, only one chunk will be removed.

 Note: removing an encrypted chunk will prevent you from decrypting the data previously associated with it.
 Note: removing an encrypted chunk will not leave a gap. Previous indexes might be invalidated depending on their
 position relative to removed chunks.

 @param indexes Indexes at which to remove chunks.

 @pre indexes only contain in-bounds indexes.

 @return an empty promise.
 */
- (nonnull PMKPromise*)removeAtIndexes:(nonnull NSArray<NSNumber*>*)indexes;

/*!
 @brief Decrypt an encrypted chunk and return the decrypted string.

 @param cipherText the encrypted chunk.
 @param index the index of cipherText

 @pre cipherText was returned by one of TKRChunkEncryptor encrypt methods.

 @return a Promise<NSString*> containing the decrypted string.
 */
- (nonnull PMKPromise<NSString*>*)decryptStringFromData:(nonnull NSData*)cipherText atIndex:(NSUInteger)index;

/*!
 @brief Decrypt an encrypted chunk and return the decrypted data.

 @param cipherText the encrypted chunk.
 @param index the index of cipherText

 @pre cipherText was returned by one of TKRChunkEncryptor encrypt methods.

 @return a Promise<NSData*> containing the decrypted data.
 */
- (nonnull PMKPromise<NSData*>*)decryptDataFromData:(nonnull NSData*)cipherText atIndex:(NSUInteger)index;

/*!
 @brief Seal the ChunkEncryptor and share the seal with the user's registered devices.

 @return a Promise<NSData*> containing the seal.
 */
- (nonnull PMKPromise<NSData*>*)seal;

/*!
 @brief Seal the ChunkEncryptor, with custom options.

 @param options Custom encryption options.

 @return a Promise<NSData*> containing the seal.
 */
- (nonnull PMKPromise<NSData*>*)sealWithOptions:(nonnull TKREncryptionOptions*)options;

- (void)dealloc;

/// number of chunks in the encryptor
@property(readonly) NSUInteger count;

@end
