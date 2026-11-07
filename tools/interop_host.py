"""Run Tabber Studio's remote host on localhost for RemoteKit's interop test.

The real ``remote_host`` from a Tabber Studio checkout, with the protocol's
test key and an open pairing window, and no song or window: enough for
hello, pair, auth, refusals and the TLS pin. It prints one line of JSON
({"port", "pin", "token", "host_id"}) and serves until killed or 120 s.

Run with Tabber Studio's venv (it has PySide6, websockets, cryptography):

    ../tabber_studio/venv/bin/python tools/interop_host.py ../tabber_studio
"""

from __future__ import annotations

import base64
import json
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent


def main() -> None:
    studio = Path(sys.argv[1] if len(sys.argv) > 1 else REPO.parent / "tabber_studio").resolve()
    sys.path.insert(0, str(studio))
    from cryptography.hazmat.primitives import serialization
    from PySide6.QtCore import QCoreApplication, QTimer

    from remote_host import identity, pairing
    from remote_host.bridge import MainThreadBridge
    from remote_host.server import RemoteServer

    app = QCoreApplication([])
    vectors = REPO / "protocol" / "vectors"
    ident_vector = json.loads((vectors / "crypto" / "identity.json").read_text())
    key = serialization.load_pem_private_key((vectors / "keys" / "host_test_key.pem").read_bytes(), None)
    work = Path(tempfile.mkdtemp(prefix="tabber-interop-"))
    ident = identity.create(work / "remote", key=key, host_id=ident_vector["host"]["id"])
    token = base64.urlsafe_b64decode(ident_vector["token"] + "==")
    window = pairing.PairingWindow(token_source=lambda: token)
    window.open()
    server = RemoteServer(identity=ident, registry=pairing.DeviceRegistry(work / "devices.json"),
                          pairing_window=window, bridge=MainThreadBridge(), name="Interop Studio",
                          app_version="interop", host="127.0.0.1", port=0, log_path=work / "remote.log")
    port = server.start()
    print(json.dumps({"port": port, "pin": ident.pin, "token": ident_vector["token"],
                      "host_id": ident.host_id}), flush=True)
    QTimer.singleShot(120_000, app.quit)
    app.exec()
    server.stop()


if __name__ == "__main__":
    main()
