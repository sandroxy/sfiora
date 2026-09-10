require "xcodeproj"

root, output = ARGV.take(2).map { |path| File.expand_path(path) }
minimum_ios = ARGV.fetch(2)
project_path = File.join(output, "SfioraRuntimeTests.xcodeproj")
project = Xcodeproj::Project.new(project_path)
core = project.new_target(:framework, "Sfiora", :ios, minimum_ios)
tests = project.new_target(:unit_test_bundle, "SfioraRuntimeTests", :ios, minimum_ios)
tests.add_dependency(core)
tests.frameworks_build_phase.add_file_reference(core.product_reference)
Dir.glob(File.join(root, "native/ios/Sources/Sfiora/*.swift")).sort.each do |path|
  core.source_build_phase.add_file_reference(project.main_group.new_file(path))
end
Dir.glob(File.join(root, "tests/ios-runtime/*.{swift,m}")).sort.each do |path|
  tests.source_build_phase.add_file_reference(project.main_group.new_file(path))
end
[core, tests].each do |target|
  target.build_configurations.each do |config|
    config.build_settings.merge!(
      "SWIFT_VERSION" => "5.0", "CLANG_ENABLE_OBJC_ARC" => "YES",
      "CODE_SIGNING_ALLOWED" => "NO", "GENERATE_INFOPLIST_FILE" => "YES",
      "PRODUCT_BUNDLE_IDENTIFIER" => "com.sandrox.sfiora.#{target.name.downcase}",
      "SWIFT_TREAT_WARNINGS_AS_ERRORS" => "YES", "ENABLE_TESTABILITY" => "YES"
    )
  end
end
tests.build_configurations.each do |config|
  config.build_settings["SWIFT_OBJC_BRIDGING_HEADER"] = File.join(root, "tests/ios-runtime/ControlledCoreNFC.h")
end
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(core)
scheme.add_test_target(tests)
scheme.save_as(project_path, "SfioraRuntimeTests", true)
