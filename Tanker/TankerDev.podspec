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

  s.source_files = 'Tanker/Classes/**/*'
  s.private_header_files = 'Tanker/Classes/**/*+Private.h'
  s.pod_target_xcconfig = {
    'HEADER_SEARCH_PATHS' => "${PODS_ROOT}/../../conan/out/universal/include/**",
    'OTHER_LDFLAGS' => "'-exported_symbols_list ${PODS_ROOT}/../../Tanker/export_symbols.list'"
    }

  s.preserve_path = 'Tanker/export_symbols.list'

  s.subspec 'libtanker' do |libtanker|

    # Extract library name from full path:
    # path/to/libfoo.a -> foo
    extract_lib_name = lambda do |lib_path|
      res = File.basename(lib_path, ".a")
      res[3..-1]
    end

    all_libs = Dir['conan/out/universal/lib/*.a']

    libtanker.preserve_paths = 'conan/out/universal/lib/*.a', 'conan/out/universal/include/*.h'
    libtanker.vendored_libraries = all_libs

    libnames = all_libs.map { |lib| extract_lib_name.call(lib) }
    libtanker.libraries = libnames + ['c++', 'c++abi']
  end

  s.test_spec 'Tests' do |test_spec|
    test_spec.source_files = 'Tanker/Tests/*.{h,m}'
    test_spec.dependency 'Specta'
    test_spec.dependency 'Expecta'
    test_spec.dependency 'PromiseKit/Promise', '~> 1.7'
    test_spec.dependency 'PromiseKit/Hang', '~> 1.7'
    test_spec.dependency 'PromiseKit/When', '~> 1.7'
  end

end
