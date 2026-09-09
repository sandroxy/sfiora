#!/usr/bin/env python3
"""Verify downloaded release bytes without rebuilding or publishing anything."""

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import stat
import subprocess
import tarfile
import zipfile


class VerificationError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise VerificationError(message)


def command(*args):
    result = subprocess.run(args, capture_output=True, text=True, check=False)
    require(result.returncode == 0, result.stderr.strip() or result.stdout.strip() or f"Command failed: {args[0]}")
    return result.stdout


def digest(data):
    return hashlib.sha256(data).hexdigest()


def safe_name(name):
    require(isinstance(name, str) and name != "" and "\\" not in name and
            not any(ord(char) < 32 for char in name), f"Unsafe archive path: {name!r}")
    path = PurePosixPath(name)
    require(not path.is_absolute() and ".." not in path.parts and
            str(path) == name.rstrip("/"), f"Unsafe archive path: {name!r}")
    return name.rstrip("/")


def read_archive(path):
    """Read regular payloads only. Never extract a downloaded archive to disk."""
    files, seen = {}, set()
    if path.name.endswith(".tgz"):
        with tarfile.open(path, "r:gz") as archive:
            for entry in archive:
                name = safe_name(entry.name)
                require(name not in seen, f"Duplicate archive path: {name}")
                seen.add(name)
                require(entry.isfile() or entry.isdir(), f"Non-regular archive entry: {name}")
                require(name == "package" or name.startswith("package/"), "npm archive must have a package/ root")
                if entry.isfile():
                    files[name.removeprefix("package/")] = archive.extractfile(entry).read()
    else:
        with zipfile.ZipFile(path) as archive:
            for entry in archive.infolist():
                name = safe_name(entry.filename)
                require(name not in seen, f"Duplicate archive path: {name}")
                seen.add(name)
                mode = entry.external_attr >> 16
                require(stat.S_IFMT(mode) in (0, stat.S_IFREG, stat.S_IFDIR),
                        f"Non-regular archive entry: {name}")
                if not entry.is_dir():
                    files[name] = archive.read(entry)
    require(files, f"Empty archive: {path.name}")
    return files


def verify_sidecar(path, expected=None):
    actual = digest(path.read_bytes())
    fields = Path(str(path) + ".sha256").read_text().split()
    require(fields == [actual, path.name], f"Checksum sidecar differs: {path.name}")
    if expected is not None:
        require(re.fullmatch(r"[0-9a-f]{64}", expected) is not None, "Invalid accepted SHA-256")
        require(actual == expected, f"Accepted SHA-256 differs: {path.name}")
    return actual


def verify_bytes(path, entry):
    require(path.is_file() and not path.is_symlink(), f"Missing regular artifact: {path}")
    data = path.read_bytes()
    require(len(data) == entry["bytes"] and digest(data) == entry["sha256"],
            f"Native artifact bytes differ: {path.name}")
    return data


def ruby_manifest_check(source, manifest, version, ios=None):
    verifier_root = Path(__file__).resolve().parents[2]
    program = """
require "json"
require "pathname"
require "native-release-manifest"
source, path, version, ios = ARGV
policy = ReleasePolicy.load(File.join(source, "release-policy.json"))
manifest = JSON.parse(File.read(path))
NativeReleaseManifest.validate!(manifest, version: version, policy: policy)
NativeReleaseManifest.verify_reuse!(manifest, root: source)
NativeReleaseManifest.verify_ios!(manifest, root: source, archive: ios) if ios
"""
    args = ["ruby", "-I", str(verifier_root / "scripts"), "-e", program,
            str(source), str(manifest), version]
    if ios:
        args.append(str(ios))
    command(*args)


def release_context(source, artifacts, version):
    require(re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version) is not None, "Only stable release versions are supported")
    product = json.loads((source / "plugin.json").read_text())
    require(product["id"] == "sfiora" and product["version"] == version, "Release source identity differs")
    require(command("git", "-C", str(source), "cat-file", "-t", f"refs/tags/{version}").strip() == "tag",
            "An annotated release tag is required")
    commit = command("git", "-C", str(source), "rev-parse", "HEAD").strip()
    require(command("git", "-C", str(source), "rev-parse", f"refs/tags/{version}^{{commit}}").strip() == commit,
            "Release source HEAD differs from the annotated tag")
    require(not command("git", "-C", str(source), "status", "--porcelain").strip(),
            "Release source checkout must be clean")
    manifest_path = artifacts / f"sfiora-native-{version}.json"
    manifest = json.loads(manifest_path.read_text())
    ruby_manifest_check(source, manifest_path, version)
    require(manifest["commit"] == commit and manifest["dirty"] is False and
            manifest["androidMavenSigned"] is True and manifest["iosBinaryPromoted"] is True,
            "Native manifest is not the clean, signed, accepted release")
    entries = {PurePosixPath(entry["file"]).name: entry for entry in manifest["artifacts"]}
    android = {}
    for artifact_id in ("sfiora", "sfiora-ui"):
        name = f"{artifact_id}-{version}.aar"
        android[f"{artifact_id}.aar"] = verify_bytes(artifacts / name, entries[name])
    return manifest_path, entries, android


def verify_ios(source, artifacts, version, manifest_path, entries):
    path = artifacts / f"sfiora-{version}.xcframework.zip"
    verify_bytes(path, entries[path.name])
    files = read_archive(path)
    package = (source / "Package.swift").read_text()
    checksum = re.search(r'let sfioraBinaryChecksum =\s*"([0-9a-f]{64})"', package)
    require(checksum is not None and checksum[1] == digest(path.read_bytes()),
            "Swift Package checksum differs from the public XCFramework")
    require(f'let sfioraVersion = "{version}"' in package, "Swift Package version differs")
    ruby_manifest_check(source, manifest_path, version, path)
    return path, files


def source_files(source, scope):
    return command("git", "-C", str(source), "ls-files", "-z", "--", scope).split("\0")[:-1]


def rn_sources(source):
    adapter = "adapters/react-native/"
    expected = {}
    for name in ("package.json", "index.js", "index.d.ts", "app.plugin.js", "react-native.config.js",
                 "SfioraReactNative.podspec", "README.md", "android/build.gradle", "android/consumer-rules.pro"):
        expected[name] = (source / adapter / name).read_bytes()
    for name in ("LICENSE", "CHANGELOG.md", "contract/types.ts", "contract/bridge.schema.json"):
        expected[name] = (source / name).read_bytes()
    for scope in ("plugin", "src", "android/src", "ios"):
        for path in source_files(source, adapter + scope):
            expected[path.removeprefix(adapter)] = (source / path).read_bytes()
    prefix = "adapters/shared/ios/Sources/"
    for path in source_files(source, prefix):
        expected["shared/ios/Sources/" + path.removeprefix(prefix)] = (source / path).read_bytes()
    return expected


def verify_embedded(files, version, prefix, android_dir, ios_dir, android, ios_path, ios_files, whole):
    def entry(name):
        return files[prefix + name]

    provenance = json.loads(entry("sfiora-artifacts.json"))
    require(provenance["schemaVersion"] == 1 and provenance["version"] == version,
            "Adapter provenance identity differs")
    legacy = prefix != ""
    names = ({"sfiora": f"Sfiora-{version}", "sfiora-ui": f"SfioraUI-{version}",
              "sfiora-bridge-support": "SfioraBridgeSupport", "sfiora-uniapp": "SfioraUniApp"}
             if legacy else {name: name for name in ("sfiora", "sfiora-ui", "sfiora-bridge-support")})
    require(set(provenance["nativeArtifacts"]["android"]) == {name + ".aar" for name in names},
            "Adapter Android provenance entries differ")
    for name, packaged_name in names.items():
        data = entry(f"{android_dir}/{packaged_name}.aar")
        require(digest(data) == provenance["nativeArtifacts"]["android"][name + ".aar"],
                f"Embedded Android provenance differs: {name}")
        if name + ".aar" in android:
            require(data == android[name + ".aar"], f"Embedded Android core differs: {name}")
    require(provenance["nativeArtifacts"]["ios"] == {"sfiora.xcframework.zip": digest(ios_path.read_bytes())},
            "Adapter iOS provenance differs")
    device = "Sfiora.xcframework/ios-arm64/Sfiora.framework/"
    selected = ios_files if whole else {name: data for name, data in ios_files.items() if name.startswith(device)}
    require(selected, "Native iOS device framework is missing")
    expected = {}
    for name, data in selected.items():
        name = name if whole else "Sfiora.framework/" + name.removeprefix(device)
        expected[prefix + ios_dir + "/" + name] = data
    actual = {name: data for name, data in files.items()
              if name.startswith(prefix + ios_dir + ("/Sfiora.xcframework/" if whole else "/Sfiora.framework/"))}
    require(actual == expected, "Embedded iOS framework differs from the accepted native bytes")
    return expected


def verify_npm(source, artifacts, version, android, ios_path, ios_files):
    path = artifacts / f"sandrox-sfiora-{version}.tgz"
    verify_sidecar(path)
    files = read_archive(path)
    package = json.loads(files["package.json"])
    require(package["name"] == "@sandrox/sfiora" and package["version"] == version,
            "npm package identity differs")
    require(package["repository"]["url"] == "https://github.com/sandroxy/sfiora.git",
            "npm repository differs")
    require(not package.get("private") and not package.get("dependencies"),
            "Unexpected npm package visibility or runtime dependencies")
    require(not set(package.get("scripts", {})) & {
        "preinstall", "install", "postinstall", "prepare", "prepublish", "prepublishOnly", "prepack", "postpack", "publish", "postpublish"
    }, "Unexpected npm lifecycle scripts")
    expected = rn_sources(source)
    expected.update(verify_embedded(files, version, "", "android/libs", "ios/Frameworks",
                                    android, ios_path, ios_files, True))
    for name in ("sfiora.aar", "sfiora-ui.aar", "sfiora-bridge-support.aar"):
        expected["android/libs/" + name] = files["android/libs/" + name]
    expected["sfiora-artifacts.json"] = files["sfiora-artifacts.json"]
    require(files.keys() == expected.keys(),
            f"npm file set differs: missing={sorted(expected.keys() - files.keys())}, extra={sorted(files.keys() - expected.keys())}")
    for name, data in expected.items():
        require(files[name] == data, f"npm source payload differs from the release tag: {name}")


def verify_uniapp(artifacts, version, android, ios_path, ios_files, uts_sha256, legacy_sha256):
    for legacy, expected in ((False, uts_sha256), (True, legacy_sha256)):
        filename = f"sfiora-uniapp{'-uts' if not legacy else ''}-{version}.zip"
        path = artifacts / filename
        verify_sidecar(path, expected)
        files = read_archive(path)
        prefix = "Sandrox-Sfiora/" if legacy else ""
        package = json.loads(files[prefix + "package.json"])
        require(package["id"] == "Sandrox-Sfiora" and package["version"] == version,
                "UNI package identity differs")
        require(package.get("_dp_type") == "nativeplugin" if legacy else package.get("dcloudext", {}).get("type") == "uts",
                "UNI package mode differs")
        verify_embedded(files, version, prefix, "android" if legacy else "utssdk/app-android/libs",
                        "ios" if legacy else "utssdk/app-ios/Frameworks", android, ios_path, ios_files, False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--artifacts", type=Path, required=True)
    parser.add_argument("--channel", choices=("android", "npm", "uniapp"), required=True)
    parser.add_argument("--uts-sha256")
    parser.add_argument("--legacy-sha256")
    args = parser.parse_args()
    if args.channel == "uniapp":
        require(all(value and re.fullmatch(r"[0-9a-f]{64}", value)
                    for value in (args.uts_sha256, args.legacy_sha256)), "Both accepted UNI checksums are required")
    else:
        require(args.uts_sha256 is None and args.legacy_sha256 is None, "UNI checksums apply only to the uniapp channel")
    source, artifacts = args.source.resolve(strict=True), args.artifacts.resolve(strict=True)
    manifest, entries, android = release_context(source, artifacts, args.version)
    if args.channel != "android":
        ios, files = verify_ios(source, artifacts, args.version, manifest, entries)
        if args.channel == "npm":
            verify_npm(source, artifacts, args.version, android, ios, files)
        else:
            verify_uniapp(artifacts, args.version, android, ios, files, args.uts_sha256, args.legacy_sha256)
    print(f"Verified public {args.channel} release bytes for Sfiora {args.version}.")


if __name__ == "__main__":
    try:
        main()
    except (VerificationError, OSError, KeyError, ValueError, tarfile.TarError, zipfile.BadZipFile) as error:
        raise SystemExit(str(error))
