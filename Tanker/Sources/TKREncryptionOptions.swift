@objc(TKREncryptionOptions)
public class EncryptionOptions: NSObject {
  @objc
  public var shareWithUsers: Array<String>;
  @objc
  public var shareWithGroups: Array<String>;
  @objc
  public var shareWithSelf: Bool;
  @objc
  public var paddingStep: Padding;
  
  @objc
  public override init() {
    self.shareWithUsers = [];
    self.shareWithGroups = [];
    self.shareWithSelf = true;
    self.paddingStep = Padding.automatic()!;
  }
}
