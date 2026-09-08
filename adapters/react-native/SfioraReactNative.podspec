require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |spec|
  spec.name = "SfioraReactNative"
  spec.version = package.fetch("version")
  spec.summary = package.fetch("description")
  spec.description = <<-DESC
    Sfiora exposes contract-first NFC reading and verified NDEF writing through
    the same native cores on legacy and new-architecture React Native apps.
  DESC
  spec.homepage = package.fetch("homepage")
  spec.license = { :type => "Apache-2.0", :file => "LICENSE" }
  spec.authors = { "SandroX" => "sandroxy" }
  spec.source = {
    :git => package.fetch("repository").fetch("url"),
    :tag => spec.version.to_s
  }

  spec.platform = :ios, "13.0"
  spec.swift_version = "5.9"
  spec.static_framework = true
  spec.frameworks = "CoreNFC"
  spec.vendored_frameworks = "ios/Frameworks/Sfiora.xcframework"
  spec.source_files = [
    "shared/ios/Sources/SfioraBridgeSupport/**/*.swift",
    "ios/SfioraReactNativeModule.mm"
  ]
  spec.pod_target_xcconfig = {
    "CLANG_CXX_LANGUAGE_STANDARD" => "c++20",
    "DEFINES_MODULE" => "YES"
  }

  if defined?(install_modules_dependencies)
    install_modules_dependencies(spec)
  else
    spec.dependency "React-Core"
    if ENV["RCT_NEW_ARCH_ENABLED"] == "1"
      spec.compiler_flags = "-DRCT_NEW_ARCH_ENABLED=1"
      spec.dependency "React-Codegen"
      spec.dependency "RCTRequired"
      spec.dependency "RCTTypeSafety"
      spec.dependency "ReactCommon/turbomodule/core"
    end
  end
end
