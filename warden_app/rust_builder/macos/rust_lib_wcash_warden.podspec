Pod::Spec.new do |s|
  s.name             = 'rust_lib_wcash_warden'
  s.version          = '0.1.0'
  s.summary          = 'Native Rust bridge for Wcash Warden Testnet.'
  s.description      = 'Cargokit-built Rust bridge for Wcash Warden Testnet.'
  s.homepage         = 'https://github.com/w-cash/wcash-wallet'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Wcash' => 'placex.com@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.15'
  s.swift_version = '5.0'

  s.script_phase = {
    :name => 'Build Wcash Warden Rust library',
    :script => 'sh "$PODS_TARGET_SRCROOT/../cargokit/build_pod.sh" ../../rust rust_lib_wcash_warden',
    :execution_position => :before_compile,
    :input_files => ['${BUILT_PRODUCTS_DIR}/cargokit_phony'],
    :output_files => ["${BUILT_PRODUCTS_DIR}/librust_lib_wcash_warden.a"],
  }
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'OTHER_LDFLAGS' => '-force_load ${BUILT_PRODUCTS_DIR}/librust_lib_wcash_warden.a',
  }
end
