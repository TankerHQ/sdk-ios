import Foundation

// A numeric key for the associated ctanker object (must match the objc value)
private var AssociatedCTankerHandle: UInt8 = 0

@objc(TKRTanker)
public extension Tanker {
  static let TANKER_IOS_VERSION = "9999";
  
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
}
