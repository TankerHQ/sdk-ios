import Quick
import Nimble

@testable import Tanker

class UnitTests: QuickSpec {
  override func spec() {
    it("has a non-empty native version string") {
      expect(Tanker.nativeVersionString().count) != 0;
    }

    describe("prehashPassword") {
      it("should fail to hash an empty password") {
        expect {
          let _: String = try Tanker.prehashPassword("");
        }.to(throwError { (error: NSError) in
          expect(error.domain).to(equal(ErrorDomain));
          expect(error.code) == Error.invalidArgument.rawValue;
          expect(error.localizedDescription) == "Tanker::Crypto(invalid buffer size): cannot hash an empty password";
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

    describe("prehashAndEncryptPassword") {
      it("fails to hash an empty password") {
        let publicKey = "iFpHADRaRYQbErZhHMDruROvqkRF3XkgJxKk+7eP1hI=";
        expect {
          let _: String = try Tanker.prehashAndEncryptPassword("", publicKey: publicKey);
        }.to(throwError { (error: NSError) in
          expect(error.domain).to(equal(ErrorDomain));
          expect(error.code) == Error.invalidArgument.rawValue;
          expect(error.localizedDescription) == "Tanker::Crypto(invalid buffer size): cannot hash an empty password";
        })
      }

      it("fails to hash with an empty public key") {
        let password = "super secretive password";
        expect {
          let _: String = try Tanker.prehashAndEncryptPassword(password, publicKey: "");
        }.to(throwError { (error: NSError) in
          expect(error.domain).to(equal(ErrorDomain));
          expect(error.code) == Error.invalidArgument.rawValue;
          expect(error.localizedDescription) == "Tanker::Tanker(invalid argument): public_key has an invalid value: ";
        })
      }

      it("fails to hash with a non-base64-encoded public key") {
        let password = "super secretive password";
        expect {
          let _: String = try Tanker.prehashAndEncryptPassword(password, publicKey: "$");
        }.to(throwError { (error: NSError) in
          expect(error.domain).to(equal(ErrorDomain));
          expect(error.code) == Error.invalidArgument.rawValue;
          expect(error.localizedDescription) == "Tanker::Tanker(invalid argument): public_key has an invalid value: $";
        })
      }

      it("fails to hash with an invalid public key") {
        let password = "super secretive password";
        expect {
          let _: String = try Tanker.prehashAndEncryptPassword(password, publicKey: "fake");
        }.to(throwError { (error: NSError) in
          expect(error.domain).to(equal(ErrorDomain));
          expect(error.code) == Error.invalidArgument.rawValue;
          expect(error.localizedDescription) == "Tanker::Tanker(invalid argument): public_key has an invalid value: fake";
        })
      }

      it("hashes and encrypt when using a valid password and public key") {
        let password = "super secretive password";
        let publicKey = "iFpHADRaRYQbErZhHMDruROvqkRF3XkgJxKk+7eP1hI=";
        let hashed = try! Tanker.prehashAndEncryptPassword(password, publicKey: publicKey);
        expect(hashed.count) != 0;
        expect(!hashed.contains(password));
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
