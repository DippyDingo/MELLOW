#!/usr/bin/env python3
"""Patches a freshly generated `android/` project for Mellow.

`flutter create` produces a generic app; this script applies the changes that
Mellow actually needs and that cannot live in the repository (because `android/`
is generated, not committed):

  * `minSdk` 23 — flutter_secure_storage uses the Keystore APIs available from
    API 23; the Flutter default (21) would crash on the Android 5 devices.
  * `android:allowBackup="false"` — a backed-up Keystore key is unusable on the
    new device and produces `InvalidKeyException: Failed to unwrap key`.
  * an intent filter for the OAuth redirect scheme, and
    `flutter_deeplinking_enabled=false` so go_router does not swallow the link.
  * `<queries>` for the browser, required by url_launcher on Android 11+.
  * `REQUEST_INSTALL_PACKAGES` — needed from Android 8 to hand a downloaded APK
    to the system installer. The app is distributed outside Play, so the
    permission is legitimate here.
  * a `FileProvider` with authority `app.mellow.updates` plus
    `res/xml/update_paths.xml` — Android refuses a `file://` URI, so the APK has
    to travel to the installer as a content URI.
  * `ApkInstallerPlugin.java`, the Java side of the `app.mellow/apk_installer`
    channel, registered from `MainActivity`. Written here instead of pulling a
    third-party plugin: a plugin's Gradle requirements can be incompatible with
    this Flutter version, and one broken dependency takes the APK build down.

Run from the repository root after `flutter create`:

    python3 tool/platform/prepare_android.py --scheme com.googleusercontent.apps.X

The script is idempotent: running it twice changes nothing.
"""

from __future__ import annotations

import argparse
import pathlib
import re
import sys

MANIFEST = pathlib.Path("android/app/src/main/AndroidManifest.xml")
MAIN_ACTIVITY = pathlib.Path(
    "android/app/src/main/kotlin/app/mellow/mellow/MainActivity.kt"
)
JAVA_PLUGIN = pathlib.Path(
    "android/app/src/main/java/app/mellow/ApkInstallerPlugin.java"
)
UPDATE_PATHS = pathlib.Path("android/app/src/main/res/xml/update_paths.xml")

# FileProvider authority; the Dart side names the same value in `ApkInstaller`.
FILE_PROVIDER_AUTHORITY = "app.mellow.updates"

PROVIDER_LINES = [
    "        <!-- Update APKs reach the installer as content:// URIs:",
    "             Android rejects file:// with FileUriExposedException. -->",
    "        <provider",
    '            android:name="androidx.core.content.FileProvider"',
    f'            android:authorities="{FILE_PROVIDER_AUTHORITY}"',
    '            android:exported="false"',
    '            android:grantUriPermissions="true">',
    "            <meta-data",
    '                android:name="android.support.FILE_PROVIDER_PATHS"',
    '                android:resource="@xml/update_paths" />',
    "        </provider>",
    "",
]

UPDATE_PATHS_XML = """<?xml version="1.0" encoding="utf-8"?>
<!-- Paths the update FileProvider may share. Only the app's own cache is
     exposed: the installer has to read the APK and nothing else. -->
<paths>
    <cache-path name="updates" path="updates/" />
    <external-cache-path name="external_updates" path="updates/" />
</paths>
"""

JAVA_SOURCE = """package app.mellow;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;

import androidx.core.content.FileProvider;

import java.io.File;

import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/**
 * Java side of the {@code app.mellow/apk_installer} channel.
 *
 * <p>Registered from {@code MainActivity}, because it needs the current
 * activity: the channel is not a Flutter plugin, so it does not need a plugin
 * registration entry or a dependency of its own.
 *
 * <p>It cannot install anything silently. Android always shows its own
 * confirmation screen, and from Android 8 the user must first allow this app to
 * install unknown apps - that is the {@code permissionRequired} answer the Dart
 * side turns into a readable hint with a button to the right settings screen.
 */
public final class ApkInstallerPlugin implements MethodChannel.MethodCallHandler {

    public static final String CHANNEL = "app.mellow/apk_installer";

    private final Activity activity;

    public ApkInstallerPlugin(Activity activity) {
        this.activity = activity;
    }

    @Override
    public void onMethodCall(MethodCall call, MethodChannel.Result result) {
        if ("installApk".equals(call.method)) {
            installApk(
                    (String) call.argument("path"),
                    (String) call.argument("authority"),
                    result);
        } else if ("openInstallSettings".equals(call.method)) {
            openInstallSettings(result);
        } else {
            result.notImplemented();
        }
    }

    private void installApk(String path, String authority, MethodChannel.Result result) {
        if (path == null || authority == null) {
            result.success("missingFile");
            return;
        }
        File file = new File(path);
        if (!file.exists()) {
            result.success("missingFile");
            return;
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                && !activity.getPackageManager().canRequestPackageInstalls()) {
            result.success("permissionRequired");
            return;
        }
        try {
            Uri uri = FileProvider.getUriForFile(activity, authority, file);
            Intent intent = new Intent(Intent.ACTION_VIEW);
            intent.setDataAndType(uri, "application/vnd.android.package-archive");
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            activity.startActivity(intent);
            result.success("opened");
        } catch (Exception error) {
            result.success("failed");
        }
    }

    private void openInstallSettings(MethodChannel.Result result) {
        try {
            Intent intent;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                intent = new Intent(
                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:" + activity.getPackageName()));
            } else {
                intent = new Intent(Settings.ACTION_SECURITY_SETTINGS);
            }
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            activity.startActivity(intent);
            result.success(null);
        } catch (Exception error) {
            result.error("settingsUnavailable", error.getMessage(), null);
        }
    }
}
"""

BUILD_GRADLE_KTS = pathlib.Path("android/app/build.gradle.kts")
BUILD_GRADLE = pathlib.Path("android/app/build.gradle")

QUERIES_LINES = [
    "    <!-- url_launcher: the OAuth consent page opens in the system browser. -->",
    "    <queries>",
    "        <intent>",
    '            <action android:name="android.intent.action.VIEW" />',
    '            <data android:scheme="https" />',
    "        </intent>",
    "    </queries>",
    "",
]


def patch_manifest(scheme: str) -> list[str]:
    """Line-based so different `flutter create` templates all get patched."""
    if not MANIFEST.exists():
        sys.exit(f"✗ {MANIFEST} not found — run this after `flutter create`")

    lines = MANIFEST.read_text(encoding="utf-8").splitlines()
    changes: list[str] = []

    # 0. Install permission, as the outermost child of <manifest>.
    #    Without it Android silently refuses the install and the user sees
    #    "nothing happens" after tapping «Установить».
    if "android.permission.REQUEST_INSTALL_PACKAGES" not in "\n".join(lines):
        for index, line in enumerate(lines):
            if line.lstrip().startswith("<application"):
                lines.insert(
                    index,
                    '    <!-- In-app updates: hand a downloaded APK to the installer. -->',
                )
                lines.insert(
                    index + 1,
                    '    <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />',
                )
                changes.append("REQUEST_INSTALL_PACKAGES")
                break

    # 1. <queries> right before <application>.
    if not any("<queries>" in line for line in lines):
        for index, line in enumerate(lines):
            if line.lstrip().startswith("<application"):
                lines[index:index] = QUERIES_LINES
                changes.append("<queries> for the browser")
                break

    # 2. allowBackup="false" on the <application> element.
    if not any('android:allowBackup="false"' in line for line in lines):
        for index, line in enumerate(lines):
            stripped = line.lstrip()
            if stripped.startswith("<application"):
                indent = line[: len(line) - len(stripped)]
                rest = stripped[len("<application") :]
                lines[index] = f'{indent}<application android:allowBackup="false"{rest}'
                changes.append("allowBackup=false")
                break

    # 3. Deep-linking metadata inside the MainActivity element.
    if not any("flutter_deeplinking_enabled" in line for line in lines):
        for index, line in enumerate(lines):
            if "<activity" not in line:
                continue
            # The activity tag spans several lines: insert after its closing `>`.
            end = index
            while end < len(lines) and not lines[end].rstrip().endswith(">"):
                end += 1
            indent = line[: len(line) - len(line.lstrip())] + "    "
            lines.insert(
                end + 1,
                f'{indent}<meta-data android:name="flutter_deeplinking_enabled" '
                'android:value="false" />',
            )
            changes.append("flutter_deeplinking_enabled=false")
            break

    # 4. Intent filter for the OAuth redirect scheme, inside the activity.
    already = any(f'android:scheme="{scheme}"' in line for line in lines)
    if not already:
        closing = None
        for index, line in enumerate(lines):
            if line.strip() == "</activity>":
                closing = index
                break
        if closing is None:
            sys.exit("✗ could not find </activity> in AndroidManifest.xml")

        indent = "            "
        lines[closing:closing] = [
            f"{indent}<!-- OAuth redirect: {scheme}:/oauth2redirect -->",
            f"{indent}<intent-filter>",
            f'{indent}    <action android:name="android.intent.action.VIEW" />',
            f'{indent}    <category android:name="android.intent.category.DEFAULT" />',
            f'{indent}    <category android:name="android.intent.category.BROWSABLE" />',
            f'{indent}    <data android:scheme="{scheme}" />',
            f"{indent}</intent-filter>",
        ]
        changes.append(f"intent-filter for {scheme}")

    if changes:
        MANIFEST.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return changes


def patch_provider() -> list[str]:
    """Declares the update FileProvider inside <application>."""
    lines = MANIFEST.read_text(encoding="utf-8").splitlines()
    if FILE_PROVIDER_AUTHORITY in "\n".join(lines):
        return []

    for index, line in enumerate(lines):
        if "<application" not in line:
            continue
        # The opening tag can span several lines: `<application` followed by
        # android:label=… on its own lines. Inserting right after the first one
        # would land inside the tag and break the manifest, so walk to the line
        # that closes it.
        insert_at = index + 1
        while insert_at < len(lines) and ">" not in lines[insert_at - 1]:
            insert_at += 1
        lines[insert_at:insert_at] = PROVIDER_LINES
        MANIFEST.write_text("\n".join(lines) + "\n", encoding="utf-8")
        return ["FileProvider for update APKs"]
    return []


def write_update_paths() -> list[str]:
    """Writes the FileProvider path map; only the update cache is shared."""
    if UPDATE_PATHS.exists() and UPDATE_PATHS.read_text(encoding="utf-8") == UPDATE_PATHS_XML:
        return []
    UPDATE_PATHS.parent.mkdir(parents=True, exist_ok=True)
    UPDATE_PATHS.write_text(UPDATE_PATHS_XML, encoding="utf-8")
    return ["res/xml/update_paths.xml"]


def write_java_plugin() -> list[str]:
    """Writes the installer channel implementation."""
    if JAVA_PLUGIN.exists() and JAVA_PLUGIN.read_text(encoding="utf-8") == JAVA_SOURCE:
        return []
    JAVA_PLUGIN.parent.mkdir(parents=True, exist_ok=True)
    JAVA_PLUGIN.write_text(JAVA_SOURCE, encoding="utf-8")
    return ["ApkInstallerPlugin.java"]


def patch_main_activity() -> list[str]:
    """Registers the installer channel on the Flutter engine."""
    if not MAIN_ACTIVITY.exists():
        return []

    text = MAIN_ACTIVITY.read_text(encoding="utf-8")
    if "ApkInstallerPlugin" in text:
        return []

    original = text
    imports = [
        "import app.mellow.ApkInstallerPlugin",
        "import io.flutter.embedding.engine.FlutterEngine",
        "import io.flutter.plugin.common.MethodChannel",
    ]
    for line in imports:
        if line not in text:
            text = text.replace(
                "import io.flutter.embedding.android.FlutterActivity",
                "import io.flutter.embedding.android.FlutterActivity\n" + line,
                1,
            )

    override = (
        "\n    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {\n"
        "        super.configureFlutterEngine(flutterEngine)\n"
        "        MethodChannel(\n"
        "            flutterEngine.dartExecutor.binaryMessenger,\n"
        "            ApkInstallerPlugin.CHANNEL,\n"
        "        ).setMethodCallHandler(ApkInstallerPlugin(this))\n"
        "    }\n"
    )
    marker = "class MainActivity : FlutterActivity() {"
    if marker in text:
        text = text.replace(marker, marker + override, 1)
    else:
        text = text + override

    if text == original:
        return []
    MAIN_ACTIVITY.write_text(text, encoding="utf-8")
    return ["MainActivity registers the installer channel"]


def patch_gradle() -> list[str]:
    """Raises minSdk to 23 in either the Kotlin or the Groovy DSL."""
    for path in (BUILD_GRADLE_KTS, BUILD_GRADLE):
        if not path.exists():
            continue
        text = path.read_text(encoding="utf-8")
        original = text

        if re.search(r"minSdkVersion\s+23\b", text) or re.search(r"minSdk\s*=\s*23\b", text):
            return []
        if re.search(r"minSdk\s*=\s*flutter\.minSdkVersion", text):
            text = re.sub(r"minSdk\s*=\s*flutter\.minSdkVersion", "minSdk = 23", text)
        elif re.search(r"minSdkVersion\s+flutter\.minSdkVersion", text):
            text = re.sub(
                r"minSdkVersion\s+flutter\.minSdkVersion", "minSdkVersion 23", text
            )
        else:
            return []

        if text != original:
            path.write_text(text, encoding="utf-8")
            return [f"minSdk 23 in {path.name}"]
    return []


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--scheme",
        default="app.mellow",
        help="OAuth redirect scheme (reversed Google client id)",
    )
    args = parser.parse_args()

    changes = patch_manifest(args.scheme)
    changes += patch_provider()
    changes += write_update_paths()
    changes += write_java_plugin()
    changes += patch_main_activity()
    changes += patch_gradle()

    if changes:
        for change in changes:
            print(f"▸ android: {change}")
    else:
        print("▸ android: already prepared")


if __name__ == "__main__":
    main()
