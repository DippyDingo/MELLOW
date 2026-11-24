#!/usr/bin/env bash
# Creates the stable signing key the update channel needs, and (optionally)
# stores it in the repository secrets.
#
# Why this exists: Android refuses to install an APK over another one unless
# both are signed with the same key. CI runners are fresh machines, so their
# default debug key is different every run — an update built that way cannot be
# installed over the previous build. One key, generated once, solves it.
#
# Requires: openssl, and `gh` already authenticated if you want the secret set.
#
#   tool/platform/make_signing_key.sh                 # write the key locally
#   tool/platform/make_signing_key.sh --set-secret    # and store it in GitHub
#   tool/platform/make_signing_key.sh --print-base64  # print it for the web UI
#
# `--print-base64` exists for people without a terminal: it writes the key files
# and prints one long line, which is pasted into the GitHub settings page
# (Settings → Secrets and variables → Actions → New repository secret).
#
# The key is a Debug signing key: 2048-bit RSA, PKCS#8 DER, SHA-256 with the
# JDK's default alias and password (`androiddebugkey` / `android`). That is
# exactly what the Android Gradle plugin expects to find at
# ~/.android/debug.keystore, so no Gradle configuration is involved.
set -euo pipefail

set_secret=0
fingerprint_only=0
print_base64=0
for arg in "$@"; do
  case "$arg" in
    --set-secret) set_secret=1 ;;
    --print-base64) print_base64=1 ;;
    --fingerprint) fingerprint_only=1 ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

command -v openssl >/dev/null || { echo "openssl is required" >&2; exit 1; }

out_dir="${MELLOW_KEY_DIR:-$PWD/build/signing}"
mkdir -p "$out_dir"
key_der="$out_dir/debug.keystore"
key_pem="$out_dir/debug.keystore.pem"

if [ "$fingerprint_only" -eq 1 ]; then
  # Prints one line, `SHA-256 <hex>`, so CI can compare builds without
  # reading the key itself.
  openssl dgst -sha256 "$key_der" | awk '{print "SHA-256 " $2}'
  exit 0
fi

if [ -f "$key_der" ]; then
  echo "▸ keeping the existing key at $key_der"
else
  openssl genrsa -out "$key_pem" 2048 2>/dev/null
  openssl pkcs8 -topk8 -nocrypt -in "$key_pem" -outform DER -out "$key_der"
  chmod 600 "$key_der" "$key_pem"
  echo "▸ generated $key_der"
fi

echo "▸ fingerprint:"
openssl dgst -sha256 "$key_der" | awk '{print "  SHA-256 " $2}'
echo "  Every build must report the same fingerprint, or updates cannot install"
echo "  over each other."

if [ "$print_base64" -eq 1 ]; then
  echo
  echo "▸ MELLOW_DEBUG_KEYSTORE_B64 — paste this whole line as the secret value:"
  echo
  base64 < "$key_der" | tr -d '\n'
  echo
  echo
  echo "▸ Name the secret exactly MELLOW_DEBUG_KEYSTORE_B64"
  echo "  Settings → Secrets and variables → Actions → New repository secret"
  exit 0
fi

if [ "$set_secret" -eq 1 ]; then
  command -v gh >/dev/null || { echo "gh is required for --set-secret" >&2; exit 1; }
  repo="${MELLOW_REPO:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"
  base64 < "$key_der" | tr -d '\n' | gh secret set MELLOW_DEBUG_KEYSTORE_B64 --repo "$repo"
  echo "▸ secret MELLOW_DEBUG_KEYSTORE_B64 is set for $repo"
  echo "  Re-run the APK workflow: the next build will be signed with this key."
else
  echo "▸ to store it in the repository secrets, run with --set-secret"
  echo "  (or: base64 < $key_der | tr -d '\\n' | gh secret set MELLOW_DEBUG_KEYSTORE_B64)"
fi

echo "▸ keep $key_pem private and backed up: losing it means users must"
echo "  uninstall Mellow to install a new build, and local mail is lost."
