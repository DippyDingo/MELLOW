#!/usr/bin/env bash
# Creates the stable signing key the update channel needs, and (optionally)
# stores it in the repository secrets.
#
# Why this exists: Android refuses to install an APK over another one unless
# both are signed with the same key. CI runners are fresh machines, so their
# default debug key is different every run — an update built that way cannot be
# installed over the previous build. One key, generated once, solves it.
#
# Requires: `keytool` (a JDK) OR python3 with pyjks+cryptography.
#
#   tool/platform/make_signing_key.sh                 # write the key locally
#   tool/platform/make_signing_key.sh --set-secret    # and store it in GitHub
#   tool/platform/make_signing_key.sh --print-base64  # print it for the web UI
#
# `--print-base64` exists for people without a terminal of their own: it writes
# the key files and prints one long line, which is pasted into the GitHub
# settings page (Settings → Secrets and variables → Actions → New repository
# secret).
#
# The result is an Android debug keystore: JKS, alias `androiddebugkey`,
# store and key password `android`. That is exactly what the Android Gradle
# plugin opens at ~/.android/debug.keystore, so no Gradle configuration is
# involved. A raw PKCS#8 key is NOT a keystore and would be silently ignored.
set -euo pipefail

set_secret=0
fingerprint_only=0
print_base64=0
for arg in "$@"; do
  case "$arg" in
    --set-secret) set_secret=1 ;;
    --print-base64) print_base64=1 ;;
    --fingerprint) fingerprint_only=1 ;;
    -h|--help) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

out_dir="${MELLOW_KEY_DIR:-$PWD/build/signing}"
key_store="$out_dir/debug.keystore"
key_pem="$out_dir/debug.keystore.pem"
fingerprint_file="$out_dir/fingerprint.txt"
alias_name="androiddebugkey"
password="android"

mkdir -p "$out_dir"

# Fingerprint of the certificate inside a JKS, without keytool: the file layout
# is not trivial, so ask python when it is available, else fall back to a hash
# of the whole file (stable and comparable, just not the X.509 fingerprint).
cert_fingerprint() {
  if [ -f "$fingerprint_file" ]; then
    # Written by the python generator: a real X.509 fingerprint.
    awk '{print $2}' "$fingerprint_file"
    return 0
  fi
  # No dependencies: reads the certificate straight out of the JKS container.
  if finger="$(python3 "$(dirname "$0")/jks_fingerprint.py" "$key_store" 2>/dev/null)"; then
    printf '%s\n' "$finger" | awk '/^SHA-256/{gsub(/:/,""); print tolower($2)}'
    return 0
  fi
  if "${MELLOW_PYTHON:-python3}" - "$key_store" "$password" "$alias_name" <<'PY' 2>/dev/null
import sys
import jks
from cryptography import x509
from cryptography.hazmat.primitives import hashes
try:
    store = jks.KeyStore.load(sys.argv[1], sys.argv[2])
    entry = store.private_keys[sys.argv[3]]
    cert = x509.load_der_x509_certificate(entry.cert_chain[0][1])
    print(cert.fingerprint(hashes.SHA256()).hex())
except Exception:
    sys.exit(1)
PY
  then
    return 0
  fi
  if command -v keytool >/dev/null; then
    keytool -list -v -keystore "$key_store" -storepass "$password" 2>/dev/null \
      | awk -F': ' '/SHA256:/{gsub(/:/,"",$2); print tolower($2); exit}'
    return 0
  fi
  if command -v openssl >/dev/null; then
    # Not the X.509 fingerprint, but a stable identity for the file.
    openssl dgst -sha256 "$key_store" | awk '{print "file:" $2}'
    return 0
  fi
  echo "unknown"
}

if [ "$fingerprint_only" -eq 1 ]; then
  echo "SHA-256 $(cert_fingerprint)"
  exit 0
fi

if [ -f "$key_store" ]; then
  echo "▸ keeping the existing key at $key_store"
else
  if command -v keytool >/dev/null; then
    keytool -genkeypair -v \
      -keystore "$key_store" \
      -storetype JKS \
      -storepass "$password" \
      -keypass "$password" \
      -alias "$alias_name" \
      -keyalg RSA \
      -keysize 2048 \
      -validity 10950 \
      -dname "CN=Android Debug,O=Android,C=US" >/dev/null
    echo "▸ generated $key_store (keytool)"
    keytool -exportcert -rfc -keystore "$key_store" -storepass "$password" \
      -alias "$alias_name" > "$key_pem" 2>/dev/null
  else
    echo "▸ keytool not found, using the python generator"
    # A virtualenv with pyjks is enough and avoids touching system packages.
    python_bin="${MELLOW_PYTHON:-python3}"
    if ! "$python_bin" -c "import jks" >/dev/null 2>&1; then
      echo "✗ keytool (a JDK) is missing and so is pyjks." >&2
      echo "  Install a JDK (recommended, then this uses keytool), or run:" >&2
      echo "    python3 -m venv .venv && .venv/bin/pip install pyjks" >&2
      echo "    MELLOW_PYTHON=.venv/bin/python tool/platform/make_signing_key.sh" >&2
      exit 1
    fi
    "$python_bin" "$(dirname "$0")/make_debug_keystore.py" --out-dir "$out_dir"
  fi
fi

cert_sha="$(cert_fingerprint)"
if [ ! -f "$fingerprint_file" ]; then
  printf 'SHA-256 %s\n' "$cert_sha" > "$fingerprint_file"
fi

echo "▸ certificate fingerprint:"
if [ -f "$key_store" ] && python3 "$(dirname "$0")/jks_fingerprint.py" "$key_store" >/dev/null 2>&1; then
  python3 "$(dirname "$0")/jks_fingerprint.py" "$key_store" \
    | sed 's/^SHA-1   /  SHA-1   /; s/^SHA-256 /  SHA-256 /'
  echo "  The SHA-1 is what a Google Cloud OAuth client asks for."
else
  echo "  SHA-256 ${cert_sha}"
fi
echo "  Every build must report the same value, or updates cannot install over"
echo "  each other."

if [ "$print_base64" -eq 1 ]; then
  echo
  echo "▸ MELLOW_DEBUG_KEYSTORE_B64 — paste this whole line as the secret value:"
  echo
  base64 < "$key_store" | tr -d '\n'
  echo
  echo
  echo "▸ Name the secret exactly MELLOW_DEBUG_KEYSTORE_B64"
  echo "  Settings → Secrets and variables → Actions → New repository secret"
  exit 0
fi

if [ "$set_secret" -eq 1 ]; then
  command -v gh >/dev/null || { echo "gh is required for --set-secret" >&2; exit 1; }
  repo="${MELLOW_REPO:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"
  base64 < "$key_store" | tr -d '\n' | gh secret set MELLOW_DEBUG_KEYSTORE_B64 --repo "$repo"
  echo "▸ secret MELLOW_DEBUG_KEYSTORE_B64 is set for $repo"
  echo "  Re-run the APK workflow: the next build will be signed with this key."
  exit 0
fi

echo "▸ to store it in the repository secrets, run with --set-secret"
echo "  (or: tool/platform/make_signing_key.sh --print-base64)"
echo
echo "▸ keep $out_dir/debug.keystore.pem private and backed up: losing the key"
echo "  means users must uninstall Mellow to install a new build, and local"
echo "  mail is lost with it."
