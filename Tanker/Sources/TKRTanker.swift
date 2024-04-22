import Foundation

internal func getExpectedString(_ expected: OpaquePointer) -> String {
  let expectedRawPtr = TKR_unwrapAndFreeExpected(UnsafeMutableRawPointer(expected));
  // NOTE: freeWhenDone will call free() instead of tanker_free(), but this should be fine
  return NSString(
    bytesNoCopy: expectedRawPtr,
    length: strlen(expectedRawPtr),
    encoding: String.Encoding.utf8.rawValue,
    freeWhenDone: true
  )! as String
}

@objc(TKRTanker)
public extension Tanker {
  @objc
  static func prehashPassword(_ password: String) throws -> String {
    if password.isEmpty {
      throw NSError(domain: "TKRErrorDomain", code: TKRError.invalidArgument.rawValue, userInfo: [
        NSLocalizedDescriptionKey: "Cannot hash empty password"
      ])
    }
    
    let cPassword = password.cString(using: .utf8);
    return getExpectedString(tanker_prehash_password(cPassword)!);
  }
}
