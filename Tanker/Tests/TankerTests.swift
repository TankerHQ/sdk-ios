import Quick
import Nimble

@testable import Tanker

class TankerTests: TankerFunctionalQuickSpec {
  var appID: String!;
  var appSecret: String!;
  
  var tankerOptions = TKRTankerOptions();
    
  override func spec() {
    beforeSuite {
      let createResponse = self.admin.createApp(withName: "sdk-ios-tests")!;
      let appDescriptor = createResponse["app"] as! NSDictionary;
      self.appID = appDescriptor["id"] as? String;
      self.appSecret = appDescriptor["secret"] as? String;
    }
    
    afterSuite {
      self.admin.deleteApp(self.appID);
    }
    
    beforeEach {
      self.tankerOptions = createTankerOptions(url: self.appdUrl, appID: self.appID);
    }
    
    describe("open") {
      var tanker: TKRTanker!;
      var identity: String!;

      beforeEach {
        tanker = try! TKRTanker(options: self.tankerOptions);
        identity = createIdentity(appID: self.appID, appSecret: self.appSecret, userID: NSUUID().uuidString);
      }

      it("should return .identityRegistrationNeeded when start is called for the first time") {
        startAndRegister(tanker, identity, TKRVerification(fromPassphrase: "passphrase"));
        stop(tanker);
      }

      it("should return .ready when start is called after identity has been registered") {
        startAndRegister(tanker, identity, TKRVerification(fromPassphrase: "passphrase"));
        stop(tanker);
        start(tanker, identity);
        stop(tanker);
      }

      it("should be able to stop tanker while a call is in flight") {
        // This test tries to cancel an on-going HTTP request. There is no
        // assertion, it's just a best effort to check that we won't crash
        // because of some use-after-free.

        startAndRegister(tanker, identity, TKRVerification(fromPassphrase: "passphrase"));

        // trigger an encrypt and do not wait
        tanker.encryptString("Rosebud", completionHandler: { _, _ in });

        stop(tanker);
      }
    }
  }
}
