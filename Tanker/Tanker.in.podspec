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

  s.ios.deployment_target = '9.0'

  s.source_files = 'Sources/*', 'Headers/TKR*'
  s.private_header_files = 'Headers/*+Private.h'
  s.pod_target_xcconfig = {
    'USE_HEADERMAP' => "NO",
    'HEADER_SEARCH_PATHS' => '"$(inherited)" "$(PODS_TARGET_SRCROOT)/Headers"',
    'LIBRARY_SEARCH_PATHS' => '$(PODS_TARGET_SRCROOT)/Libraries',
    'OTHER_LDFLAGS' => "'-exported_symbols_list ${PODS_TARGET_SRCROOT}/export_symbols.list -nostdlib++ @static_libs_link_flags@'",
    # Until Apple provides a way to have both x86_64 and arm64 simulators working with the same static libs, simply exclude arm64 for simulators.
    # This will likely cause issues in the future w.r.t Apple Silicon
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64'
    }


  s.header_mappings_dir = 'Headers'
  s.preserve_paths = 'export_symbols.list', 'Libraries', 'Tests/Dummy.m'
  s.dependency 'POSInputStreamLibrary'

  # Workaround Cocoapods issue with headers having the same filename
  s.subspec "core" do |ss|
    ss.source_files = 'Headers/ctanker.h', 'Headers/ctanker/**/*.h'
    ss.private_header_files = 'Headers/ctanker.h', 'Headers/ctanker/**/*.h'
  end


  s.test_spec 'Tests' do |test_spec|
    test_spec.source_files = 'Tests/*.{h,m}'
    test_spec.dependency 'Specta'
    test_spec.dependency 'Expecta'
    test_spec.dependency 'Tanker/core'
    test_spec.dependency 'PromiseKit/Promise', '~> 1.7'
    test_spec.dependency 'PromiseKit/Hang', '~> 1.7'
    test_spec.dependency 'PromiseKit/When', '~> 1.7'
    # tests use admin parts
    test_spec.vendored_libraries = 'Libraries/*.a'
    test_spec.scheme = {
      :environment_variables => Hash[
        [
          'TANKER_ADMIND_URL',
          'TANKER_TRUSTCHAIND_URL',
          'TANKER_ID_TOKEN',
          'TANKER_OIDC_CLIENT_ID',
          'TANKER_OIDC_CLIENT_SECRET',
          'TANKER_OIDC_PROVIDER',
          'TANKER_OIDC_MARTINE_EMAIL',
          'TANKER_OIDC_MARTINE_REFRESH_TOKEN'
        ].map { |key| [key, ENV[key]] }
      ]
    }
  end

end
