"""Write protocol/vectors/keys/ and protocol/vectors/crypto/ (spec 4 and 13).

Everything here is deterministic: the test keys are derived from fixed
strings and the signatures use RFC 6979, so running this again must leave
`git diff` empty. The keys are public test keys; they are never used outside
tests.

Run: .venv/bin/python tools/make_crypto_vectors.py
"""

from __future__ import annotations

import base64
import hashlib
import json
from pathlib import Path
from urllib.parse import quote

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec

ROOT = Path(__file__).resolve().parent.parent / "protocol" / "vectors"
CURVE_ORDER = int("FFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551", 16)

PAIR_CONTEXT = b"tabber-remote pair v1\x00"
AUTH_CONTEXT = b"tabber-remote auth v1\x00"
CODE_CONTEXT = b"tabber-remote code v1\x00"

HOST_ID = "8c1f2e47-5a93-4d0b-9e26-7f3a1c4b5d60"
HOST_NAME = "Studio Mac"
ROUTES = ["studio-mac.local:9474", "192.168.1.20:9474", "[fd12:3456:789a::20]:9474"]


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def sha256(data: bytes) -> bytes:
    return hashlib.sha256(data).digest()


def test_key(label: str) -> ec.EllipticCurvePrivateKey:
    scalar = int.from_bytes(sha256(label.encode()), "big") % (CURVE_ORDER - 1) + 1
    return ec.derive_private_key(scalar, ec.SECP256R1())


def spki_der(key: ec.EllipticCurvePrivateKey) -> bytes:
    return key.public_key().public_bytes(
        serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo)


def sign(key: ec.EllipticCurvePrivateKey, message: bytes) -> bytes:
    return key.sign(message, ec.ECDSA(hashes.SHA256(), deterministic_signing=True))


def pairing_code(pin_raw: bytes, device_id_raw: bytes, challenge: bytes) -> str:
    digest = sha256(CODE_CONTEXT + pin_raw + device_id_raw + challenge)
    return f"{int.from_bytes(digest[:4], 'big') % 1_000_000:06d}"


def write(rel: str, payload) -> None:
    path = ROOT / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    if isinstance(payload, bytes):
        path.write_bytes(payload)
    else:
        path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n")


def main() -> None:
    host = test_key("tabber-remote test host key v1")
    device = test_key("tabber-remote test device key v1")
    other = test_key("tabber-remote test other device key v1")
    for name, key in (("host", host), ("device", device), ("other_device", other)):
        write(f"keys/{name}_test_key.pem", key.private_bytes(
            serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
            serialization.NoEncryption()))

    host_spki = spki_der(host)
    pin_raw = sha256(host_spki)
    device_spki = spki_der(device)
    device_id_raw = sha256(device_spki)
    other_spki = spki_der(other)
    challenge = sha256(b"tabber-remote test challenge 1")
    challenge_2 = sha256(b"tabber-remote test challenge 2")
    token = sha256(b"tabber-remote test token 1")[:16]

    write("crypto/identity.json", {
        "description": "Pins and device ids (spec 4.1). The validator recomputes every derived field.",
        "host": {
            "key_file": "keys/host_test_key.pem",
            "spki_der_b64url": b64url(host_spki),
            "pin": b64url(pin_raw),
            "id": HOST_ID,
            "name": HOST_NAME,
        },
        "device": {
            "key_file": "keys/device_test_key.pem",
            "spki_der_b64url": b64url(device_spki),
            "key": b64url(device_spki),
            "device_id": b64url(device_id_raw),
        },
        "other_device": {
            "key_file": "keys/other_device_test_key.pem",
            "spki_der_b64url": b64url(other_spki),
            "device_id": b64url(sha256(other_spki)),
        },
        "challenge": b64url(challenge),
        "challenge_2": b64url(challenge_2),
        "token": b64url(token),
    })

    cases = []
    for name, context, extra, key, key_spki, ch in (
        ("pair_token", PAIR_CONTEXT, token, device, device_spki, challenge),
        ("pair_code", PAIR_CONTEXT, b"", device, device_spki, challenge),
        ("auth", AUTH_CONTEXT, b"", device, device_spki, challenge),
        ("auth_second_challenge", AUTH_CONTEXT, b"", device, device_spki, challenge_2),
    ):
        message = context + pin_raw + ch + extra
        cases.append({
            "name": name,
            "context": context[:-1].decode(),
            "challenge": b64url(ch),
            "token": b64url(extra) if extra else None,
            "signed_bytes_hex": message.hex(),
            "device_key": b64url(key_spki),
            "signature": b64url(sign(key, message)),
            "verifies": True,
        })
    good = cases[0]
    message = bytes.fromhex(good["signed_bytes_hex"])
    cases.append({**good, "name": "pair_token_signed_by_another_key",
                  "signature": b64url(sign(other, message)), "verifies": False})
    flipped = bytearray(message)
    flipped[len(PAIR_CONTEXT)] ^= 0x01
    cases.append({**good, "name": "pair_token_for_another_host",
                  "signed_bytes_hex": bytes(flipped).hex(),
                  "note": "The signature over the real host's bytes does not verify for these bytes.",
                  "verifies": False})
    write("crypto/signatures.json", {
        "description": ("Signed bytes are context || 0x00 || pin hash || challenge || token "
                        "(spec 4.3 to 4.5). ECDSA P-256 SHA-256, DER, b64url. These signatures "
                        "use RFC 6979; a Secure Enclave signs randomly, and both verify."),
        "host_pin": b64url(pin_raw),
        "cases": cases,
    })

    write("crypto/pairing_code.json", {
        "description": "The 6-digit code both screens show (spec 4.4).",
        "cases": [
            {"host_pin": b64url(pin_raw), "device_id": b64url(device_id_raw),
             "challenge": b64url(ch), "code": pairing_code(pin_raw, device_id_raw, ch)}
            for ch in (challenge, challenge_2)
        ],
    })

    params = [("v", "1"), ("id", HOST_ID), ("name", HOST_NAME), ("spki", b64url(pin_raw)),
              ("tok", b64url(token)), ("hosts", ",".join(ROUTES))]
    link = "tabber-remote://pair?" + "&".join(f"{k}={quote(v, safe='')}" for k, v in params)
    write("crypto/qr_link.json", {
        "description": "The pairing link in the QR code (spec 4.2). Values are percent-encoded.",
        "link": link,
        "fields": {k: v for k, v in params},
        "routes": ROUTES,
    })


if __name__ == "__main__":
    main()
