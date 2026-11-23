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
    changes += patch_gradle()

    if changes:
        for change in changes:
            print(f"▸ android: {change}")
    else:
        print("▸ android: already prepared")


if __name__ == "__main__":
    main()
