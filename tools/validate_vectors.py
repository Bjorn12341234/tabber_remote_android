"""Check the protocol's schemas and vectors (spec 13). Exit status 1 on any failure.

Run: .venv/bin/python tools/validate_vectors.py
"""

from __future__ import annotations

import base64
import hashlib
import json
import sys
from pathlib import Path
from urllib.parse import parse_qsl, quote, urlsplit

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from jsonschema import Draft202012Validator
from referencing import Registry
from referencing.jsonschema import DRAFT202012

PROTOCOL = Path(__file__).resolve().parent.parent / "protocol"
BASE = "https://tabber.studio/schemas/remote/1/"
CONTEXTS = {"pair": b"tabber-remote pair v1\x00", "auth": b"tabber-remote auth v1\x00"}
CODE_CONTEXT = b"tabber-remote code v1\x00"
PRE_AUTH = {"hello", "pair", "auth"}
REFUSED_BEFORE_RUN = {"unauthenticated", "rate_limited", "busy", "invalid_params", "method_not_found",
                      "parse_error", "invalid_request"}
CLOSE_CODES = {1000, 1003, 1006, 1008, 1009, 4000, 4001, 4002, 4003, 4004}


def unb64(text: str) -> bytes:
    return base64.urlsafe_b64decode(text + "=" * (-len(text) % 4))


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def sha256(data: bytes) -> bytes:
    return hashlib.sha256(data).digest()


def verifies(spki_b64: str, signature_b64: str, message: bytes) -> bool:
    try:
        key = serialization.load_der_public_key(unb64(spki_b64))
        if not isinstance(key, ec.EllipticCurvePublicKey) or key.curve.name != "secp256r1":
            return False
        key.verify(unb64(signature_b64), message, ec.ECDSA(hashes.SHA256()))
        return True
    except (InvalidSignature, ValueError):
        return False


class Checker:
    def __init__(self) -> None:
        self.failures: list[str] = []
        resources = []
        self.schema_count = 0
        for path in sorted((PROTOCOL / "schemas").rglob("*.json")):
            data = json.loads(path.read_text())
            rel = path.relative_to(PROTOCOL / "schemas").as_posix()
            if data.get("$id") != BASE + rel:
                self.fail(f"schemas/{rel}", f"$id should be {BASE + rel}")
            resources.append((BASE + rel, DRAFT202012.create_resource(data)))
            if rel != "errors.json":
                try:
                    Draft202012Validator.check_schema(data)
                    self.schema_count += 1
                except Exception as exc:  # noqa: BLE001 - report any schema error
                    self.fail(f"schemas/{rel}", f"not a valid schema: {exc}")
        self.registry = Registry().with_resources(resources)
        self.methods = {p.stem: json.loads(p.read_text())
                        for p in (PROTOCOL / "schemas" / "methods").glob("*.json")}
        self.topics = {p.stem for p in (PROTOCOL / "schemas" / "topics").glob("*.json")}
        table = json.loads((PROTOCOL / "schemas" / "errors.json").read_text())
        self.errors = {e["reason"]: e for e in table["errors"]}
        self.error_codes = {e["code"]: e for e in table["errors"]}
        if len(self.error_codes) != len(self.errors):
            self.fail("schemas/errors.json", "codes and reasons must both be unique")
        self.covered = {"methods": set(), "topics": set(), "errors": set()}

    def fail(self, where: str, what: str) -> None:
        self.failures.append(f"{where}: {what}")

    def problems(self, uri: str, instance) -> list[str]:
        validator = Draft202012Validator({"$ref": uri}, registry=self.registry)
        return [f"{'/'.join(map(str, e.absolute_path)) or '(top)'}: {e.message}"
                for e in validator.iter_errors(instance)]

    def check(self, uri: str, instance, where: str) -> bool:
        found = self.problems(uri, instance)
        for problem in found:
            self.fail(where, problem)
        return not found

    # Exchanges

    def exchange(self, path: Path) -> None:
        name = path.relative_to(PROTOCOL).as_posix()
        vector = json.loads(path.read_text())
        for field in ("name", "description", "start", "steps"):
            if field not in vector:
                self.fail(name, f"missing {field}")
                return
        if vector["name"] != path.stem:
            self.fail(name, "name must match the file name")
        state = vector.get("host_state", {})
        devices = {d["device_id"]: d["key"] for d in state.get("paired_devices", [])}
        for device_id, key in devices.items():
            if b64url(sha256(unb64(key))) != device_id:
                self.fail(name, f"paired device {device_id} does not match its key")
        base_seq = 0
        if "snapshot" in state:
            self.check(BASE + "snapshot.json", state["snapshot"], f"{name} host_state.snapshot")
            base_seq = state["snapshot"]["seq"]
        keys: dict[str, tuple[str, str, str]] = {}

        def new_connection(start: str) -> dict:
            return {"authed": start == "authenticated", "pending": {}, "seq": base_seq if start == "authenticated" else 0,
                    "challenge": None, "used": set(), "failures": 0, "closed": False, "raw": None,
                    "caps": set(state.get("capabilities", [])) if start == "authenticated" else set()}

        conn = new_connection(vector["start"])
        for index, step in enumerate(vector["steps"]):
            where = f"{name} step {index}"
            if step.get("reconnect"):
                conn = new_connection("connected")
                base_seq = 0
                continue
            if conn["closed"]:
                self.fail(where, "a step after the connection closed (add a reconnect step)")
                continue
            if conn["failures"] >= 3 and not (step.get("from") == "host" and step.get("close") == 1008):
                self.fail(where, "three failed pair or auth attempts must be followed by a host close 1008")
            sender = step.get("from")
            if "close" in step:
                if step["close"] not in CLOSE_CODES:
                    self.fail(where, f"unknown close code {step['close']}")
                conn["closed"] = True
                conn["pending"].clear()
                continue
            if "raw" in step:
                if sender != "remote":
                    self.fail(where, "only the remote sends raw frames in vectors")
                try:
                    parsed = json.loads(step["raw"])
                except json.JSONDecodeError:
                    conn["raw"] = "parse_error"
                else:
                    if not self.problems(BASE + "envelope.json#/$defs/request", parsed):
                        self.fail(where, "a raw step must be something the host cannot accept")
                    conn["raw"] = "invalid_request"
                continue
            message = step.get("message")
            if not isinstance(message, dict):
                self.fail(where, "a step needs message, raw, close or reconnect")
                continue
            if sender == "remote":
                self.remote_message(message, conn, where)
            elif sender == "host":
                self.host_message(step, message, conn, devices, keys, where)
            else:
                self.fail(where, "from must be remote or host")
        if conn["pending"] and not conn["closed"]:
            self.fail(name, f"requests never answered: {sorted(map(str, conn['pending']))}")
        if conn["failures"] >= 3 and not conn["closed"]:
            self.fail(name, "three failed pair or auth attempts must be followed by a host close 1008")

    def remote_message(self, message: dict, conn: dict, where: str) -> None:
        if "id" not in message:
            if self.check(BASE + "envelope.json#/$defs/notification", message, where):
                if message["method"] != "heartbeat":
                    self.fail(where, "the remote sends only heartbeat notifications")
                else:
                    self.check(BASE + "heartbeat.json#/$defs/remote", message["params"], where)
            return
        if not self.check(BASE + "envelope.json#/$defs/request", message, where):
            return
        if message["id"] in conn["pending"]:
            self.fail(where, f"request id {message['id']} is already in use")
        conn["pending"][message["id"]] = (message["method"], message["params"], conn["authed"])

    def host_message(self, step: dict, message: dict, conn: dict, devices: dict, keys: dict, where: str) -> None:
        if step.get("lost") and "id" not in message:
            self.fail(where, "only an answer can be marked lost")
        if "id" not in message:
            if not self.check(BASE + "envelope.json#/$defs/notification", message, where):
                return
            params = message["params"]
            if message["method"] == "heartbeat":
                if self.check(BASE + "heartbeat.json#/$defs/host", params, where) and params["seq"] < conn["seq"]:
                    self.fail(where, "a heartbeat's seq can never be older than an event already sent")
                return
            if not self.check(BASE + "event.json", params, where):
                return
            if not conn["authed"]:
                self.fail(where, "events before authentication")
            topic = params["topic"]
            self.covered["topics"].add(topic)
            self.check(BASE + f"topics/{topic}.json", params["data"], f"{where} ({topic})")
            if step.get("gap"):
                if params["seq"] <= conn["seq"] + 1:
                    self.fail(where, "marked as a gap, but seq follows on")
            elif params["seq"] != conn["seq"] + 1:
                self.fail(where, f"seq {params['seq']} should be {conn['seq'] + 1}")
            conn["seq"] = params["seq"]
            return

        is_error = "error" in message
        if not self.check(BASE + ("envelope.json#/$defs/error" if is_error else "envelope.json#/$defs/result"),
                          message, where):
            return
        if message["id"] is None:
            if not is_error or conn["raw"] is None:
                self.fail(where, "a null id answers only a frame the host could not read")
            elif message["error"]["data"]["reason"] != conn["raw"]:
                self.fail(where, f"expected {conn['raw']}")
            conn["raw"] = None
            self.error_table(message["error"], where)
            return
        if message["id"] not in conn["pending"]:
            self.fail(where, f"answers id {message['id']}, which no pending request has")
            return
        method, params, authed = conn["pending"].pop(message["id"])
        reason = message["error"]["data"]["reason"] if is_error else None
        if is_error:
            self.error_table(message["error"], where)

        if method not in self.methods:
            if reason != "method_not_found":
                self.fail(where, f"{method} is not a verb: the answer must be method_not_found")
            return
        schema = self.methods[method]
        params_problems = self.problems(BASE + f"methods/{method}.json#/$defs/params", params)
        if reason == "invalid_params":
            if not params_problems:
                self.fail(where, "invalid_params, but the params match the schema")
        else:
            for problem in params_problems:
                self.fail(f"{where} params", problem)
        if not authed and method not in PRE_AUTH and reason != "unauthenticated":
            self.fail(where, f"{method} before authentication must be answered with unauthenticated")
        capability = schema.get("x-capability")
        if authed and capability and reason != "unauthenticated":
            if capability not in conn["caps"] and reason != "not_supported":
                self.fail(where, f"the host lacks {capability}: the answer must be not_supported")
            if reason == "not_supported" and capability in conn["caps"]:
                self.fail(where, f"not_supported, but the host lists {capability}")

        if method in ("pair", "auth"):
            self.check_attempt(method, params, reason, conn, devices, where)
        if not is_error:
            self.covered["methods"].add(method)
            self.check(BASE + f"methods/{method}.json#/$defs/result", message["result"], f"{where} result")
            result = message["result"]
            if method == "hello":
                conn["challenge"], conn["caps"] = result.get("challenge"), set(result.get("capabilities", []))
            elif method in ("pair", "auth"):
                conn["authed"] = True
                if method == "pair":
                    device_key = params["device"]["key"]
                    if result.get("device_id") != b64url(sha256(unb64(device_key))):
                        self.fail(where, "device_id must be b64url(SHA-256(device key))")
                    devices[result.get("device_id")] = device_key
            elif method in ("session.subscribe", "session.snapshot"):
                conn["seq"] = result.get("seq", conn["seq"])

        key = params.get("key") if isinstance(params, dict) else None
        if key and reason not in REFUSED_BEFORE_RUN:
            answer = json.dumps({k: v for k, v in message.items() if k != "id"}, sort_keys=True)
            request = json.dumps(params, sort_keys=True)
            if key in keys:
                first_method, first_request, first_answer = keys[key]
                if (first_method, first_request) != (method, request):
                    self.fail(where, f"key {key} reused for a different request")
                elif first_answer != answer:
                    self.fail(where, f"key {key} answered differently the second time")
            else:
                keys[key] = (method, request, answer)

    def check_attempt(self, method: str, params: dict, reason: str | None, conn: dict, devices: dict, where: str) -> None:
        if reason in ("unauthenticated", "unsupported_version", "invalid_params"):
            return
        challenge = conn["challenge"]
        if challenge is None:
            self.fail(where, f"{method} before any hello challenge")
            return
        if challenge in conn["used"]:
            if reason != "challenge_invalid":
                self.fail(where, "a challenge used twice must be refused with challenge_invalid")
        elif reason == "challenge_invalid":
            self.fail(where, "challenge_invalid, but this challenge was not used before")
        conn["used"].add(challenge)
        if reason is not None:
            conn["failures"] += 1
        if method == "pair":
            device_key = params["device"]["key"]
            token = unb64(params["token"]) if params.get("mode") == "token" else b""
        else:
            device_key = devices.get(params["device_id"])
            if device_key is None:
                if reason != "unknown_device":
                    self.fail(where, "auth from a device the host does not know must get unknown_device")
                return
            if reason == "unknown_device":
                self.fail(where, "unknown_device, but the host knows this device")
            token = b""
        pin_raw = unb64(self.pin)
        message = CONTEXTS[method] + pin_raw + unb64(challenge) + token
        good = verifies(device_key, params["signature"], message)
        if reason == "signature_invalid" and good:
            self.fail(where, "signature_invalid, but the signature verifies")
        if reason not in ("signature_invalid", "challenge_invalid") and not good:
            self.fail(where, "this signature must verify: the host would answer signature_invalid")

    def error_table(self, error: dict, where: str) -> None:
        entry = self.error_codes.get(error["code"])
        reason = error["data"]["reason"]
        if entry is None:
            self.fail(where, f"error code {error['code']} is not in the table")
            return
        self.covered["errors"].add(reason)
        if entry["reason"] != reason:
            self.fail(where, f"code {error['code']} is {entry['reason']}, not {reason}")
        if entry["message"] != error["message"]:
            self.fail(where, f"message for {reason} must be: {entry['message']}")
        for field, value in error["data"].items():
            if field == "reason":
                continue
            if field not in entry["data"]:
                self.fail(where, f"{reason} does not carry {field}")
                continue
            self.check(BASE + f"errors.json#/data_schemas/{field}", value, f"{where} data.{field}")

    # Crypto

    def crypto(self) -> int:
        crypto = PROTOCOL / "vectors" / "crypto"
        ident = json.loads((crypto / "identity.json").read_text())
        spki = {}
        for role in ("host", "device", "other_device"):
            pem = (PROTOCOL / "vectors" / ident[role]["key_file"]).read_bytes()
            key = serialization.load_pem_private_key(pem, None)
            spki[role] = key.public_key().public_bytes(serialization.Encoding.DER,
                                                       serialization.PublicFormat.SubjectPublicKeyInfo)
            if b64url(spki[role]) != ident[role]["spki_der_b64url"]:
                self.fail("crypto/identity.json", f"{role} SPKI does not match its key file")
        self.pin = b64url(sha256(spki["host"]))
        if ident["host"]["pin"] != self.pin:
            self.fail("crypto/identity.json", "the pin must be b64url(SHA-256(host SPKI))")
        for role in ("device", "other_device"):
            if ident[role]["device_id"] != b64url(sha256(spki[role])):
                self.fail("crypto/identity.json", f"{role} device_id must be b64url(SHA-256(SPKI))")
        if ident["device"]["key"] != b64url(spki["device"]):
            self.fail("crypto/identity.json", "the device key must be b64url(SPKI)")

        sigs = json.loads((crypto / "signatures.json").read_text())
        if sigs["host_pin"] != self.pin:
            self.fail("crypto/signatures.json", "host_pin differs from identity.json")
        for case in sigs["cases"]:
            where = f"crypto/signatures.json {case['name']}"
            message = bytes.fromhex(case["signed_bytes_hex"])
            if case["verifies"]:
                expected = ((case["context"].encode() + b"\x00") + unb64(self.pin) + unb64(case["challenge"])
                            + (unb64(case["token"]) if case["token"] else b""))
                if message != expected:
                    self.fail(where, "signed bytes are not context || 0x00 || pin hash || challenge || token")
            if verifies(case["device_key"], case["signature"], message) != case["verifies"]:
                self.fail(where, f"signature should {'verify' if case['verifies'] else 'fail'}")

        codes = json.loads((crypto / "pairing_code.json").read_text())
        for case in codes["cases"]:
            digest = sha256(CODE_CONTEXT + unb64(case["host_pin"]) + unb64(case["device_id"]) + unb64(case["challenge"]))
            if f"{int.from_bytes(digest[:4], 'big') % 1_000_000:06d}" != case["code"]:
                self.fail("crypto/pairing_code.json", f"code for {case['challenge']} is wrong")

        qr = json.loads((crypto / "qr_link.json").read_text())
        rebuilt = "tabber-remote://pair?" + "&".join(f"{k}={quote(v, safe='')}" for k, v in qr["fields"].items())
        if rebuilt != qr["link"]:
            self.fail("crypto/qr_link.json", "the link does not encode its fields")
        parts = urlsplit(qr["link"])
        fields = dict(parse_qsl(parts.query, keep_blank_values=True))
        if (parts.scheme, parts.netloc) != ("tabber-remote", "pair") or fields != qr["fields"]:
            self.fail("crypto/qr_link.json", "the link does not parse back to its fields")
        if fields.get("hosts", "").split(",") != qr["routes"]:
            self.fail("crypto/qr_link.json", "hosts must be the routes, comma-separated")
        if fields.get("spki") != self.pin or fields.get("tok") != ident["token"] or fields.get("id") != ident["host"]["id"]:
            self.fail("crypto/qr_link.json", "spki, tok and id must match identity.json")
        return 4

    def coverage(self) -> None:
        everything = {"methods": set(self.methods), "topics": self.topics, "errors": set(self.errors)}
        for kind, wanted in everything.items():
            missing = sorted(wanted - self.covered[kind])
            if missing:
                self.fail("coverage", f"no vector shows these {kind}: {', '.join(missing)}")


def main() -> int:
    checker = Checker()
    crypto_files = checker.crypto()
    exchanges = sorted((PROTOCOL / "vectors" / "exchanges").glob("*.json"))
    for path in exchanges:
        checker.exchange(path)
    checker.coverage()
    if checker.failures:
        print("\n".join(checker.failures))
        print(f"\nFAILED: {len(checker.failures)} problems")
        return 1
    c = checker.covered
    print(f"OK: {checker.schema_count} schemas, {len(exchanges)} exchange vectors, {crypto_files} crypto vectors; "
          f"{len(c['methods'])} verbs, {len(c['topics'])} topics and {len(c['errors'])} errors covered")
    return 0


if __name__ == "__main__":
    sys.exit(main())
