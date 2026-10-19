Pod::Spec.new do |s|
  s.name             = 'sinew_security'
  s.version          = '0.1.0'
  s.summary          = 'Sinew BiometricVault: a Keychain item with biometryCurrentSet access control.'
  s.homepage         = 'https://github.com/srctool/sinew-dart'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'srctool' => 'https://github.com/srctool' }
  s.source           = { :path => '.' }
  s.source_files = 'sinew_security/Sources/sinew_security/**/*.swift'
  s.dependency 'Flutter'
  s.frameworks = 'LocalAuthentication', 'Security'
  s.platform = :ios, '15.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
  s.resource_bundles = {'sinew_security_privacy' => ['sinew_security/Sources/sinew_security/PrivacyInfo.xcprivacy']}
end
