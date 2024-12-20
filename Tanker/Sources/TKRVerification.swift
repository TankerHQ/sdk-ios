// Objective-C doesn't support enums with associated values, so we expose a wrapper
@objc(TKRVerification)
public class Verification: NSObject {
  public let data: VerificationData;
  
  @objc(withPassphrase:)
  public init(passphrase: String) {
    self.data = VerificationData.passphrase(passphrase)
  }
  
  @objc(withE2ePassphrase:)
  public init(e2ePassphrase: String) {
    self.data = VerificationData.e2ePassphrase(e2ePassphrase)
  }
  
  @objc(withVerificationKey:)
  public init(verificationKey: VerificationKey) {
    self.data = VerificationData.verificationKey(verificationKey)
  }
  
  @objc(withEmail:verificationCode:)
  public init(email: String, verificationCode: String) {
    self.data = VerificationData.email(EmailVerification(email: email, verificationCode: verificationCode))
  }
  
  @objc(withOIDCIDToken:)
  public init(oidcIDToken: String) {
    self.data = VerificationData.oidcIDToken(oidcIDToken)
  }
  
  @objc(withPhoneNumber:verificationCode:)
  public init(phoneNumber: String, verificationCode: String) {
    self.data = VerificationData.phoneNumber(PhoneNumberVerification(phoneNumber: phoneNumber, verificationCode: verificationCode))
  }
  
  @objc(withPreverifiedEmail:)
  public init(preverifiedEmail: String) {
    self.data = VerificationData.preverifiedEmail(preverifiedEmail)
  }
  
  @objc(withPreverifiedPhoneNumber:)
  public init(preverifiedPhoneNumber: String) {
    self.data = VerificationData.preverifiedPhoneNumber(preverifiedPhoneNumber)
  }
  
  @objc(withPreverifiedOIDCSubject:providerID:)
  public init(preverifiedOIDCSubject: String, providerID: String) {
    self.data = VerificationData.preverifiedOIDC(PreverifiedOIDCVerification(subject: preverifiedOIDCSubject, providerID: providerID))
  }
  
  @objc(withOIDCAuthorizationCode:providerID:state:)
  public init(oidcAuthorizationCode: String, providerID: String, state: String) {
    self.data = VerificationData.oidcAuthorizationCode(OIDCAuthorizationCodeVerification(providerID: providerID, authorizationCode: oidcAuthorizationCode, state: state))
  }
  
  @objc(withPrehashedAndEncryptedPassphrase:)
  public init(prehashedAndEncryptedPassphrase: String) {
    self.data = VerificationData.prehashedAndEncryptedPassphrase(prehashedAndEncryptedPassphrase)
  }

  internal func toCVerification() -> tanker_verification_t {
    return self.data.toCVerification()
  }
}

public enum VerificationData {
  case passphrase(String)
  case e2ePassphrase(String)
  case verificationKey(VerificationKey)
  case email(EmailVerification)
  case oidcIDToken(String)
  case phoneNumber(PhoneNumberVerification)
  case preverifiedEmail(String)
  case preverifiedPhoneNumber(String)
  case preverifiedOIDC(PreverifiedOIDCVerification)
  case oidcAuthorizationCode(OIDCAuthorizationCodeVerification)
  case prehashedAndEncryptedPassphrase(String)
}

extension VerificationData {
  static let C_VERIFICATION_VERSION: UInt8 = 9;
  
  func toCVerification() -> tanker_verification_t {
    var verif = tanker_verification_t();
    verif.version = Self.C_VERIFICATION_VERSION;
    switch self {
    case .passphrase(let passphrase):
      verif.verification_method_type = UInt8(VerificationMethodType.passphrase.rawValue);
      verif.passphrase = (passphrase as NSString).utf8String;
    case .e2ePassphrase(let passphrase):
      verif.verification_method_type = UInt8(VerificationMethodType.e2ePassphrase.rawValue);
      verif.e2e_passphrase = (passphrase as NSString).utf8String;
    case .verificationKey(let key):
      verif.verification_method_type = UInt8(VerificationMethodType.verificationKey.rawValue);
      verif.verification_key = (key.value as NSString).utf8String;
    case .email(let emailVerif):
      verif.verification_method_type = UInt8(VerificationMethodType.email.rawValue);
      verif.email_verification.email = (emailVerif.email as NSString).utf8String;
      verif.email_verification.verification_code = (emailVerif.verificationCode as NSString).utf8String;
    case .oidcIDToken(let token):
      verif.verification_method_type = UInt8(VerificationMethodType.oidcidToken.rawValue);
      verif.oidc_id_token = (token as NSString).utf8String;
    case .phoneNumber(let phoneVerif):
      verif.verification_method_type = UInt8(VerificationMethodType.phoneNumber.rawValue);
      verif.phone_number_verification.phone_number = (phoneVerif.phoneNumber as NSString).utf8String;
      verif.phone_number_verification.verification_code = (phoneVerif.verificationCode as NSString).utf8String;
    case .preverifiedEmail(let email):
      verif.verification_method_type = UInt8(VerificationMethodType.preverifiedEmail.rawValue);
      verif.preverified_email = (email as NSString).utf8String;
    case .preverifiedPhoneNumber(let phoneNumber):
      verif.verification_method_type = UInt8(VerificationMethodType.preverifiedPhoneNumber.rawValue);
      verif.preverified_phone_number = (phoneNumber as NSString).utf8String;
    case .preverifiedOIDC(let oidcVerif):
      verif.verification_method_type = UInt8(VerificationMethodType.preverifiedOIDC.rawValue);
      verif.preverified_oidc_verification.subject = (oidcVerif.subject as NSString).utf8String;
      verif.preverified_oidc_verification.provider_id = (oidcVerif.providerID as NSString).utf8String;
    case .oidcAuthorizationCode(let oidcVerif):
      verif.verification_method_type = UInt8(VerificationMethodType.oidcAuthorizationCode.rawValue);
      verif.oidc_authorization_code_verification.provider_id = (oidcVerif.providerID as NSString).utf8String;
      verif.oidc_authorization_code_verification.authorization_code = (oidcVerif.authorizationCode as NSString).utf8String;
      verif.oidc_authorization_code_verification.state = (oidcVerif.state as NSString).utf8String;
    case .prehashedAndEncryptedPassphrase(let prehashedAndEncryptedPassphrase):
      verif.verification_method_type = UInt8(VerificationMethodType.prehashedAndEncryptedPassphrase.rawValue);
      verif.prehashed_and_encrypted_passphrase = (prehashedAndEncryptedPassphrase as NSString).utf8String;
    }
    return verif;
  }
}

@objc(TKREmailVerification)
public class EmailVerification: NSObject {
  public let email: String;
  public let verificationCode: String;
  
  init(email: String, verificationCode: String) {
    self.email = email
    self.verificationCode = verificationCode
  }
}

@objc(TKRPhoneNumberVerification)
public class PhoneNumberVerification: NSObject {
  public let phoneNumber: String;
  public let verificationCode: String;
  
  init(phoneNumber: String, verificationCode: String) {
    self.phoneNumber = phoneNumber
    self.verificationCode = verificationCode
  }
}

@objc(TKRPreverifiedOIDCVerification)
public class PreverifiedOIDCVerification: NSObject {
  public let subject: String;
  public let providerID: String;
  
  init(subject: String, providerID: String) {
    self.subject = subject
    self.providerID = providerID
  }
}

@objc(TKROIDCAuthorizationCodeVerification)
public class OIDCAuthorizationCodeVerification: NSObject {
  public let providerID: String;
  public let authorizationCode: String;
  public let state: String;
  
  init(providerID: String, authorizationCode: String, state: String) {
    self.providerID = providerID
    self.authorizationCode = authorizationCode
    self.state = state
  }
}
