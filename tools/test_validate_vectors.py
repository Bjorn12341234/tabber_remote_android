"""The validator must catch broken vectors, not only pass good ones.

Each case copies protocol/ and the validator to a temporary folder, breaks one
thing and expects the validator to fail with a telling message.

Run: .venv/bin/python -m unittest tools/test_validate_vectors.py
"""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent


def load(root: Path, rel: str):
    return json.loads((root / "protocol" / rel).read_text())


def save(root: Path, rel: str, data) -> None:
    (root / "protocol" / rel).write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")


def steps(vector: dict, method: str | None = None, **match):
    for step in vector["steps"]:
        message = step.get("message", {})
        if method and message.get("method") != method:
            continue
        if all(message.get(k) == v for k, v in match.items()):
            yield step


class ValidatorCatches(unittest.TestCase):
    def run_broken(self, breaker) -> str:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shutil.copytree(REPO / "protocol", root / "protocol")
            (root / "tools").mkdir()
            shutil.copy(REPO / "tools" / "validate_vectors.py", root / "tools")
            breaker(root)
            done = subprocess.run([sys.executable, str(root / "tools" / "validate_vectors.py")],
                                  capture_output=True, text=True)
            self.assertEqual(done.returncode, 1, "the validator passed a broken vector:\n" + done.stdout)
            return done.stdout

    def test_the_good_vectors_pass(self):
        done = subprocess.run([sys.executable, str(REPO / "tools" / "validate_vectors.py")],
                              capture_output=True, text=True)
        self.assertEqual(done.returncode, 0, done.stdout)

    def test_a_wrong_pairing_signature(self):
        def breaker(root):
            v = load(root, "vectors/exchanges/connect_pair_token.json")
            pair = next(steps(v, "pair"))
            other = load(root, "vectors/crypto/signatures.json")["cases"][1]["signature"]
            pair["message"]["params"]["signature"] = other
            save(root, "vectors/exchanges/connect_pair_token.json", v)
        self.assertIn("this signature must verify", self.run_broken(breaker))

    def test_an_event_seq_gap_that_is_not_marked(self):
        def breaker(root):
            v = load(root, "vectors/exchanges/take_loop.json")
            event = next(steps(v, "event"))
            event["message"]["params"]["seq"] += 1
            save(root, "vectors/exchanges/take_loop.json", v)
        self.assertIn("seq", self.run_broken(breaker))

    def test_an_error_message_that_differs_from_the_table(self):
        def breaker(root):
            v = load(root, "vectors/exchanges/conflicts.json")
            step = next(s for s in v["steps"] if "error" in s.get("message", {}))
            step["message"]["error"]["message"] = "Nope."
            save(root, "vectors/exchanges/conflicts.json", v)
        self.assertIn("message for stale_target must be", self.run_broken(breaker))

    def test_three_failures_without_a_close(self):
        def breaker(root):
            v = load(root, "vectors/exchanges/pairing_errors.json")
            v["steps"] = [s for s in v["steps"] if "close" not in s]
            save(root, "vectors/exchanges/pairing_errors.json", v)
        self.assertIn("host close 1008", self.run_broken(breaker))

    def test_a_resent_key_answered_differently(self):
        def breaker(root):
            v = load(root, "vectors/exchanges/idempotent_resend.json")
            answers = [s for s in v["steps"] if s.get("from") == "host" and "result" in s.get("message", {})
                       and "record" in s["message"]["result"] and "take" not in s["message"]["result"]]
            answers[-1]["message"]["result"]["record"]["started"]["t"] += 1
            save(root, "vectors/exchanges/idempotent_resend.json", v)
        self.assertIn("answered differently", self.run_broken(breaker))

    def test_an_unknown_field(self):
        def breaker(root):
            v = load(root, "vectors/exchanges/connect_auth.json")
            event = next(steps(v, "event"))
            event["message"]["params"]["data"]["volume"] = 1
            save(root, "vectors/exchanges/connect_auth.json", v)
        self.assertIn("Additional properties are not allowed", self.run_broken(breaker))

    def test_a_verb_that_works_before_authentication(self):
        def breaker(root):
            v = load(root, "vectors/exchanges/auth_errors.json")
            for step in v["steps"]:
                if step.get("message", {}).get("error", {}).get("data", {}).get("reason") == "unauthenticated":
                    request_id = step["message"]["id"]
                    step["message"] = {"jsonrpc": "2.0", "id": request_id, "result": {"transport": None}}
            save(root, "vectors/exchanges/auth_errors.json", v)
        self.assertIn("before authentication must be answered with unauthenticated", self.run_broken(breaker))

    def test_a_qr_link_with_the_wrong_pin(self):
        def breaker(root):
            qr = load(root, "vectors/crypto/qr_link.json")
            qr["fields"]["spki"] = "A" * 43
            save(root, "vectors/crypto/qr_link.json", qr)
        self.assertIn("qr_link.json", self.run_broken(breaker))

    def test_a_wrong_pairing_code(self):
        def breaker(root):
            codes = load(root, "vectors/crypto/pairing_code.json")
            codes["cases"][0]["code"] = "000000"
            save(root, "vectors/crypto/pairing_code.json", codes)
        self.assertIn("pairing_code.json", self.run_broken(breaker))

    def test_coverage_of_every_error(self):
        def breaker(root):
            (root / "protocol" / "vectors" / "exchanges" / "limits_and_errors.json").unlink()
        self.assertIn("no vector shows these errors", self.run_broken(breaker))


if __name__ == "__main__":
    unittest.main()
