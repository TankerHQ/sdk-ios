import Foundation

@objc(TKRStatus)
public enum Status: UInt {
    case stopped
    case ready
    case identityRegistrationNeeded
    case identityVerificationNeeded
}
