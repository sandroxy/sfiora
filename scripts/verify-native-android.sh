#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/release-common.sh"

skip_package=0
require_signatures=0
for argument in "$@"; do
    case "${argument}" in
        --skip-package) skip_package=1 ;;
        --require-signatures) require_signatures=1 ;;
        *)
            echo "Usage: $0 [--skip-package] [--require-signatures]" >&2
            exit 1
            ;;
    esac
done

for command_name in jar openssl unzip; do
    sfiora_require_command "${command_name}"
done

if [[ ${skip_package} -eq 0 ]]; then
    "${script_dir}/package-native-android.sh"
fi

artifact_dir="${sfiora_root}/dist/native-android"
core_artifact="${artifact_dir}/sfiora-${sfiora_version}.aar"
ui_artifact="${artifact_dir}/sfiora-ui-${sfiora_version}.aar"
repository_artifact="${artifact_dir}/sfiora-${sfiora_version}-maven.zip"
for artifact_path in "${core_artifact}" "${ui_artifact}" "${repository_artifact}"; do
    sfiora_verify_checksum "${artifact_path}"
done

temporary_root="${TMPDIR:-/tmp}"
temporary_dir="$(mktemp -d "${temporary_root%/}/sfiora-android-verify.XXXXXX")"
gpg_home=""
cleanup_android_verification() {
    if [[ -n "${gpg_home}" ]]; then
        gpgconf --homedir "${gpg_home}" --kill all >/dev/null 2>&1 || true
        sfiora_cleanup_temporary_directory "${gpg_home}"
    fi
    sfiora_cleanup_temporary_directory "${temporary_dir}"
}
trap cleanup_android_verification EXIT

verify_aar() {
    local artifact_id="$1"
    local artifact_path="$2"
    local expected_class="$3"
    local legal_resource="$4"
    local aar_dir="${temporary_dir}/${artifact_id}-aar"
    local classes_dir="${temporary_dir}/${artifact_id}-classes"
    local class_listing
    mkdir -p "${aar_dir}" "${classes_dir}"
    unzip -q "${artifact_path}" -d "${aar_dir}"

    if [[ ! -f "${aar_dir}/classes.jar" ]]; then
        echo "classes.jar is missing from ${artifact_path}" >&2
        exit 1
    fi
    class_listing="$(jar tf "${aar_dir}/classes.jar")"
    if ! grep -Fxq "${expected_class}" <<<"${class_listing}"; then
        echo "Expected public class is missing from ${artifact_path}: ${expected_class}" >&2
        exit 1
    fi
    if ! grep -Fxq "META-INF/${legal_resource}" <<<"${class_listing}"; then
        echo "Sfiora license is missing from ${artifact_path}" >&2
        exit 1
    fi

    (
        cd "${classes_dir}"
        jar xf "${aar_dir}/classes.jar" "META-INF/${legal_resource}"
    )
    cmp "${sfiora_root}/LICENSE" "${classes_dir}/META-INF/${legal_resource}"
}

verify_aar \
    sfiora \
    "${core_artifact}" \
    "com/sandrox/sfiora/NfcClient.class" \
    "SFIORA_LICENSE"
verify_aar \
    sfiora-ui \
    "${ui_artifact}" \
    "com/sandrox/sfiora/ui/NfcScanController.class" \
    "SFIORA_UI_LICENSE"

ui_class_listing="$(jar tf "${temporary_dir}/sfiora-ui-aar/classes.jar")"
if grep -Fxq "com/sandrox/sfiora/NfcClient.class" <<<"${ui_class_listing}"; then
    echo "sfiora-ui must depend on sfiora instead of embedding its classes." >&2
    exit 1
fi
if [[ ! -f "${temporary_dir}/sfiora-ui-aar/res/layout/nfc_reader_scan_panel.xml" ]]; then
    echo "Sfiora managed UI resources are missing from ${ui_artifact}" >&2
    exit 1
fi

core_manifest="${temporary_dir}/sfiora-aar/AndroidManifest.xml"
if ! grep -Fq 'android.permission.NFC' "${core_manifest}" \
    || ! grep -Fq 'android.hardware.nfc' "${core_manifest}" \
    || ! grep -Fq 'android:required="false"' "${core_manifest}"; then
    echo "Sfiora AAR has unexpected NFC manifest metadata." >&2
    exit 1
fi

repository_dir="${temporary_dir}/maven"
mkdir -p "${repository_dir}"
unzip -q "${repository_artifact}" -d "${repository_dir}"
repository_metadata="$(find "${repository_dir}" -type f -name 'maven-metadata.xml*' -print)"
if [[ -n "${repository_metadata}" ]]; then
    echo "Fixed-version Maven candidate must not contain repository metadata." >&2
    exit 1
fi

verify_repository_checksum() {
    local packaged_file="$1"
    local algorithm="$2"
    local checksum_file="${packaged_file}.${algorithm}"
    local expected_checksum
    local actual_checksum
    if [[ ! -f "${checksum_file}" ]]; then
        echo "Maven checksum is missing: ${checksum_file}" >&2
        exit 1
    fi
    expected_checksum="$(tr -d '[:space:]' < "${checksum_file}")"
    actual_checksum="$(openssl dgst "-${algorithm}" "${packaged_file}" | awk '{ print $NF }')"
    if [[ "${actual_checksum}" != "${expected_checksum}" ]]; then
        echo "Maven ${algorithm} mismatch: ${packaged_file}" >&2
        exit 1
    fi
}

for artifact_id in sfiora sfiora-ui; do
    version_dir="${repository_dir}/io/github/sandroxy/${artifact_id}/${sfiora_version}"
    for suffix in aar pom module sources.jar javadoc.jar; do
        packaged_file="${version_dir}/${artifact_id}-${sfiora_version}-${suffix}"
        case "${suffix}" in
            aar|pom|module)
                packaged_file="${version_dir}/${artifact_id}-${sfiora_version}.${suffix}"
                ;;
        esac
        if [[ ! -f "${packaged_file}" ]]; then
            echo "Maven artifact is missing: ${packaged_file}" >&2
            exit 1
        fi
        for algorithm in md5 sha1 sha256 sha512; do
            verify_repository_checksum "${packaged_file}" "${algorithm}"
        done
        if [[ ${require_signatures} -eq 1 ]]; then
            signature_path="${packaged_file}.asc"
            if [[ ! -f "${signature_path}" ]]; then
                echo "Maven signature is missing: ${signature_path}" >&2
                exit 1
            fi
            for algorithm in md5 sha1 sha256 sha512; do
                verify_repository_checksum "${signature_path}" "${algorithm}"
            done
        fi
    done

    cmp \
        "${artifact_dir}/${artifact_id}-${sfiora_version}.aar" \
        "${version_dir}/${artifact_id}-${sfiora_version}.aar"

    for classifier in sources javadoc; do
        classified_jar="${version_dir}/${artifact_id}-${sfiora_version}-${classifier}.jar"
        legal_resource="SFIORA_LICENSE"
        if [[ "${artifact_id}" == "sfiora-ui" ]]; then
            legal_resource="SFIORA_UI_LICENSE"
        fi
        classified_listing="$(jar tf "${classified_jar}")"
        if ! grep -Fxq "META-INF/${legal_resource}" <<<"${classified_listing}"; then
            echo "Sfiora license is missing from ${classified_jar}" >&2
            exit 1
        fi
    done
done

ruby -rrexml/document -e '
    root, version = ARGV
    expected = {
      "sfiora" => false,
      "sfiora-ui" => true
    }
    expected.each do |artifact, expects_core_dependency|
      path = File.join(root, "io/github/sandroxy", artifact, version, "#{artifact}-#{version}.pom")
      document = REXML::Document.new(File.read(path))
      value = ->(xpath) { REXML::XPath.first(document, xpath)&.text }
      abort("Unexpected group in #{path}") unless value.call("//groupId") == "io.github.sandroxy"
      abort("Unexpected artifact in #{path}") unless value.call("//artifactId") == artifact
      abort("Unexpected version in #{path}") unless value.call("//version") == version
      abort("Unexpected project URL in #{path}") unless
        value.call("//project/url") == "https://github.com/sandroxy/sfiora"
      abort("Apache-2.0 metadata is missing from #{path}") unless
        value.call("//licenses/license/url") == "https://www.apache.org/licenses/LICENSE-2.0.txt"
      abort("Canonical SCM metadata is missing from #{path}") unless
        value.call("//scm/connection") == "scm:git:https://github.com/sandroxy/sfiora.git"
      dependencies = REXML::XPath.match(document, "//dependencies/dependency")
      if expects_core_dependency
        abort("sfiora-ui must declare one dependency") unless dependencies.length == 1
        dependency = dependencies.fetch(0)
        fields = dependency.elements
        abort("sfiora-ui has unexpected core dependency metadata") unless
          fields["groupId"]&.text == "io.github.sandroxy" &&
          fields["artifactId"]&.text == "sfiora" &&
          fields["version"]&.text == version &&
          fields["scope"]&.text == "compile"
      else
        abort("sfiora core must not add runtime dependencies") unless dependencies.empty?
      end
    end
  ' "${repository_dir}" "${sfiora_version}"

ruby -rjson -e '
    root, version = ARGV
    path = File.join(root, "io/github/sandroxy/sfiora-ui", version, "sfiora-ui-#{version}.module")
    metadata = JSON.parse(File.read(path))
    dependencies = metadata.fetch("variants").flat_map { |variant| variant.fetch("dependencies", []) }
    abort("Gradle metadata does not expose sfiora-ui -> sfiora") unless dependencies.any? do |dependency|
      dependency["group"] == "io.github.sandroxy" &&
        dependency["module"] == "sfiora" &&
        dependency.dig("version", "requires") == version
    end
  ' "${repository_dir}" "${sfiora_version}"

if [[ ${require_signatures} -eq 1 ]]; then
    sfiora_require_command gpg
    sfiora_require_command gpgconf
    if [[ -z "${SFIORA_SIGNING_KEY:-}" ]]; then
        echo "SFIORA_SIGNING_KEY is required to verify Maven signatures." >&2
        exit 1
    fi
    gpg_home="$(mktemp -d /tmp/sfiora-gpg.XXXXXX)"
    chmod 700 "${gpg_home}"
    gpgconf --homedir "${gpg_home}" --launch gpg-agent
    printf '%s' "${SFIORA_SIGNING_KEY}" \
        | gpg \
            --batch \
            --quiet \
            --homedir "${gpg_home}" \
            --pinentry-mode loopback \
            --passphrase "${SFIORA_SIGNING_PASSWORD:-}" \
            --import
    while IFS= read -r signature_path; do
        gpg --batch --quiet --homedir "${gpg_home}" \
            --verify "${signature_path}" "${signature_path%.asc}"
    done < <(find "${repository_dir}" -type f -name '*.asc' | LC_ALL=C sort)
    gpgconf --homedir "${gpg_home}" --kill all
fi

consumer_dir="${temporary_dir}/consumer"
mkdir -p "${consumer_dir}/app/src/main/java/com/sandrox/sfiora/consumer"
cat > "${consumer_dir}/settings.gradle" <<'EOF'
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        maven { url = uri(providers.gradleProperty("candidateRepository").get()) }
        google()
        mavenCentral()
    }
}

rootProject.name = "SfioraArtifactConsumer"
include(":app")
EOF
cat > "${consumer_dir}/build.gradle" <<'EOF'
plugins {
    id "com.android.application" version "8.12.3" apply false
}
EOF
cat > "${consumer_dir}/app/build.gradle" <<EOF
plugins {
    id "com.android.application"
}

android {
    namespace = "com.sandrox.sfiora.consumer"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.sandrox.sfiora.consumer"
        minSdk = ${sfiora_android_min_sdk}
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
    }

    buildTypes {
        release {
            minifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
}

dependencies {
    implementation "${sfiora_android_group}:sfiora-ui:${sfiora_version}"
}
EOF
cat > "${consumer_dir}/app/src/main/AndroidManifest.xml" <<'EOF'
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application android:theme="@android:style/Theme.Material.Light.NoActionBar">
        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
EOF
cat > "${consumer_dir}/app/src/main/java/com/sandrox/sfiora/consumer/MainActivity.java" <<'EOF'
package com.sandrox.sfiora.consumer;

import android.app.Activity;
import android.os.Bundle;

import com.sandrox.sfiora.NfcClient;
import com.sandrox.sfiora.ui.NfcScanController;

public final class MainActivity extends Activity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        Class<?>[] publicTypes = {NfcClient.class, NfcScanController.class};
        if (publicTypes.length != 2) {
            throw new AssertionError("Unexpected Sfiora API probe");
        }
    }
}
EOF

"${sfiora_root}/native/android/gradlew" \
    -p "${consumer_dir}" \
    --no-daemon \
    -PcandidateRepository="${repository_dir}" \
    :app:lintRelease \
    :app:assembleRelease

merged_manifest="$(find "${consumer_dir}/app/build/intermediates" \
    -path '*/release/*' -name AndroidManifest.xml -print \
    | LC_ALL=C sort | tail -n 1)"
if [[ -z "${merged_manifest}" ]] \
    || ! grep -Fq 'android.permission.NFC' "${merged_manifest}" \
    || ! grep -Fq 'android.hardware.nfc' "${merged_manifest}"; then
    echo "Artifact-only Android consumer did not receive Sfiora NFC metadata." >&2
    exit 1
fi

printf '%s\n' "Verified Android artifacts for Sfiora ${sfiora_version}."
