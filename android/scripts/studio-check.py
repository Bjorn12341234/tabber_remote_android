#!/usr/bin/env python3
"""android/scripts/studio-check.py: Tabber Spak on the emulator against the installed Tabber Studio.

TA2's and TA3's check on this laptop, end to end, with nothing heard and no microphone recorded:
Tabber Studio runs under Tabber Studio Linux's isolated JACK dummy server, whose input and
output are silent. Run it from this repository's root, with the emulator up:

    ../tabber_studio_linux/scripts/with_jack_dummy.sh \\
        ../tabber_studio_linux/.venv/bin/python android/scripts/studio-check.py

1. Tabber Studio (dist/Tabber-Studio-latest.AppImage) offscreen in a fresh home, with the
   Control API; a new song with an audio track, Vocals; the remote on; its pairing link.
2. The debug app on the emulator, fresh, gets the link as the phone's camera hands it over
   (the route rewritten to 10.0.2.2, the emulator's name for this laptop) and connects.
3. S1 on the phone, read back from Tabber Studio over the Control API after each step: arm
   Vocals, record, stop, the take card, Delete, Undo.
4. Drum tab (TR45, tab.drum/1, from Tabber Studio 0.3.31): the Tab screen's "+ Add Drum Track"
   makes a drum track, a tap on the Drum Map's snare writes 38 on the beat and a second takes it
   off, each read back from the track's first measure over the Control API.
5. Tabber Studio quits and starts again in the same home (the same key and paired phones),
   the remote goes back on, and the phone reconnects by itself (TA2).

Screens: android/shots/studio-*.png. Prints one JSON line of evidence; exits 1 on a failure.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.parse
import xml.etree.ElementTree as ET
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
ANDROID = REPO / "android"
SHOTS = ANDROID / "shots"
STUDIO = Path(os.environ.get("TABBER_STUDIO", REPO.parent / "tabber_studio_linux")).resolve()
SDK = Path(os.environ.get("ANDROID_HOME", Path.home() / "Android/Sdk"))
ADB = str(SDK / "platform-tools/adb")
APP = "com.tabberspak.app.debug"
ACTIVITY = f"{APP}/com.tabberspak.app.MainActivity"

sys.path.insert(0, str(STUDIO))
from tools import linux_release_check as lrc  # noqa: E402  (Tabber Studio's packaged-app launcher)

evidence: dict = {"studio": str(STUDIO)}


def fail(why: str) -> None:
    evidence["ok"] = False
    evidence["failure"] = why
    print(json.dumps(evidence))
    sys.exit(1)


def adb(*args: str, check: bool = True) -> str:
    done = subprocess.run([ADB, *args], capture_output=True, text=True, timeout=120)
    if check and done.returncode != 0:
        fail(f"adb {' '.join(args)}: {done.stderr.strip()}")
    return done.stdout


def screen() -> list[dict]:
    """The phone's accessibility tree: each node's resource id (the Compose test tag), and the
    words of the node and everything under it (Compose puts a control's description on a child)."""
    raw = subprocess.run([ADB, "exec-out", "uiautomator", "dump", "/dev/tty"], capture_output=True, text=True, timeout=60).stdout
    raw = raw[: raw.rfind(">") + 1] if ">" in raw else raw
    try:
        root = ET.fromstring(raw)
    except ET.ParseError:
        return []
    nodes = []
    for node in root.iter("node"):
        words = " ".join(filter(None, (n.get("content-desc", "") + " " + n.get("text", "") for n in node.iter("node"))))
        bounds = [int(n) for n in re.findall(r"\d+", node.get("bounds", ""))]
        nodes.append({"id": node.get("resource-id", ""), "desc": words, "bounds": bounds})
    return nodes


def find(tag: str, nodes: list[dict] | None = None) -> dict | None:
    for node in nodes if nodes is not None else screen():
        if node["id"] == tag or node["id"].endswith(":id/" + tag):
            return node
    return None


def wait_for(what: str, check, timeout: float = 20.0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        found = check()
        if found:
            return found
        time.sleep(0.4)
    shot(f"failed-{re.sub(r'[^a-z0-9]+', '-', what.lower())}")
    fail(f"timed out waiting for {what}")


def tap(tag: str) -> None:
    tap_node(wait_for(f"the control {tag}", lambda: find(tag)))


def tap_node(node: dict) -> None:
    x1, y1, x2, y2 = node["bounds"]
    adb("shell", "input", "tap", str((x1 + x2) // 2), str((y1 + y2) // 2))


def connected(nodes: list[dict]) -> bool:
    chip = find("connection", nodes)
    return bool(chip) and ", connected." in chip["desc"]


def shot(name: str) -> None:
    SHOTS.mkdir(exist_ok=True)
    (SHOTS / f"studio-{name}.png").write_bytes(subprocess.run([ADB, "exec-out", "screencap", "-p"], capture_output=True, timeout=60).stdout)


def drums_on_first_beat(client) -> list[int] | None:
    """The GM numbers on the first beat of the drum track's first measure, as Tabber Studio holds
    them (tabs.get_measure); None while the song has no drum track."""
    tracks = client.call("tracks.list").get("tracks", [])
    drums = next((track for track in tracks if track.get("is_drum") and not track.get("is_audio")), None)
    if drums is None:
        return None
    # tabs.* count the score tracks only: the row's domain_index, not its strip index.
    beats = client.call("tabs.get_measure", track=drums["domain_index"], measure=0).get("beats", [])
    return sorted(int(note["fret"]) for note in (beats[0].get("notes", []) if beats else []))


def take_count(client) -> int:
    """The passes Tabber Studio holds: one linear recording on an audio track is one pass, which
    is what the phone calls a take (takes.passes, the read the remote's own take list uses)."""
    return len(client.call("takes.passes", limit=200).get("passes", []))


def studio(root: Path):
    """Tabber Studio on the isolated JACK dummy server only. Auto would choose PipeWire, the
    laptop's real speakers and microphone, over native JACK, so the JACK mode is set and the
    route is checked before anything else happens; nothing runs on real audio hardware."""
    launcher = (STUDIO / "dist/Tabber-Studio-latest.AppImage").resolve()
    if not launcher.exists():
        fail(f"no installed Tabber Studio at {launcher}")
    process, client, log = lrc._launch_and_connect(launcher, root=root)
    client.call("config.set_audio_settings", mode="jack", _timeout=60)
    actual = client.call("config.get_audio_settings").get("actual") or {}
    evidence["audio_route"] = actual.get("route")
    if actual.get("route") != "native-jack":
        lrc._quit_packaged(process, client, log)
        fail(f"Tabber Studio is not on the dummy JACK server ({actual.get('route')}, {actual.get('backend_name')}): stopped before any audio")
    return process, client, log


def main() -> None:
    if not os.environ.get("JACK_DEFAULT_SERVER"):
        fail("run under tabber_studio_linux/scripts/with_jack_dummy.sh: nothing may be heard or recorded")
    if subprocess.run([ADB, "get-state"], capture_output=True).returncode != 0:
        fail("no emulator: android/scripts/emulator.sh start")
    root = Path(tempfile.mkdtemp(prefix="tabberspak-studio-"))
    # Kept after a failure, for Tabber Studio's logs there; removed after a pass.
    evidence["studio_home"] = str(root)
    process, client, log = studio(root)
    try:
        client.call("project.new")
        client.call("tracks.create_audio", name="Vocals")
        status = client.call("remote.enable")
        paired = client.call("remote.pair")
        port = int(str(paired["routes"][0]).rsplit(":", 1)[1])
        parts = urllib.parse.urlsplit(paired["link"])
        query = dict(urllib.parse.parse_qsl(parts.query))
        query["hosts"] = f"10.0.2.2:{port}"
        link = urllib.parse.urlunsplit((parts.scheme, parts.netloc, parts.path,
                                        urllib.parse.urlencode(query, quote_via=urllib.parse.quote), ""))
        evidence.update(studio_name=query.get("name"), port=port, remote=status.get("running", status))

        subprocess.run([str(ANDROID / "gradlew"), "-p", str(ANDROID), ":app:assembleDebug", "-q"], check=True,
                       env={**os.environ, "JAVA_HOME": os.environ.get("JAVA_HOME", "/opt/android-studio/jbr")})
        adb("install", "-r", "-t", str(ANDROID / "app/build/outputs/apk/debug/app-debug.apk"))
        adb("shell", "am", "force-stop", APP)
        adb("shell", "am", "start", "-W", "-n", ACTIVITY, "--ez", "reset", "true")
        time.sleep(1.5)
        adb("shell", "am", "start", "-W", "-a", "android.intent.action.VIEW", "-d", f"'{link}'", APP)
        started = time.monotonic()
        wait_for("the phone to connect", lambda: connected(screen()), timeout=40)
        evidence["paired_and_connected_s"] = round(time.monotonic() - started, 1)
        wait_for("the Vocals track", lambda: find("track-Vocals"))
        shot("connected")

        tap("arm-Vocals")
        wait_for("Vocals armed", lambda: "armed for recording" in (find("track-Vocals") or {}).get("desc", ""))
        tap("record")
        wait_for("recording", lambda: "Recording" in (find("readout") or {}).get("desc", ""), timeout=15)
        time.sleep(2.5)
        tap("stop")
        wait_for("the take card", lambda: find("take-card"))
        shot("take-card")
        evidence["takes_after_stop"] = take_count(client)
        if evidence["takes_after_stop"] != 1:
            fail(f"Tabber Studio has {evidence['takes_after_stop']} takes after the phone's take")

        tap("delete")
        wait_for("the take gone from Tabber Studio", lambda: take_count(client) == 0, timeout=10)
        evidence["takes_after_delete"] = 0
        # Undo is offered for five seconds and a screen dump takes one or two: tap it from the
        # same dump that shows it.
        undo = wait_for("the Undo banner", lambda: find("undo-delete"), timeout=4)
        tap_node(undo)
        wait_for("the take back in Tabber Studio", lambda: take_count(client) == 1, timeout=10)
        evidence["takes_after_undo"] = 1

        # TR45: drum tab from the phone, on a song whose only track is audio.
        tap("tab-tab")
        tap("add-drum-track")
        wait_for("the Drum Map", lambda: find("drum-38"), timeout=20)
        wait_for("the drum track in Tabber Studio", lambda: drums_on_first_beat(client) == [], timeout=10)
        tap("drum-38")
        wait_for("the snare on the first beat in Tabber Studio", lambda: drums_on_first_beat(client) == [38], timeout=10)
        shot("drum-map")
        tap("drum-38")
        wait_for("the snare off again in Tabber Studio", lambda: drums_on_first_beat(client) == [], timeout=10)
        evidence["drum_tab"] = "added, 38 written and taken off"

        lrc._quit_packaged(process, client, log)
        restarted = time.monotonic()
        process, client, log = studio(root)
        client.call("remote.enable")
        wait_for("the phone to reconnect", lambda: connected(screen()), timeout=40)
        evidence["reconnected_after_restart_s"] = round(time.monotonic() - restarted, 1)
        shot("reconnected")
        evidence["ok"] = True
        evidence.pop("studio_home")
        print(json.dumps(evidence))
    finally:
        try:
            lrc._quit_packaged(process, client, log)
        except Exception:  # noqa: BLE001  (already gone)
            pass
        if evidence.get("ok"):
            shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    main()
