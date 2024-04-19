Pod::Spec.new do |s|
  s.name             = 'Tanker'
  s.version          = '9999'
  s.summary          = 'End to end encryption'

  s.description      = <<-DESC
Tanker is a end-to-end encryption SDK.

It's available for browsers, desktop, iOS and Android.
                       DESC

  s.homepage         = 'https://tanker.io'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = 'Tanker developers'
  s.source           = { :http => "https://storage.googleapis.com/cocoapods.tanker.io/ios/tanker-ios-sdk-#{s.version}.tar.gz" }

  s.ios.deployment_target = '12.0'
  s.swift_version = '5.0'

  s.source_files = [
    'Sources/**/*.{m,swift}',
    'Headers/**/*.h',
  ]
  s.private_header_files = 'Headers/*+Private.h'

  s.pod_target_xcconfig = {
    'USE_HEADERMAP' => "NO",
    'DEFINES_MODULE' => "YES",
  }

  s.header_mappings_dir = 'Headers'
  s.vendored_framework = 'Frameworks/TankerDeps.xcframework'
  s.preserve_paths = 'Tests/Dummy.m'

  s.test_spec 'Tests' do |test_spec|
    test_spec.source_files = 'Tests/*.{h,m,swift}'
    test_spec.exclude_files = 'Tests/TankerTests-Bridging-Header.h'
    test_spec.preserve_paths = 'Tests/TankerTests-Bridging-Header.h'
    test_spec.pod_target_xcconfig = {
      "SWIFT_OBJC_BRIDGING_HEADER" => "$(PODS_TARGET_SRCROOT)/Tests/TankerTests-Bridging-Header.h"
    }

    # Quick/Nimble require iOS 13 min starting from v6/v11
    test_spec.dependency 'Quick', '~> 5.0'
    test_spec.dependency 'Nimble', '~> 10.0'

    test_spec.dependency 'Specta'
    test_spec.dependency 'Expecta'

    test_spec.dependency 'PromiseKit/Promise', '~> 1.7'
    test_spec.dependency 'PromiseKit/Hang', '~> 1.7'
    test_spec.dependency 'PromiseKit/When', '~> 1.7'

    # tests use admin parts
    test_spec.scheme = {
      :environment_variables => Hash[
        [
          'TANKER_APPD_URL',
          'TANKER_FAKE_OIDC_URL',
          'TANKER_MANAGEMENT_API_ACCESS_TOKEN',
          'TANKER_MANAGEMENT_API_URL',
          'TANKER_MANAGEMENT_API_DEFAULT_ENVIRONMENT_NAME',
          'TANKER_TRUSTCHAIND_URL',
          'TANKER_OIDC_CLIENT_ID',
          'TANKER_OIDC_CLIENT_SECRET',
          'TANKER_OIDC_PROVIDER',
          'TANKER_OIDC_ISSUER',
          'TANKER_OIDC_MARTINE_EMAIL',
          'TANKER_OIDC_MARTINE_REFRESH_TOKEN',
          'TANKER_VERIFICATION_API_TEST_TOKEN'
        ].map { |key| [key, ENV[key]] }
      ]
    }
  end

end
