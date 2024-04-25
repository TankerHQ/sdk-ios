@objc(TKRSharingOptions)
public class SharingOptions: NSObject {
  @objc
  public var shareWithUsers: Array<String>;
  @objc
  public var shareWithGroups: Array<String>;

  @objc
  public override init() {
    self.shareWithUsers = [];
    self.shareWithGroups = [];
  }
}
