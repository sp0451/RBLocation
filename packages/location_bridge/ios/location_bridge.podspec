#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint location_bridge.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'location_bridge'
  s.version          = '0.0.1'
  s.summary          = 'Native location simulation and observation bridge.'
  s.description      = <<-DESC
Type-safe native session management with a pinned MIT idevice runtime.
                       DESC
  s.homepage         = 'https://github.com/jkcoxson/idevice'
  s.license          = { :file => '../LICENSE' }
  s.author           = 'CLocation'
  s.source           = { :path => '.' }
  s.source_files = 'location_bridge/Sources/location_bridge/**/*.swift'
  s.vendored_frameworks = 'location_bridge/IdeviceRuntime.xcframework'
  s.frameworks = 'Security', 'Network', 'CoreLocation'
  s.libraries = 'resolv'
  s.dependency 'Flutter'
  s.platform = :ios, '26.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.9'
  s.resource_bundles = {'location_bridge_privacy' => ['location_bridge/Sources/location_bridge/PrivacyInfo.xcprivacy']}
  s.resources = 'location_bridge/Sources/location_bridge/ThirdPartyNotices.txt'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'location_bridge_privacy' => ['location_bridge/Sources/location_bridge/PrivacyInfo.xcprivacy']}
end
