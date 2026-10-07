Pod::Spec.new do |s|
  s.name             = 'slint_skia'
  s.version          = '0.0.1'
  s.summary          = 'Flutter textures for the slint_skia GPU backend.'
  s.description      = <<-DESC
Registers the IOSurface-backed Flutter texture slint-skia-ffi renders into with Metal.
                       DESC
  s.homepage         = 'https://github.com/listepo/slint_dart'
  s.license          = { :file => '../LICENSE' }
  s.author           = 'listepo'
  s.source           = { :path => '.' }
  s.source_files     = 'slint_skia/Sources/slint_skia/**/*'
  s.ios.deployment_target = '15.0'
  s.osx.deployment_target = '12.0'
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.frameworks = 'CoreVideo', 'Metal'
  s.ios.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.osx.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
