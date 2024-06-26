import Quick
import Nimble

@testable import Tanker

class UnitTests: QuickSpec {
  override func spec() {
    it("has a non-empty native version string") {
      expect(Tanker.nativeVersionString().count) != 0
    }
    
    describe("prehashPassword") {
      it("should fail to hash an empty password") {
        expect {
          let _: String = try Tanker.prehashPassword("")
        }.to(throwError { (error: NSError) in
          expect(error.domain).to(equal(ErrorDomain));
          expect(error.code) == Error.invalidArgument.rawValue;
          expect(error.localizedDescription) == "Cannot hash empty password";
        })
      }
      
      it("should hash a test vector 1") {
        let hashed = try! Tanker.prehashPassword("super secretive password");
        let expected = "UYNRgDLSClFWKsJ7dl9uPJjhpIoEzadksv/Mf44gSHI=";
        expect(hashed) == expected;
      }

      it("should hash a test vector 2") {
        let hashed = try! Tanker.prehashPassword("test éå 한국어 😃");
        let expected = "Pkn/pjub2uwkBDpt2HUieWOXP5xLn0Zlen16ID4C7jI=";
        expect(hashed) == expected;
      }
    }
    
    describe("init") {
      it("should throw when the AppID is not base64") {
        let tankerOptions = TankerOptions();
        tankerOptions.appID = ",,";
        
        expect { try Tanker(options:tankerOptions) }.to(throwError { (error: NSError) in
          expect(error.domain).to(equal(ErrorDomain));
          expect(error.code) == Error.invalidArgument.rawValue;
        })
      }
    }
  }
}
