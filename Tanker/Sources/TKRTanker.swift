import Foundation

@objc
extension TKRTanker {
  static func prehashPassword(_ password: String) throws -> String {
    if password.isEmpty {
      throw NSError(domain: "TKRErrorDomain", code: TKRError.invalidArgument.rawValue, userInfo: [
        NSLocalizedDescriptionKey: "Cannot hash empty password"
      ])
    }
    
    let cPassword = password.cString(using: .utf8);
    let hashedExpected = UnsafeMutableRawPointer(tanker_prehash_password(cPassword)!);
    let hashedPtr: UnsafeMutableRawPointer = TKR_unwrapAndFreeExpected(hashedExpected);
    
    return NSString(
      bytesNoCopy: hashedPtr,
      length: strlen(hashedPtr),
      encoding: String.Encoding.utf8.rawValue,
      freeWhenDone: true
    )! as String
  }
}
