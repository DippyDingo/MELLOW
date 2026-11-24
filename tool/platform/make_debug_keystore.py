#!/usr/bin/env python3
"""Creates an Android debug keystore (JKS) without a JDK, for CI signing.

Why not just `openssl genrsa`: a bare PKCS#8/DER key is **not** a Java
keystore. The Android Gradle plugin opens `~/.android/debug.keystore` with
`keytool`-compatible semantics (alias + store password), so a raw key file makes
the build fall back to the runner's own throwaway key without any error — the
exact failure that makes updates impossible to install over each other.

This produces a real JKS with:

    alias       androiddebugkey
    storepass   android
    keypass     android

which is what AGP looks for by default. Requires `pyjks` and `cryptography`:

    pip install pyjks pycryptodomex cryptography

Prefer `tool/platform/make_signing_key.sh`, which uses `keytool` when a JDK is
present and falls back to this script.
"""

from __future__ import annotations

import argparse
import datetime
import hashlib
import os
import sys
from pathlib import Path

ALIAS = "androiddebugkey"
PASSWORD = "android"  # noqa: S105 - fixed password of the Android debug keystore
VALIDITY_YEARS = 30


def build(out_dir: Path) -> Path:
    try:
        import jks
        from cryptography import x509
        from cryptography.hazmat.primitives import hashes, serialization
        from cryptography.hazmat.primitives.asymmetric import rsa
        from cryptography.x509.oid import NameOID
    except ImportError as error:  # pragma: no cover - environment problem
        sys.exit(
            f"✗ {error.name} is missing. Run: pip install pyjks pycryptodomex cryptography"
        )

    out_dir.mkdir(parents=True, exist_ok=True)
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    subject = issuer = x509.Name(
        [
            x509.NameAttribute(NameOID.COMMON_NAME, "Android Debug"),
            x509.NameAttribute(NameOID.ORGANIZATION_NAME, "Android"),
            x509.NameAttribute(NameOID.COUNTRY_NAME, "US"),
        ]
    )
    now = datetime.datetime.now(datetime.timezone.utc)
    certificate = (
        x509.CertificateBuilder()
        .subject_name(subject)
        .issuer_name(issuer)
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - datetime.timedelta(days=1))
        .not_valid_after(now + datetime.timedelta(days=365 * VALIDITY_YEARS))
        .add_extension(
            x509.BasicConstraints(ca=True, path_length=None),
            critical=True,
        )
        .sign(key, hashes.SHA256())
    )

    key_der = key.private_bytes(
        encoding=serialization.Encoding.DER,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )
    cert_der = certificate.public_bytes(serialization.Encoding.DER)

    entry = jks.PrivateKeyEntry.new(ALIAS, [cert_der], key_der, "rsa_raw")
    store = jks.KeyStore.new("jks", [entry])
    keystore = out_dir / "debug.keystore"
    store.save(str(keystore), PASSWORD)

    # Read back immediately: a keystore that cannot be reopened only shows up
    # as a broken build much later.
    check = jks.KeyStore.load(str(keystore), PASSWORD)
    if ALIAS not in check.private_keys:
        sys.exit("✗ the keystore was written but the alias cannot be read back")

    (out_dir / "debug.keystore.pem").write_bytes(
        key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.TraditionalOpenSSL,
            encryption_algorithm=serialization.NoEncryption(),
        )
    )

    fingerprint = certificate.fingerprint(hashes.SHA256()).hex()
    (out_dir / "fingerprint.txt").write_text(
        f"SHA-256 {fingerprint}\n",
        encoding="utf-8",
    )
    return keystore


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--out-dir",
        default=os.environ.get("MELLOW_KEY_DIR", "build/signing"),
        help="where debug.keystore is written (default: build/signing)",
    )
    args = parser.parse_args()
    keystore = build(Path(args.out_dir))
    digest = hashlib.sha256(keystore.read_bytes()).hexdigest()
    print(f"▸ keystore : {keystore} ({keystore.stat().st_size} bytes)")
    print(f"▸ alias    : {ALIAS}")
    print(f"▸ storepass: {PASSWORD}")
    print(f"▸ file SHA-256: {digest}")


if __name__ == "__main__":
    main()
