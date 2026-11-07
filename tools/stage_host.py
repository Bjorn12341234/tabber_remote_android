"""A headless Tabber Studio with the remote on, for testing the phone end to end.

A real MainWindow (offscreen) with a small song and an engine that opens no
audio device (Tabber Studio's ``tests/remote/fakes.py``), the remote on, with
Bonjour, and pairing open. It prints one line of JSON with the pairing link,
the port and the host id, then serves until killed or ``--seconds`` pass.

It keeps Tabber Studio's own test isolation by importing its
``tests/conftest.py`` (throwaway settings, logs and state, the release
engine), so the owner's settings, recent files and journals are not touched.
``--state DIR`` keeps the computer's keys and paired phones in DIR: start it
again with the same DIR and another ``--port``, and a paired phone must find
it again by itself (TR6: the computer's address changed).

It listens on every interface (the phone in the Simulator reaches it through
the Mac's own address, as a real phone does), so run it only on a trusted
network. Run with Tabber Studio's venv:

    ../tabber_studio/venv/bin/python tools/stage_host.py --studio ../tabber_studio --state /tmp/stage --port 9481
"""

from __future__ import annotations

import argparse
import json
import os
import signal
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--studio", default=str(REPO.parent / "tabber_studio"))
    parser.add_argument("--state", required=True, help="keys and paired phones live here")
    parser.add_argument("--port", type=int, default=9474)
    parser.add_argument("--seconds", type=int, default=900)
    args = parser.parse_args()

    studio = Path(args.studio).resolve()
    state = Path(args.state).resolve()
    state.mkdir(parents=True, exist_ok=True)
    os.environ["TABBER_USER_STATE_DIR"] = str(state / "user_state")
    os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
    os.chdir(studio)
    sys.path.insert(0, str(studio))

    import tests.conftest  # noqa: F401  Tabber Studio's test isolation, applied on import
    from core import recovery
    from core.models import AudioTrack, Song
    from core.tabber_format import save_tabber
    from PySide6.QtCore import QTimer
    from PySide6.QtWidgets import QApplication
    from tests.remote.fakes import FakeEngine

    recovery.user_state = lambda *parts: state.joinpath("recovery", *parts)
    app = QApplication.instance() or QApplication([])
    from control_api.dispatch import dispatch_sync
    from control_api.server import set_main_window
    from remote_host import runtime
    from ui.main_window import MainWindow

    path = state / "project" / "stage_song.tabber"
    if not path.exists():
        song = Song(title="Stage Song")
        for name in ("Vocals", "Guitar"):
            song.audio_tracks.append(AudioTrack(name=name))
        path.parent.mkdir(parents=True, exist_ok=True)
        save_tabber(song, path)
    window = MainWindow()
    window._load_file(str(path))
    fake = FakeEngine(window._midi_engine)
    window._cpp_engine = window._midi_engine = fake
    set_main_window(window)
    app.processEvents()
    if not (dispatch_sync("markers.list", {}).result or {}).get("markers"):
        for measure, name in ((0, "Intro"), (8, "Verse"), (16, "Chorus")):
            dispatch_sync("markers.add", {"measure": measure, "name": name})

    def activity(text, _paired):
        print(json.dumps({"activity": text}), flush=True)

    runtime.set_hooks(activity=activity)
    status = runtime.enable(port=args.port)
    pairing = runtime.pair(True)
    print(json.dumps({"link": pairing["link"], "port": status["port"], "host_id": status["host_id"],
                      "advertised": status.get("advertised")}), flush=True)

    def stop(*_):
        app.quit()

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    pulse = QTimer()                     # lets Python run the signal handlers
    pulse.start(200)
    pulse.timeout.connect(lambda: None)
    QTimer.singleShot(args.seconds * 1000, app.quit)
    app.exec()
    runtime.disable()
    window._dirty = False
    window._cpp_engine = window._midi_engine = fake._real
    os._exit(0)                          # as Tabber Studio does: no teardown-phase crashes


if __name__ == "__main__":
    main()
