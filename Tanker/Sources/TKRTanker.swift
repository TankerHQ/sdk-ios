import Foundation

// A numeric key for the associated ctanker object (must match the objc value)
private var AssociatedCTankerHandle: UInt8 = 0

@objc(TKRTanker)
public extension Tanker {
  static let TANKER_IOS_VERSION = "9999.0.0";
  
  private var cTanker: OpaquePointer? {
    get {
        return objc_getAssociatedObject(self, &AssociatedCTankerHandle) as! OpaquePointer?
    }
    set {
        objc_setAssociatedObject(self, &AssociatedCTankerHandle, newValue, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN)
    }
  }
  
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
  
  @objc
  static func versionString() -> String {
    TANKER_IOS_VERSION
  }
  
  @objc
  static func nativeVersionString() -> String {
    String(cString: tanker_version_string())
  }
  
  @objc
  func start(identity: String, completionHandler handler: @escaping (_ status: TKRStatus, _ error: NSError?) -> ()) {
    let adapter: TKRAdapter = {(status: NSNumber?, error: (any Error)?) in
      if (error != nil) {
        handler(TKRStatus(rawValue: 0)!, error as NSError?);
      } else {
        handler(TKRStatus(rawValue: status!.uintValue)!, nil);
      }
    };
    let bridgeRetainedAdapter = Unmanaged.passRetained(adapter as AnyObject).toOpaque();
    
    let startFuture = tanker_start(self.cTanker, identity.cString(using: .utf8));
    let resolveFuture = tanker_future_then(startFuture, resolvePromise, bridgeRetainedAdapter)
    tanker_future_destroy(startFuture);
    tanker_future_destroy(resolveFuture);
  }
  
  @objc
  func registerIdentity(verification: Verification,
                        completionHandler handler: @escaping (_ error: NSError?) -> ()) {
    self.registerIdentity(verification: verification, options: VerificationOptions()) { (_: String?, error: NSError?) in
      handler(error);
    }
  }
  
  @objc
  func registerIdentity(verification: Verification,
                        options: VerificationOptions,
                        completionHandler handler: @escaping (_ sessionToken: String?, _ error: NSError?) -> ()) {
    let adapter: TKRAdapter = {(tokenPtrVal: NSNumber?, error: (any Error)?) in
      let tokenPtr = UnsafeRawPointer(bitPattern: tokenPtrVal?.uintValue ?? 0)
      if (error != nil || tokenPtr == nil) {
        handler(nil, error as NSError?)
      } else {
        let sessToken = String(cString: tokenPtr!.assumingMemoryBound(to: UInt8.self))
        tanker_free_buffer(tokenPtr)
        handler(sessToken, nil)
      }
    }
    let bridgeRetainedAdapter = Unmanaged.passRetained(adapter as AnyObject).toOpaque()
    
    let cOptions = options.toCVerificationOptions()
    let cVerif = verification.toCVerification()
    
    withUnsafePointer(to: cOptions) { cOptionsPtr in
      withUnsafePointer(to: cVerif) { cVerifPtr in
        let registerFuture = tanker_register_identity(self.cTanker, cVerifPtr, cOptionsPtr)
        let resolveFuture = tanker_future_then(registerFuture, resolvePromise, bridgeRetainedAdapter)
        tanker_future_destroy(registerFuture)
        tanker_future_destroy(resolveFuture)
      }
    }
  }
  
  @objc
  func verifyIdentity(verification: Verification,
                      completionHandler handler: @escaping (_ error: NSError?) -> ()) {
    self.verifyIdentity(verification: verification, options: VerificationOptions()) { (_: String?, error: NSError?) in
      handler(error);
    }
  }
  
  @objc
  func verifyIdentity(verification: Verification,
                      options: VerificationOptions,
                      completionHandler handler: @escaping (_ sessionToken: String?, _ error: NSError?) -> ()) {
    let adapter: TKRAdapter = {(tokenPtrVal: NSNumber?, error: (any Error)?) in
      let tokenPtr = UnsafeRawPointer(bitPattern: tokenPtrVal?.uintValue ?? 0)
      if (error != nil || tokenPtr == nil) {
        handler(nil, error as NSError?)
      } else {
        let sessToken = String(cString: tokenPtr!.assumingMemoryBound(to: UInt8.self))
        tanker_free_buffer(tokenPtr)
        handler(sessToken, nil)
      }
    }
    let bridgeRetainedAdapter = Unmanaged.passRetained(adapter as AnyObject).toOpaque()
    
    let cOptions = options.toCVerificationOptions()
    let cVerif = verification.toCVerification()
    
    withUnsafePointer(to: cOptions) { cOptionsPtr in
      withUnsafePointer(to: cVerif) { cVerifPtr in
        let verifyFuture = tanker_verify_identity(self.cTanker, cVerifPtr, cOptionsPtr)
        let resolveFuture = tanker_future_then(verifyFuture, resolvePromise, bridgeRetainedAdapter)
        tanker_future_destroy(verifyFuture)
        tanker_future_destroy(resolveFuture)
      }
    }
  }
  
  @objc
  func setVerificationMethod(verification: Verification,
                             completionHandler handler: @escaping (_ error: NSError?) -> ()) {
    self.setVerificationMethod(verification: verification, options: VerificationOptions()) { (_: String?, error: NSError?) in
      handler(error);
    }
  }
  
  @objc
  func setVerificationMethod(verification: Verification,
                             options: VerificationOptions,
                             completionHandler handler: @escaping (_ sessionToken: String?, _ error: NSError?) -> ()) {
    let adapter: TKRAdapter = {(tokenPtrVal: NSNumber?, error: (any Error)?) in
      let tokenPtr = UnsafeRawPointer(bitPattern: tokenPtrVal?.uintValue ?? 0)
      if (error != nil || tokenPtr == nil) {
        handler(nil, error as NSError?)
      } else {
        let sessToken = String(cString: tokenPtr!.assumingMemoryBound(to: UInt8.self))
        tanker_free_buffer(tokenPtr)
        handler(sessToken, nil)
      }
    }
    let bridgeRetainedAdapter = Unmanaged.passRetained(adapter as AnyObject).toOpaque()
    
    let cOptions = options.toCVerificationOptions()
    let cVerif = verification.toCVerification()
    
    withUnsafePointer(to: cOptions) { cOptionsPtr in
      withUnsafePointer(to: cVerif) { cVerifPtr in
        let setFuture = tanker_set_verification_method(self.cTanker, cVerifPtr, cOptionsPtr)
        let resolveFuture = tanker_future_then(setFuture, resolvePromise, bridgeRetainedAdapter)
        tanker_future_destroy(setFuture)
        tanker_future_destroy(resolveFuture)
      }
    }
  }
  
  @objc
  func verifyProvisionalIdentity(verification: Verification,
                                 completionHandler handler: @escaping (_ error: NSError?) -> ()) {
    let adapter: TKRAdapter = {(_unused: NSNumber?, error: (any Error)?) in
      handler(error as NSError?)
    }
    let bridgeRetainedAdapter = Unmanaged.passRetained(adapter as AnyObject).toOpaque()
    
    let cVerif = verification.toCVerification()
    
    withUnsafePointer(to: cVerif) { cVerifPtr in
      let verifyFuture = tanker_verify_provisional_identity(self.cTanker, cVerifPtr)
      let resolveFuture = tanker_future_then(verifyFuture, resolvePromise, bridgeRetainedAdapter)
      tanker_future_destroy(verifyFuture)
      tanker_future_destroy(resolveFuture)
    }
  }
  
  @objc(authenticateWithIDP:cookie:completionHandler:)
  func authenticateWithIDP(providerID: String,
                           cookie: String,
                           completionHandler handler: @escaping (_ verification: Verification?, _ error: NSError?) -> ()) {
    let adapter: TKRAdapter = {(verifPtrValue: NSNumber?, error: (any Error)?) in
      if (error != nil) {
        handler(nil, error as NSError?)
      } else {
        let cVerifPtr = UnsafeMutableRawPointer(bitPattern: verifPtrValue!.uintValue)
        let cVerif = cVerifPtr!.assumingMemoryBound(to: tanker_oidc_authorization_code_verification_t.self)
        let verif = Verification(oidcAuthorizationCode: String(cString: cVerif.pointee.authorization_code),
                                 providerID: String(cString: cVerif.pointee.provider_id),
                                 state: String(cString: cVerif.pointee.state))
        tanker_free_authenticate_with_idp_result(cVerif)
        handler(verif, nil)
      }
    }
    let bridgeRetainedAdapter = Unmanaged.passRetained(adapter as AnyObject).toOpaque()

    let authFuture = tanker_authenticate_with_idp(self.cTanker, providerID.cString(using: .utf8), cookie.cString(using: .utf8))
    let resolveFuture = tanker_future_then(authFuture, resolvePromise, bridgeRetainedAdapter)
    tanker_future_destroy(authFuture)
    tanker_future_destroy(resolveFuture)
  }
}
