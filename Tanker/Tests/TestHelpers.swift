import Quick
import Nimble

import Tanker

func hangWithResolver(_ handler: @escaping (PMKResolver?) -> Void) -> Any?
{
  return PMKPromise<AnyObject>.hang(PMKPromise(resolver: { (resolve: PMKResolver?) in
    handler(resolve);
  }));
}

func createIdentity(appID: String, appSecret: String, userID: String) -> String
{
  let cAppID = appID.cString(using: .utf8);
  let cAppSecret = appSecret.cString(using: .utf8);
  let cUserID = userID.cString(using: .utf8);
  
  let identity_expected = UnsafeMutableRawPointer(tanker_create_identity(cAppID, cAppSecret, cUserID)!);
  let identity_ptr: UnsafeMutableRawPointer = TKR_unwrapAndFreeExpected(identity_expected);
  return NSString(
    bytesNoCopy: identity_ptr,
    length: strlen(identity_ptr),
    encoding: String.Encoding.utf8.rawValue,
    freeWhenDone: true
  )! as String
}

func createStorageFullpath(_ dir: FileManager.SearchPathDirectory) -> String
{
  let paths: [String] = NSSearchPathForDirectoriesInDomains(dir, .userDomainMask, true);
  let path = URL(fileURLWithPath: paths[0]).appendingPathComponent(NSUUID().uuidString);
  try! FileManager.default.createDirectory(at: path, withIntermediateDirectories: true);
  return path.absoluteString;
}

func createTankerOptions(url: String, appID: String) -> TankerOptions
{
  let opts = TankerOptions();
  opts.url = url;
  opts.appID = appID;
  opts.persistentPath = createStorageFullpath(.libraryDirectory);
  opts.cachePath = createStorageFullpath(.libraryDirectory);
  opts.sdkType = "sdk-ios-tests";
  return opts;
}

func startAndRegister(_ tanker: Tanker, _ identity: String, _ verification: Verification) {
  let err = hangWithResolver({ (resolver: _!) in
    tanker.start(withIdentity: identity, completionHandler: { (status: TKRStatus, err: Error?) in
      if (err != nil) {
        resolver(err);
      } else {
        expect(status) == .identityRegistrationNeeded;
        expect(tanker.status) == .identityRegistrationNeeded;
        tanker.registerIdentity(with: verification, completionHandler: resolver)
      }
    });
  }) as? NSError;
  expect(err) == nil;
}

func start(_ tanker: Tanker, _ identity: String) {
  let err = hangWithResolver({ (resolver: _!) in
    tanker.start(withIdentity: identity, completionHandler: { (status: TKRStatus, err: Error?) in
      if (err == nil) {
        expect(status) == .ready;
      }
      resolver!(err);
    });
  }) as? NSError;
  expect(err) == nil;
  expect(tanker.status) == .ready;
}

func stop(_ tanker: Tanker) {
  let err = hangWithResolver({ (resolver: _!) in
    tanker.stop(completionHandler: resolver);
  });
  expect(err) == nil;
  expect(tanker.status) == .stopped;
};

class TankerFunctionalQuickSpec: QuickSpec {
  let appdUrl = getEnv("TANKER_APPD_URL");
  let trustchaindUrl = getEnv("TANKER_TRUSTCHAIND_URL");
  let verificationToken = getEnv("TANKER_VERIFICATION_API_TEST_TOKEN");
  let oidcTestConfig: NSDictionary! = [
    "clientId": getEnv("TANKER_OIDC_CLIENT_ID"),
    "clientSecret": getEnv("TANKER_OIDC_CLIENT_SECRET"),
    "provider": getEnv("TANKER_OIDC_PROVIDER"),
    "issuer": getEnv("TANKER_OIDC_ISSUER"),
    "fakeOidcIssuerUrl": getEnv("TANKER_FAKE_OIDC_URL") + "/issuer",
    "users": [
      "martine": [
        "email": getEnv("TANKER_OIDC_MARTINE_EMAIL"),
        "refreshToken": getEnv("TANKER_OIDC_MARTINE_REFRESH_TOKEN"),
      ]
    ]
  ];

  let admin = TKRTestAdmin(
    url: getEnv("TANKER_MANAGEMENT_API_URL"),
    appManagementToken: getEnv("TANKER_MANAGEMENT_API_ACCESS_TOKEN"),
    environmentName: getEnv("TANKER_MANAGEMENT_API_DEFAULT_ENVIRONMENT_NAME")
  );

  static func getEnv(_ key: String) -> String { ProcessInfo.processInfo.environment[key]! }
}
