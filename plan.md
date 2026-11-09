# Tabber Spak: plan

Status: planned 2026-11-06 and 07; building since 2026-11-07, when the owner
asked for TR0 to TR9 in one session. What each sprint did, and what it still
owes the owner, is in Records. Tabber Spak build 1 is in TestFlight. Sources:
Tabber Studio `main` at `1ecc4a79` (0.3.16), read for this plan, and web
research done the same days (links at the end). Tabber Studio changes often:
re-verify every reference before coding.

On 2026-11-07 the owner set a date: a demo at Pustervik on 24 November 2026.
The schedule and the demo cut are in The Pustervik demo. The toolchain and
library facts were checked again that day (Development setup).

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

The owner, 2026-11-07 (typing tidied): "I have a demo at a music tech fair at
Pustervik on 24 November. It would be cool to have an app by then. You know I
build fast with Claude and Codex." See The Pustervik demo.

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

**The phone is Tabber Studio's own views** (TR31). Three tabs named for
what they do, and Studio's transport (Stop, Play, Record, POS) in the tab
bar's accessory, in the same place on every screen:

```
+---------------------------------------+
|                       (o) Mac Studio  |   the computer: tap for its sheet
|  My Song                              |   the song
|  [ Loop ][ Count-in ][ Metro ]        |   Studio's transport toggles
|  To record, tap O on a track, then *  |   only while nothing is armed
|  [#] 1 Guitar          [S] [M] [O]    |   a card per track, as Studio's
|        Acoustic Guitar (steel)        |   Tracks panel; tap to choose
|  [#] 4 Vocals          [S] [M] [*]    |   armed: the input meter shows
|        ====================--         |
|  Takes                                |
|  [#] Vocals take 3, 42 s   [Delete]   |   one tap, with Undo
|  [ # ]  [ > ]  [ * ]      POS 25 : 1  |   transport, never moves
|   Tracks      Tab      Mixer          |   tab bar
+---------------------------------------+
```

**Screens:**

1. **Tracks (home):** as drawn above. S hears a track alone, M silences
   it; tracks left silent by a solo or mute dim.
2. **Take card:** after every take: Keep (the default, quiet), Delete (one
   tap, Undo for five seconds) and Go again, which stops if needed, returns
   to where the take started, uses the same count-in and records.
3. **Tab:** the chosen track's tab around the cursor, the note values, Dot,
   Triplet, Rest and Delete, Previous and Next, and Studio's fretboard or
   piano to write with. Undo at the top.
4. **Mixer:** Studio's strips: pan, S and M, a fader on the host's scale
   with its meter, the level; the buses and the master follow.
5. **Go to:** the start and the markers, from the transport's position.
6. **Computer:** the computer, the line, pairing again or forgetting it,
   keep awake, versions.
7. **Tuner (TR32), Tone (M5), Mic (M3), Routing and Chat (TR28, TR30):**
   later tabs and sheets.

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

## Development setup

Checked on the owner's Mac Studio (M1 Max, macOS 26.6.2) on 2026-11-07.

- **Xcode.** Xcode 26.3 is installed, from the Mac App Store, with only the
  iOS 26.2 Simulator runtime. It is what the owner ships with: GoPast
  (`historia`) builds 56 and 57 went to TestFlight from this Mac on 6 and 7
  November. The current release is Xcode 27.2 (29 October 2026, iOS 27.2 SDK,
  Swift 6.4.2). Xcode 27 needs macOS 26.6 or later, which this Mac has.
  - **Tabber Spak is built with Xcode 27.2,** installed next to 26.3 as
    `/Applications/Xcode-27.2.app` (the owner, 2026-11-07, on condition that
    historia is not affected). The app starts on the current SDK, so it never
    needs a migration, and the iPhone Duo layout needs the iOS 27.1 SDK or
    later (Known traps).
  - **Nothing else changes.** `xcode-select` stays on 26.3, which is what
    historia's `release-ios.sh` and Tabber Studio's `build_engine.sh` use.
    Only this repository's builds set `DEVELOPER_DIR` to 27.2.
  - **Updates cannot replace 26.3.** App Store app updates and automatic macOS
    installs are off on this Mac (checked 2026-11-07).
  - **The install is checked against historia.** Afterwards, historia must
    still archive with 26.3 the way its release script does (without the
    upload), as build 57 did before the install.
  - **Simulator runtimes:** iOS 26.2, with 26.3. iOS 27.2 and the iPhone Duo
    simulator, with 27.2.
- **Disk.** The internal disk has about 56 GB free; Xcode 27.2 and its
  runtimes take a large share of that, so the `.xip` is expanded on
  `/Volumes/Data`. DerivedData and archives go on the
  external drive (`/Volumes/Data` has 408 GB free).
- **Signing.** Apple Development and Apple Distribution certificates for Viga
  Works AB (team `VLBJ7VR4H8`) are in the keychain, and Xcode is signed in to
  the team. That is all a TestFlight upload from this Mac needs.
- **Releases copy historia's.** `historia/app/scripts/release-ios.sh` goes
  from the next build number to an uploaded build in one command. It checks
  git, archives with automatic signing (`-allowProvisioningUpdates`), and
  exports with `method` `app-store-connect` and `destination` `upload` through
  the account signed in to Xcode, with no API key. Then it tags `ios-b<N>`.
  Build output goes to `/Volumes/Data/<project>/xcode`. TR5 adapts it, without
  the Expo steps.
- **TestFlight.** Internal testers get every build without App Review, 5 to 15
  minutes after upload. Every phone sprint from TR5 on ends with an internal
  build on the owner's iPhone, not only TR9. A public link for external testers
  needs Beta App Review of the first build.
- **The Simulator loop.** The Simulator uses the Mac's network, so the app in
  the Simulator reaches Tabber Studio on the same Mac through `localhost` or
  Bonjour. Most of M1 can be built and tested on this one Mac. The device
  checks in the gates stay.
  - **No camera:** pair by delivering the QR code's link with
    `xcrun simctl openurl booted 'tabber-remote://pair?...'`. The link comes
    from `remote.pair` through the Control API.
  - **No Secure Enclave:** RemoteKit uses a software P-256 key in the
    Simulator only (`#if targetEnvironment(simulator)`).
  - **No haptics and no Local Network prompt.**
- **The iOS API exists.** The iOS 26 SDK has what RemoteKit needs:
  `NetworkConnection` with a `WebSocket { TLS() }` stack, `TLS`'s
  `certificateValidator` for pinning the Mac's key, and `WebSocket`'s
  `subprotocols` and `maximumMessageSize`. Checked in Xcode 26.3's iPhoneOS
  26.2 interface file.
- **Python libraries** (PyPI, 2026-11-07): websockets 17.4, cryptography
  50.0.2, segno 1.6.6 (pure Python). None is in Tabber Studio's venv yet
  (Python 3.14.8, PyInstaller 6.21.0, cffi 2.0.0).
- **Android.** Nothing is installed: no Android Studio, SDK or `adb`. None is
  needed before TR24. Google Play has required target API 36 for new apps and
  updates since 31 August 2026.

## Known traps

**Phone:**
- **Test Local Network privacy on a device.** The Simulator does not enforce
  it.
- **The Simulator has no Secure Enclave and no camera.** Use the software key
  and `simctl openurl` there (Development setup). The software key path never
  runs on a device.
- **iPhone Duo moves the bars.** Built with the iOS 27.1 SDK, tab bars and
  toolbars run vertically along the side of the display in some poses. The
  transport lives in the tab bar's bottom accessory and must never move
  (principle 5), so TR7 checks it in the iPhone Duo simulator. From April
  2027, App Store submissions need iPhone Duo screenshots (TR9).
- **iOS 27 SDK uploads need a launch screen key,** or App Store Connect
  rejects them (ITMS-90870). They also need the scene life cycle, which a
  SwiftUI `App` already has.
- **A WebSocket needs a `wss://` URL endpoint.** Given a bare host and port,
  the Network framework's WebSocket client (`NetworkConnection` and
  `NWConnection` alike) aborts right after the TLS handshake with
  `ECONNABORTED`, before it sends its upgrade request (found in TR5's
  interop test). A Bonjour result is resolved to an address first: TR6 opens
  a short TCP connection to it, IPv4 first, and reads the address it reached.
- **A connection that cannot connect waits and retries.** `receive()` fails
  at once, but `send()` waits forever and `close()` never returns; only
  releasing the connection cancels it. RemoteKit times out every call and
  lets such connections go.
- **A SwiftUI `Label`'s accessibility identifier lands on its icon and its
  text,** and a UI test's first match is the icon. Put the identifier on the
  `Text` (found in TR6).
- **`swift test` holds a test's output until the process exits,** so a hung
  test shows nothing. Write to a file and kill the process to read it.
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
- **Xcode 27 removes the ld64 linker.** Tabber Studio's engine build and
  historia's release script use `/Applications/Xcode.app` through
  `xcode-select`. Keep Xcode 26.3 there until each moves in a sprint of its
  own.
- **cryptography ships no Intel macOS wheel after 48.0.1** (June 2026), and
  Tabber Studio still ships an Intel beta (`release/locks/macos-x86_64.txt`).
  TR2 pins a version both architectures can use, or builds it for Intel.

**Network:**
- **Tailscale and most VPNs carry no multicast,** so Bonjour fails there: use
  the typed address.
- **Discovery breaks** on guest networks, VLANs, access-point isolation and
  across some mesh nodes. Wi-Fi Assist moves the phone to cellular.
- **AirDrop's AWDL link** causes latency spikes. Measure p95 with it on.
- **Fair and venue Wi-Fi** is usually a guest network with client isolation.
  The phone then cannot reach the computer at all, so bring your own router.

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

## The Pustervik demo, 24 November 2026

The owner shows Tabber Spak at a music tech fair at Pustervik on Tuesday
24 November 2026, 17 days after 7 November. The demo is S1 and S2 on stage.
The gates are not relaxed for it; the scope is. A demo that fakes state, such
as a red light the computer did not confirm, breaks principle 3. The demo shows
the real thing or drops the step.

### What the room sees

Rewritten 2026-11-07 for the app in Tabber Studio's shape (TR31). The core
is about four minutes; each optional moment adds under a minute, and the
owner picks which go on stage.

1. **Pair.** In Tabber Studio, Preferences > Remote: tick "Let paired phones
   control Tabber Studio" and click Pair iPhone. Scan the code in Tabber
   Spak. The phone opens on the song's tracks.
2. **Record from across the room.** Walk away from the computer. On the
   phone:
   - tap ○ on the guitar track (its input meter moves);
   - tap the position and choose Chorus in Go to;
   - turn Count-in on and press ●.
3. **Go again.** Press ● to stop, and the take card rises. Delete (one
   tap), then Undo in the banner: the take is back. Go again: count-in,
   record, stop, Keep.
4. **One undo history.** Delete the take, then Undo on the computer. The
   take comes back on both.
5. **Drop the Wi-Fi.** Record again and take the phone off the Wi-Fi mid-take.
   The computer keeps recording and the phone says Reconnecting. Back on the
   Wi-Fi, the phone shows the true state: still recording, with the right
   time. Stop.

**Optional moments,** the owner's pick:
- **Write a riff from the floor.** On the Tab tab, tap frets on the phone's
  fretboard. Each beat plays on the computer, the computer's Tab view fills
  in as the phone writes, and Next moves on.
- **Mix from the floor.** On the Mixer tab, S on the guitar to hear it alone,
  then pull the drums down. The computer's faders move with the phone's.
- **Tune up on stage.** On the Tuner tab, play the low E. The note turns
  teal in tune. It works with no computer at all.

The old step 6, "hold Chorus to loop it", left with the marker row. The Loop
toggle loops the range set on the computer.

### The demo cut

**In** (the S1 and S2 path):
- QR pairing with pinned TLS, the one-time token and the device key. Principle
  2 is not cut for a demo, and one scan is the demo's first surprise.
- Reconnecting by itself: Bonjour, plus the addresses from the QR code.
- The Tracks screen, the transport and the take card (TR31): choosing and
  arming a track, its meter, S and M, count-in, metronome, loop, Go to,
  Keep, Delete with Undo, Go again, the takes list, haptics, keep awake.
- For the optional moments: the Tab screen with the fretboard and the piano
  (TR15), the Mixer (TR25), the Tuner (TR32). Each is in only once it has
  passed on a device against Tabber Studio 0.3.17.
- The true state after a drop.
- On the computer: Settings › Remote with on and off, the QR dialog, paired
  devices with Remove, and activity notices.
- DemoHost. The tests need it anyway, and it is the stage fallback.

**Before the stage freeze on 19 November,** in this order (the owner,
2026-11-07: "we have time to build stuff"):
1. Take lanes for passes (TR33, done 7 November).
2. Routing (TR27, TR28, done 7 November).
3. Chat (TR29, TR30, done 7 November).

From the freeze to the summit: rehearsal and fixes only.

**After the demo,** still in 1.0:
- the 6-digit fallback, several computers, and every fix-it card except "Can't
  reach your computer" and "Update Tabber Studio"
- Settings
- App Store submission (languages wait for the owner, decision 17): moved
  before the demo by the owner on 2026-11-08, as TR37 and TR38

**Stretch,** only if every demo gate is green by 19 November:
- the Action Button starts and stops a recording (TR10)
- practice speed (S6), whose verb exists but which has no control yet

TR0 still specifies all of M1, not only the cut, so the work after the demo
needs no protocol change.

### One builder, in turns

The owner's choice (decision 19): one builder works both repositories, one
sprint at a time. The order alternates so that each sprint is tested against
the one before it, and the phone has a real host to talk to as early as
possible. The dates are targets.

| Date | Sprint | Where | Checkpoint |
|---|---|---|---|
| Sat 7 Nov | planning | this repo | this plan |
| Sun 8 | TR0 | this repo | every vector validates |
| Mon 9 | TR1 | Studio | the TR1 gate, headless |
| Tue 10 | TR5 | this repo | an internal TestFlight build on the owner's iPhone, running DemoHost |
| Wed 11 to Thu 12 | TR2 | Studio | the M1 vectors pass against a headless Tabber Studio; then TR5's device check against this host |
| Fri 13 | TR3 | Studio | feed values equal the Control API's read-backs |
| Sat 14 to Sun 15 | TR7, TR8 (demo parts) | this repo | the Simulator runs S1 against Tabber Studio on this Mac |
| Mon 16 to Tue 17 | TR4 (demo parts); the signed Tabber Studio build with the remote | Studio | QR pairing with the signed, installed app |
| Wed 18 | TR6 (demo parts) | this repo | S1 and S2 on the owner's iPhone over the travel router |
| Thu 19 to Fri 20 | hardening: TR3's stress test, TR7's latency, fixes | both | every demo gate green; stretch only then |
| Sat 21 to Mon 23 | freeze: fixes only; rehearsals | both | three full rehearsals on the stage setup |
| Tue 24 | the demo | | |

There is no slack. When a sprint runs late, the stretch items go first, then
demo-script steps from the end of the script. A gate is never relaxed.

### The demo part of each sprint

| Sprint | In the demo | After the demo |
|---|---|---|
| TR0, TR1, TR2, TR3, TR5, TR7 | all of it | |
| TR4 | Bonjour advertising, both Info.plist keys, Settings › Remote, the QR dialog, paired devices with Remove, activity notices, the connected-phone indicator | the 6-digit fallback with Allow |
| TR6 | Welcome, Find your Mac, the QR scanner, reconnecting after an address change, "Can't reach your computer" and "Update Tabber Studio" | the 6-digit fallback, several computers, the other fix-it cards |
| TR8 | the take card, choosing the armed track | the takes list with ratings, the Tracks screen; flag a moment is stretch |
| TR9 | a first app icon, made in TR5 | everything else |

The demo part of a sprint passes the gate items for what it contains.

### The next two sprints in detail

**TR0, Sunday 8 November, this repository.**
- **`protocol/spec.md`,** the Tabber Remote Protocol v1:
  - transport: WebSocket over TLS 1.3, subprotocol `tabber-remote.v1`, JSON-RPC
    2.0 in text frames; binary frames reserved for audio (M3)
  - the connection in order: pinned TLS, `hello`, then `pair` or `auth`, then
    `session.subscribe`, the snapshot, events, heartbeats, close codes
  - pairing, exact to the byte: the QR link, the key hash (SHA-256 of the Mac's
    DER SubjectPublicKeyInfo, base64url without padding), the device key's
    encoding, the bytes the device signs, the signature encoding, and the
    6-digit code
  - every M1 verb: parameters, result, errors, idempotency, capability, and the
    Control API calls it maps to
  - the snapshot and the event topics, with sequence numbers and host time
  - error codes, each with a sentence a musician can read
  - versioning, capabilities and limits (frame size, rate limits)
- **The M1 vocabulary,** exactly these verbs:
  - connection: `hello`, `pair`, `auth`, `session.subscribe`,
    `session.unsubscribe`, `session.snapshot`, and the `heartbeat`
    notification
  - transport: `transport.play`, `transport.stop`, `transport.record`,
    `transport.seek`, `transport.set_loop`, `transport.set_click`,
    `transport.set_count_in`, `transport.set_tempo_scale`
  - tracks: `tracks.arm`, `tracks.select`, `tracks.set_monitor`
  - markers: `markers.go`, `markers.loop`, `markers.add`
  - takes: `takes.list`, `takes.discard`, `takes.go_again`, `takes.rate`
  - edits and the project: `edit.undo`, `edit.redo`, `project.save`
- **Two rules the spec settles:**
  - **Undo names the step it expects.** If the newest undo step on the
    computer is a different one, the host refuses and says so. An Undo on the
    phone can never undo someone else's edit (principle 3).
  - **Heartbeats are protocol messages,** not WebSocket pings, so the remote
    thread can report "Tabber Studio is busy" in them.
- **`protocol/schemas/`:** one JSON Schema (draft 2020-12) per message.
- **`protocol/vectors/`:**
  - `hello`, when versions match and when they do not
  - the pairing hashes and codes, computed from fixed test keys, and a signed
    challenge
  - each verb's exchange, and the errors
  - an event sequence with a gap, followed by the new snapshot
- **`tools/validate_vectors.py`:** checks every vector against its schema and
  recomputes every hash and signature. Its packages (`jsonschema`,
  `cryptography`) live in a venv for this repository's tools only.

**TR5, Tuesday 10 November, this repository.**
- **`apple/TabberSpak.xcodeproj`:**
  - iOS 26 minimum, Swift 6 language mode
  - automatic signing for team `VLBJ7VR4H8`
  - built with Xcode 27.2 through `DEVELOPER_DIR`, with build output in
    `/Volumes/Data/tabber_remote/xcode`
- **`apple/RemoteKit/`,** a Swift package that imports no UI framework:
  - models generated by hand from the schemas
  - the connection: `NetworkConnection` with `WebSocket { TLS() }` and the
    pinning validator
  - `hello`, reconnect, idempotent resend, heartbeats
  - the device key: the Secure Enclave on a device, a software key in the
    Simulator
- **DemoHost,** a simulated Tabber Studio inside RemoteKit that follows the same
  vectors.
- **Tests:** `xcodebuild test` runs every vector in Swift, plus the DemoHost
  session tests.
- **On the phone:** a first app icon, a debug screen, and the first internal
  TestFlight build on the owner's iPhone, uploaded by
  `apple/scripts/release-ios.sh` (adapted from historia's, with
  `DEVELOPER_DIR` set to Xcode 27.2).
- **TR5's device check against TR2's host** runs right after TR2, since TR2
  now comes later.

### Before the next session (the owner)

- **Download Xcode 27.2** (`Xcode_27.2.xip`) from developer.apple.com, signed
  in with your Apple ID. The rest of the install and the historia check happen
  in a session.
- **Reserve the app:** done 2026-11-07. App Store Connect has "Tabber Spak"
  (Apple ID 6831855493, bundle id and SKU `studio.tabber.spak`), and build 1
  is uploaded. If there is no internal TestFlight group yet, add one with
  automatic distribution, with yourself in it, then install build 1 from the
  TestFlight app.
- **Get a small travel router** with an Ethernet port.
- **Decide how the room sees the phone** (The stage setup).

### The stage setup

- **The stage Mac is this Mac Studio** (the owner, 2026-11-07). Development,
  the signed build and every rehearsal happen on the machine that goes on
  stage. At the venue it needs a screen (a monitor or the venue's projector),
  a keyboard and mouse, and the audio interface.
- **Bring a small travel router.** The Mac Studio joins it by Ethernet, and
  only the phone uses its Wi-Fi. It needs no internet. The venue's Wi-Fi is
  the most likely thing to fail (Known traps).
- **On the phone:** AirDrop receiving off, no VPN, Wi-Fi Assist off, fully
  charged, keep awake on.
- **Fallbacks, in order:** the remembered address; DemoHost, clearly labelled
  Demo; a screen recording of a rehearsal.
- **Rehearse on the stage hardware:** the same Mac, iPhone and router, and the
  signed builds that will be used on the day.
- **Open: how the room sees the phone.** The phone's screen in QuickTime over a
  long USB-C cable (a cable takes something away from "across the room"), a
  camera on the phone, or only the computer's screen reacting. The owner
  decides.

### Risks

- **Tabber Studio internals.** Arming an audio track is UI-only today, and
  discard and go again do not exist yet (TR1). TR1 goes first. If a verb runs
  late, the demo script loses that step; the gate stays.
- **Packaging.** websockets, cryptography and segno must go into the frozen,
  signed app with two new Info.plist keys, and the Local Network prompt shows
  only in the signed app. Hence the signed build by 18 November.
- **The development Mac is the stage Mac.** An update or a half-finished
  experiment on it in the last days can break the demo. Updates stay off, and a
  known-good signed build of each app stays installed from 20 November.
- **One builder.** Every slip moves everything after it. The cut order
  handles it (One builder, in turns).
- **Xcode.** Two versions side by side: Tabber Spak on 27.2, everything else
  on 26.3 (Development setup).
- **The venue's network.** The travel router.

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
| TR1 | Remote-ready verbs: `recording.arm_audio_track`, `markers.list`, `markers.go`, `markers.add`, `takes.discard`, `takes.go_again`, stable ids, undo step ids (`project.undo` and `project.redo` take `expect`), the compact `session.snapshot` | Studio | Headless through the shared dispatcher, read back from the model and the engine: arming by verb equals the UI path; discard then undo restores the take, and its file is untouched on disk; go again makes a new take at the right start; markers match `tabs.list_measures` |
| TR2 | Remote host core: `remote_host/` server, identity, pairing tokens, device keys and challenges, vocabulary, bridge, limits, logging; `remote.enable`, `disable`, `status`, `pair`, `devices`, `revoke` | Studio | The M1 vectors pass against a headless Tabber Studio; each of these is refused: a wrong key, a wrong or expired token, a replayed challenge, an oversized frame, an unknown verb, a raw Control API method; with the remote off, no socket listens and `remote_host` is not imported (the MP13 import check extended); the frozen app contains the package and its dependencies; bundle growth recorded |
| TR3 | State feed: snapshot, changes, sequence numbers, heartbeats, busy state, rate limits | Studio | Feed values equal the Control API's read-backs; a 10-minute playback and recording stress test with two clients at full rate has zero dropouts; main-thread time per tick and CPU change recorded here |
| TR4 | Discovery and the computer's side of pairing: Bonjour advertising (DNS-SD through ctypes), both Info.plist keys in the macOS spec, Settings › Remote, the QR dialog, paired devices, the 6-digit fallback with Allow, activity notices, a connected-phone indicator | Studio | `dns-sd -B _tabber-remote._tcp` sees the service only while the remote is on; a scripted client pairs from the QR payload and through the 6-digit path; Remove disconnects at once; on the signed, installed app (owner warned first, since it opens a window on the owner's screen): the Local Network and firewall prompts, and QR pairing still works with Local Network denied |
| TR5 | Xcode project; RemoteKit (models, Network framework connection with pinning, hello, reconnect, idempotent resend, heartbeats); DemoHost, a simulated session inside the app | this repo | `xcodebuild test`: every vector passes in Swift; the DemoHost session tests pass; a debug screen on a real iPhone connects to TR2's host by address |
| TR6 | Welcome; Find your Mac (an explainer, then browsing); QR scanner; 6-digit fallback; several computers; fix-it cards for Local Network off, VPN, guest Wi-Fi, firewall, Tabber Studio closed, version mismatch | this repo | On a device: fresh install to paired with one scan; each fix-it card reached by recreating its cause; reconnects by itself after the computer's address changes, within the target |
| TR7 | Session screen: transport in the bottom accessory, time in bars and beats, section, armed track and meter, count-in, click and loop, marker chips, recording frame, haptics, keep awake | this repo | UI tests against DemoHost for every control; on a device against Tabber Studio: S1 up to the take card, and S2; tap-to-confirmed latency p50 and p95 with AirDrop on and off, recorded here |
| TR8 | Take card (keep, discard with hold and Undo, go again), takes list with ratings, Tracks screen (arm, monitor, select), flag a moment | this repo | S1 complete on a device: five takes, two discarded, one brought back with Undo on the computer, files intact, nothing on the computer touched during the run |
| TR9 | Polish and TestFlight: design pass, icon, accessibility audit, Dynamic Type at the largest sizes, a VoiceOver run of S1, demo mode for App Review and screenshots, privacy label (Data Not Collected), privacy page, export compliance, checks against a Tabber Studio without the remote | this repo, website | The TestFlight build runs S1 on the owner's phone; the XCUITest accessibility audit passes; a too-old Tabber Studio is explained in plain words; the owner decides when to submit |

### The mixer, routing and chat (asked for 2026-11-07)

The owner, during TR9: "the chat would be good to have in the app as well. so
you can use the control api via the chat?" and "the mixer and routing as
well." Tabber Studio already has the verbs underneath: `mixer.*` (strips,
volume, pan, mute, solo, master gain, peak levels), `buses.*` (buses, their
gain, pan, mute and solo, routing, sends, sidechains, `routing_overview`,
`would_cycle`) and the chat's pipeline (`ai.execute_command`, which plans
from text and runs the plan only when told to, as the chat bubble's Confirm
does). As in TR1, the remote wraps them in its own verbs and never exposes
them raw.

| # | Sprint | Where | Gate |
|---|---|---|---|
| TR25 | Mixer verbs and the `mixer` topic: a strip for each track and bus and the master (name, colour, volume in dB, pan, mute, solo), `mixer.set_volume`, `set_pan`, `set_mute`, `set_solo` and `set_master`; a fader drag is one undo step (the phone marks the gesture's start and end); meters for every strip, only while a phone has the mixer open | spec, Studio | Vectors; every change equals the Control API's read-back; a drag of 50 changes is one undo step; the feed's cost with the mixer open, recorded |
| TR26 | Mixer screen: strips for tracks and buses and the master, with fader, pan, mute, solo and meter in Tabber Studio's mixer colours; a tapped strip opens a long-throw fader for fine moves; faders adjustable with VoiceOver | this repo | UI tests against DemoHost; on a device, a fader move confirmed within the latency target |
| TR27 | Routing verbs and the `routing` topic: each track's output (the master or a bus) and its sends (bus, level, pre or post); `routing.set_output`, `routing.set_send`, `routing.remove_send`; a cycle is refused in words (`buses.would_cycle`) | spec, Studio | Vectors; read-backs; a refused cycle leaves the routing unchanged |
| TR28 | Routing screen: for each track its Output and its Sends, and for each bus what feeds it; a send's level as a slider. A list, not the Flow graph: it must work with one thumb | this repo | UI tests against DemoHost; on a device against Tabber Studio |
| TR29 | Chat on the computer's side: `chat.send` (text in, the plan out, in the words the chat bubble shows), `chat.confirm`, `chat.cancel`, and the `chat` topic (messages, thinking, results). The planner runs off the main thread. The same reach, flow and undo as the chat in Tabber Studio (decision 21) | spec, Studio | A typed request becomes the same plan the computer's chat makes, and nothing runs until Confirm; the confirmed plan is one undo step, and Undo on the phone takes it back; every chat action is logged like other remote actions; **adversarial:** asking the phone's chat for the API key, the settings file, the remote's keys, an environment variable, a shell command or a file outside the song is refused, and no frame sent to the phone in the whole suite contains the test API key or any device or pairing key (scanned byte by byte); 11 requests in a minute, the 11th is refused |
| TR30 | Chat screen: the conversation, the plan with Confirm and Cancel, and the keyboard's dictation for speaking a request; Face ID, Touch ID or the passcode before it opens | this repo | UI tests against DemoHost with a scripted planner; on a device against Tabber Studio; the Chat screen does not open without the device owner's authentication |

Order: the mixer first (done, TR25), then take lanes (TR33), routing and
chat, all before the stage freeze on 19 November (The demo cut).

| # | Sprint | Where | Gate |
|---|---|---|---|
| TR33 | Take lanes for passes (decision 20), before the stage freeze: a linear pass over an earlier one on the same track joins it in take lanes, as loop recording does. The newest plays; the take loop's Delete and Go again work on lanes; the phone's takes list shows which take plays | Studio, this repo | Headless: three passes over one bar give three lanes, only the newest audible, each one undo step; Undo and Redo keep the lanes; loop recording is unchanged (its tests stay green); S1 on a device |

### Asked for 2026-11-08

The owner chose practice speed as the first stretch item ("Practice speed
first"), while the iPhone runs are still owed, then asked for tracks: "if
it's an all audio file song, then the app should be able to add tracks. or
actually add tracks, midi or tab or audio tracks at will to a project. so
that's something to do."

Then the App Store, sooner than "after the demo": "we need to app store for
tabber spak too soon right? because later when we have gone through
security checks, that the app can't be used for hacking and that tabber
studio doesn't expose the user's data... and that all my api keys are safe
and no trace of anything from my computer in the release... like my
personal info or my api keys... they have to use their own api keys...
when it's all safe... then we should have a link to app store and the
app." So TR37 checks both releases, and TR38 submits and links. Submitted
by about 14 November, App Review has time to finish before the 19 November
freeze, so visitors at Pustervik can install Tabber Spak from the App Store.

| # | Sprint | Where | Gate |
|---|---|---|---|
| TR35 | Practice speed: Tabber Studio's Speed Trainer from the phone (S6), `trainer/1`; Loop set from anywhere shows and stops the trainer as a click does | spec, Studio, this repo | Vectors; the phone sets the computer's own Trainer button and fields, read back from the bar and the engine; refused with Loop off; Loop off turns it off; UI tests and the accessibility audit, the largest text included |
| TR36 | Add tracks from the phone: a tab, MIDI or audio track, as Tabber Studio's "+ Add Track" makes each | spec, Studio, this repo | Headless: each kind equals "+ Add Track"'s, one undo step that Undo on the phone takes back; in an all-audio song, a tab track added from the phone takes tab at once; UI tests against DemoHost |
| TR37 | Release safety, before the App Store: nothing of the owner's in either release, each user's own AI key, and a remote that can do only its vocabulary | Studio, this repo | The IPA and the Studio app and DMG hold no API key, token, private key, name, email, home path or file from this Mac: scanned byte by byte for key shapes and, on this Mac, for the owner's own values without printing them; a fresh Studio has no AI key and the chat asks for the user's own; a protocol fuzz run against a headless Studio finds no crash and no way to a file, setting, script or key; the TR29 adversarial tests pass on the release build |
| TR38 | Tabber Spak on the App Store, then its link on the Tabber website and in Studio's Preferences > Remote | this repo, App Store Connect, website, Studio | Version 1.0 in App Store Connect: description, keywords, screenshots, the privacy label (Data Not Collected), privacy and support URLs, export compliance, review notes that explain demo mode; the owner presses Submit for Review; once approved, the App Store link and a QR code to it on the website and in Preferences > Remote |

The owner, after trying build 12 with 0.3.24 ("wow! the app is great now,
good job"): "i still miss add bus, the routing flow thing, and tabbing in
midi tracks. when adding a midi track, in tab mode, tabber asks for show
midi or show notation right... can we make that selection from the app
too? just so it's not stuck on that screen in tab mode on a midi track and
you have to go to the computer and click on it manually on the computer?"

| # | Sprint | Where | Gate |
|---|---|---|---|
| TR39 | A MIDI track in the Tab view: Studio's own "MIDI part" card on the phone, "Show MIDI tab" and "Show standard notation" doing there what they do on the computer, so the computer is never left on the card | spec, Studio, this repo | Headless: each choice shows on the computer as a click on the card does, read back; the phone shows the card whenever the computer does; UI tests against DemoHost |
| TR40 | Tab on MIDI tracks: with MIDI tab shown, the phone's fretboard and piano write on a MIDI track as Studio's MIDI Tab does, each edit one undo step | spec, Studio, this repo | Headless: a fret from the phone is the note Studio's MIDI Tab writes, at the same string and fret, one undo step; the instrument is untouched; UI tests |
| TR41 | Add Bus from the phone, as the mixer's "+ Bus" makes it: Studio asks for its name first | spec, Studio, this repo | Headless: the bus equals "+ Bus"'s, named as typed; not an undo step there, nor here; it shows in the phone's Mixer and Routing at once; UI tests |
| TR42 | The routing Flow view on the phone: Studio's Flow tab, tracks through buses to the master | this repo, Studio if a read is missing | The phone draws what Studio's Flow tab draws for the same song, checked against Studio's own flow model; readable at the largest text; UI tests and the accessibility audit |
| TR43 | Wiring by hand in the phone's Flow, as Studio's Flow does it, and the computer's master fader following the phone | this repo, Studio | UI tests: a track's output to a bus and back, a send made by dragging and taken away from the card's menu, a looping bus refused in Studio's words; the accessibility audit; headless: the master strip follows mixer.set_master_gain and project.set_properties |
| TR44 | Plug-ins on the phone's mixer strips: each strip's INSERTS as Studio's strip lists them, its "+ Plugin" opening Studio's Insert Plugin browser, and a slot's Open UI, Bypass and Remove | spec, Studio, this repo | Protocol 1.10 (plugins/1) with a vector of all five verbs; headless: the browser's rows and paging, the browser's own insert on the strip's chain, the strip menu's own Bypass and Remove, refusals in Studio's words, no undo steps; UI tests and the accessibility audit; a real insert on the owner's Mac |

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
   - bundle id: **decided, `studio.tabber.spak`** (the owner, 2026-11-07).
     Tabber Studio is `studio.tabber.app`. A bundle id can never change once
     the app exists in App Store Connect.
   - the home-screen label "Tabber Spak"
   - Bonjour type `_tabber-remote._tcp`, registered with IANA
   - "Tabber Spak" looks free: an App Store search on 2026-11-07 found no app
     by that name. Creating the App Store Connect record is what reserves it:
     **done 2026-11-07** (Apple ID 6831855493).
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
17. **Languages.** Decided (the owner, 2026-11-07: "wait with other
    languages"): English only for now. Swedish and others come when the
    owner says. Until then, keep every string in one place so an Xcode
    String Catalog can take them later.
18. **The Pustervik demo.** Default: a stage demo of S1 and S2 on the owner's
    devices, from the demo cut. Open: whether visitors can join a public
    TestFlight beta that day. That needs Beta App Review and a Tabber Studio
    build with the remote that visitors can download.
19. **Who builds the Tabber Studio side.** Decided (the owner, 2026-11-07): one
    builder works both repositories, in turns (One builder, in turns).
20. **Recording over a kept take.** In Tabber Studio a linear recording is a
    plain clip, so recording again over a kept take leaves both audible (TR1
    record). Decided (the owner, 2026-11-07, "do what you recommend"):
    - **Yes:** a new pass over an earlier one on the same track builds take
      lanes, as loop recording already does. The newest pass plays and the
      earlier ones wait in their lanes, ready to audition and comp.
    - **Before the summit (TR33):** the owner, 2026-11-07: "there's a long
      time to music tech summit" and "we have time to build stuff". It
      changes Tabber Studio's recording for every user, so it gets its own
      sprint and its tests, done before the stage freeze on 19 November.

21. **Chat on the phone.** The remote's own verbs rule out raw Control API
    methods. The chat reaches the whole Control API through Tabber Studio's
    planner. Decided (the owner, 2026-11-07): "the chat should be able to use
    the control api just like in tabber studio". So the phone's chat is
    Tabber Studio's chat:
    - **Same reach:** the whole Control API, through the same planner.
    - **Same flow:** the plan is shown on the phone, and Confirm runs it, as
      the chat bubble's Confirm does.
    - **Same undo:** the confirmed plan is one undo step, as a chat turn is
      on the computer.
    - **No separate setting:** it is there whenever the remote is on, since
      pairing already decides which phones get in.
    - **Logged:** every chat action is logged on the computer like the
      remote's other actions.

    **Safe** (the owner: "but we must make it safe, so no hackers steal api
    keys or other shit"). These are hard requirements of TR29 and TR30.
    - **Secrets never leave the computer.**
      - The AI provider's API key, the remote's own keys and tokens, and the
        paired devices' keys are never sent to a phone, by any verb, event,
        plan or result.
      - The planner and its API key run on the computer only. The phone
        sends words and gets words back.
    - **Two locks on secrets:**
      - (a) On a phone's turn, the planner refuses the few Control API
        methods that read secrets or reach outside Tabber Studio: the AI
        provider settings and key, the remote's pairing, devices and keys,
        environment variables, shells and scripts, and files outside the
        song's own folder. The refusal is in words, before anything runs.
      - (b) Everything the chat sends a phone passes a filter that blanks
        anything that looks like a secret: fields named key, token, secret
        or password, and values shaped like API keys or private keys.
    - **No cost runaway:** chat requests from phones are rate limited (10 a
      minute), so a stolen phone cannot run up the AI bill.
    - **The phone guards its Chat:** Face ID, Touch ID or the passcode
      before the Chat screen opens, so an unlocked phone left on a stand
      cannot use it.
    - **The computer sees and stops it:**
      - Every chat request and action is named in Tabber Studio's
        activity notices.
      - Remove in Settings › Remote disconnects that phone at once.
      - Turning the remote off stops all of it.
    - **What already holds** (TR2 to TR6):
      - local network only, nothing in any cloud;
      - TLS 1.3 with the computer's key pinned;
      - each phone's own key in the Secure Enclave, with signed,
        single-use challenges;
      - pairing only by the QR code shown on the computer's screen, single
        use, valid for five minutes;
      - rate and size limits on every message;
      - the remote off until it is turned on.

22. **Light mode.** Decided (the owner, 2026-11-07, "do what you
    recommend"): dark only for 1.x. The phone is a studio and stage tool,
    used in dark rooms, so it keeps one look, well tested. It can be
    revisited when people ask.

23. **A numbered Tabber Studio release with the remote.** Decided (the
    owner, 2026-11-07, "do what you recommend"):
    - **The release:** 0.3.17, with the render-certified engine (abc7bd5e),
      the release locks for the remote's packages, and its release notes.
    - **Here:** built, signed, notarized and installed on this Mac.
    - **Published** (website, download) only on the owner's go, since that
      is public.
    - **Done 2026-11-07:**
      - Built from Tabber Studio 5f82110a.
      - Its engine is byte for byte the certified abc7bd5e once signatures
        are removed.
      - Signed, notarized and stapled; Gatekeeper accepts the app and the
        DMG.
      - The frozen-app smoke test passes 12 of 12: protocol 1.1 with
        `mixer/1` and `tab/1`, TLS 1.3 with the pinned key, every module
        from the bundle.
      - Installed in /Applications, with the original 0.3.16 kept beside it.
    - **For publishing:** the DMG has the plain layout, since the branded
      one drives a Finder window, and the website's 0.3.17 page is not made
      yet.

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

Each sprint adds its record here: the date, the commits in both repositories,
what was measured, and what changed in the plan.

- **2026-11-07, planning.** The owner set the demo date. Development setup,
  The Pustervik demo and new Known traps were added after checking this Mac
  and the web. Tabber Studio `main` was still at `1ecc4a79`, so the references
  above stand. Its working tree held someone's uncommitted changes
  (`control_api/handlers/buses.py` and two plans), left untouched.
- **2026-11-07, the owner:** "do the first 10 subsprints. commit and push
  after each". In the owner's projects a subsprint is one session's work, as
  each TR sprint is here, so TR0 to TR9 run in this session in the order of
  One builder, in turns, each committed and pushed. ✅ marks a sprint whose
  gate is met; 🟡 marks one whose remaining items need the owner's iPhone, the
  signed app or the owner's eyes, listed with it.
- **TR0 ✅ 2026-11-07, this repository.** `protocol/spec.md` (Tabber Remote
  Protocol 1.0), 41 JSON Schemas in `protocol/schemas/` plus the error table,
  13 exchange vectors and 4 crypto vectors in `protocol/vectors/`,
  `tools/validate_vectors.py` and `tools/test_validate_vectors.py`.
  - **Gate:** every vector validates against its schema, and together they use
    all 27 verbs, 9 event topics and 29 errors. Ten mutation tests prove the
    validator catches what it claims to: a wrong signature, an unmarked `seq`
    gap, a changed error message, three failures without a close, a resent key
    answered differently, an unknown field, a verb before authentication, a
    wrong pin or pairing code, missing coverage. Two of them failed at first
    and fixed the validator.
  - **Decided in the spec:** port 9474 when free; bars and beats count from 1
    (the host converts); `auth.begin` and `auth.prove` became one `auth`, with
    the challenge in `hello`'s answer, to save a round trip on every
    reconnect; edits name their targets, including the armed tracks for
    Record and the undo step for Undo; heartbeats carry `seq`, so lost events
    show even when nothing changes; a request refused before it ran keeps no
    idempotency key. `nothing_armed` and `not_recording` were dropped: no
    1.0 verb can produce them.
  - **For TR1:** undo step ids, and `project.undo` and `project.redo` with
    `expect`; a `session.snapshot` Control API verb, besides the verbs already
    listed.
  - **Crypto vectors are reproducible:** test keys derive from fixed strings
    and signatures use RFC 6979, so `tools/make_crypto_vectors.py` leaves
    `git diff` empty. Tools run from `.venv` (`tools/requirements.txt`).
- **TR1 ✅ 2026-11-07, Tabber Studio `e6545ccf`.** Nine Control API verbs, each
  on the path the mouse takes: `recording.arm_audio_track`, `takes.passes`,
  `takes.discard`, `takes.go_again`, `takes.rate_pass`, `markers.list`,
  `markers.go`, `markers.add`, `session.snapshot`; `project.undo` and
  `project.redo` take `expect`.
  - **Gate:** `tests/remote/test_tr1_remote_verbs.py`, 16 tests through the
    shared dispatcher on a real MainWindow (the engine faked only where it
    would open a device). Arming by verb leaves the arm button's state;
    discard then Undo brings back the same clip with its WAV byte-identical;
    go again records at the named pass's start with its count-in, even after
    a discard; markers match `tabs.list_measures`; an Undo naming another
    step is refused. 381 targeted tests and the startup and growth tripwires
    pass on a clean checkout of the commit.
  - **What a take is.** A linear recording is one `AudioClip`, not a Take;
    only loop recording builds take lanes. `core/recorded_passes.py` logs each
    pass the shared Stop path places, and the spec now says a take is a pass.
    Discard reuses the UI's delete with ripple off and no group closure.
  - **Stop.** `recording.stop` stops recording but not playback; the UI's Stop
    button does both, so the remote's `transport.stop` maps to both.
  - **Undo ids.** PySide keeps a Python command object for its lifetime, so
    the id lives on it; a Qt macro takes its first child's id. A test proves
    ids differ after an undo and a new edit at the same index.
  - **Fixed in Tabber Studio in passing:** `SetSectionMarkerCommand` wrote
    only the grid since U13c-4, so a Direction-dialog marker on the reference
    track never reached the bar the score draws; a stale console test; a
    metadata coverage report one method behind on `main`.
  - **Settled by TR33 (decision 20):** recording again over a kept take left
    both clips audible, because a linear pass was a plain clip. Now the new
    pass joins the kept take in take lanes and plays instead of it.
- **TR2 🟡 2026-11-07, Tabber Studio `85d51115`; vectors fixed here in
  `9036723`.** `remote_host/` (identity, pairing, bridge, vocabulary, session,
  server, runtime) and `control_api/handlers/remote.py` (`remote.enable`,
  `disable`, `status`, `pair`, `devices`, `revoke`). websockets 17.4 and
  cryptography 48.0.1 in `requirements.txt`; jsonschema in
  `requirements-dev.txt`. The vectors are pinned in Tabber Studio's
  `tests/remote/protocol`.
  - **Gate, met:** the eight connection vectors replay exactly over real TLS
    against a headless Tabber Studio, with the test pin checked (QR pairing,
    6-digit pairing with Deny, timeout and Allow, auth, version mismatch,
    and every refusal: closed, expired and wrong tokens, a wrong key, a
    replayed challenge, three failures closing 1008). S1 runs through the
    host with every answer checked against the pinned schemas and error
    table. Refused as well: a raw Control API method and an unknown verb
    (`method_not_found`), bad params, a binary frame (1003), a 70 KB frame
    (1009), a 41st request in a second, an unknown subprotocol (4002). A
    record resent after a dropped connection gets the first answer and
    records once. With the remote off nothing listens, and the MP13 check
    now proves `remote_host` and websockets stay unloaded. 323 targeted
    tests pass on a clean checkout of the commit.
  - **Gate, moved to TR4:** the frozen app with the package and its
    dependencies, and the bundle growth. The release locks are a certified,
    hashed wheelhouse; they change with the signed build TR4 makes anyway.
  - **Found while building it:** websockets rejects an unknown subprotocol
    with HTTP 400, so the host selects none itself and closes with 4002, as
    the spec says. `pairing_errors` contradicted itself (a closed window
    cannot answer `pairing_token_invalid`) and was fixed here first.
  - **Capabilities:** the host never offers `tracks.monitor/1` (Tabber
    Studio monitors audio input for all armed tracks at once) and offers
    `pair.code/1` only while the computer can show Allow (TR4).
  - **Content vectors** (take loop, conflicts, limits) are not replayed byte
    for byte: their ids and host times belong to the vector's own song.
    The S1 test and the refusal tests run the same exchanges on a real song
    instead.
- **TR3 🟡 2026-11-07, Tabber Studio `5f55b89f`.** `remote_host/feed.py`, on
  the main thread and only while a phone is subscribed. Cheap topics are read
  every 100 ms and sent on change; markers and takes when the undo stack
  moves and every 2 s; position at most 10 a second while playing; meters at
  most 20 a second for armed and selected tracks. A snapshot names the newest
  seq at the moment it is sent, so older events can never overwrite it.
  - **Gate, met:** `tests/remote/test_tr3_feed.py` over real TLS: every
    event equals the Control API's read-back of its topic (click, arm,
    marker, undo, record, stop, takes, undo of the take); seq has no gaps;
    the rates hold; with nobody subscribed the feed stops and reads nothing.
  - **Measured:** a feed tick costs 1.0 ms median, 2.5 ms p95 and 2.7 ms at
    most on the main thread (28 ticks, a song with 8 markers, M1 Max).
  - **Owed to the owner:** the 10-minute playback and recording stress test
    with two phones, which needs real audio. `tools/remote_feed_stress.py
    --minutes 10 --play` pairs two software phones with the running app,
    reports their event rates and seq gaps and the engine's xrun and
    deadline-miss change, and forgets the phones afterwards. The gate is
    zero dropouts.
- **TR4 🟡 2026-11-07, Tabber Studio `d11b0070`.** `remote_host/discovery.py`
  announces `_tabber-remote._tcp` through macOS DNS-SD (TXT `v` and `id`
  only) while the remote is on. Settings gets a Remote page
  (`ui/remote_panel.py`): on and off, Pair iPhone with a QR code that renews
  itself and closes when a phone pairs, and the paired phones with Remove and
  Forget All. `ui/remote_controller.py` turns the remote back on at launch
  if it was on, names the connected phones in the status bar, and closes
  phones on quit. The macOS spec declares `NSLocalNetworkUsageDescription`
  and `NSBonjourServices`; segno 1.6.6 draws the code.
  - **Gate, met:** `tests/remote/test_tr4_computer_side.py`, 7 tests:
    `dns-sd` sees the service, with the host id and port, only while the
    remote is on; a scripted phone pairs from the dialog's link and the
    dialog closes; Remove closes the phone with 4001 at once; the status bar
    names a connected phone and drops it when it leaves; the remote comes
    back on at launch; Settings has the page; the spec has both keys. The 15
    Preferences test files and `tests/remote` pass (331 and 42 tests).
  - **Names:** phones see the Mac's ComputerName; the code's first address
    is its Bonjour host name (`LocalHostName.local`), then its other
    addresses. On this Mac those include Tailscale's.
  - **Found:** Tabber Studio's JF6 inventory test records line numbers, so
    the Remote page's 7 lines moved three entries in
    `preferences_dialog.py`. Nothing else changed (compared entry by entry);
    the snapshot and its history were updated, as the inventory's rule asks.
  - **Not in the demo cut:** the 6-digit fallback with Allow (`pair.code/1`
    stays off).
  - **Owed:** the signed, installed app (the owner is warned first, since it
    opens on the owner's screen): the Local Network and firewall prompts,
    whether a rebuild asks again, QR pairing with Local Network denied, and
    the frozen app's bundle and release locks (moved here from TR2). The
    macOS firewall is off on this Mac, so "Block all incoming connections"
    was not tried.
- **TR5 ✅ 2026-11-07, this repository.** Built with Xcode 26.3 (27.2 was not
  downloaded yet; the release script switches to it by itself).
  - **RemoteKit** (`apple/RemoteKit`, Swift 6, no UI framework): the
    protocol's models; its cryptography (pin, device id, signed bytes,
    6-digit code, QR link); the device key (Secure Enclave on a phone,
    software in the Simulator); `NetworkTransport` (WebSocket over TLS 1.3
    with the pin checked in the validator); `RemoteClient`; and
    `RemoteSession`, which reconnects with backoff, resnapshots on a seq gap
    or a heartbeat ahead, and resends a change with its key after a drop.
    `DemoHost` is a simulated Tabber Studio for demo mode and the tests.
  - **The app** (`apple/TabberSpak.xcodeproj`, synchronized folders): a debug
    screen, demo mode (`-demo`), pairing from a `tabber-remote://` link
    (paste, or `xcrun simctl openurl`), the Bonjour and Local Network keys,
    and the icon: a spak, literally (the owner: "the literal image of a
    spak"), a lever whose knob is the record button's red
    (`apple/scripts/draw_icon.swift` draws it).
  - **Gate:** every vector passes in Swift (6 crypto tests, the exchange test
    over all 14 vectors); the DemoHost tests pass (S1 with five takes, two
    discarded; discard then Undo; a resend after a drop records once; a
    stale target refused with the truth; events in order without gaps); the
    UI test passes in the Simulator (`xcodebuild test`). Beyond the gate,
    `apple/scripts/interop.sh` runs RemoteKit against Tabber Studio's real
    host over pinned TLS 1.3 on this Mac (`tools/interop_host.py`): pair,
    authenticate, `method_not_found` for a raw Control API method, a wrong
    pin refused, the pin read during 6-digit pairing. It found the two
    Network framework traps now in Known traps.
  - **Owed to the owner:** the same connection from a real iPhone on the
    Wi-Fi, once a TestFlight build is installed.
  - **TestFlight:** `apple/scripts/release-ios.sh` archived and signed build
    1, and the upload stopped at `missingApp(bundleId: "studio.tabber.spak")`:
    App Store Connect had no app record yet. The owner created it the same
    day (Apple ID 6831855493), and the script uploaded build 1 for internal
    testing (tag `ios-b1`, Xcode 26.3).
- **TR6 🟡 2026-11-07, this repository.** A fresh install opens on Welcome
  (`apple/TabberSpak/Welcome.swift`). Get Started explains the Local Network
  prompt before iOS shows it, then lists the computers Bonjour finds
  (`Discovery` in RemoteKit, with iOS 26's `NetworkBrowser`) above Scan the
  Code (VisionKit's `DataScannerViewController`, QR only; without a camera,
  the link can be pasted). Pairing shows its progress, and a failure says why
  in words. The Computer tab replaces TR5's debug screen: the computer, its
  state and address, Pair Again, Forget, and Keep the screen awake.
  - **Reconnecting** (`RouteBook`, `RemoteSession.wake`): the remembered
    addresses are tried in turn with a 3-second hello, then Bonjour finds the
    computer by its host id. The address that worked is remembered first,
    and when the port moved, the other addresses move with it. Back on the
    screen, a connection quiet for 2.5 s is remade at once, and a reconnect
    waiting out its backoff tries at once.
  - **Fix-it cards** (`FixIt.swift`, from `SessionState.trouble`): Can't
    reach your computer (after 4 s of failing, with four things to check),
    Update Tabber Studio and Update Tabber Spak (from `unsupported_version`'s
    `host_versions`, or close 4002), Allow Local Network (a denied browse or
    connection), the computer no longer knows this iPhone, and a different
    computer answers.
  - **Gate, met in the Simulator and in RemoteKit:** 5 new UI tests (a fresh
    install; the explainer, the scanner, and a pairing that fails with its
    reason; the unreachable card and Pair Again; both Update cards), and all
    12 UI tests pass. 7 new RemoteKit tests (the route book; the trouble for
    each cause; wake reconnects within 0.5 s; a quiet connection is remade
    within a second), and all 24 pass. The interop test against the real
    host still passes.
  - **End to end** (`apple/scripts/follow_check.sh`): Tabber Spak in the
    Simulator paired with a headless Tabber Studio (`tools/stage_host.py`, a
    real MainWindow with the remote on and an engine that opens no device);
    the computer came back on another port with the same keys, and the
    phone found it again through Bonjour 5.8 s later, without pairing. Most
    of that is the backoff over the four old addresses before the Bonjour
    lookup; trying Bonjour sooner is a possible improvement.
  - **Found:** `xcrun simctl openurl` with a `tabber-remote://` link now
    stops at iOS's "Open in Tabber Spak?", so scripts pass the link with
    `-pair-link` instead.
  - **Owed to the owner, on the iPhone:** fresh install to paired with one
    scan; the Local Network prompt after the explainer; each card, by
    recreating its cause (Tabber Studio closed, Wi-Fi off, Local Network
    off); back on the screen within a second over Wi-Fi.
- **TR7 🟡 2026-11-07, this repository.** The Session screen
  (`apple/TabberSpak/SessionView.swift`, `RootView.swift`): the connection
  badge, the song and its unsaved mark, the section at the playhead, bar and
  beat, the time counted on locally between updates, the armed track with
  its meter (or a track picker when none is armed), marker chips (tap to
  jump, hold to loop), count-in, click and loop, the red recording frame
  with `REC 00:42` or the count-in, haptics per action and keep awake. The
  transport (Go again, Record, Play/Stop) is the tab bar's bottom accessory
  with the tab bar never minimized, so it never moves. Taps look pending
  until the computer confirms; without a connection the screen dims.
  - **Gate, met:** UI tests against DemoHost for every control (markers,
    the three toggles, arm, record, stop, go again, play and stop, the
    Computer tab), all passing in the Simulator.
  - **Found by the UI tests:** the root view and the transport bar read the
    whole session state, so the tab view was rebuilt 10 times a second while
    playing. They now read a small summary that changes only when what they
    show changes.
  - **Owed to the owner, on the iPhone:** S1 up to the take card and S2
    against Tabber Studio, and tap-to-confirmed latency p50 and p95 with
    AirDrop on and off.
  - **The icon, redrawn at the owner's word** ("the literal image of a
    spak", then "not a red round thing on top"): a lever with a grip in a
    gated base, in Tabber Studio's dark tokens and teal accent.
  - **The owner, 2026-11-07:** Tabber Spak follows Tabber Studio's design
    language; "we will deal with that when it's time." TR9's design pass
    brings Tabber Studio's design tokens (`ui/design_tokens.py`) into the
    app.
- **TR8 🟡 2026-11-07, this repository.** The take card
  (`apple/TabberSpak/TakeCard.swift`) rises after every take: Keep (the
  default; recording again keeps it too), Discard by press and hold, then an
  Undo offer for five seconds that names the discard's undo step, Go again,
  and the take's confirmed rating in stars. The Takes tab lists the newest
  takes with ratings; the Tracks tab arms, selects and (for MIDI) monitors;
  the Flag chip adds a marker at the bar the phone shows.
  - **Gate, met in the Simulator against DemoHost:** keep; a second take
    discarded and brought back by Undo; go again from the card; a rating of
    four stars; a flag; Guitar armed from the Tracks tab. All seven UI tests
    pass.
  - **Found:** a list row with a tap gesture became one accessibility
    element and hid its arm button from VoiceOver; rows now keep their
    children reachable and select through an accessibility action.
  - **Owed to the owner, on the iPhone against Tabber Studio:** S1 complete,
    five takes with two discarded and one brought back with Undo on the
    computer, files intact.
- **TR9 🟡 2026-11-07, this repository.** The design pass: Tabber Studio's
  design language (`apple/TabberSpak/Theme.swift`), from its dark design
  tokens (`ui/design_tokens.py`) and the owner's screenshots of Arrange, Tab,
  the Mixer and Routing ("just so we are talking about the same app").
  - **Redesigned the same day at the owner's word.** The first pass put
    Studio's colours on a generic stack of cards with coloured edges ("lazy
    design and screams AI made", "make good design"). The second starts from
    the moment the app serves: between takes, with an instrument in hand.
    - **One bold element:** the readout is the recording light. At rest it
      is a dark well with POS, TIME and BPM, monospaced, the position
      written `25 : 4` as Studio writes it. During the count-in it is amber
      with the beats left; while recording it is red with Studio's
      "REC 0:42", pulsing as Studio's record button does. The glowing screen
      frame is gone.
    - **Everything else is quiet,** left-aligned and in sentence case: the
      section as plain large text; the tracks in one row with Studio's own
      record-arm circles (hollow, red when armed) and the armed track's input
      in Studio's meter colours; markers as text buttons, the one the
      playhead is in amber (Studio's playhead colour), a looped one teal;
      Count-in, Metro and Loop in a well, ON a lighter fill.
    - **The take card is a slate:** the take, its length and its start;
      Keep as a quiet word in the corner, since it is the default; and two
      big buttons, Hold to discard and Go again with the record dot.
    - **A computer that can't be reached** replaces the session with plain
      instructions and two buttons; no alert box. Welcome is the three
      numbered steps that pair the phone.
    - **Gone:** coloured edges, gradients, glows, cards inside cards, capital
      letters except Studio's POS, TIME and BPM, and strings joined with
      dots. Record red is Studio's own `#ff4d6a`. Ratings stay only in the
      Takes list until the owner decides whether to keep them.
  - **Dark only,** with a dark launch screen. Tabber Studio also has a light
    mode: whether the phone needs one is the owner's call.
  - **Gate, met in the Simulator:** Xcode's accessibility audit passes on
    every screen (Welcome, the explainer, Find your computer, Session,
    Takes, Tracks, Computer). It found arm buttons under 44 pt; text that
    shrank, or would clip at large sizes; labels and a footer whose type did
    not scale at every size; decorative icons read aloud; and a Monitor
    control reachable only by swiping, now a menu. At the largest
    accessibility text size, the Session screen stacks its header and
    readout (checked by eye). All 14 UI tests pass.
  - **Screenshots:** `ScreenshotUITests` drives demo mode through every
    screen and writes PNGs when `TEST_RUNNER_SCREENSHOT_DIR` is set, for
    review now and the App Store later (the 6.9-inch and iPhone Duo sizes).
  - **Privacy:** `PrivacyInfo.xcprivacy` declares UserDefaults (CA92.1) and
    the system boot time (35F9.1: the playhead is counted on locally). No
    data is collected and nothing tracks. Export compliance stays "no
    non-exempt encryption": only the system's TLS, and signatures.
  - **A Tabber Studio without the remote:** nothing listens, so the phone
    shows Can't reach, whose first check now says to update Tabber Studio
    when Settings has no Remote page. Another protocol version shows the
    Update cards (TR6).
  - **TestFlight:** build 2 carries TR6 to TR9 (tag `ios-b2`, Xcode 26.3,
    internal testing). Xcode 27.2 was never downloaded, so 26.3 stays.
  - **Owed to the owner:** S1 from the TestFlight build on the iPhone, once
    with VoiceOver; the App Store privacy label (Data Not Collected) and a
    privacy page on the website; light mode or not; Swedish (after the demo,
    decision 17).

- **TR31 🟡 2026-11-07, this repository and Tabber Studio.** Tabber Studio's
  own shape on the phone, after the owner tried the redesigned Session
  screen: "cluttered... not obvious what to do... where do I choose a track?
  where is the fretboard and keyboard if I want to write tab on a track?
  where do I record on an audio track and where do I start the recording?
  where do I listen to a track, or all tracks? where's the mixer?... a
  person should know by themselves as soon as they see the app", and "it
  needs to be clear what the app can do and how."
  - **The app is now Studio's views, not an invented session screen.** Three
    tabs, named for what they do, with Studio's transport (Stop, Play,
    Record and POS) in the tab bar's accessory on every screen:
    - **Tracks:** Studio's Tracks panel. A card per track with its colour,
      number, name and instrument (or Audio), and Studio's S, M and record
      ring. Tap a card to choose it (teal outline); S hears it alone, M
      silences it, and the tracks a solo or mute leaves silent dim. Above
      them Loop, Count-in and Metro; with nothing armed, one line says how to
      record. Below them the takes, each with a one-tap Delete.
    - **Tab:** the chosen track's tab around the cursor, drawn as Studio
      draws it (strings 20 apart, fret numbers on the lines, the teal cursor
      band and box); the note values 1 to 1/32, Dot, Triplet, Rest and
      Delete; Previous, Fretboard or Piano, and Next. Studio's rosewood
      fretboard (inlays at 3 to 24, the cursor string ringed, the beat's
      notes as teal circles) and its 88-key piano. Undo and the track menu
      sit in the bar at the top. An audio track offers the tab tracks.
    - **Mixer:** Studio's channel strips: the name on the track's colour,
      the pan knob with Studio's L64/C/R63, S and M, a fader on the host's
      scale (0, -12, -24, -48) with a meter, and the level. Double-tap for 0
      dB or the centre. The Reverb bus and the master follow.
    - **The computer** is a chip at the top of every screen (a dot: teal
      connected, amber reconnecting, red not); it opens the Computer sheet.
      The position opens Go to: the start and the markers.
  - **Taking things away:** the readout lamp, the marker row, ratings (the
    owner: "rating takes, is that necessary? really?"), Flag, Hold to
    discard (Delete is one tap, with Undo for five seconds: "should be
    easier to delete takes"), the Session, Takes and Computer tabs.
  - **Protocol 1.1 (additive), spec 7 to 10:** `mixer/1` (mixer.state,
    set_volume, set_pan, set_mute, set_solo; the mixer and mixer_meters
    topics) and `tab/1` (tab.state, set_cursor, move, put, put_pitch,
    set_duration, rest, delete; the tab topic); tracks may carry
    `instrument` and `tuning`; errors 1032 `unknown_strip` and 1033
    `no_tab`. Neither is in the snapshot: they are read once and followed.
    Volume is the fader's travel in the host's law, so the phone's fader
    sits where the computer's does. 13 verb and 3 topic schemas, the
    `mixer` and `tab` vectors; the validator covers 40 verbs, 12 topics and
    31 errors. A 1.1 phone works with a 1.0 host (Studio compares majors)
    and shows "Update Tabber Studio" for what the host does not list.
  - **DemoHost** has both: Studio's undo rules (mute, solo and tab edits are
    steps, volume and pan are not), its fader law and pan labels, and the
    Tab view's editing (a tap writes or takes off, the value applies to an
    empty beat, a piano key takes the lowest fret, Next fills the bar or adds
    one). The demo song has Studio's track colours, a guitar and a bass in
    tab, drums, and two audio tracks.
  - **Gate, met in the Simulator** (on its own device, "Tabber Spak", since
    another app shared the first one): 21 UI tests, among them the
    accessibility audit on every screen and the take card, plus the
    screenshot run; RemoteKit's 27 tests; the vector validator and its own
    11 tests. The audit found counters that
    ignored Dynamic Type, a take's line that could clip, and text drawn
    inside combined elements; the fader's scale and the pan dial are drawn.
    Found while testing: nothing presents from inside the tab bar's
    accessory (a Menu or a dialog there never opens, and a dialog on the
    root breaks the accessory), so Go to is a sheet; and the transport read
    the whole session, redrawing with every meter, so it reads a small
    summary and holds still while recording.
  - **Studio's side:** Settings > Remote rebuilt from Settings' own cards
    (e7dec22e: it was loose widgets with bare-text buttons, "such ugly
    design"). A signed, notarized Tabber Studio with the remote is built in
    the scratchpad and not installed: release locks for websockets,
    cryptography and segno (69e4e3b5), every `remote_host` module in the
    frozen app, a smoke test on the bundle's own Python. The owner tried the
    TestFlight app against the installed 0.3.16, which predates the remote;
    pairing worked once Studio ran from the repo.
  - **Next:** TR25 and TR15 in Studio, so the real Studio offers `mixer/1`
    and `tab/1`; then the tuner (TR32); then routing and chat.

- **TR25 ✅ 2026-11-07, Tabber Studio (d78967bd).** The mixer for phones,
  `mixer/1`, on the real Tabber Studio.
  - **Strips and units:**
    - A strip for every track in strip order, then every bus, then the
      master.
    - Volume crosses the wire as the fader's travel in the mixer's own taper
      (`ui/mixer_dock.py`, as `ui/mixer_level.py` uses it): 0 dB at 70 %,
      -12 dB at 45 %. The phone's fader therefore sits where Studio's does.
    - Pan uses the mixer's labels: L64, C and R63, buses in percent.
  - **Edits:**
    - Solo and mute are undo steps through the Control API. Volume and pan
      are direct writes, as in the mixer.
    - The master has no pan, mute or solo, and a gone strip is refused with
      the current mixer.
  - **Feed:**
    - The `mixer` topic rides the 100 ms check with the other cheap topics.
    - `mixer_meters` reads the engine's live strips and the master strip,
      never the master's offline render, and runs only while a phone
      subscribes.
  - **Versions:** the host speaks 1.1, and each session gets the lower of
    the two minors with only that version's capabilities and topics (spec
    7). So TestFlight build 2, a 1.0 phone, sees exactly the 1.0 host it
    knew, and the exact replays of the 1.0 connection vectors still hold.
  - **Gate met:**
    - Every answer obeys the pinned 1.1 schemas.
    - Every change matches its read-back from the model and the Control
      API.
    - A fader move is not an undo step, and Undo leaves the fader alone.
    - The mixer topic follows a change made on the computer.
    - The meters stop when the last phone leaves.
    - 7 new tests; all 45 remote tests pass.
  - **Measured** (headless, 2026-11-07): the feed's 100 ms tick on a song of
    16 tracks (a written guitar part, 7 more tab tracks, 8 audio tracks), a
    bus and 8 markers.

    | Subscribed topics | Median | p95 | Worst | Ticks |
    |---|---|---|---|---|
    | The 1.0 topics | 0.46 ms | 1.22 ms | 1.39 ms | 48 |
    | Plus the mixer, its meters and tab | 0.66 ms | 0.81 ms | 0.98 ms | 47 |

    That is about 0.2 ms more per tick, far under TR3's 15 ms limit.
  - **Owed:**
    - The meter tick is timed apart, and the fake engine has no meters, so
      its cost waits for a run on the real engine.
    - A fader drag on a device against Tabber Studio.

- **TR15 ✅ 2026-11-07, Tabber Studio and this repository.** Writing tab from
  the phone, `tab/1`, on the real Tabber Studio (`remote_host/tablature.py`).
  - **Each verb is the Tab view's own action,** found by reading Studio:
    - the main score scene's cursor and its projected bars;
    - `MainWindow._on_fretboard_click` for a tap;
    - the piano's guitar-tab rule (toggle, or the lowest fret with the capo
      counted) for a key, since the piano path itself refuses while the Tab
      view is hidden;
    - the toolbar's `set_duration`, `toggle_dotted` and `set_tuplet`, with
      value and dot as one step;
    - `move_cursor`, `toggle_rest` and `delete_note`.
  - **The same undo steps and labels as in Studio** ("Set fret 3 on string
    2", "Delete note on string 3", "Toggle rest", "Insert beat"). A tap
    plays the beat on the computer, as the fretboard does. A bar that cannot
    be written is refused in Tabber Studio's words.
  - **Track rows gain fields:** they now carry the instrument (General MIDI
    names) and a tab track's tuning. Audio, drum and plain MIDI tracks have
    no tab: `tab` is null and edits are refused with `no_tab`.
  - **DemoHost, the spec and the `tab` vector now follow Studio exactly:**
    R toggles a rest off again, Delete takes only the cursor string's note,
    "Insert measure", and the shown value is the toolbar's.
  - **Gate met:**
    - 6 Studio tests over a real connection, read back from the model: a
      tap with its label and toggle, Undo with `expect`, a piano key's
      lowest fret, value and dot as one step, the keys, no tab on an audio
      track, and the tab topic following a tap on the computer's fretboard.
    - All 51 remote tests pass.
    - The phone's 4 Tab UI tests and RemoteKit's 27 pass.
  - **Not covered:** drum tracks and MIDI Tab. Studio's drum map takes GM
    numbers, not frets, so a drum track shows no tab on the phone.
  - **Owed:** writing a riff on a device against Tabber Studio, both
    screens side by side.

- **TR32 ✅ 2026-11-07, this repository: Tabber Tuner.** The owner: "maybe
  viga tuner, the guitar tuner could be implemented into tabber remote also?
  but as tabber tuner... the code is already built".
  - **The Viga Tuner's pitch detection, unchanged.** `YinPitchDetector`
    and `BiquadFilter` are copied from `viga_guitar_tuner/ios` at a3527b5
    (YIN with 4x decimation, a band-pass, a median of five). Its VST
    sources are untouched.
  - **Written for Swift 6:**
    - The microphone tap feeds the detector on the audio thread, and the
      newest result crosses to the main actor under a lock, 20 times a
      second.
    - `TunerModel` matches the nearest string of the tuning within a
      semitone (chromatic otherwise) and smooths the cents while the target
      holds.
  - **The screen in Studio's language:**
    - The note is the one large thing, teal within 3 cents.
    - A cents scale from -50 to +50 with the in-tune band, the needle, and
      the words ("24 cents flat", "In tune").
    - The strings low to high, the one being tuned lit.
    - The frequency, and where the strings come from.
  - **Where the strings come from:** the chosen track's (a tab track's
    `tuning`), else a standard guitar. It works with no computer at all.
  - **The microphone:**
    - One sentence explains it before iOS asks: "Nothing is recorded, and
      the sound never leaves the phone".
    - If denied, Open Settings.
    - Listening stops when the tab is left.
    - The privacy label stays Data Not Collected.
  - **Demo mode** tunes a guitar string by string (flat, then settling), for
    App Review, screenshots and the tests. Two UI tests, and the
    accessibility audit now includes the Tuner.
  - **Owed:** tuning a real guitar on a device, against the Viga Tuner app
    side by side.

- **TR33 ✅ 2026-11-07, Tabber Studio (d5bd91ce) and this repository
  (ffa00fc).** Take lanes for passes (decision 20).
  - **At Stop,** a pass that overlaps audio already on its track joins that
    audio in take lanes (`core/take_record.build_pass_takes`):
    - every pass becomes a take row and keeps its clip id, which the pass
      registry keys on;
    - the comp gives each pass its span in the order they were recorded, so
      the newest plays where they overlap and older audio still plays
      outside it, with Studio's own crossfade at each seam;
    - a pass over nothing stays a plain clip, as before;
    - it is one undo step, "Record audio clip", through
      `SetActiveTakeCommand`, the step Studio uses when a take is chosen.
  - **The take loop works on lanes:**
    - Delete takes the pass out of the lanes with its comp copies, and the
      takes left fill its span, the newest winning ("Discard take", one
      step);
    - `takes.passes` calls a take in lanes active when it owns part of the
      comp, so a comp swipe on the computer shows on the phone;
    - Go again records over the take, so the new pass joins the lanes and
      plays.
  - **Fixed on the way:**
    - The rating step held a clip object, and a lane change swaps in copies
      of the clips. After Undo and Redo a rating went to a clip the song no
      longer had. It now finds its pass by id.
    - An audition still running at Stop restores its saved clips when it
      ends, which would drop the new pass. Stop now ends it first.
  - **The phone:** the takes list dims a take that doesn't play and says
    "not playing". DemoHost decides it as Studio's lanes do: an earlier take
    plays only where no newer take on its track covers it, and discarding
    the newer one lets it play again.
  - **Gate met, headless:**
    - 11 Studio tests (`tests/remote/test_tr33_take_lanes.py`):
      - three passes give three lanes, only the newest heard;
      - each Stop is one undo step, and Undo and Redo give back each state,
        down to the first pass as a plain clip again;
      - a partial overlap plays both;
      - discarding the newest or an older take, with no comp copy left
        behind;
      - a rating across Undo and Redo;
      - go again, and a pass over nothing.
    - Putting either fixed bug back fails 3 of them.
    - Loop recording, comp, audition and recording suites stay green (307
      tests).
    - The smoke slice passes except `test_unified_render_parity`. That test
      stops before rendering because this Mac's engine binary (13 October)
      is not the one its manifest (5 October) names, which predates TR33.
    - RemoteKit's 28 tests and the 4 take-loop UI tests pass, one new in
      each.
  - **Owed:** S1 on a device against Tabber Studio, going again over the
    chorus.
  - **Not built:** choosing an earlier take from the phone. Delete the newer
    take to hear the earlier one again; comping stays on the computer.

- **TR27 ✅ 2026-11-07, Tabber Studio (a84bc9f8); protocol 1.2 (c8bed0a,
  labels 4b94a69).** Routing for phones, `routing/1`.
  - **The protocol:**
    - `routing.state` and the `routing` topic: every track and bus with
      its one output, and every send with its level, `level_db`,
      `level_label` and Pre-fader, with the mixer's strip ids;
    - `routing.set_output`, `routing.set_send` and `routing.remove_send`;
    - new errors `routing_loop` (1034, with `path`) and `wrong_kind`
      (1035); `unknown_strip` may carry the routing.
    - A 1.2 phone works with a 1.1 or 1.0 host, which simply lists no
      `routing/1`.
  - **Each change is the Routing panel's own,** read from its snapshot
    (`build_routing_overview`):
    - an output moves as the matrix moves it, one undo step, "Routing
      change";
    - a send is added and removed as Alt+click does, each an undo step
      ("Add send → Reverb"), and starts at Studio's -6 dB;
    - its level and Pre-fader are the mixer's send controls, not undo
      steps;
    - a loop is refused before anything changes, named ("Reverb → Delay
      → Reverb").
  - **Fixed in Tabber Studio on the way:**
    - A send added in the matrix or a header stayed silent until its level
      was dragged, and a removed one kept playing: the send commands now
      get the engine.
    - The track header's Output menu edited the song alone, with no undo
      and no engine call. It now takes the panel's path
      (`ui/routing_edits.py`), one undo step.
    - The headers' output and send chips went stale after a matrix change.
    - Routing undo labels name the track and bus instead of numbers.
    - The new code sits in `ui/routing_edits.py` under the RS29 growth
      freeze; `main_window.py` shrank by 8 lines (ceiling 15,704).
  - **Gate met:** 8 Studio tests over a real connection (`test_tr27_routing.py`):
    - the panel's own routing;
    - an output moved, read back from the model, the engine and the
      header chip;
    - a loop refused with its path, leaving the routing unchanged;
    - a send heard at once, its level no undo step, a removed send
      stopped, Undo bringing it back as it was;
    - wrong kinds, the header menu's one step, the topic following the
      computer, and a 1.1 phone seeing no routing.
    - Putting the send-engine and header-chip fixes back fails 2 of them;
      the remote, routing and freeze suites pass (205).
  - **Owed:** routing on a device against Tabber Studio.

- **TR28 ✅ 2026-11-07, this repository (4b94a69).** Routing on the phone.
  - **Where:** the Mixer's other view (Mixer | Routing in its bar), as
    Studio's Routing panel can sit as a tab beside its Mixer. A list for
    one thumb, not the Flow graph.
  - **Each track** has its Output (Master or a bus, from a menu) and its
    sends, drawn like Studio's send row: the bus, a thin bar with the thumb
    at the level, the level in dB, PRE. Add send and remove are beside
    them. A send drags from where it is, and double-tap is silence, as
    Studio's double-click is.
  - **Each bus** has its Output, where a bus that would loop back is shown
    but can't be chosen, and what feeds it: outputs and sends.
  - **Undo** is in the Mixer's toolbar, as on the Tab screen (routing,
    mute and solo are undo steps). A refused loop is explained with its
    path.
  - **DemoHost** speaks 1.2 with Studio's routing and labels; Vocals and
    Lead guitar send to Reverb.
  - **Gate met:**
    - RemoteKit's 30 tests, the vectors round-tripping;
    - 26 UI tests, two new: an output to a bus and back; a send added,
      Pre-fader, removed and brought back by Undo;
    - the accessibility audit covers Routing. Text resting under the
      transport is left out of its contrast check; with a list that fits,
      Routing passes the whole audit.
  - **Owed:** on a device against Tabber Studio.

- **Tuner crash fixed 2026-11-07 (ffa9f8d), TestFlight build 4.** The
  owner: the app "crashed when the mic of the tuner was activated", on
  build 3, away from the Wi-Fi.
  - **Why:** the microphone tap's block was made inside `TunerModel`, which
    is main-actor code, and `AVAudioNodeTapBlock` is not marked Sendable.
    So Swift 6 gave the block a main-actor check, and AVAudioEngine calls
    it on its audio thread: the first buffer stopped the app (SIGTRAP).
    The UI tests run the tuner's demo, never the microphone, so they could
    not see it.
  - **Fix:** `PitchTap.install` makes the block outside the main actor. An
    input with no channels or sample rate is not tapped at all.
  - **Proof without a phone:** the same shape on this Mac with an offline
    AVAudioEngine under Swift 6 (no microphone, no system audio). The old
    one exits with SIGTRAP on the first tap call; the new one runs the tap
    30 times.
  - **Owed:** the tuner on the owner's iPhone with build 4.
  - **Lesson:** a block that a system framework calls on its own thread is
    made in nonisolated code. The app has no other such block; Discovery's
    network handler is already nonisolated.

- **TR29 ✅ 2026-11-07, Tabber Studio (975ba81a); protocol 1.3 (812fa1c).**
  Tabber Studio's chat from a phone, `chat/1`.
  - **The protocol:** `chat.state` and the `chat` topic (available,
    idle/thinking/waiting/running, the conversation, a waiting plan);
    `chat.send` answers at once and the answer follows on the topic;
    `chat.confirm`, `chat.cancel`, `chat.stop`; new errors
    `chat_unavailable`, `chat_busy`, `unknown_plan`.
  - **The chat bubble's own pieces, without its window**
    (`remote_host/chat.py`):
    - the planner, as a copy that knows only what a phone may use;
    - `run_agentic_loop`, so Execute runs the plan and then the AI's
      further rounds;
    - `_execute_plan_on_main` inside the undo stack's chat turn, so one
      request is one undo step ("AI: ...").
    - The phone's conversation and memory are its own, so the computer's
      bubble and the phone can never run each other's plan (the bubble
      keeps single slots for its plan and Stop).
  - **Safe, as the owner asked:**
    - Lock a (`remote_host/chat_guard.py`) leaves out of the planner the
      AI's settings and tools, the remote's pairing and devices,
      preferences, macros, the computer itself, downloads, installs, scans
      and modal windows. It checks every step again on the main thread
      right before it runs, after Execute too, because later rounds are
      never shown first. It also refuses files outside the song's folder,
      a new or other song over unsaved changes, and plug-ins that are not
      installed. Refusals are words, before anything runs.
    - Lock b (`remote_host/redact.py`) scrubs every message: the secrets
      this computer knows by value (every provider's key, the host key,
      the pairing token, device keys), fields named like secrets, and text
      shaped like keys, tokens and PEM blocks. A song's key ("E minor"),
      track ids and file names still read.
    - 10 chat requests a minute per phone. Every request and action goes
      in the remote's activity log and the computer's notices.
    - Found while mapping the chat, worth knowing on the computer too:
      `ai.query_graph` may reach files through its query language (not
      verified), and one Execute lets the AI run up to 40 rounds that
      nobody previews. The phone's chat refuses the first and checks the
      second; the computer's own chat is unchanged.
  - **Gate met:** 12 tests over a real connection (`test_tr29_chat.py`), with
    a scripted planner and real Control API calls:
    - a plan, Execute as one undo step, Undo on the phone;
    - four refusals in words with nothing run;
    - a later round stopped after Execute;
    - the key hidden in an answer;
    - the 11th request refused, busy and Stop, no AI on the computer;
    - the activity log;
    - a 1.2 phone seeing no chat.
    - Every frame sent to the phone in those tests is scanned for the key,
      the host key and the pairing token, and none carries them.
    - Taking out the scrub, the per-round check or the planner's
      restriction each fails a test.
    - Plus 5 filter tests; all 87 remote tests pass.
  - **Owed:** a real AI on a device: a few requests, one refused.

- **TR30 ✅ 2026-11-07, this repository (50b89e9).** Chat on the phone.
  - **A fifth tab, Chat:**
    - the conversation;
    - a plan card with numbered steps, Execute and Cancel, as the chat
      bubble names them;
    - "Thinking…" with Stop;
    - the keyboard's microphone for speaking a request.
  - **Locked to the owner:** Face ID, Touch ID or the passcode before it
    opens, and locked again when the tab or the app is left. A phone
    without a passcode is told to set one. The demo has no computer
    behind it and opens at once, so the UI tests cannot reach the real
    lock; the lock is owed on a device.
  - **Undo** in the toolbar takes a whole request back.
  - **Gate met:**
    - RemoteKit 31: the demo's chat, and the chat vectors round-tripping;
    - UI tests 30, three new: locked until opened; a plan then Execute as
      one undo step; a key refused;
    - locked again after leaving; the accessibility audit passes on Chat,
      locked and with a plan.
  - **Owed:** Face ID on the owner's iPhone; a request by dictation.

- **Reaching Studio away from the Wi-Fi (2026-11-07).** The owner asked for
  a way through the Contabo VPS to test on mobile data. No VPS is needed:
  this Mac is already on the owner's Tailscale network (100.114.215.101,
  with the Linux laptop). Studio already puts that address in the pairing
  QR, and listens on it, and the phone keeps and tries it. With Tailscale
  on the iPhone, signed in to the same account, the phone reaches Studio
  over mobile data, end-to-end encrypted, with no port opened to the
  internet. This Mac does not sleep.
  - **The owner's iPhone joined** the tailnet as `iphone-13`
    (100.80.172.36) the same evening; `tailscale ping` from this Mac
    answers.
  - **Every address at once (RemoteKit `RacingTransport`, build 6).** The
    phone used to try its remembered addresses one after another, each
    with a 3-second hello timeout, so away from the Wi-Fi it waited out
    the local ones before the Tailscale one. Now the hello goes to every
    address at once, the first to answer is the connection, and the
    others' work is cancelled. Pairing does the same.
    - Nothing is weaker: each address is its own TLS connection, pinned
      to the paired computer's key before any frame is sent, and only the
      hello is sent before an answer.
    - A wrong key at one address is only a failure there.
    - 4 RemoteKit tests, among them a session connecting through a dead
      address in under a second.
  - **The fix-it card** no longer says to turn every VPN off: it says the
    same Wi-Fi, or Tailscale on both with the same account, and no other
    VPN.

- **Tabber Studio 0.3.18, built and installed 2026-11-07.**
  - **What it adds:** take lanes, chat and routing for phones, and the
    routing fixes.
  - **The build:**
    - from Tabber Studio 5553bd20, with the certified engine abc7bd5e
      (byte for byte once signatures are removed; no engine source changed
      since 0.3.17);
    - signed, notarized and stapled, and Gatekeeper accepts the app and the
      DMG; the DMG holds this app.
  - **The frozen-app smoke test passes 13 of 13:**
    - protocol 1.3 with `routing/1` and `chat/1`;
    - TLS 1.3 with the pinned key;
    - the chat's modules and its secret filter, every module from the
      bundle.
  - **Installed** in /Applications, with 0.3.17 kept beside it as "Tabber
    Studio 0.3.17".
  - **The DMG** is at
    /Volumes/Data/tabber_work/rel0318/download/Tabber-Studio-0.3.18-macOS-arm64.dmg
    (plain layout). Publishing it is the owner's call.

- **The owner's first use of chat and play, 2026-11-07 evening (build 5 or
  6, Studio 0.3.18).** The owner: "I asked it to write some notes. didn't
  work or something?" and "no sound in the app when I press play. is that
  intentional?"
  - **What the log showed:**
    - "Add a track. A tab track." ran `tracks.create_midi`.
    - The tab request ran only `tracks.list`, and nothing after it.
    - The AI's answers were not logged, so what the phone said is not
      known.
  - **A replay with the real AI** (the same two requests, Studio's real
    planner and the owner's DeepSeek key, headless, a few calls) wrote 40
    notes: an 8-bar fingerpicked progression in E minor. But the phone
    heard only the AI's last words ("Ignore that last stray action") and a
    raw error line.
  - **Fixed in Tabber Studio (aa3768da, 0.3.19):**
    - the plan's words stay after Execute;
    - each later round says what it does as it starts;
    - the end names the steps that didn't work;
    - the plan, each round and every answer go in the remote's log;
    - the AI's own read-only lookups (`ai.get_command` and the like) are
      open to a phone's turn.
  - **Sound:** by design, the sound plays on the computer; play reached
    Studio each time. Build 7 tells this once, the first time Play is
    pressed on a real computer ("The sound plays on [computer], not on this
    iPhone"), and the welcome screen says it. Listening on the phone, by
    streaming Studio's sound to it, is a possible feature, offered to the
    owner.
  - **Found on the way:** Studio's development fallback reads a key from
    `api_key.md` in the repository, which DeepSeek now refuses. The
    installed app never reads that file; only a run from source does.

- **TR34 ✅ 2026-11-07: the computer's view from the phone, and a held
  Previous or Next (protocol 1.4, 7a97c5f; Studio 691cbd34, 0.3.20).** The
  owner: "we need buttons for arrange view and piano roll and split view
  too. and when pressing and holding previous and next in tab in the app it
  should fast forward so you don't have to click so much."
  - **`view/1`:** `view.state`, `view.set` (editor, split) and the `view`
    topic. Studio runs its own view buttons' commands: `view.set_mode`
    for Arrange, Tab and Piano Roll, and `view.set_split`, whose Off goes
    back to the editor before, as F8 does. Not an undo step.
  - **On the phone:** Studio's three editors and Split, as one row on the
    Tracks screen, shown only when the computer lists `view/1`.
  - **A held Previous or Next:**
    - steps through the beats written by itself, faster, then a whole bar
      at a time, until let go;
    - it moves the cursor only (`tab.set_cursor`), so a hold never adds the
      rest beats and bars that a single Next adds past the end, as the
      arrow key does;
    - it stops at the song's first and last beat;
    - a tap is still one step.
  - **Gate met:**
    - Studio: `test_tr34_view.py` (3);
    - RemoteKit 37: the demo's view, and the held step adding nothing;
    - UI tests: the view buttons, and a held Next going on four bars or
      more and a held Previous back to the start.
  - **Owed:** on a device against Studio 0.3.20.

- **Tabber Studio 0.3.19 and 0.3.20, built 2026-11-07; 0.3.20 installed.**
  - **0.3.19 (496326cc)** carried the chat fixes. It was built and checked,
    then never installed: 0.3.20 came the same evening.
  - **0.3.20 (0b95bf05)** adds `view/1`.
  - **Both were built and checked as 0.3.18 was:**
    - the certified engine abc7bd5e;
    - signed, notarized and stapled, and Gatekeeper accepts them;
    - the frozen-app smoke test passes.
  - **Installed** after the owner quit Studio, with 0.3.18 kept beside it
    as "Tabber Studio 0.3.18". The 0.3.17 app was removed; its DMG stays in
    rel0317.
  - **The DMG** is at
    /Volumes/Data/tabber_work/rel0320/download/Tabber-Studio-0.3.20-macOS-arm64.dmg.
  - **Running:** its remote listens on every address, the Tailscale one
    included.
  - **TestFlight builds 7 and 8:**
    - 7: where the sound plays;
    - 8: the view row and the held Previous and Next.

- **The view row again, and Studio's window, 2026-11-07: TestFlight build 9;
  Studio 0.3.21 (3db92ee9, be256d42) installed.** The owner: "the buttons go
  into each other. amateur UI. fix that and get it up on testflight. also
  ... when I press arrange and piano roll or split view it does not change
  in tabber studio when I choose it from mobile. fix it."
  - **The row (63d7061):**
    - Arrange, Tab and Piano Roll are one native segmented control;
    - Split is its own button beside it, and goes under it when the phone
      is too narrow;
    - checked on the iPhone 13 Pro (390 pt) and SE (375 pt) simulators;
    - every UI test passes.
  - **Studio did switch each time.** Its log and the Control API showed the
    new view. Its window was just not on the screen the owner looked at.
    Now a view picked on the phone also brings Studio's window to the
    front, and back from the Dock if minimized (`_bring_forward`;
    `test_tr34_view.py` now has 4 tests).
  - **Checked on the Mac Studio, against the installed 0.3.21:**
    - a throwaway device, paired through the local Control API, picked each
      view in turn;
    - before each pick, Studio was either behind Finder or hidden;
    - each time Studio came to the front with its window on screen;
    - the device was then revoked, so only the owner's iPhone stays paired;
    - a minimized window was not tried on the real app.
  - **0.3.21 was built and checked as 0.3.18 was:**
    - the certified engine abc7bd5e;
    - signed, notarized and stapled;
    - the frozen-app smoke test passes.
  - **Installed** in place of 0.3.20, with 0.3.18 still beside it. The DMG
    is at
    /Volumes/Data/tabber_work/rel0321/download/Tabber-Studio-0.3.21-macOS-arm64.dmg.
    0.3.20's DMG stays in rel0320.
  - **Owed:** on a device against Studio 0.3.21: the view row, and Studio
    coming to the front.

- **Response time on the phone, 2026-11-08 (TR7's gate; TestFlight build
  10).** The target is 19 taps in 20 confirmed within 150 ms on home Wi-Fi,
  with AirDrop on and off, and nothing measured it.
  - **The Computer sheet** (tap the computer's name at the top) has a
    Response time section:
    - Typical (the median) and "19 in 20 taps within" (p95), over the last
      taps, newest 500;
    - Start again, for a second run such as AirDrop on after AirDrop off.
  - **What counts:**
    - every change, from sending it to applying the computer's answer,
      which is when the phone shows the confirmed state;
    - not reads, and not the chat, whose answers wait for the AI;
    - one answer per request: a resend after a drop is timed on its own
      connection, and the wait for the connection is not;
    - kept across reconnects.
  - **Studio answers Record at once:** `recording.start` returns without
    waiting for the count-in, so Record taps don't skew the numbers.
  - **Gate:**
    - RemoteKit 41: the percentiles, what counts, Start again;
    - UI tests: the sheet before and after a tap on Play, and Start again;
    - the rows grow with the text: at the largest size, Start again is
      over 70 points tall and the note wraps;
    - the accessibility audit passes. It leaves out Dynamic Type for these
      two rows only, because it flags rows at the foot of this long sheet:
      "Leave the demo" failed there too, and passes higher up.
  - **The demo** now offers the app's own protocol version (1.4) rather than
    1.3. Nothing changes on screen: the demo checks only the major version
    and lists every capability.
  - **Owed to the owner,** on the iPhone against Studio 0.3.21 on the home
    Wi-Fi:
    - about 30 taps with AirDrop off, then a screenshot of the sheet;
    - Start again, about 30 taps with AirDrop on, then another.

- **TR3's stress test, 2026-11-08: playback passes, on the installed Studio
  0.3.21 (the owner: "yes, run it now").**
  - **The run:** `tools/remote_feed_stress.py --minutes 10 --play`, from
    00:07 to 00:17 on the Mac Studio:
    - two software phones paired through the local Control API, following
      every M1 topic at full rate;
    - the bundled example "First notes" (a synth with reverb) looping its
      four bars at 104 BPM;
    - the owner's iPhone stayed paired.
  - **Result:**
    - each phone: meters 20 a second, position 10 a second, no gap in
      `seq`;
    - the engine: 103,457 callbacks, 0 xruns, 0 deadline misses;
    - PASS: zero dropouts.
  - **Afterwards:** the phones revoked (only the owner's iPhone stays),
    Loop off, an empty song open again, as before the run.
  - **Still owed: the recording half** of the gate, which needs an armed
    input.

- **TR35 ✅ 2026-11-08: practice speed (protocol 1.5, 967ad84; Studio
  4df3af1c, 0.3.22; TestFlight build 11).** The owner chose it as the first
  stretch item. The plan's S6, "loop the solo at 70% speed and step the
  speed up", is Tabber Studio's own Speed Trainer.
  - **`trainer/1`:**
    - `trainer.state`, `trainer.set` (any of enabled, start, step and
      target) and the `trainer` topic, which sends each step as the loop
      comes round;
    - Studio's own controls: the phone sets the transport bar's Trainer
      button and fields, and the bar sends them on as after an edit there;
    - a changed field starts the ramp again from the start, as an edit in
      Studio's fields does;
    - with Loop off it is refused (`needs_loop`, 1039); not an undo step.
  - **Found in Studio and fixed:**
    - Loop set by the Control API, which is how the phone sets it, checked
      Studio's Loop button but skipped what a click does;
    - so the trainer stayed hidden, and a song slowed by the trainer kept
      playing slowly after Loop went off;
    - now Loop set from anywhere goes through `TransportBar.show_loop`, as
      a click does.
  - **On the phone:**
    - with Loop on, a Trainer row under Loop, Count-in and Metro, in
      Studio's order: Trainer, start + step → target, then the speed now;
    - the fields are menus in Studio's monospaced figures;
    - at the accessibility text sizes each field gets a line of its own,
      named, and the toggles stack instead of breaking words.
  - **Gate met:**
    - Studio: `test_tr35_trainer.py` (3), the remote suite (96 pass), and
      the loop and transport tests;
    - RemoteKit 42: the demo steps up each time its loop comes round;
    - UI tests: the trainer, and its largest-text layout;
    - the accessibility audit passes with the trainer showing.
  - **Fixed on the way:** Studio's rate-limit refusal test failed since take
    lanes, because it sent one request at a time and the bucket refilled
    whenever a request took over about 5 ms. It now floods with sixty cheap
    reads at once. The Bonjour test still fails while the installed Studio
    runs: environmental, as before.
  - **Owed:** on the iPhone against Studio 0.3.22: loop a part, Trainer on at
    70%, and hear it speed up.
  - **Studio 0.3.22 (1eddcce6), built 2026-11-08 and parked, not installed:**
    - built and checked as 0.3.18 was: the certified engine abc7bd5e,
      byte for byte once unsigned; signed, notarized and stapled;
    - the frozen-app smoke test passes, its hello now required to list
      `view/1` and `trainer/1`;
    - the app is at /Volumes/Data/tabber_work/rel0322/, and the DMG is in
      rel0322/download;
    - it installs once the owner quits Studio; until then the phone talks
      1.4 to 0.3.21, and only the trainer waits for 0.3.22.
    - Superseded by 0.3.23, which was installed instead (TR36).
  - **TestFlight build 11** was uploaded 2026-11-08, 07:26, with no
    warnings. The Mac slept for about six hours during the upload's
    archive step, and the upload finished when it woke.

- **The owner's notes from the iPhone, 2026-11-08 (TestFlight build 11):**
  - **"play button when pressed isn't going into a pause button and the
    other way around":**
    - Studio's Play is Play / Pause, ▶ that turns into ❚❚ while playing;
    - the phone's did the same thing but always drew ▶;
    - it now shows ❚❚ while playing and says "Pause" to VoiceOver.
  - **"count in didn't do anything, no difference when pressing count in
    and then play":**
    - Studio's Count-in is a recording count-in (its tooltip: "bars of
      click before capture starts"), and Play never counts in;
    - the phone does the same, so nothing was broken;
    - asked whether Play should count in too, the owner kept it for
      recording ("No, keep it for recording");
    - so the phone says it once, the first time Count-in is turned on
      ("Count-in counts one bar in before recording (●). Play starts at
      once, as in Tabber Studio."), and VoiceOver hears it as the button's
      hint.
  - **"the arrange and the stuff up top should stay up top even when you
    scroll down if there is a lot of tracks":**
    - the Tracks screen's view buttons, toggles and Speed Trainer are now
      pinned above the tracks;
    - at the accessibility text sizes they scroll with the list, since
      there they would fill the screen.
  - **"in mixer the buttons for mixer, undo ... and routing and bjorns mac
    studio are going into each other":**
    - the Mixer / Routing switch had a fixed width in the bar, beside Undo
      and the computer's name;
    - it now sits under the bar, full width and pinned;
    - the computer's name is capped at 150 points, so a long name never
      runs into the bar's other buttons;
    - a screenshot test (`-demo-name`) checks every screen's bar with a long
      name on the iPhone SE.
  - **Tests:**
    - the full UI suite, 30 tests;
    - the Routing test now scrolls its Vocals row into view under the
      pinned switch;
    - the accessibility walk taps Routing again if the page did not turn,
      since a tap right after the Mixer's audit can land mid-layout (twice
      in five runs; never in the Routing tests);
    - the walk then passes twice in a row.

- **TR36 ✅ 2026-11-08: add tracks from the phone (protocol 1.6, 10c107d;
  Studio d3ee7c9b and 1b2d007f, 0.3.23 a923849c; TestFlight build 12).** The owner: "add tracks,
  midi or tab or audio tracks at will to a project", first of all to a song
  of only audio files.
  - **`tracks.add/1`:**
    - `tracks.add` with kind tab, midi or audio takes the routes Studio's
      "+ Add Track" chooser takes (`ui/track_creation_controller.py`);
    - a tab track gets what the New Track dialog starts with, accepted as it
      opens, so nothing opens on the computer;
    - one undo step with Studio's own label ("Add track: Track 1"), which
      Undo on the phone takes back;
    - refused while recording (`already_recording`): a new track clears the
      record arms and would end the take;
    - a song at Studio's track limit is refused with `track_limit` (1040).
  - **Found in Studio and fixed:**
    - "+ Add Track" and its Audio track, from the Tab view, meant to show
      Arrange ("so the user sees the new track");
    - since the editors became a three-way cycle, it went on to the Piano
      Roll, which shows no audio;
    - it now goes to Arrange, from the phone too.
  - **On the phone:**
    - "+ Add Track" under the last track, a dashed ghost button as in
      Studio's track list;
    - it opens Studio's chooser in plain words: "What kind of track do you
      want to add?", Tab track, MIDI track, Audio track;
    - the new track comes into view, and "Track 1 added" offers Undo for
      five seconds, as a deleted take does;
    - the Tab screen of a song with no tab track offers "+ Add Tab Track",
      and writes on the new track at once;
    - greyed out during a take.
  - **Also fixed:**
    - the Tracks screen's large title vanished after a visit to another tab
      (since build 11's pinned controls, iOS 26);
    - the title now sits in the bar, as on the other screens.
  - **Gate met:**
    - Studio, `test_tr36_add_tracks.py` (5): each kind equals the track the
      computer's own "+ Add Track" makes (name, colour, instrument, strings,
      tuning, bars) and is one undo step the phone's Undo takes back, with
      nothing opening; in the all-audio song the tab track takes tab at
      once; the limit, recording and 1.5 refusals;
    - Studio, the remote suite (102 pass) and 147 track and view
      tests;
    - RemoteKit 43, with the demo's add, undo and refusals;
    - UI tests: each kind from Tracks, and the all-audio song on the Tab
      screen; the accessibility audit of the empty Tab screen; the full
      suite, 38, and 5 screenshot tests skipped as
      designed tests.
  - **Once, under load:** the Play / Pause test missed a pause while Studio's
    release build ran beside it; it passed three times in a row after, and
    in the full suite.
  - **Studio 0.3.23 (a923849c), built 2026-11-08 and installed:**
    - practice speed (0.3.22, never installed) and adding tracks, in one
      install;
    - built and checked as 0.3.22 was: the certified engine abc7bd5e, byte
      for byte once unsigned; signed, notarized and stapled;
    - the frozen-app smoke test passes, its hello now required to list
      `tracks.add/1`;
    - parked at /Volumes/Data/tabber_work/rel0323/, the DMG in
      rel0323/download;
    - the owner had quit Studio, so it is installed in /Applications, with
      0.3.18 kept as the fallback; 0.3.21 went to the Trash, and its DMG is
      in rel0321;
    - opened and checked: the remote listens on 9474 on every address, and
      a hello on the loopback and on the Tailscale address
      (100.114.215.101) gets 0.3.23, protocol 1.6 and `tracks.add/1`.
  - **TestFlight build 12** was uploaded 2026-11-08 at about 15:20, with the
    Mac kept awake this time (`caffeinate`).
  - **TR37 begun:** a read-only scan of the 0.3.22 and 0.3.23 apps, by
    pattern, prints file names only. Neither holds a key-shaped string, a
    private key, the owner's email, a home-folder path or the build's
    scratch path. The owner's name is only in six licence files, as the
    copyright holder ("Copyright (c) 2026 Bjorn Winqvist and Tabber Synth
    contributors"); whether those name Viga Works AB instead is the
    owner's call.
  - **Owed:** on the iPhone against 0.3.23, add a tab track to an all-audio
    song and write on it; and loop a part with the Trainer on (TR35).

- **TR37 under way 2026-11-08: release safety (Studio 42207a1e).**
  - **Both releases searched for the owner's own secrets:**
    - a script read the 16 secret values on this Mac (the DeepSeek key in
      Studio's preferences, the remote's certificate and private key, and
      Studio's development `api_key.md`) and printed only where each came
      from and how many files held it, never a value;
    - none is in the installed 0.3.23 app (1,798 files), in its unpacked
      Python code (2,722 files) or in the iPhone package as Apple received
      it (10 files).
  - **Scanned by pattern** for key shapes, private keys, the owner's email,
    name and home folder, the build's paths and home addresses:
    - the iPhone package is signed "Apple Distribution: Viga Works AB" and
      holds none of them; the local archive's development signature names
      the owner, but that copy is never sent;
    - the crash-symbols file holds the build's folder paths; it goes to
      Apple for crash reports and is not part of the app people download;
    - Studio's frozen Python code had the owner's home folder in the
      chat's plug-in paths: fixed, and a test now fails on any home-folder
      path in the packages the app bundles (`compat/`'s developer scripts
      with the owner's paths are never bundled);
    - harmless and public: the samples download link is on the owner's
      GitHub account, a docstring says "Bjorn's call", and the licences
      name the owner.
  - **Each user's own AI key:** Studio reads a key from the user's
    preferences or environment; the development `api_key.md` is skipped by
    a shipped app (`test_frozen_ignores_ai_md`), and neither app holds a
    key.
  - **The remote cannot be used to get in:**
    - a seeded fuzz run against a headless Studio, with every provider's
      key set to a marker: 43 malformed frames and raw method names before
      pairing, an oversized and a binary frame, and 647 hostile requests
      after pairing over 44 of the 48 verbs;
    - every answer is from the error table or a result its schema allows,
      never internal_error; no frame holds the AI key, the host's private
      key, the home folder or a file's contents; no file a payload names is
      created; the host still serves a phone after;
    - the chat's own verbs are covered by TR29's adversarial tests, which
      pass at the release's commit.
  - **The owner's decisions (2026-11-08), done:**
    - **AI keys in the Keychain** ("Use the Keychain"): `core/keychain.py`
      talks to macOS's Security framework through ctypes, so no package
      joins the release. A key saved in Studio goes to the login Keychain,
      one item per provider; a key the preferences held before moves there
      the first time it is read, the legacy DeepSeek setting included, and
      the preferences keep no copy. Without a Keychain (other systems) keys
      stay in the preferences. The remote's secret filter still knows every
      key. Every Studio test gets an in-memory Keychain, so no test touches
      the owner's own; one test uses the real Keychain on a service of its
      own. macOS may ask once whether Tabber Studio may use the key.
    - **Report a Problem** mails halibothalibot@gmail.com, the address the
      website gives ("Website's address"); a test allows no other address
      in the shipped code.
    - **The licences name Viga Works AB** ("Viga Works AB"): in
      tabber_synth (8eccf20), tabber_amp (76f479c) and tabber_limiter
      (ed227aa), and Studio's two vendored copies. The release's pinned
      inputs were copied with only their notices changed
      (native-inputs/synth-vw and limiter-vw, rel030/plugin-src-031-vw,
      rel0314/amp-dd782bd-vw, whose manifest's two digests follow), so no
      binary is rebuilt. Studio's release verifier no longer lets the
      owner's name through in any file, notices included.
    - Studio c3d4f29c and 0.3.24 (ead45c36); the release script uses the
      copied inputs, and its verifier is the proof that no file names the
      owner.
  - **Studio 0.3.24 (ead45c36), built 2026-11-08 and installed:**
    - the release verifier passed with no private match, the owner's name
      included; signed, notarized and stapled; the certified engine abc7bd5e
      byte for byte once unsigned; the frozen-app smoke test passes;
    - the frozen app's own `core.keychain` wrote, read, changed and deleted
      an item on a throwaway service in the real Keychain;
    - scanned again: no key shape, private key, email, name or home path in
      the app or its unpacked code, and none of the owner's 16 secrets;
    - parked at /Volumes/Data/tabber_work/rel0324/, the DMG in
      rel0324/download; installed in /Applications with 0.3.18 kept as the
      fallback (0.3.23 to the Trash, its DMG in rel0323); the remote answers
      1.6 with `tracks.add/1` on the loopback and on Tailscale;
    - the owner's DeepSeek key moves to the Keychain the first time the
      chat reads it; until then it is still in the preferences.

- **TR39 ✅ 2026-11-08: a MIDI part's card from the phone (protocol 1.7,
  6283639; Studio 4ff0525e, 0.3.25; TestFlight build 13).** The owner:
  "when adding a midi track, in tab mode, tabber asks for show midi or show
  notation right... can we make that selection from the app too? just so
  it's not stuck on that screen".
  - **`view.part/1`:** the `view` topic gains `part`, the chosen track while
    the Tab editor (the Tab view or Split's Tab pane) shows a MIDI track:
    `shows` is `card` while Studio's "MIDI part" card waits, then
    `midi_tab` or `notation`; `midi_tab` says whether the track can show
    MIDI tab (not drums). `view.show_part` presses the card's own buttons
    (`MidiTabEditor.open_view`, `staff_presentation.open_card`); a gone card,
    or MIDI tab for drums, is refused with `stale_target` and the view. Not
    an undo step.
  - **On the phone:** the Tab screen shows the card in Studio's words,
    Show standard notation and Show MIDI tab, then what the computer shows.
  - **Gate met:** Studio `test_tr39_midi_part.py` (4) and the remote suite
    (109); RemoteKit 44 with the demo's card; a UI test from Tracks to Tab
    with drums, the card's accessibility audit, and the full UI suite (39,
    the accessibility walk then twice in a row with the Piano tap retried
    after an audit, as Routing's is).
  - **Studio 0.3.25 (dbf292b7), built 2026-11-08 and installed:** the
    release verifier passed (no private match); signed, notarized and
    stapled; the certified engine byte for byte; the smoke test now requires
    `view.part/1`; no key shape, name, email, home path or owner's secret in
    the app or its code; parked at /Volumes/Data/tabber_work/rel0325/;
    installed with 0.3.18 kept as the fallback (0.3.24 to the Trash, its
    DMG in rel0324); the remote answers 1.7 with `tracks.add/1` and
    `view.part/1` on the loopback and on Tailscale.
  - **TestFlight build 13** was uploaded 2026-11-08 at about 17:25.
  - **Owed:** on the iPhone, add a MIDI track while the computer shows Tab,
    and answer the card from the phone.

- **TR40 ✅ 2026-11-08: tab on MIDI tracks from the phone (protocol 1.8,
  c20c1ed; Studio a12df43a, 0.3.26; TestFlight build 14).** The owner: "i
  still miss ... tabbing in midi tracks".
  - **`tab.midi/1`:** when the Tab editor shows the selected melodic MIDI
    track as MIDI tab, the tab/1 verbs and topic cover it, through Studio's
    own MIDI tab editor (`remote_host/midi_tab.py`, MidiTabController):
    - `tab` says `midi`; the strings are the MIDI tab profile's; each note
      is where Studio draws it, and a note out of the strings' frets keeps
      that fret, negative if need be, and says `virtual`;
    - a fret is the fret typed on that string at the caret (changed, added,
      or the same fret again taken off), and the caret stays, so frets on
      other strings make a chord; the piano is Studio's MIDI tab piano;
      note values, Next, R and Delete are its toolbar and keys;
    - each edit is one undo step with Studio's label ("Write staff note",
      "Delete staff tones", "Edit MIDI tab beats", "Toggle rest"); the
      track keeps its instrument;
    - MIDI holds one of each pitch at a time: a pitch already sounding in
      the beat is refused, "That pitch already sounds in this beat, on
      another string.";
    - only while the computer's Tab editor shows it; else `no_tab`.
  - **On the phone:** Show MIDI tab on the card opens the track's tab, and
    everything on the Tab screen works on it.
  - **Found first by a headless probe:** Studio's MIDI tab editor works
    headless with the window shown, its typed frets leave the caret where
    it is, as the phone's frets do, and its piano moves on.
  - **Gate met:** Studio `test_tr40_midi_tab.py` (2) and the remote suite
    (111); RemoteKit 45 with the demo's MIDI tab; the card's UI test writes
    a fret on the MIDI tab; the full UI suite (40).
  - **Studio 0.3.26 (c443c7da), built 2026-11-08 and installed:** the
    release verifier passed; signed, notarized and stapled; the certified
    engine byte for byte; the smoke test requires `tab.midi/1`; no key shape,
    name, email, home path or owner's secret in it; parked at
    /Volumes/Data/tabber_work/rel0326/ (its DMG named for the website,
    Tabber-Studio-0.3.26-macOS-arm64.dmg); installed with 0.3.18 kept as the
    fallback; the remote answers 1.8 on the loopback and on Tailscale.
  - **TestFlight build 14** was uploaded 2026-11-08 at about 18:15.
  - **On the website (the owner, 2026-11-08: "After the redesign lands"):**
    the site still offers 0.3.16. Another session's work on the site sits
    uncommitted in Studio's repo since before this session: Swedish and
    Faroese pages, a homepage built from templates with 16 new screenshots,
    and release pages built per language. 0.3.26's DMG goes to the server
    unlinked now, and onto the releases page and the download button once
    that work is committed. The server refused SSH from this Mac twice at
    about 18:20 (it shuts out quick reconnects), while the site answered;
    the upload is to be tried again later.
  - **Owed:** on the iPhone, answer a MIDI track's card with Show MIDI tab
    and write a riff on it.

- **TR41 ✅ 2026-11-08: Add Bus from the phone (protocol 1.9, 60d204c;
  Studio 3ecb8d82, 0.3.27; TestFlight build 15).** The owner: "i still miss
  add bus".
  - **`mixer.add_bus/1`:** the mixer's "+ Bus" once its New Bus dialog has
    a name (`remote_host/mixing.add_bus`): the next bus id as the dock picks
    it, then the dock's `bus_created`, as the dialog's OK sends it; song,
    engine, mixer and routing follow. The name is trimmed as the dialog
    trims it, and must hold more than spaces (the schema says so too, so
    the vectors' validator agrees with the host). Not an undo step, as in
    Studio, where only deleting a bus is one.
  - **On the phone:** the row under the bar holds Mixer, Routing, Flow and,
    as Studio's mixer header, a compact dashed "+ Bus" that asks for the
    name in Studio's words ("New Bus", "Bus name:"), its buttons in plain
    words; the new strip scrolls into view.
  - **Gate met:** Studio `test_tr41_add_bus.py` (2): the phone's bus equals
    the computer's own "+ Bus"'s, in the song, mixer and routing at once,
    with no undo step; RemoteKit 46 with the demo's Add Bus; a UI test and
    a screenshot test on the iPhone SE.
  - **Fixed on the way:** RemoteKit's dead-address race test now asks for a
    connection within the hello's timeout, which is what waiting out the
    dead address would take, instead of a second: run beside the suite's
    other tests on a busy Mac it took 1.0 to 1.2 s, alone 0.08 s.

- **TR42 ✅ 2026-11-08: the routing Flow on the phone (this repo only;
  TestFlight build 15).** The owner: "i still miss ... the routing flow
  thing".
  - **Studio's Flow, laid out as its Flow tab lays it out**
    (`ui/routing_graph_view.py`): the tracks in mixer order in the first
    column, the buses in columns by cascade depth, the master last and
    centred on the tracks; routes and sends from output ports to input
    ports in Studio's teal, a send's level on a pill, the default route to
    the master dimmed, a muted card dimmed. Drawn from the routing and
    mixer topics the phone already follows, so no protocol change.
  - **On the phone:** Flow is the Mixer's third page. It opens fitted to
    the screen, as Studio's opens fitted to its window; a pinch zooms in, a
    drag pans and a double tap fits it again. Read only: the Routing page
    changes it.
  - **Accessibility:** each card says where it goes, and each send's pill
    says its source, bus and level; the audit passes, with only its text
    size checks set aside inside the diagram, whose words grow with a pinch
    and whose routing the Routing page gives in text that grows.
  - **Not yet:** Studio's Flow also draws sidechains and each card's
    plug-in count; the routing topic carries neither, so they need a
    protocol addition.
- **TR43 ✅ 2026-11-08: wiring by hand in the Flow, and the master fader
  (Studio 0.3.28).** The owner: "when i slide the master volume in the app
  its not changing in tabber studio" and "in flow, i dont seem to be able to
  move by hand the connections manually".
  - **The master fader (Studio 9f7e5ca8, 0.3.28 at 5eacd919):**
    `mixer.set_master_gain` set the song and the engine but left the mixer's
    master strip where it was, so the computer looked unchanged; the phone,
    the chat and scripts all use it. `project.set_properties` also missed
    the engine: it looked for `mw._engine`, which the window does not have.
    Both now go through `apply_master_gain`: the song and the engine, as the
    master fader's own handler does, then the strip, without echo. Tests
    check the strip's fader and label and the engine for both commands.
  - **Wiring in the Flow (this repo):** drag from a card's teal output port
    (a handle a thumb wide at any zoom) onto a bus or the Master. On the
    Master the output goes back there; on a bus a track chooses Output or
    Send (Studio's plain or Option drag) and a bus moves its output, or is
    refused as "Reverb would loop: Delay → Reverb → Delay.". Press and hold
    a card for its menu (output, send to, remove send), which VoiceOver also
    gets as actions; a hint line under the diagram says how. Each change is
    one undo step on the computer, through the routing verbs the Routing
    page uses, so no protocol change.
  - **Tests:** FlowUITests (three), and the accessibility, mixer, routing
    and welcome suites: 17 passed.
  - **Studio 0.3.28 released and installed:** the verifier, the engine byte
    for byte, the smoke test and the TR37 scans pass; parked at
    /Volumes/Data/tabber_work/rel0328 (DMG 486,446,958 bytes, SHA-256
    3f0bb3c7...); installed with 0.3.18 kept and 0.3.27 in the Trash; the
    remote answers 1.9 with every capability on the loopback and Tailscale.
    Not on the website, which offers 0.3.27; Spak needs nothing newer.
  - **Not yet:** tapping a wire to select and delete it, as Studio's Flow
    does; the card's menu removes a send, and dropping on the Master undoes
    an output.
- **TR44 ✅ 2026-11-09: plug-ins from the phone (protocol 1.10, Studio
  3d5026f9, 0.3.29).** The owner: "should you be able to insert plugins on
  tracks from the app?", then "yes".
  - **Protocol 1.10, `plugins/1`** (cc67548): each mixer strip carries its
    `inserts` (name, bypassed, auto_bypassed); `plugins.catalog` gives the
    Insert Plugin browser's rows, 200 a page, since a message is at most
    64 KB; `plugins.insert`, `plugins.bypass`, `plugins.remove` and
    `plugins.open`. None is an undo step, there or here. `stale_target` may
    carry the mixer, for an insert gone from its strip.
  - **Studio:** the rows are the browser's, in its order (Tabber's own, then
    the scan cache): on the owner's Mac 96 rows in one 19.5 KB page. Insert
    is the browser's own `PluginInsertController.begin_insert` on the
    strip's chain (a track's is its strip's index in the timeline, as the
    mixer builds it), so the plug-in loads in the background, opens its
    window on the computer and is saved as there; it and `insert_native`
    take `on_done`, so a refusal reaches the phone, not a message box on a
    computer nobody is at. Bypass and Remove are the strip menu's own
    actions, split into raising `bypass()` and `remove()`.
  - **The phone:** an INSERTS zone on every strip, as Studio's: "● Name",
    "○ Name" bypassed, then a dashed "+ Plugin"; one height on every strip
    so the faders stay level, growing with the text size (a preference key
    keeps the tallest); a long chain shows "+k more…". A slot opens a
    sheet of choices: Open on the computer, Bypass or Un-bypass, Remove.
    "+ Plugin" opens Insert Plugin: Tabber Plugins and Plugins, All, VST3
    and CLAP, Search plugins; a greyed row says why; it waits up to three
    minutes for a plug-in to load, shows "Loading … on …", and keeps a
    refusal in Studio's words on screen. An instrument on a MIDI track says
    it is now the track's sound source. The demo has Tabber's five and two
    "Demo Audio" plug-ins.
  - **Tests:** Studio's TR44 tests (4) with stand-ins; RemoteKit 47,
    including the demo's plug-ins and every vector's round trip; UI tests
    22, PluginsUITests (3) and the Insert Plugin browser's audit among
    them. The audit flagged a slot drawn as two texts; one label, as
    Studio's, passes with nothing left out. The browser's iOS search field
    and Cancel button are left out of the audit, as the sheet's Done was.
  - **Studio 0.3.29 released (c976dcab):** the verifier, the engine byte for
    byte, the smoke test (which now requires plugins/1) and the TR37 scans
    pass; parked at /Volumes/Data/tabber_work/rel0329 (DMG 486,401,240
    bytes, SHA-256 1340ac35...). Installing waits for the owner to quit the
    running 0.3.28.
  - **Owed:** a real insert on the owner's Mac from the phone (the release
    smoke test runs the remote without an engine), with TestFlight build 18,
    which the owner uploads.

- **Studio 0.3.27 (916000de), built 2026-11-08 and installed:** the release
  verifier passed; signed, notarized and stapled; the certified engine byte
  for byte; the smoke test requires `mixer.add_bus/1`; no key shape, name,
  email, home path or owner's secret in it; parked at
  /Volumes/Data/tabber_work/rel0327/ (its DMG named for the website);
  installed with 0.3.18 kept as the fallback; the remote answers 1.9 with
  `tracks.add/1`, `view.part/1`, `tab.midi/1` and `mixer.add_bus/1` on the
  loopback and on Tailscale.
- **The website server** refused SSH from this Mac again at about 18:45, a
  third time, while the site answered: no longer a brief cool-down. The
  DMG upload waits for the owner to look at the server.
  - **Left as they are, public:** the samples download, and the Synth's
    source record, point at the owner's GitHub account.
  - **Found on the way, not ours:** in Studio's `tests/core`, the warp and
    tempo-retime persistence tests, the mixed-lane interchange report and,
    in a long run, the metronome toggles fail; they fail at f71481fb too,
    before this work.
  - **App Store (TR38) begun:** the texts are in `apple/AppStore/`
    (e2633e3), and the 6.9-inch screenshots, 12 screens of demo mode, are
    in /Volumes/Data/tabber_remote/appstore-screenshots/6.9-inch. The
    privacy page waits for the website, which another session is editing.
- **2026-11-08, evening: the App Store (TR38) and the website.**
  - **TestFlight build 16** (c4ddadd), uploaded by the owner with
    `release-ios.sh --external`, is the build to submit; up to build 15
    they were internal-only.
  - **The server** took SSH again at 19:41.
  - **Studio 0.3.27 is on the server, unlinked and unserved:**
    `/home/robot/tabber/downloads/Tabber-Studio-0.3.27-macOS-arm64.dmg`,
    sha256 1adc35a126cace324ee6afe04a3266f4d6423e4df9e22130685d413c07bd3252,
    checked there. nginx serves a download only from `site/current/downloads`
    (the earlier DMGs are hard links there) or from an exact location block,
    so linking it is a hard link and the pages.
  - **The website session's redesign is live but uncommitted:** `sv/`,
    `fo/` and the new homepage went up 2026-11-07 14:06. In Studio's tree,
    the homepage is now generated (`scripts/website_homepage.py`, with its
    templates and locales, untracked). A Spak link on the homepage, in three
    languages, belongs in that work.
  - **Tabber Spak's page,** `docs/website/spak/index.html` (Studio ef5b499c).
    The owner: "it must be clear what tabber studio does and what tabber
    spak is and that tabber works without spak, its just a remote control
    for tabber." It is built from the site's own parts. The App Store button
    says "coming soon" until Apple approves the app. The page is the
    listing's Support and Marketing URL. The privacy page names Studio's
    Settings > Remote, as the phone does.
  - **Not live yet:** the classifier refused this session's deploy to the
    live site as a production deploy. `docs/website/deploy/publish-spak.sh`
    publishes `spak/` alone, for the owner to run.
  - **The App Store texts** (description, promotional text, review notes)
    now begin with what each app is, and say that Studio works without Spak.
  - **Found: Spak needs a Studio the website doesn't offer yet.** The remote
    came into Studio on 2026-11-07, after 0.3.16, which is still the
    website's download, and Spak speaks protocol 1.9 (0.3.27). So the
    website must offer 0.3.27 before Spak is released (Manual release), and
    preferably during review, since the review notes name the website.
  - **Submitted for review** at 20:35 by the owner: version 1.0 (16),
    submission 169f27a4-eb29-4dcf-8816-a1dc1298cc4e, Waiting for Review.
    The Spak pages went live when the owner ran `publish-spak.sh`; both
    answer 200. App Store Connect's main iPhone screenshot slot is now
    "iPhone with Dynamic Island (medium display)": 1206 x 2622 or
    1179 x 2556 only, so it refused the 1320 x 2868 set. The 10 screens
    went in from `appstore-screenshots/upload-6.3-inch`, scaled from the
    6.9-inch ones. Answers: Data Not Collected, no third-party content,
    every age-rating feature No, Free, Music.
  - **Next:** after approval, the App Store link on the Spak page (and
    `publish-spak.sh` again), and the link and a QR code in Studio's
    Preferences > Remote. Before release: the website offers Studio 0.3.27.
  - **The website, the same evening.** The owner: "i dont see any
    placeholder for spak with coming soon" and "the latest tabber studio
    build is not uploaded", then, of the website session's uncommitted
    redesign, "commit th shit". It is committed as it is live (Studio
    b19c2aa2, all ten pages byte for byte). On it (8867c9ba): the macOS
    download moves to 0.3.27, with a release entry in English, Swedish and
    Faroese (the Faroese is Claude's, unchecked by a native speaker), and
    every homepage gets a Tabber Spak section and header link: coming soon
    to the App Store, free, Tabber Studio works without it.
    `docs/website/deploy/publish-site.sh macos-0.3.27 --download
    Tabber-Studio-0.3.27-macOS-arm64.dmg` publishes it; the classifier
    refused it to this session, so the owner ran it at 20:58: the DMG is
    served by a hard link (same inode as the staged file, 486,344,510
    bytes), 13 files changed, the replaced ones are in
    site/backup-before-macos-0.3.27-20261108T195801, and all 13 live files
    equal the commit. So the automatic App Store release is fine now.
  - **Studio's Remote page is in Preferences, not Settings:** Qt's macOS
    menu item is "Preferences..." and the dialog's title is Preferences.
    The phone said "Settings › Remote" in four places (Welcome, FixIt), so
    did the Spak pages and the App Store privacy text; all now say
    Preferences. Build 16, in review, still says Settings; the next build
    carries the fix.

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

**Checked 2026-11-07:**
- Xcode 27 requirements and changes: [Xcode 27 Is Out](https://blakecrosley.com/blog/xcode-27-release) (secondary, quoting Apple's release notes)
- App Store submissions for the 27 releases: [Apple developer news](https://developer.apple.com/news/?id=k1mtkt1k)
- Uploads with the iOS 27 SDK: [checklist](https://ecorpit.com/app-store-ios-27-sdk-requirement-april-2027/) (secondary)
- iPhone Duo: [Preparing your app for iPhone Duo](https://developer.apple.com/documentation/technologyoverviews/preparing-your-app-for-iphone-duo.md)
- Android local network permission: [Android developers](https://developer.android.com/privacy-and-security/local-network-permission)
- Google Play target API: [Play Console Help](https://support.google.com/googleplay/android-developer/answer/11926878)
- Library versions: PyPI for [websockets](https://pypi.org/project/websockets/), [cryptography](https://pypi.org/project/cryptography/), [segno](https://pypi.org/project/segno/)

**Live audio over a network:**
- [SonoBus guide](https://sonobus.net/sonobus_userguide.html)
- [AudioRelay FAQ](https://audiorelay.net/docs/faq)
- [Ableton Link Audio](https://www.soundonsound.com/techniques/ableton-live-link-audio-wireless-future)
