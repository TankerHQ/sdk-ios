import Foundation

@objc public enum TKRStatus: UInt {
    case stopped
    case ready
    case identityRegistrationNeeded
    case identityVerificationNeeded
}
