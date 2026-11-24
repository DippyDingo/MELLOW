#!/usr/bin/env python3
"""Prints the SHA-1 and SHA-256 fingerprints of the key in a JKS keystore.

Dependency-free: Java keystores are a simple container, so the certificate can
be read without `keytool`, `pyjks` or a JDK. Used by `make_signing_key.sh` as a
fallback, and by anyone who needs the fingerprint for a Google Cloud OAuth
client without installing a Java runtime.

    python3 tool/platform/jks_fingerprint.py build/signing/debug.keystore
"""

from __future__ import annotations

import hashlib
import struct
import sys
from pathlib import Path

MAGIC = 0xFEEDFEED


class JksError(Exception):
    """The file is not a JKS keystore we can read."""


def _read_utf(data: bytes, offset: int) -> tuple[str, int]:
    """JKS stores strings as a big-endian uint16 length, then modified UTF-8."""
    (length,) = struct.unpack_from(">H", data, offset)
    offset += 2
    return data[offset : offset + length].decode("utf-8", "replace"), offset + length


def first_certificate(data: bytes) -> bytes:
    """Returns the DER bytes of the first certificate in the store."""
    if len(data) < 12:
        raise JksError("file is too short to be a keystore")
    (magic,) = struct.unpack_from(">I", data, 0)
    if magic != MAGIC:
        raise JksError(
            "not a JKS keystore (PKCS#12 starts with 0x30; this needs JKS)"
        )
    _version, count = struct.unpack_from(">II", data, 4)
    offset = 12

    for _ in range(count):
        (tag,) = struct.unpack_from(">I", data, offset)
        offset += 4
        if tag == 1:  # private key entry
            _, offset = _read_utf(data, offset)  # alias
            offset += 8  # timestamp
            (key_length,) = struct.unpack_from(">I", data, offset)
            offset += 4 + key_length
            (chain_length,) = struct.unpack_from(">I", data, offset)
            offset += 4
            for _ in range(chain_length):
                if data[offset : offset + 2] == b"\x30\x82":
                    # Keys/certs are written with their own length prefix.
                    pass
                (cert_type, offset) = _read_utf(data, offset)
                (cert_length,) = struct.unpack_from(">I", data, offset)
                offset += 4
                cert = data[offset : offset + cert_length]
                offset += cert_length
                if cert_type.upper() in {"X.509", "X509"}:
                    return cert
            raise JksError("private key entry has no X.509 certificate")
        if tag == 2:  # trusted certificate entry
            _, offset = _read_utf(data, offset)  # alias
            offset += 8  # timestamp
            (cert_type, offset) = _read_utf(data, offset)
            (cert_length,) = struct.unpack_from(">I", data, offset)
            offset += 4
            cert = data[offset : offset + cert_length]
            offset += cert_length
            if cert_type.upper() in {"X.509", "X509"}:
                return cert
            continue
        raise JksError(f"unknown entry type {tag}")

    raise JksError("the keystore holds no certificate")


def format_fingerprint(digest: bytes) -> str:
    return ":".join(f"{byte:02X}" for byte in digest)


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    path = Path(argv[1])
    try:
        cert = first_certificate(path.read_bytes())
    except (OSError, JksError, struct.error) as error:
        print(f"✗ {path}: {error}", file=sys.stderr)
        return 1

    print(f"SHA-1   {format_fingerprint(hashlib.sha1(cert).digest())}")
    print(f"SHA-256 {format_fingerprint(hashlib.sha256(cert).digest())}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
