Pod::Spec.new do |s|
  s.name             = 'gost_root_ca_ios'
  s.version          = '0.1.0'
  s.summary          = 'iOS implementation of gost_root_ca: URLSession/WKWebView swizzling with Russian Trusted Root CA'
  s.description      = <<-DESC
iOS implementation of gost_root_ca: URLSession/WKWebView swizzling with Russian Trusted Root CA
                       DESC
  s.homepage         = 'https://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'gost_root_ca' => 'gost_root_ca@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  s.frameworks = 'WebKit'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
