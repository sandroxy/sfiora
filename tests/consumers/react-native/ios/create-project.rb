require "xcodeproj"

project_path = File.expand_path("SfioraConsumer.xcodeproj", __dir__)
project = Xcodeproj::Project.new(project_path)
target = project.new_target(
  :application,
  "SfioraConsumer",
  :ios,
  "15.1"
)

sources_group = project.main_group.new_group("Sources", "Sources")
main_file = sources_group.new_file("main.m")
target.source_build_phase.add_file_reference(main_file)

target.build_configurations.each do |configuration|
  configuration.build_settings["CODE_SIGNING_ALLOWED"] = "NO"
  configuration.build_settings["GENERATE_INFOPLIST_FILE"] = "YES"
  configuration.build_settings["INFOPLIST_KEY_NFCReaderUsageDescription"] =
    "Verifies that the packaged NFC reader can be consumed."
  configuration.build_settings["PRODUCT_BUNDLE_IDENTIFIER"] =
    "io.github.sandroxy.sfiora.artifactconsumer"
  configuration.build_settings["SWIFT_VERSION"] = "5.9"
end

project.save

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(target)
scheme.set_launch_target(target)
scheme.save_as(project_path, "SfioraConsumer", true)
