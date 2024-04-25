@objc(TKRVerificationOptions)
public class VerificationOptions: NSObject {
  static let C_VERIFICATION_OPTIONS_VERSION: UInt8 = 2;
  
  @objc
  public var withSessionToken: Bool = false;
  @objc
  public var allowE2eMethodSwitch: Bool = false;
  
  func toCVerificationOptions() -> tanker_verification_options_t {
    return tanker_verification_options_t(version: Self.C_VERIFICATION_OPTIONS_VERSION,
                                         with_session_token: self.withSessionToken,
                                         allow_e2e_method_switch: self.allowE2eMethodSwitch);
  }
}
