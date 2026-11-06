# Tabber Spak: plan

Status: planning only, 2026-11-06. No code exists yet, in this repository or
in Tabber Studio. Sources: Tabber Studio `main` at `1ecc4a79` (0.3.16), read
for this plan, and web research done the same day (links at the end). Tabber
Studio changes often: re-verify every reference before coding.

Read `guiding_principles_remote.md` first. It decides every conflict in this
plan. Inside Tabber Studio, Tabber Studio's own guiding principles and
`AGENTS.md` apply in full.

## Why

The owner, 2026-11-06 (typing tidied):

- A remote control for Tabber Studio: start and stop recording from the
  phone, use it as a microphone, on the same Wi-Fi or away from home.
- "The app should be very user friendly and modern and sleek."
- "It should work without me as a dev having to provide a server I pay for."
  The user connects to their own computer, "very easy for them and it just
  works".
- The same thing later for Windows and Linux, and an Android version that is
  easy to port.
- "In a studio perhaps you want to look at the guitarist or singer and not sit
  by the computer. So you can start and stop recordings, delete the last one if
  it was not good and retake and all that. All from your mobile."

The owner has an Apple Developer Program membership and a Google Play
developer account, so TestFlight, the App Store and Google Play are all
available. The plan has no running costs: there is no server.

## Goal

Tabber Spak is an iPhone app that turns the phone into the remote for Tabber
Studio running on the user's own computer.

Version 1.0 runs a recording session from across the room. You can arm a
track, count in, record, stop, keep or discard the take, go again, jump to a
section, loop it and watch the input level, all without looking at the
computer.

Later updates add:
- the Lock Screen and the Action Button
- the phone as a microphone
- one-bar tab entry
- choosing and adjusting plug-ins on the computer

Setup is one QR scan. There are no accounts and no developer-run server. The
protocol is designed once, for macOS, Windows and Linux hosts and for an
Android client.

## The name

The app is **Tabber Spak**. The owner, in an earlier chat: "Tabber spak var
väldigt bra." A spak is a lever, like a control on a studio desk. The App Store
listing reads "Tabber Spak", with the subtitle "Remote for Tabber Studio".

The About screen carries the acronym as a small bonus:

- **SPAK in Swedish:** Spela, Prova, Arrangera, Kontrollera. Record a take
  (M1), try a new guitar tone (M5), arrange a riff in tab (M4), control the
  studio from the phone (M1 and M2).
- **SPAK in English:** Studio Performance & Arrangement Kit.

Everything that is not the product name keeps the plain word "remote", so it
can outlive any branding:
- this repository (`tabber_remote`)
- the Tabber Remote Protocol and the Bonjour type `_tabber-remote._tcp`
- the `remote_host` package and Settings › Remote in Tabber Studio

A later Android app is Tabber Spak too and speaks the same protocol.

## Who it is for

1. **The musician recording themselves:** the drummer at the kit, the
   guitarist on the couch, the singer in the booth.
2. **The engineer in the room,** watching the performer instead of a screen.

These scenarios are the acceptance tests. Sprints refer to them by number.

- **S1, five takes of the chorus.** The engineer arms the vocal track, jumps
  to Chorus, sets a one-bar count-in and records. After each take: keep it, or
  discard it and go again. The engineer never touches the computer.
- **S2, the Wi-Fi drops mid-take.** The computer keeps recording. The phone
  says "Reconnecting", then shows the true state: still recording with the
  right elapsed time, or stopped.
- **S3, a riff from the couch.** Open bar 12 of the guitar track, enter frets,
  loop the bar, fix a note, undo from the phone or the computer.
- **S4, a tone.** Add an amp plug-in to the guitar track from the phone,
  bypass it, change its gain.
- **S5, an idea away from the computer.** Record a riff on the phone. It lands
  in Tabber Studio's inbox the next time the phone connects.
- **S6, practice.** Loop the solo at 70% speed and step the speed up.

## Lessons from other remotes

The research covered Logic Remote, Cubase iC Pro, Studio One/Studio Pro
Remote, REAPER's web remote and OSC, Avid Control, touchAble Pro, R-KONTROL
and TouchOSC, plus their reviews and forum threads.

- **The job is always the same:** recording yourself from across the room. The
  transport must be readable and hittable at a distance.
- **"Connected, but nothing works" and "status not updating"** are the worst
  reviews. Show the computer's confirmed state, and drive the connection badge
  from heartbeats.
- **Version mismatch between the phone app and the desktop** is the most
  common breakage: Studio One, Avid and touchAble all broke this way after
  updates. Plan versioning and plain-language mismatch messages from day one.
- **Typing an IP address is a support burden.** It breaks after a router
  reset (REAPER and TouchOSC). Use Bonjour, with QR pairing and a manual
  address as fallbacks.
- **Look-alike buttons get confused.** Studio One Remote's grey play, stop and
  record buttons are a named complaint. Cubase iC Pro users want loop points,
  and time shown in bars and beats.
- **Network layout breaks discovery.** Guest Wi-Fi, VLANs, access-point
  isolation, VPNs, Wi-Fi Assist, mesh nodes and the Mac firewall all do. AirDrop
  (AWDL) causes latency spikes up to about 90 ms.
- **Writing tab on a phone, tied to a desktop editor, appears unclaimed.**
  Guitar Pro for iOS has no link to the desktop app, and a reviewer "would have
  paid triple for an editor" (one review, not a market study).

## What exists today in Tabber Studio

The Control API (`control_api/`) is what the remote builds on. These facts
shape the design.

- **It is local-only and unauthenticated.** It listens on TCP `127.0.0.1:9473`
  and speaks newline-delimited JSON-RPC 2.0 (`server.py:246,268-277`). Its only
  guard stops browser POSTs (`server.py:127-166`). It must never be opened to
  the network as it is.
- **Handlers run synchronously on the Qt main thread** (`server.py:175-194`).
  - Some block that thread for seconds: `system.wait_drain` waits up to 10 s
    (`handlers/system.py:193-206`).
  - Deferred replies can arrive out of order, and the bundled client does not
    match reply ids (`dispatch.py:46-245`, `client.py:144-187`).
- **One dispatcher already serves three callers:** TCP, the AI chat and the
  Control Console (`dispatch.py:383-428`). The remote host uses the same
  in-process funnel.
- **There is no push.** Nothing is pushed over the wire.
  - In-process, `CppEngineWrapper` emits position, beat, start/stop,
    tempo-scale and device signals from a 33 ms poll
    (`core/engine_bridge.py:542-569,709`).
  - Recording and undo changes have Qt signals. Meters have none.
  - `system.status` and `transport.get_state` are cheap. `state.snapshot`
    serializes the whole song.
- **Command metadata exists but is not enforced.** The command catalog records
  each command's effect: read, live, reversible_edit, external_file,
  destructive or advanced (`command_catalog.py:88-108`,
  `console_metadata.py:20-25`).
  - Methods without metadata default to `advanced` (`command_catalog.py:332`).
  - `undo_support` is not reliable (`console_metadata.py:242`).
- **Runtime and packaging:**
  - PySide6 6.10.2 on Python 3.14.
  - The installed app has QtNetwork and Qt's TLS plug-ins, but not
    QtWebSockets. No mDNS, WebSocket or crypto library is a dependency.
  - Info.plist has only `NSMicrophoneUsageDescription`.
  - The app is Developer ID-signed with the hardened runtime and is not
    sandboxed (`tabber_macos.spec:299-312`, `tabber.entitlements`).
- **Placement constraints:**
  - Every module in `control_api/handlers/` is imported when the ControlServer
    is built (`server.py:79-94`). The remote server must not live there, and
    handlers that use it must import it lazily.
  - The startup import check is
    `tests/perf/test_mp13_performance_overview.py:315-333`.

| The remote needs | Exists | Gap |
|---|---|---|
| Play, pause, stop | `transport.play`, `pause`, `stop` | none |
| Record and stop | `recording.start` (takes targets and `count_in_bars`), `recording.stop`, `is_recording`, `record_loop` | none |
| Arm a track | `recording.arm_track`, MIDI tracks only | **audio-track arm** is UI-only (`_on_audio_track_record_arm`, `ui/main_window.py:14074`) |
| Count-in, click, loop | `recording.set_count_in` (0 to 2 bars), `transport.set_metronome`, `transport.set_loop` | none for 1.0 (no separate pre-roll) |
| Practice speed | `transport.set_tempo_scale` (0.25 to 2.0), `transport.set_speed_trainer` | none |
| Markers | `tabs.set_section_marker`; listed only inside `tabs.list_measures`; jump with `transport.seek` or `view.goto_bar` | **list markers, go to a marker** |
| Tracks | `tracks.list`, `select`, `get_selected` | stable track ids for the remote (verify what the model has) |
| Meters | `recording.get_input_peak`, `mixer.get_peak_levels` | no push; `mixer.get_master_peak` runs an offline render when stopped (`mixer.py:365-369`), so the remote never polls it |
| Discard a take | `takes.delete` keeps the take's sound by design (`takes.py:426-433`); `project.undo` reverts only the newest step | **discard this take**, undoable, file kept on disk |
| Undo, redo, save | `project.undo`, `redo`; `project.save` needs an existing file | none (an unsaved project is saved on the computer) |
| Status | `system.status`, `transport.get_state` | **compact session snapshot**, and push |
| Tab entry | `tabs.set_note`, `insert_beat`, `set_duration` | **undo**: on ordinary bars these are direct mutations, "non-undoable exactly as before EP-A17d3" (`tabs.py:241-246`) |
| Loop one bar | `transport.set_loop` plus `transport.play(from_measure)` | one host verb |
| Plug-in inventory | `plugins.scan`; `plugins.list_available` is empty until a scan has run; `devices.catalog` | scan state; insert by id (today only the AI-only `insert_plugin` takes a name) |
| Add, bypass, reorder, remove | `plugins.load` plus `plugins.insert`, `set_bypass`, `reorder`, `remove`; `devices.*` | verify undo for each |
| Parameters | `plugins.list_parameters`, `set_parameter` (0 to 1), `find_parameter` | a short controls page per plug-in |
| A phone take into the project | `clips.import_audio` takes a path on the computer and makes no undo step (`clips.py:142-145`) | **upload**, **undoable placement** |

Two of these gaps are Control API parity defects under Tabber Studio's
principle 6: tab edits on ordinary bars and audio import make no undo step.
They affect every Control API caller, including the AI chat when it uses these
verbs.

At the owner's request, this session saved files only in this repository. The
defects are therefore recorded here, as work inside TR12 and TR15, and not yet
in Tabber Studio's backlog.

## Corrections to the first sketch

The conversation that started this plan got five things wrong or incomplete.

- **Where the server lives.** The sketch put the remote server "in Tabber's
  existing C++/Qt codebase". Tabber Studio's app, model and Control API are
  Python on PySide6; the C++ engine does the audio. The remote host is a Python
  package beside the Control API, and the engine is not touched.
- **"The iPhone app can call the same commands you use from the terminal."**
  Yes, but only through a new authenticated layer with a fixed vocabulary. The
  Control API accepts anything from localhost and must stay off the network.
- **Streaming the phone mic into a live track.** Wi-Fi jitter and dropouts
  make that a monitor or scratch feed at best. The take that counts is a file
  recorded on the phone.
- **Apple's iPhone microphone for the Mac (Continuity Camera).** It does show
  up as an input Tabber Studio can record. But it works only while the phone
  lies still, in landscape, with its screen off, so the phone cannot be the
  remote at the same time. It goes in the help text as the zero-effort option.
- **A relay "for easier setup" away from home.** That is a server someone has
  to run, so it is out. Away from home means the user's own VPN or Tailscale,
  with an address entered once.

## Design

### Architecture

```
iPhone: Tabber Spak (SwiftUI)
  screens    Session, Tracks, Tab, Tone, Mic, Settings
  RemoteKit  Swift package, no UI: protocol, connection, pairing,
             reconnect, clock sync, DemoHost
  Capture    AVAudioEngine recorder, upload queue
      |
      |  WebSocket over TLS 1.3, the Mac's key pinned;
      |  found with Bonjour (_tabber-remote._tcp) or a typed address
      v
Mac: Tabber Studio
  remote_host/        new package, imported only when the remote is on
    server            WebSocket and TLS on its own thread
    identity          the Mac's key and certificate
    pairing           one-time QR tokens, paired devices, challenges
    vocabulary        the fixed remote verbs, each mapped to Control API calls
    bridge            runs a call on the Qt main thread via the shared dispatcher
    feed              pushes transport, record, meter and take changes
    discovery         Bonjour advertising (macOS now; Windows, Linux later)
    transfer          phone takes in, resumable
  control_api/handlers/remote.py   enable, disable, status, pair, devices, revoke
  ui/remote_controller.py, ui/remote_panel.py, ui/dialogs/remote_pairing_dialog.py
      |
      v
  existing Control API handlers -> model, undo stack, C++ engine
```

- **Only the final call touches the Qt main thread.** Network I/O, TLS,
  parsing, authentication and rate limits all run on the remote thread. The
  final call goes through the same dispatcher the AI chat uses, so a remote
  command has exactly the UI's effect (Tabber Studio principle 6).
- **The remote never goes silent.** When the main thread is busy (a project
  loading, say), the remote thread still answers heartbeats and tells the phone
  "Tabber Studio is busy".
- **Nothing new runs on the audio thread.**

### Where the code goes

**This repository (`tabber_remote`):**

```
guiding_principles_remote.md, plan.md
protocol/   spec.md, schemas/ (JSON Schema per message), vectors/ (example exchanges)
apple/      TabberSpak.xcodeproj, TabberSpak/ (the app), RemoteKit/ (Swift package),
            Extensions/ (Controls and Live Activity, from M2)
android/    later (TR24)
tools/      vector validator, latency report
```

**Tabber Studio** follows its `AGENTS.md`: new features go in their own
modules. `ui/main_window.py` gets at most one thin menu delegator, and
`core/engine_bridge.py` gets nothing.

- **`remote_host/`:** the package described above. It is not under
  `control_api/handlers/`, which is auto-imported at server construction.
- **New catalogue modules:** `control_api/handlers/remote.py` and
  `control_api/handlers/markers.py`.
- **Additions to existing catalogues:** `recording.arm_audio_track` in
  `recording.py`, and `takes.discard` and `takes.go_again` in `takes.py` (one
  more unit in a catalogue is fine). Their behaviour lives in
  `core/take_remote_commands.py`, never as new `MainWindow` methods (it has 679
  already).
- **UI:** `ui/remote_controller.py` owns the remote's UI state and takes its
  collaborators as constructor arguments, with no `self.mw` shim. Alongside it:
  `ui/remote_panel.py` (Settings › Remote) and
  `ui/dialogs/remote_pairing_dialog.py`.
- **Tests:** `tests/remote/`, targeted, including a pinned copy of
  `protocol/vectors/`.

### Connection, pairing and security

This design comes from the research. It carries over unchanged to Android,
Windows and Linux.

1. **The Mac creates its identity once.** The first time the remote is
   turned on, the Mac creates an ECDSA P-256 key and a long-lived self-signed
   certificate (Python `cryptography`). Every connection is TLS 1.3 (Python's
   `ssl` under `websockets`), at home too.
2. **"Pair iPhone" shows a QR code:**
   `tabber-remote://pair?v=1&id=<host id>&spki=<SHA-256 of the Mac's public key>&tok=<128-bit one-time token>&hosts=<addresses:port>`.
   The token is valid for five minutes. The dialog counts down and renews it.
3. **The phone pairs.** It scans the code inside the app (VisionKit),
   connects, and accepts the TLS session only if the Mac's key matches `spki`.
   That is pinning: no certificate authority is involved. The phone then sends
   the token, its name and a public key created in its Secure Enclave. The
   computer adds it to Paired devices and says so on screen.
4. **Later connections need nothing typed.** They use pinned TLS. The phone
   then signs a fresh challenge from the Mac, bound to the Mac's key hash, with
   its Secure Enclave key. There are no passwords.
5. **Fallback without the QR.** If there is no camera or the QR code is out
   of reach, pick the computer from the Bonjour list. Both screens show the same
   6-digit code, derived from both keys, and you click Allow on the computer.
6. **Managing devices.** Settings › Remote lists the paired devices with their
   last connection. Remove disconnects one at once and forgets it. "Forget all
   and make new keys" resets everything.

**What a paired phone can do** is the vocabulary below and nothing else. That
rules out file paths, scripts, settings and raw Control API methods.

- **Input limits:** every argument is checked against its schema, and text
  frames are capped at 64 KB.
- **Uploads** go only into the project's media folder, under names the
  computer chooses.
- **Rate limits** apply per device.
- **Secrets stay out of logs:** tokens and keys never reach a log.
- **Bonjour records** carry only the protocol version and the random host id.
- **Every remote action is visible on the computer.** Actions are logged to
  `~/.tabber_studio/logs/remote.log` and shown on screen ("Sam's iPhone started
  recording"), because hidden state changes are product failures (Tabber
  Studio principle 3).

**Rejected options:**
- **TLS with a pre-shared key:** Apple supports it only on the older API and
  without TLS 1.3.
- **The Noise protocol:** there is no first-party support.
- **Plain `ws://` at home:** anyone on the network could drive the session.

### The protocol

This is the Tabber Remote Protocol, version 1. TR0 writes the full spec.

- **Transport:** WebSocket over TLS over TCP. Text frames carry JSON. Binary
  frames carry audio chunks with a small header.
- **Framing:** JSON-RPC 2.0, as in the Control API, which keeps the host's
  bridge simple. Requests and responses carry ids. Host events are
  notifications (`"method": "event"`) carrying a topic, a sequence number and
  the host's monotonic time.
- **`hello` comes first.**
  - The phone sends its app version and the protocol versions it supports.
  - The host answers with its id, its name, the Tabber Studio version, the
    chosen protocol version, its capabilities (`takes.discard/1`,
    `tab.edit/1` and so on) and its limits.
  - The app shows only what the host can do. When versions do not meet, it says
    in plain words what to update ("Update Tabber Studio to use Tab").
- **A curated, stable vocabulary:** `transport.record`, `takes.discard`,
  `markers.go` and so on. The host maps each verb to Control API calls, so
  Control API names can change without breaking phones.
- **Safe to resend:** every request that changes something carries an
  idempotency key, so a resend after a reconnect never records twice.
- **Explicit targets:** every edit names its target by stable ids (track,
  take, bar, beat). Tab edits also carry the bar's revision. If the bar has
  changed on the computer, the host refuses the edit and returns the new
  content.
- **Readable errors:** each error has a stable code and a sentence a musician
  can read ("Arm a track first").
- **Versioning:** an additive change raises the minor version and adds a
  capability. A breaking change raises the major version, and the host keeps
  serving the previous major version for at least one more Tabber Studio
  release.
- **Vectors:** `protocol/vectors/` holds example exchanges: hello, pairing
  hashes and codes, each verb, errors and event sequences. The Python host
  tests and the Swift tests both run them, and the Kotlin tests will too.

### The state feed

The feed pushes changes, so the phone never polls.

- **On connect:** the phone gets a compact snapshot. It is sent again whenever
  the phone sees a gap in sequence numbers. It contains:
  - the project title and unsaved flag
  - the transport state, with position in bars and in seconds
  - tempo and tempo scale
  - loop, click and count-in
  - the record state, armed tracks and selected track
  - the markers and the newest takes
- **Then changes only.** They come from the existing engine and Qt signals,
  plus one main-thread timer for meters that runs only while some phone is
  showing meters.
- **Starting rates, to be measured in TR3:** meters 20 times a second, for
  armed and selected tracks only; the playhead 10 times a second. The phone
  draws a smooth playhead and meter falloff by extrapolating between updates,
  so the network stays quiet.
- **Heartbeats:** both sides send one every 2 seconds. Three missed in a row
  means "Reconnecting".
- **Cost:** the feed never reads anything that renders or blocks. TR3 measures
  its cost per tick, and playback must stay clean (zero dropouts in the stress
  test).

The targets below are starting points. The first measurement records the
baseline, and the owner sets the limit.

| What | Starting target | Measured in |
|---|---|---|
| A tap shows as pressed | the next frame (local) | TR7 |
| Tap to confirmed state on the phone | p95 under 150 ms on home Wi-Fi, with AirDrop on and off | TR7 |
| Reconnect when the app returns to the screen | under 1 s | TR6 |
| Host cost while the remote is off | nothing runs, nothing imported | TR2 |
| Host cost while a phone is subscribed | main-thread time per tick recorded; zero dropouts | TR3 |

### The app

**Look and feel:**
- **Built native:** SwiftUI on iOS 26 and later, built with the current Xcode
  as App Store uploads require. Logic Remote also requires iOS 26.
- **Liquid Glass comes from the system components.** Following Apple's
  guidelines, glass goes only on the floating controls (tab bar, transport,
  sheets), never on content. No custom chrome imitates it.
- **The character comes from the music:** meters, takes, markers and tab, in
  Tabber Studio's colours, on a calm surface that works in a dark room. Use SF
  Symbols and system type, with monospaced digits so the timer never jiggles.
- **Big, distinct targets.** Transport buttons are far larger than Apple's
  44 pt minimum. Record is red, and record, play and stop each have their own
  shape and colour.
- **Recording reads across the room.** The screen's frame glows red around a
  large "REC 00:42". The state is also given in words and shape, not colour
  alone.
- **Haptics** (`sensoryFeedback`): a different one for record, stop, discard
  and go again. They are off during a phone-mic take: iOS mutes them while
  recording anyway, and the microphone would pick them up.
- **Motion that explains:** the take card rises out of the transport. Reduce
  Motion is respected.
- **Accessibility:**
  - Dynamic Type up to the largest sizes.
  - VoiceOver labels that say what will happen ("Record on Vocals").
  - Layouts that adapt to any size and orientation; Apple is moving iOS apps to
    resizable windows.
- **Ready at once:** the app opens straight into the last session, and the
  screen stays awake while a session is open (a setting).

**The transport never moves.** Go again, Record and Play/Stop live in the tab
bar's bottom accessory (`tabViewBottomAccessory`), in the same place on every
screen.

```
+---------------------------------------+
|  (o) Studio Mac           My Song  *  |   connection, project, unsaved
|                                       |
|                CHORUS                 |   section at the playhead
|                37 . 2                 |   bar . beat, large
|                01:42                  |   time, smaller
|                                       |
|  Vocals           armed  [======---]  |   armed track, input meter
|                                       |
|  (Intro) (Verse) (Chorus) (Solo) (>)  |   markers: tap to jump, hold to loop
|                                       |
|  Count-in 1 bar     Click     Loop    |   toggles
|                                       |
|  [ Go again ]  [  ( REC )  ]  [ Play ]|   transport, never moves
|  Session     Tracks     Tab     Tone  |   tab bar
+---------------------------------------+
```

**Screens:**

1. **Session (home):** as drawn above.
2. **Take card:** appears after every take.
   - **Keep** is the default. Recording again also keeps the take.
   - **Discard** takes a press and hold, then offers Undo for 5 seconds. It
     removes the take as one undo step; the audio file stays on disk, so Undo
     on either device brings it back.
   - **Go again** is one host verb. It stops if needed, returns to where the
     take started, uses the same count-in and records.
   - A takes list per track has ratings.
   - Flag a moment: one tap drops a marker at the current bar.
3. **Tracks:** name, type, arm, monitor, input meter, select.
4. **Tab (M4):** a one-bar editor. Tap a string and a beat, enter the fret on
   a big pad, pick the duration, then play or loop the bar.
5. **Tone (M5):** the plug-in chain. Add, bypass, reorder, open a controls
   page, or show the plug-in's own window on the computer.
6. **Mic (M3):** record on the phone.
7. **Settings:** computers, pairing, keep awake, haptics, a connection check,
   help, about.

### The phone as a microphone

- **A local master file on the phone.** The format is CAF, which survives a
  crash or a cut-off; WAV needs its header finished at the end. The audio is
  PCM at the hardware rate (48 kHz), 24-bit.
  - No voice processing. Measurement mode is an option for the least
    processing.
  - Stereo built-in capture where the phone supports it, and USB-C audio
    interfaces on iPhones that take them.
- **Background behaviour:**
  - Recording starts with the app on screen. With the audio background mode it
    carries on after the screen locks.
  - The app shows its own recording indicator next to the system's orange dot
    (App Review 2.5.14).
- **Upload during the take** over the paired connection: numbered chunks, each
  hashed. The computer acknowledges offsets, and the upload resumes after a
  drop. Mono 48 kHz 24-bit is about 8.6 MB a minute. The phone deletes its copy
  only after the computer confirms the whole file's hash.
- **Two modes:**
  - **Idea** needs no computer. The file waits in the phone's outbox and lands
    in a Phone takes inbox in the project.
  - **Take** records together with a computer take and is placed on the
    timeline.
- **Placement:**
  - A clock-offset estimate over the connection gives coarse placement. It
    works NTP-style: many probes, keeping the fastest round trips.
  - Optionally, a short sync chirp from the computer at the start and end gives
    sub-millisecond alignment and measures clock drift. Phone clocks drift tens
    of ppm; 40 ppm is 12 ms over five minutes. Resampling corrects the drift.
  - TR14 measures both methods. The chirp is built only if the clock alone is
    not good enough.
- **No live streaming into a track** (see Ideas). At best it would be a monitor
  feed, and never the only copy.

### Around the iPhone (M2)

- **Controls and App Intents.**
  - Actions: start recording, stop, go again, discard the last take, toggle
    the click.
  - Places: Control Center, the Lock Screen, the Action Button, Shortcuts and
    Siri.
  - Each action connects, sends one idempotent command and closes.
  - The local network permission must be granted in the app first, because
    requests from the background are denied silently.
- **A Live Activity while recording:** "REC 02:14 · Vocals" on the Lock Screen
  and in the Dynamic Island, with a Stop button. Without a push server nothing
  outside the app can update it. So the time counts on the phone (a
  self-updating timer), and a stale date marks it as out of date if the app
  loses the computer.
- **No background keep-alive tricks.** iOS suspends apps and closes their
  sockets, so the app reconnects quickly when it returns to the screen. The
  audio background mode is used only while the phone itself records (App Review
  2.5.4).
- **Apple Watch comes later,** relayed through the iPhone. watchOS does not
  allow this kind of networking directly.

### Other platforms

- **Windows and Linux hosts** use the same `remote_host` package with
  different discovery backends: Windows' built-in DNS-SD (`DnsServiceRegister`,
  Windows 10 and later) and Avahi on Linux. Everything else is plain Python.
  They are built in those repositories when the owner schedules them.
- **Android** is native Kotlin and Jetpack Compose, using the same protocol and
  vectors.
  - Discovery: NsdManager. Android 17 asks for a local network permission
    unless the system picker is used.
  - The device key lives in the Android Keystore.
  - The iPhone app stays thin because the computer owns all state, so a second
    native client is a modest job.
  - Skip Fuse (Swift compiled for Android) gets a fresh look when Android work
    starts.
  - Not used for the iPhone app: Kotlin Multiplatform, whose Swift export is
    still alpha, and Compose Multiplatform, which would give up native Liquid
    Glass.

## Known traps

**Phone:**
- **Test Local Network privacy on a device.** The Simulator does not enforce
  it.
- **Denial is silent in the background.** Get the permission in the
  foreground before offering Shortcuts or Controls.
- **Detecting denial:** a denied connection waits with `localNetworkDenied`,
  and a denied browse fails with `PolicyDenied` (-65570). There is no API that
  reads the permission directly.
- **Extensions need their own keys.** An App Intents extension needs its own
  `NSLocalNetworkUsageDescription`.
- **A missing `NSBonjourServices` entry** fails with NoAuth (-65555).

**Computer:**
- **Tabber Studio started from Terminal never shows the macOS Local Network
  prompt.** Test the signed app.
- **Advertising and connecting have different rules.** Advertising with
  Bonjour needs the Mac's Local Network permission; accepting the phone's
  connection does not. If the user denies it, QR and manual connections still
  work.
- **Rebuilds and the permission prompt.** Every Tabber Studio rebuild asks for
  the microphone again. Check in TR4 whether the Local Network prompt does the
  same.
- **The macOS firewall's "Block all incoming connections"** blocks the remote.
  The app must name it.

**Network:**
- **Tailscale and most VPNs carry no multicast,** so Bonjour fails there: use
  the typed address.
- **Discovery breaks** on guest networks, VLANs, access-point isolation and
  across some mesh nodes. Wi-Fi Assist moves the phone to cellular.
- **AirDrop's AWDL link** causes latency spikes. Measure p95 with it on.

**Control API:**
- **Never put a blocking verb in the vocabulary.** Handlers run on the main
  thread, and some block for seconds.
- **Match replies by id.** They can arrive out of order.
- **Never poll `mixer.get_master_peak`.** It renders offline when stopped.
- **`plugins.list_available` is empty** until a scan has run.

**Phone audio:**
- **iOS mutes haptics while the phone records,** and they would be heard
  anyway.
- **Record to CAF, not WAV,** so a cut-off take survives.

## Milestones and sprints

One sprint per session. "Studio" means the Tabber Studio repository. "This
repo" means `tabber_remote`.

### M0, foundation

| # | Sprint | Where | Gate |
|---|---|---|---|
| TR0 | Protocol v1 spec, schemas and first vectors; the owner's decisions recorded; App Store name checked | this repo | Every vector validates against its schema; the spec covers hello, pairing, every M1 verb, events and errors |

### M1, run the session from the phone (version 1.0)

| # | Sprint | Where | Gate |
|---|---|---|---|
| TR1 | Remote-ready verbs: `recording.arm_audio_track`, `markers.list`, `markers.go`, `markers.add`, `takes.discard`, `takes.go_again`, stable ids, compact session snapshot | Studio | Headless through the shared dispatcher, read back from the model and the engine: arming by verb equals the UI path; discard then undo restores the take, and its file is untouched on disk; go again makes a new take at the right start; markers match `tabs.list_measures` |
| TR2 | Remote host core: `remote_host/` server, identity, pairing tokens, device keys and challenges, vocabulary, bridge, limits, logging; `remote.enable`, `disable`, `status`, `pair`, `devices`, `revoke` | Studio | The M1 vectors pass against a headless Tabber Studio; each of these is refused: a wrong key, a wrong or expired token, a replayed challenge, an oversized frame, an unknown verb, a raw Control API method; with the remote off, no socket listens and `remote_host` is not imported (the MP13 import check extended); the frozen app contains the package and its dependencies; bundle growth recorded |
| TR3 | State feed: snapshot, changes, sequence numbers, heartbeats, busy state, rate limits | Studio | Feed values equal the Control API's read-backs; a 10-minute playback and recording stress test with two clients at full rate has zero dropouts; main-thread time per tick and CPU change recorded here |
| TR4 | Discovery and the computer's side of pairing: Bonjour advertising (DNS-SD through ctypes), both Info.plist keys in the macOS spec, Settings › Remote, the QR dialog, paired devices, the 6-digit fallback with Allow, activity notices, a connected-phone indicator | Studio | `dns-sd -B _tabber-remote._tcp` sees the service only while the remote is on; a scripted client pairs from the QR payload and through the 6-digit path; Remove disconnects at once; on the signed, installed app (owner warned first, since it opens a window on the owner's screen): the Local Network and firewall prompts, and QR pairing still works with Local Network denied |
| TR5 | Xcode project; RemoteKit (models, Network framework connection with pinning, hello, reconnect, idempotent resend, heartbeats); DemoHost, a simulated session inside the app | this repo | `xcodebuild test`: every vector passes in Swift; the DemoHost session tests pass; a debug screen on a real iPhone connects to TR2's host by address |
| TR6 | Welcome; Find your Mac (an explainer, then browsing); QR scanner; 6-digit fallback; several computers; fix-it cards for Local Network off, VPN, guest Wi-Fi, firewall, Tabber Studio closed, version mismatch | this repo | On a device: fresh install to paired with one scan; each fix-it card reached by recreating its cause; reconnects by itself after the computer's address changes, within the target |
| TR7 | Session screen: transport in the bottom accessory, time in bars and beats, section, armed track and meter, count-in, click and loop, marker chips, recording frame, haptics, keep awake | this repo | UI tests against DemoHost for every control; on a device against Tabber Studio: S1 up to the take card, and S2; tap-to-confirmed latency p50 and p95 with AirDrop on and off, recorded here |
| TR8 | Take card (keep, discard with hold and Undo, go again), takes list with ratings, Tracks screen (arm, monitor, select), flag a moment | this repo | S1 complete on a device: five takes, two discarded, one brought back with Undo on the computer, files intact, nothing on the computer touched during the run |
| TR9 | Polish and TestFlight: design pass, icon, accessibility audit, Dynamic Type at the largest sizes, a VoiceOver run of S1, demo mode for App Review and screenshots, privacy label (Data Not Collected), privacy page, export compliance, checks against a Tabber Studio without the remote | this repo, website | The TestFlight build runs S1 on the owner's phone; the XCUITest accessibility audit passes; a too-old Tabber Studio is explained in plain words; the owner decides when to submit |

### M2, the Lock Screen and the Action Button (1.1)

| # | Sprint | Where | Gate |
|---|---|---|---|
| TR10 | Controls and App Intents: start, stop, go again, discard, click; in Control Center, on the Lock Screen and Action Button, in Shortcuts and Siri | this repo | On a locked device the Action Button starts and stops a Tabber Studio recording; a repeated press never records twice; the app explains what happens without the permission |
| TR11 | Live Activity while recording: self-updating time, stale date, Stop button | this repo | On a device it starts with the take; Stop from the Lock Screen stops the computer; the time matches the computer's within one second at stop; it goes stale when the computer is lost |

### M3, the phone as a microphone (1.2)

| # | Sprint | Where | Gate |
|---|---|---|---|
| TR12 | Upload into the project, the Phone takes inbox, undoable placement; `clips.import_audio` gets its undo step | Studio | A 10-minute 48 kHz take uploaded with Wi-Fi cut twice arrives byte-identical (hash) and resumes at the right offset; placement, undo and redo work; save and reopen keep it; the existing import tests stay green |
| TR13 | Mic screen: record on the phone (CAF, input choice, level), screen locked, interruptions, own indicator, outbox, upload during the take, Idea mode | this repo | On a device: a 10-minute take with the screen locked; a simulated call ends the take honestly and keeps the audio; the file reaches Tabber Studio's inbox with the same hash; nothing is deleted on the phone before confirmation |
| TR14 | Takes recorded together with the computer: shared start, clock offset, drift; the chirp only if needed | Studio, this repo | 20 takes aligned against the computer's own recording of the same click: offset error and leftover drift recorded here; if the clock alone meets the owner's limit, the chirp is struck from the plan with the evidence |

### M4, tab from the phone (1.3)

| # | Sprint | Where | Gate |
|---|---|---|---|
| TR15 | Tab verbs: every Control API tab edit is one undo step; a compact bar read (tuning, beats, notes, durations, revision); the revision check; loop this bar | Studio | Headless: each edit undoes from the computer and from a remote client; a stale revision is refused with the new content; the tab, pattern and AI chat tests that cover these verbs stay green |
| TR16 | One-bar tab editor: drawn tab for any string count and tuning, tap string and beat, fret pad, durations, rest, delete, next bar, play and loop the bar, undo | this repo | S3 on a device; UI tests against DemoHost; for a 20-bar fixture the phone shows the same notes as Tabber Studio (a data comparison) |
| TR17 | Follow-along view, optional: the current bars scroll with playback | this repo | Decision 9; within one beat of the computer over a 3-minute song |

### M5, tone (1.4)

| # | Sprint | Where | Gate |
|---|---|---|---|
| TR18 | Plug-in verbs: inventory and scan state, insert by id, chain listing, display values, undo for every chain change, and a controls page per plug-in (the CLAP remote-controls pages where a plug-in publishes them, after checking host support; otherwise pinned or first parameters) | Studio | The probe plug-in first, then the owner's plug-ins through the same generic contract, with no plug-in-name rules (Tabber Studio `AGENTS.md`); every change read back from the engine |
| TR19 | Tone screen: chain, add (search, favourites, recent), bypass, drag to reorder, remove with undo, controls page, "Show on computer" opens the plug-in's own window there | this repo | S4 on a device |

### M6, everywhere

| # | Sprint | Where | Gate |
|---|---|---|---|
| TR20 | Away from home: typed address or Tailscale name, remembered routes, a connection check screen, a help page | both | Connected over Tailscale from a cellular network with the pinned key unchanged; for each cause in Known traps, the check screen names the failing step |
| TR21 | iPad layout | this repo | Decision 3 |
| TR22 | Apple Watch through the iPhone, optional | this repo | Decision 10 |
| TR23 | Windows and Linux hosts: discovery backends, vectors | those Tabber Studio repositories | When the owner schedules it |
| TR24 | Android client | this repo | Every vector passes; S1 on a device; Google Play internal testing |

### Ideas, not planned

Each needs the owner's go-ahead:
- **A live phone-mic monitor feed.**
- **Ask Tabber from the phone:** typed or dictated words into Tabber Studio's
  chat (Tabber Studio principle 7).
- **Cue and headphone mixes.**
- **A lyrics and chord sheet** for singers.
- **Punch-in.**

## Decisions for the owner

1. **Order.** Default: M1 to M6 as listed. Scheduling is the owner's.
2. **Names and ids.** The name is decided: Tabber Spak (see The name).
   Still open, with defaults:
   - bundle id `studio.tabber.spak` (Tabber Studio is `studio.tabber.app`).
     A bundle id can never change once the app exists in App Store Connect, so
     confirm it before TR5 creates the Xcode project.
   - the home-screen label "Tabber Spak"
   - Bonjour type `_tabber-remote._tcp`, registered with IANA
   - TR0 checks that "Tabber Spak" is free on the App Store
3. **Devices.** Default: iPhone first, iOS 26 minimum, iPad in TR21.
4. **Price.** Default: free. It sells Tabber Studio.
5. **Version 1.0.** Default: M1 only.
6. **Confirming a pairing on the computer.** Default: no extra click for QR
   pairing, since the code is on the computer's screen, single-use and valid
   for five minutes. The 6-digit path needs an Allow click.
7. **The remote stays on.** Default: once turned on, it stays on across
   launches until it is turned off. It advertises only while on.
8. **Several phones at once.** Default: yes, so the engineer and the musician
   can both have one. Every action is named on the computer, and the last
   command wins.
9. **The follow-along view (TR17).** Default: decided after TR16.
10. **Apple Watch.** Default: later.
11. **New dependencies in Tabber Studio.** Default: yes, imported only when the
    remote is on.
    - `websockets` (BSD-3-Clause)
    - `cryptography` (Apache-2.0 or BSD)
    - `segno` for the QR code (BSD-3-Clause)
12. **Where the protocol lives.** Default: in this repository. Tabber Studio
    pins a copy of the vectors, with the commit they came from.
13. **Undo for tab edits and audio import everywhere,** not only for the
    remote. Default: everywhere, in TR15 and TR12 (Tabber Studio principle 6).
    The non-undoable tab path was deliberate ("exactly as before EP-A17d3"), so
    this is the owner's call.
14. **Scanning with the iPhone Camera app.** Default: later, through a
    universal link on the Tabber website. That is a static file, not a service.
    The token travels in the URL fragment, which browsers never send to the
    server. Scanning then opens the app, or its App Store page if it is not
    installed.
15. **This repository's visibility and licence.** The owner's call; no
    default.
16. **Live phone-mic streaming.** Default: not built (see Ideas).
17. **Languages.** Default: English, plus Swedish from 1.0, since an Xcode
    String Catalog makes a second language cheap. The App Store copy is in
    both.

## Rules for every sprint

- **One sprint per session.** Scheduling is the owner's. When a measurement
  shows a rung is not needed, strike it from the plan with the evidence.
- **Tabber Studio sprints follow its `AGENTS.md` and guiding principles in
  full:**
  - new features in their own modules, no feature code in `ui/main_window.py`
    or `core/engine_bridge.py`
  - `git fetch` and read the reflog before starting and before pushing
  - preserve other people's uncommitted work
  - targeted tests only
  - never touch system audio
- **Headless first.** Every remote verb exists as a Control API verb, with a
  vector and a headless test, before any screen uses it.
- **No cost when off.** With the remote off, none of it runs or is imported.
  With it on, nothing it does reaches the audio thread.
- **Measure, don't guess.** Latency, host cost and alignment are measured and
  recorded in this plan, and the owner sets the limits. A check on the phone
  comes after the headless proof, not instead of it.
- **iOS rules:**
  - SwiftUI in the Swift 6 language mode.
  - No third-party packages without the owner's yes.
  - RemoteKit imports no UI framework.
  - Every screen has DemoHost UI tests.
  - Anything touching networking or audio is also checked on a device.
- **No cloud, no accounts, no analytics,** and no SDK that phones home.
- **Protocol changes ship with their vectors in the same commit,** here and in
  Tabber Studio's pinned copy.
- **Bulky build output** (DerivedData, archives) goes on the external work
  drive, as in Tabber Studio.
- **No em dashes** in documents or app text.

## Records

None yet. Each sprint adds its record here: the date, the commits in both
repositories, what was measured, and what changed in the plan.

## Sources

Collected 2026-11-06.

**Apple platform:**
- Local Network privacy: [TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)
- Moving from Multipeer Connectivity to Network framework, including TLS pinning: [TN3213](https://developer.apple.com/documentation/technotes/tn3213-moving-from-multipeer-connectivity-to-network-framework)
- Network framework with structured concurrency (`NetworkConnection`, `NetworkBrowser`): [WWDC25 session 250](https://developer.apple.com/videos/play/wwdc2025/250/)
- App Transport Security and local networking: [NSAllowsLocalNetworking](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking)
- Bonjour registration on the Mac: [DNS-SD registering](https://developer.apple.com/library/archive/documentation/Networking/Conceptual/dns_discovery_api/Articles/registering.html)
- SwiftUI and Liquid Glass: [WWDC25 session 323](https://developer.apple.com/videos/play/wwdc2025/323/), [HIG materials](https://developer.apple.com/design/human-interface-guidelines/materials), [HIG accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- Resizable iOS apps (WWDC 2026): [MacRumors forum report](https://forums.macrumors.com/threads/ios-27-hints-at-foldable-iphone-with-app-resizability-push-and-new-framework-strings.2483556/)
- Live Activities: [ActivityKit](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)
- Controls: [Controls across the system](https://developer.apple.com/documentation/widgetkit/creating-controls-to-perform-actions-across-the-system)
- Low-level networking on watchOS: [TN3135](https://developer.apple.com/documentation/technotes/tn3135-low-level-networking-on-watchos)
- App Store Review Guidelines: [guidelines](https://developer.apple.com/app-store/review/guidelines/)
- Phone audio: [measurement mode](https://developer.apple.com/documentation/avfaudio/avaudiosession/mode-swift.struct/measurement), [stereo capture](https://developer.apple.com/documentation/avfaudio/capturing-stereo-audio-from-built-in-microphones), [haptics during recording](https://developer.apple.com/documentation/avfaudio/avaudiosession/allowhapticsandsystemsoundsduringrecording)
- Continuity Camera microphone: [Apple support](https://support.apple.com/102546), [Mac Help](https://support.apple.com/guide/mac-help/mchl77879b8a/)

**Other platforms and libraries:**
- Windows DNS-SD: [DnsServiceRegister](https://learn.microsoft.com/en-us/windows/win32/api/windns/nf-windns-dnsserviceregister)
- Android discovery: [NsdManager](https://developer.android.com/reference/android/net/nsd/NsdManager)
- Python WebSocket server: [websockets](https://pypi.org/project/websockets/)
- Kotlin Swift export status: [Kotlin 2.4](https://kotlinlang.org/docs/whatsnew24.html)
- Tailscale and multicast: [Tailscale issue 1013](https://github.com/tailscale/tailscale/issues/1013)

**How others pair:**
- Syncthing: [device IDs](https://docs.syncthing.net/dev/device-ids.html)
- KDE Connect: [pairing notes](https://openwall.com/lists/oss-security/2020/10/13/4)

**Prior art:**
- [Logic Remote](https://apps.apple.com/us/app/logic-remote/id638394624) and [its troubleshooting](https://support.apple.com/en-gb/101940)
- [Cubase iC Pro](https://apps.apple.com/us/app/id573140262)
- [Studio Pro Remote](https://apps.apple.com/us/app/id988444520) and a [forum report](https://studiooneforum.com/threads/remote-app-no-longer-works-for-studio-one-v6.1787/)
- [Avid Control](https://apps.apple.com/us/app/avid-control/id1017075761) and [its fixes](https://www.production-expert.com/production-expert-1/problems-with-avid-control-app-or-the-older-pro-tools-control-app)
- REAPER: [web interface](https://reaper.blog/2016/12/whats-new-in-reaper-v-5-30/), [TouchOSC connection issues](https://reaper.blog/2012/06/reaper-touchosc-iphone-ipad-connection-issues)
- [touchAble Pro](https://apps.apple.com/us/app/touchable-pro/id1205967746)
- [R-KONTROL](https://apps.apple.com/us/app/id6443542725)
- [TouchOSC](https://apps.apple.com/us/app/touchosc/id1569996730)
- [Guitar Pro for iOS](https://apps.apple.com/us/app/guitar-pro/id400666114)
- AirDrop latency: [AWDL research](https://www.theregister.com/2025/10/23/apple_airdrop_awdl_latency_research/)

**Live audio over a network:**
- [SonoBus guide](https://sonobus.net/sonobus_userguide.html)
- [AudioRelay FAQ](https://audiorelay.net/docs/faq)
- [Ableton Link Audio](https://www.soundonsound.com/techniques/ableton-live-link-audio-wireless-future)
