#!/usr/bin/env python3
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest
import warnings
import zipfile

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("release_assets", Path(__file__).with_name("verify-release-assets.py"))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseAssetsTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="sfiora-release-assets-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / "source"
        self.source.mkdir()
        self.artifacts = self.root / "artifacts"
        self.artifacts.mkdir()
        self.version = "1.0.0"
        self.android = {"sfiora.aar": b"accepted core", "sfiora-ui.aar": b"accepted UI"}
        self.bridge = b"accepted shared bridge"
        self.ios_files = {
            "Sfiora.xcframework/ios-arm64/Sfiora.framework/Sfiora": b"device",
            "Sfiora.xcframework/ios-arm64_x86_64-simulator/Sfiora.framework/Sfiora": b"simulator",
        }
        self.ios_path = self.artifacts / "sfiora-1.0.0.xcframework.zip"
        self.write_zip(self.ios_path, self.ios_files)
        metadata = {"name": "@sandrox/sfiora", "version": self.version,
                    "repository": {"url": "https://github.com/sandroxy/sfiora.git"}}
        sources = {
            "adapters/react-native/package.json": json.dumps(metadata).encode(),
            "adapters/react-native/src/specs/NativeSfiora.ts": b"spec",
            "adapters/react-native/plugin/withSfiora.js": b"plugin",
            "adapters/react-native/android/src/main/Sfiora.java": b"bridge",
            "adapters/react-native/ios/Sfiora.mm": b"bridge",
            "adapters/shared/ios/Sources/SfioraBridgeSupport/Options.swift": b"options",
        }
        for name in ("index.js", "index.d.ts", "app.plugin.js", "react-native.config.js",
                     "SfioraReactNative.podspec", "README.md", "android/build.gradle", "android/consumer-rules.pro"):
            sources["adapters/react-native/" + name] = name.encode()
        for name in ("LICENSE", "CHANGELOG.md", "contract/types.ts", "contract/bridge.schema.json"):
            sources[name] = name.encode()
        for name, data in sources.items():
            path = self.source / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        self.git("init", "-q")
        self.git("add", ".")
        self.npm_path = self.artifacts / "sandrox-sfiora-1.0.0.tgz"
        self.npm_files = release.rn_sources(self.source)
        self.npm_files.update({"android/libs/" + name: data for name, data in self.android.items()})
        self.npm_files["android/libs/sfiora-bridge-support.aar"] = self.bridge
        self.npm_files["sfiora-artifacts.json"] = self.provenance()
        self.npm_files.update({"ios/Frameworks/" + name: data for name, data in self.ios_files.items()})

    def git(self, *args):
        return subprocess.run(["git", "-C", str(self.source), *args], capture_output=True, check=True)

    def provenance(self, legacy=False):
        android = dict(self.android, **{"sfiora-bridge-support.aar": self.bridge})
        if legacy:
            android["sfiora-uniapp.aar"] = b"legacy bridge"
        return json.dumps({"schemaVersion": 1, "version": self.version,
                           "nativeArtifacts": {"android": {name: release.digest(data) for name, data in android.items()},
                                               "ios": {"sfiora.xcframework.zip": release.digest(self.ios_path.read_bytes())}}}).encode()

    def sidecar(self, path):
        Path(str(path) + ".sha256").write_text(f"{release.digest(path.read_bytes())}  {path.name}\n")

    def write_zip(self, path, files):
        with zipfile.ZipFile(path, "w") as archive:
            for name, data in files.items():
                archive.writestr(name, data)
        self.sidecar(path)

    def write_npm(self, files=None):
        with tarfile.open(self.npm_path, "w:gz") as archive:
            for name, data in (files or self.npm_files).items():
                entry = tarfile.TarInfo("package/" + name)
                entry.size = len(data)
                archive.addfile(entry, io.BytesIO(data))
        self.sidecar(self.npm_path)

    def verify_npm(self):
        release.verify_npm(self.source, self.artifacts, self.version, self.android, self.ios_path, self.ios_files)

    def test_exact_npm_source_and_embedded_native_payload_pass(self):
        self.write_npm()
        self.verify_npm()

    def test_changed_source_is_rejected_even_with_a_matching_tarball_sidecar(self):
        self.npm_files["index.js"] = b"changed bridge"
        self.write_npm()
        with self.assertRaisesRegex(release.VerificationError, "source payload differs"):
            self.verify_npm()

    def test_changed_ui_cannot_be_hidden_by_updating_embedded_provenance(self):
        self.npm_files["android/libs/sfiora-ui.aar"] = b"another UI"
        provenance = json.loads(self.npm_files["sfiora-artifacts.json"])
        provenance["nativeArtifacts"]["android"]["sfiora-ui.aar"] = release.digest(b"another UI")
        self.npm_files["sfiora-artifacts.json"] = json.dumps(provenance).encode()
        self.write_npm()
        with self.assertRaisesRegex(release.VerificationError, "Embedded Android core differs"):
            self.verify_npm()

    def test_extra_ios_binary_is_rejected(self):
        self.npm_files["ios/Frameworks/Sfiora.xcframework/extra"] = b"unexpected"
        self.write_npm()
        with self.assertRaisesRegex(release.VerificationError, "Embedded iOS framework differs"):
            self.verify_npm()

    def test_missing_and_extra_npm_files_are_rejected(self):
        del self.npm_files["index.d.ts"]
        self.npm_files["unexpected.js"] = b"unexpected"
        self.write_npm()
        with self.assertRaisesRegex(release.VerificationError, "npm file set differs"):
            self.verify_npm()

    def test_checksum_sidecar_must_name_this_tarball(self):
        self.write_npm()
        Path(str(self.npm_path) + ".sha256").write_text(
            f"{release.digest(self.npm_path.read_bytes())}  wrong-name.tgz\n")
        with self.assertRaisesRegex(release.VerificationError, "Checksum sidecar differs"):
            self.verify_npm()

    def test_archive_parent_paths_and_links_are_rejected_without_extraction(self):
        for name, kind in (("package/../escape", tarfile.REGTYPE), ("package/link", tarfile.SYMTYPE)):
            with self.subTest(name=name):
                with tarfile.open(self.npm_path, "w:gz") as archive:
                    entry = tarfile.TarInfo(name)
                    entry.type = kind
                    entry.linkname = "../../escape" if kind == tarfile.SYMTYPE else ""
                    archive.addfile(entry)
                with self.assertRaises(release.VerificationError):
                    release.read_archive(self.npm_path)
        self.assertFalse((self.root / "escape").exists())

    def test_duplicate_zip_entries_are_rejected(self):
        path = self.artifacts / "duplicate.zip"
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", UserWarning)
            with zipfile.ZipFile(path, "w") as archive:
                archive.writestr("payload", b"first")
                archive.writestr("payload", b"second")
        with self.assertRaisesRegex(release.VerificationError, "Duplicate"):
            release.read_archive(path)

    def test_both_uni_modes_match_the_accepted_hashes_and_native_bytes(self):
        hashes = {}
        for legacy in (False, True):
            prefix = "Sandrox-Sfiora/" if legacy else ""
            package = {"id": "Sandrox-Sfiora", "version": self.version}
            package.update({"_dp_type": "nativeplugin"} if legacy else {"dcloudext": {"type": "uts"}})
            files = {prefix + "package.json": json.dumps(package).encode(),
                     prefix + "sfiora-artifacts.json": self.provenance(legacy)}
            android_dir = "android" if legacy else "utssdk/app-android/libs"
            names = ({"Sfiora-1.0.0": self.android["sfiora.aar"], "SfioraUI-1.0.0": self.android["sfiora-ui.aar"],
                      "SfioraBridgeSupport": self.bridge, "SfioraUniApp": b"legacy bridge"} if legacy else
                     {"sfiora": self.android["sfiora.aar"], "sfiora-ui": self.android["sfiora-ui.aar"],
                      "sfiora-bridge-support": self.bridge})
            files.update({prefix + android_dir + "/" + name + ".aar": data for name, data in names.items()})
            ios_dir = "ios" if legacy else "utssdk/app-ios/Frameworks"
            files[prefix + ios_dir + "/Sfiora.framework/Sfiora"] = b"device"
            path = self.artifacts / f"sfiora-uniapp{'-uts' if not legacy else ''}-1.0.0.zip"
            self.write_zip(path, files)
            hashes[legacy] = release.digest(path.read_bytes())
        release.verify_uniapp(self.artifacts, self.version, self.android, self.ios_path, self.ios_files,
                              hashes[False], hashes[True])
        with self.assertRaisesRegex(release.VerificationError, "Accepted SHA-256 differs"):
            release.verify_uniapp(self.artifacts, self.version, self.android, self.ios_path, self.ios_files,
                                  hashes[False], "0" * 64)


if __name__ == "__main__":
    unittest.main()
