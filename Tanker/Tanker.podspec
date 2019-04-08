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
  s.source           = { :http => "https://cocoapods.tanker.io/ios/tanker-ios-sdk-#{s.version}.tar.gz" }

  s.ios.deployment_target = '9.0'

  s.source_files = 'Sources/*', 'Headers/TKR*'
  s.private_header_files = 'Headers/*+Private.h'
  s.pod_target_xcconfig = {
    'USE_HEADERMAP' => "NO",
    'HEADER_SEARCH_PATHS' => '"$(inherited)" "$(PODS_TARGET_SRCROOT)/Headers"',
    'OTHER_LDFLAGS' => "'-exported_symbols_list ${PODS_TARGET_SRCROOT}/export_symbols.list'"
    }
  s.header_mappings_dir = 'Headers'
  s.preserve_paths = 'export_symbols.list', 'Libraries', 'Tests/Dummy.m'

  # Workaround Cocoapods issue with headers having the same filename
  s.subspec "core" do |ss|
    ss.source_files = 'Headers/ctanker.h', 'Headers/ctanker/*.h'
    ss.private_header_files = 'Headers/ctanker.h', 'Headers/ctanker/*'
    libs = [
      'Libraries/libboost_atomic.a',
      'Libraries/libboost_chrono.a',
      'Libraries/libboost_context.a',
      'Libraries/libboost_contract.a',
      'Libraries/libboost_date_time.a',
      'Libraries/libboost_filesystem.a',
      'Libraries/libboost_program_options.a',
      'Libraries/libboost_random.a',
      'Libraries/libboost_stacktrace_basic.a',
      'Libraries/libboost_stacktrace_noop.a',
      'Libraries/libboost_system.a',
      'Libraries/libboost_thread.a',
      'Libraries/libcrypto.a',
      'Libraries/libfmt.a',
      'Libraries/libmockaron.a',
      'Libraries/libsioclient.a',
      'Libraries/libsodium.a',
      'Libraries/libsqlcipher.a',
      'Libraries/libsqlpp11-connector-sqlite3.a',
      'Libraries/libssl.a',
      'Libraries/libtanker.a',
      'Libraries/libtankercore.a',
      'Libraries/libtankercrypto.a',
      'Libraries/libtankerusertoken.a',
      'Libraries/libtconcurrent.a',
      'Libraries/libtls.a'
    ]
    ss.vendored_libraries = libs
    ss.libraries = ['c++', 'c++abi'] + libs.collect{|l| l[/lib(.*).a/, 1]}
  end


  s.test_spec 'Tests' do |test_spec|
    test_spec.source_files = 'Tests/*.{h,m}'
    test_spec.dependency 'Specta'
    test_spec.dependency 'Expecta'
    test_spec.dependency 'Tanker/core'
    test_spec.dependency 'PromiseKit/Promise', '~> 1.7'
    test_spec.dependency 'PromiseKit/Hang', '~> 1.7'
    test_spec.dependency 'PromiseKit/When', '~> 1.7'
  end

end
