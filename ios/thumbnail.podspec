#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint thumbnail.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'thumbnail'
  s.version          = '0.1.0'
  s.summary          = 'High-performance video thumbnail engine for Flutter.'
  s.description      = <<-DESC
Cached, scheduled, cancellable video thumbnail generation from asset, file,
and network videos, built for infinite feeds on low-end devices.
                       DESC
  s.homepage         = 'https://github.com/omar-hanafy/thumbnail'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'Omar Hanafy' => 'saberyemen48@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files = 'thumbnail/Sources/thumbnail/**/*.swift'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  s.resource_bundles = {'thumbnail_privacy' => ['thumbnail/Sources/thumbnail/PrivacyInfo.xcprivacy']}
end
