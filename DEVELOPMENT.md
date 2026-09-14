# Development

This guide is for Sfiora maintainers and contributors. Developers installing
published packages should start with [README.md](README.md),
[README-EN.md](README-EN.md), or the native and adapter guides linked there.

## Environment and repository layout

Use the existing tool installations on your machine. Source checks need Git,
Node.js (CI uses Node 24), Ruby with its standard library, Python 3, and Bash.
Android compilation needs JDK 17, Android SDK Platform 36, and the checked-in
Gradle wrapper. Set `JAVA_HOME` and `ANDROID_HOME`, or use an ignored
`native/android/local.properties` for the SDK path. The library's Java target is
11; this is separate from the JDK used to run Gradle.

Apple builds require macOS, Xcode with the iOS SDK, and a toolchain providing
`xcrun swift-format`. Production callback tests additionally need an installed
iOS Simulator runtime and the Ruby `xcodeproj` gem (or an existing `xcodeproj`
executable). Physical NFC acceptance requires real devices and suitable tags;
signed iOS hosts also need the NFC capability and matching provisioning profile.

| Location | Maintained content |
| --- | --- |
| `native/android/sfiora` | Headless Android NFC core |
| `native/android/sfiora-ui` | Optional managed Android panels |
| `native/ios/Sources/Sfiora` | Canonical Swift core |
| `adapters/shared` | Shared native bridge validation and conversion |
| `adapters/react-native` | RN module, Expo config plugin, and JS API |
| `adapters/uniapp` | Legacy bridge, packaging, and canonical UNI JavaScript API |
| `uni_modules/Sandrox-Sfiora` | UTS sources and Marketplace metadata |
| `contract` and `tests` | Shared wire types, fixtures, and regression tests |
| `scripts` | Source checks, packaging, and release verification |

The root `Package.swift` distributes a published binary; it is not the entry
for testing uncommitted Swift source. Use the source-test scripts below.

## Source checks

From the repository root:

```sh
./scripts/check-source.sh
```

This runs documentation and metadata checks, UNI JS synchronization checks,
JavaScript bridge tests, release-tool regression tests, and script syntax
checks. On macOS it also checks Swift formatting and Xcode project syntax.
It does not compile every native target or run physical NFC tests.

Useful focused checks are:

```sh
ruby scripts/verify-documentation.rb
node --test tests/js/*.test.mjs
./scripts/sync-uniapp-js.sh --check
```

Edit the canonical `adapters/uniapp/index.js` and `bridge.js`, then run
`./scripts/sync-uniapp-js.sh` to update the UTS module's JS copies. The `--check`
form detects drift without changing files. Shared types come from
`contract/types.ts`; package scripts place them into consumer packages.

Android core, panel, and bridge checks:

```sh
./native/android/gradlew -p native/android --no-daemon \
  :sfiora:testDebugUnitTest :sfiora-ui:testDebugUnitTest \
  :sfiora:lintRelease :sfiora-ui:lintRelease
./native/android/gradlew -p adapters/android --no-daemon \
  :bridge-support:testDebugUnitTest
```

Apple checks:

```sh
./scripts/test-native-ios-source.sh
./scripts/test-native-ios-runtime.sh
swift test --package-path adapters/shared -Xswiftc -warnings-as-errors
```

The first command tests portable Swift source models and codecs. The second
drives the production `NfcClient` and delegates on an iOS Simulator with system
boundaries replaced by test doubles. Neither proves real NFC hardware behavior.
Both scripts create temporary projects and remove them on exit; save command
output separately when a lasting diagnostic log is needed.

To compile the production iOS framework without packaging a release, reuse a
fixed DerivedData location:

```sh
xcodebuild -quiet -project native/ios/Sfiora.xcodeproj -scheme Sfiora \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build/development/ios \
  CODE_SIGNING_ALLOWED=NO SWIFT_TREAT_WARNINGS_AS_ERRORS=YES build
```

Use `generic/platform=iOS` for an unsigned device compile. A development
build does not require changing the product version. Packaging a new candidate
does: follow [RELEASING.md](RELEASING.md), choose an unpublished version, and
finalize package metadata and documentation before recording its identity.

## Interactive RN and UNI development

Use the separate `integrated-plugins` checkout's development entry. It prepares
source consumers without replacing the accepted candidate or stable packages.
For example:

```sh
ruby /absolute/path/to/integrated-plugins/development/run.rb --help
ruby /absolute/path/to/integrated-plugins/development/run.rb \
  --plugin sfiora --target react-native-android \
  --source /absolute/path/to/sfiora --build
ruby /absolute/path/to/integrated-plugins/development/run.rb \
  --plugin sfiora --target uniapp-uts \
  --source /absolute/path/to/sfiora
```

The available targets are `android`, `ios`, `react-native-android`,
`react-native-ios`, `uniapp-legacy`, `uniapp-uts`, and `uniapp-x`. The command
prints the generated project location; it does not install or start the app.
UNI targets omit `--build`: open the prepared project in HBuilderX and use the
host's existing build process. RN iOS accepts `--ios-sdk iphoneos` or
`--ios-sdk iphonesimulator`. Run preparation/build commands for one plugin
serially because they share native outputs.

RN uses the test repository's existing dependencies and native host. UNI needs
HBuilderX 5.24 or newer and the installed platform tools. Classic offline builds
use the official SDK/demo and the test repository's fixed generated projects;
they are rebuilt in place, not kept as a new project for every session. Follow
that repository's `verification/dcloud-offline/README.md` for SDK selection and
its scoped cleanup command. uni-app x uses its custom base workflow.

For formal package compiler checks, `scripts/verify-react-native.sh` uses the
existing external RN, Gradle-plugin, and codegen packages selected by
`SFIORA_REACT_NATIVE_PATH`, `SFIORA_REACT_NATIVE_GRADLE_PLUGIN_PATH`, and
`SFIORA_REACT_NATIVE_CODEGEN_PATH`; it also needs CocoaPods and Xcode. It checks
both RN architectures and reuses `.build/react-native-verification`.

`scripts/verify-uniapp-uts-compiler.sh` consumes an existing UTS archive. Its
default HBuilderX location is `/Applications/HBuilderX.app/Contents/HBuilderX`;
override it with `HBUILDERX_CONTENTS` when needed. Set
`DCLOUD_UNIAPP_X_ANDROID_SDK_ROOT` and `DCLOUD_UNIAPP_X_IOS_SDK_ROOT` to extracted
official SDK roots. Its temporary extraction/compiler projects are removed on
exit. These are package checks, separate from everyday source development.

## Build directories and cleanup

| Location | Ownership and retention |
| --- | --- |
| `native/android/**/build`, `adapters/**/build`, local `.gradle` | Reusable Gradle output/cache; clean the specific project when needed |
| `.build/development` | Fixed local source-build output; safe to regenerate after saving needed diagnostics |
| `.build/react-native-verification` | One reusable formal RN verification host, dependencies, and logs |
| `adapters/shared/.build` | Swift package build cache |
| `dist/native-*`, `dist/react-native`, `dist/uniapp` | Release artifacts, not a general scratch directory |
| `dist/candidate.json` | Identity and hashes of the current candidate |

Keep interactive hosts in the test repository's fixed `development/.work/sfiora`
locations. Edit source here and host pages there, not generated copies. Re-run
preparation and build after native/bridge changes; JavaScript hot reload cannot
install changed native code.

Inspect a directory before cleaning it and stop builds that use it. Build
caches are reproducible; saved logs, uncommitted host changes, accepted artifacts,
and receipts may not be. Do not clear all of `dist/` or all `.build` directories
as a generic cleanup. Candidate recording already prunes only its known older
artifact families, retaining the current version and the latest canonical local
tag's version; unknown files and historical candidate directories stay intact.
Details and exceptions are in [RELEASING.md](RELEASING.md#build-and-snapshot).

## Documentation maintenance

The two root READMEs summarize capabilities, channels, and boundaries. Each
native/adapter guide owns its complete integration examples. Keep both landing
pages aligned and put source-build instructions here, release procedures in
[RELEASING.md](RELEASING.md), and temporary device/review notes outside tracked
consumer documentation.

Maintain release notes in `CHANGELOG.md` and the UNI user guide in
`adapters/uniapp/README.md`. Packaging copies these into the published packages;
do not maintain another market-only readme. Review market declarations in
`uni_modules/Sandrox-Sfiora/package.json` when the publishing form changes them.

`verify-documentation.rb` checks local file links, bilingual guide/channel
coverage, declared minimum requirements, and bridge method names in examples.
It uses only local source and standard Ruby libraries. It does not certify
remote links, NFC behavior, or every example's semantics. When editing native
examples, compile the Java snippets against the matching core/UI classes and
Android SDK, and type-check the Swift snippets against the matching iOS module.
Use `.build/development/documentation` for disposable compiler output; avoid
building or replacing release artifacts merely to check documentation.

After publication, documentation fixes may be committed to the default branch.
Do not move a public tag or overwrite published packages. Embedded package
documentation is updated with a later package version.
