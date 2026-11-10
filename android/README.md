# Tabber Spak for Android

The Android version of Tabber Spak, plan.md's TR24: native Kotlin and Jetpack Compose, the same
protocol and vectors as the iPhone app in `apple/`, made on the owner's Linux laptop. Android is
"another client for the same protocol, not a new design" (guiding principle 8).

The repository is a clone of tabber_remote with the Android work on top, as Storman's Android
port is. `origin` is tabber_remote_android (push here); `upstream` is tabber_remote, which this
clone only fetches (its push URL is disabled on purpose). The protocol, its schemas and vectors
and the iPhone app come here by merging upstream; protocol changes are made there, with their
vectors, never here.

## Requirements

- The Android SDK in `~/Android/Sdk` (platforms 36 and 37, build tools) and Android Studio's JDK
  in `/opt/android-studio/jbr`. Gradle comes with the wrapper.
- For the interop check: a Tabber Studio checkout beside this repository
  (`../tabber_studio_linux` or `../tabber_studio`) with its venv; it provides the real
  `remote_host`.
- For the Studio check: Tabber Studio Linux beside this repository, with its packaged app
  (`dist/Tabber-Studio-latest.AppImage`) and `jackd`. The check runs Tabber Studio on a private
  JACK server with no sound card, so nothing is heard and no microphone is recorded.
- A phone with USB debugging, or the emulator: `android/scripts/emulator.sh start`.

## Commands

```bash
cd android
./gradlew :remotekit:test          # every protocol vector, the session, the demo computer, on the JVM
./gradlew :app:testDebugUnitTest   # the tuner's pitch detection and its arithmetic, on the JVM
./gradlew :app:lintDebug           # Android's own checks: no errors
scripts/interop.sh                 # RemoteKit against Tabber Studio's real host (TLS 1.3, pinned)
scripts/emulator.sh start          # the test phone, headless and without audio
./gradlew :app:connectedDebugAndroidTest    # the screens against the demo computer, and Bonjour
../../tabber_studio_linux/scripts/with_jack_dummy.sh \
    ../../tabber_studio_linux/.venv/bin/python scripts/studio-check.py   # S1 and a restart, against the installed Tabber Studio
./gradlew :app:assembleDebug       # app-debug.apk: com.tabberspak.app.debug, beside a Play build
scripts/release-android.sh --local # a signed .aab in ~/tabber-spak-releases/, nothing committed
scripts/release-android.sh         # build N+1 for Play: checks, .aab, then commit, tag android-b<N>, push
python3 scripts/draw-icon.py       # the icon, drawn again from the iPhone's design
scripts/emulator.sh stop
```

The UI tests, the Studio check and the release script's smoke test all use the one emulator; run
them one after another.

Run Gradle with `JAVA_HOME=/opt/android-studio/jbr` (the scripts set it).

## Decisions

- **Stack:** Gradle 9.4.1, Android Gradle Plugin 9.2.1 (it compiles the app's Kotlin itself, with
  Kotlin 2.2.10), Compose BOM 2026.09.00. `compileSdk` 37, because those Compose libraries need
  it; `targetSdk` 36, Google Play's level for new apps since 31 August 2026.
- **`minSdk` 29 (Android 10):** Tabber Studio's host accepts TLS 1.3 only
  (`remote_host/server.py`), and Android has TLS 1.3 from 10.
- **Third-party code: OkHttp only** (owner, 2026-11-08). Android has no WebSocket client of its
  own. OkHttp is Apache 2.0, the Android standard, and sends nothing anywhere. Kotlin's
  coroutines (JetBrains) and the AndroidX and Compose libraries (Google) are the platform's own.
  JSON is RemoteKit's own small parser, so every message round-trips exactly, as on iOS.
- **Pairing with the phone's own camera** (owner, 2026-11-08): the camera app opens the QR code's
  `tabber-remote://pair?...` link, and Tabber Spak takes it from there. No scanner in the app, no
  camera permission, no barcode library. The 6-digit path is for phones without a camera app
  that opens links.
- **The device key** is ECDSA P-256 in the Android Keystore (`KeystoreSigner`), in StrongBox where
  the phone has one, as the iPhone keeps its key in the Secure Enclave. It never leaves the phone.
- **RemoteKit** (`android/remotekit`) is a plain Kotlin library with no Android API, as
  `apple/RemoteKit` imports no UI framework, so the protocol runs and is tested on the JVM.
- **The version** is the iPhone app's `MARKETING_VERSION`, read from its Xcode project, so both
  phones say the same. The build number is `android/BUILD_NUMBER`.
- **Signing:** the Google Play upload key is `~/.android-keys/tabberspak-upload.jks` (made
  2026-11-09, RSA 4096, valid to 2054) and its passwords are `TABBERSPAK_UPLOAD_*` in
  `~/.gradle/gradle.properties`, never in this repository, as for the owner's other Android apps.
  Its certificate's SHA-256 is `store/upload-certificate.sha256`, which the release script checks
  every bundle against. Back up the `.jks` and those four lines together: without them no update
  can be uploaded (Play can reset an upload key, slowly).
- **The launch options** (`reset`, `demo`, `known_host`, `pair_link` and the rest, for tests and
  scripts) work in debug builds only. Any app may start the activity, and in a release build they
  would let it pair the phone with another computer or make it forget its own. On the iPhone only
  Xcode passes launch arguments.
- **Nothing is backed up or moved to a new phone** (`res/xml/data_extraction_rules.xml`): the
  pairing belongs to this phone's Keystore key, so a new phone pairs again.
- **Touch targets are 48 dp**, Android's figure, where the iPhone uses Apple's 44 points.

## Sprints

Proposed; the owner schedules them, one per session (plan.md, Rules for every sprint).

| Sprint | What | Gate |
|---|---|---|
| TA1 | Project; RemoteKit's JSON, every model, the crypto; the OkHttp transport pinned to the computer's key, TLS 1.3; the client (hello, pair, auth, subscribe, heartbeats); the Keystore key; pairing from the camera's link | Every vector passes in Kotlin; interop against Tabber Studio's real host; the debug app pairs on the emulator |
| TA2 | The session: reconnect, racing the routes, the snapshot and events with gap detection, idempotency keys, busy and missed heartbeats; remembered computers; Bonjour with NsdManager; 6-digit pairing; DemoHost and its tests | DemoHost session tests as on iOS; on the emulator, reconnects after the host restarts |
| TA3 | Tracks, the transport that never moves, the take card, Go to: S1 | S1 against Tabber Studio on the emulator; Compose UI tests against DemoHost |
| TA4 | Tab, Mixer, Routing and Flow, Chat, Tuner, add track and bus, the trainer, the computer's view: the iPhone 1.0's whole set | UI tests against DemoHost for every screen |
| TA5 | Polish: the icon from the iPhone app's, the theme, TalkBack, the largest text, fix-it cards, keep awake; the release script and the upload key | An accessibility pass; a signed release build |
| TA6 | Google Play internal testing: the signed bundle, Data safety (no data collected), the privacy page | TR24's gate: S1 on a real phone, the build in internal testing |

## Records

### TA1, 2026-11-08

- **RemoteKit:** `Json` (numbers as doubles, nulls kept, keys sorted), every model of
  `apple/RemoteKit` with the same null-or-absent rule per field, `RemoteCrypto`, `Base64Url`,
  `Route` and `PairingLink`, `SoftwareSigner` (the public point read from the PKCS#8, no curve
  arithmetic of our own), `OkHttpTransport` with `PinTrust`, and `RemoteClient`.
- **Vectors:** 38 tests pass (`./gradlew :remotekit:test`): 9 crypto (pins, device ids, signed
  bytes and signatures, a signature made here verified there, the 6-digit codes, the QR link and
  four bad links), all 25 exchange files (every host message decodes and encodes back to the same
  JSON; an unknown field or topic fails), and 4 JSON tests. Dropping one explicit null (a loop's
  `start`) fails most exchange files, so the check bites.
- **Interop:** 3 of 3 against `remote_host` from the Linux Tabber Studio 0.3.27 checkout
  (`scripts/interop.sh`): pair by token over pinned TLS 1.3 at protocol 1.9, a raw Control API
  method refused (`method_not_found`), authenticate on a second connection; a wrong pin never
  talks to the host; with no pin the client sees the host's key.
- **On the emulator** (`scripts/pair-check.sh`, GoPast_Light, Android 16): the debug app took the
  pairing link as the camera would, paired with the real host at 10.0.2.2 with its Keystore key,
  and said so on screen (`shots/pair-check.png`, not committed). TA3 retired the script: the app
  now pairs as soon as the link arrives, and `scripts/studio-check.py` pairs with the installed
  Tabber Studio instead of the source tree's host.
- **Found:** `apple/RemoteKit/Tests/RemoteKitTests/InteropTests.swift` still expects
  `protocol_version` "1.0", but its client now offers only "1.9", and the current host answers
  "1.9". The Kotlin test expects the version the client offers. The Swift test belongs to
  upstream (the Mac); reported to the owner.

### TA2, 2026-11-08

- **The session** (`RemoteSession`, as `apple/RemoteKit`'s): one coroutine thread owns the
  state and publishes it as a `StateFlow`. It reconnects with backoff, tries at once when the app
  comes back on screen, names trouble only after 4 seconds of trying (unreachable, the local
  network refused, a wrong key, which side to update), sends each change with an idempotency
  key, counts a connection silent for 6 seconds as dead, and asks for a snapshot when an event
  is missing.
- **Every address at once** (`RacingTransport`), the remembered addresses with a Bonjour lookup
  between rounds (`RouteBook`), and `ResponseTimes` for TR7's gate measured on the phone.
- **Remembered computers** in the app's preferences. **Bonjour** with NsdManager (`Discovery`):
  the Find screen's list, and a paired computer found again after its address or port changed.
- **The 6-digit code** (`pair` in mode `code`) for phones whose camera app does not open links.
- **The demo computer** (`DemoHost`, over `MemoryTransport`): a simulated Tabber Studio for the
  tests, and for trying the app without one.
- **Tests:** 77 on the JVM (`./gradlew :remotekit:test`): TA1's 41, the demo computer's 20, the
  session's 15 (reconnecting, racing, response times) and the event order's 1. 74 pass; the 3
  interop tests run only under `scripts/interop.sh`, where they pass against the host of Linux
  Tabber Studio 0.3.27.
- **On the emulator** (`scripts/studio-check.py`, see TA3): the phone reconnected by itself
  5.9 seconds after Tabber Studio quit and started again, Tabber Studio's own start included.
- **Found and fixed:**
  - The session asked for a new snapshot on every event already in the last one; spec 8.2 says
    to ignore those. Against the real Tabber Studio the phone lost its connection after arming
    a track. `EventOrderTests` fails without the fix.
  - The app ended when Tabber Studio quit. The Bonjour lookup between reconnect rounds handed
    NsdManager's late callbacks to an executor it had already shut down, and a task rejected on
    NsdManager's thread ends the app. On a phone on the same Wi-Fi as Tabber Studio, every
    lookup that found the computer, and every visit to the Find screen, would have ended it the
    same way. Callbacks now run on NsdManager's own thread, as its overloads without an executor
    do. `DiscoveryTest` (the phone advertises a Tabber Studio of its own and looks it up three
    times) ends the app without the fix.
- **Found upstream** (the iPhone app, reported to the owner):
  `apple/RemoteKit/Sources/RemoteKit/RemoteSession.swift` line 258 has the same event rule: it
  asks for a snapshot on any event that is not exactly the next one, stale events included.

### TA3, 2026-11-08

- **Screens** (Compose, Tabber Studio's colours): the welcome (get started, paste a link, the
  demo), finding the computer, pairing (the link and the 6-digit code), the computer sheet,
  Tracks (each track's card and arm button, adding a track, the computer's view, loop, count-in
  and the click, the trainer), the transport that never moves (stop, play, record, the readout),
  Go to, the take card (keep, delete, go again), Undo for a deleted take, and the problem banner.
  Tab, Mixer, Tuner and Chat wait for TA4.
- **UI tests against the demo computer** (`./gradlew :app:connectedDebugAndroidTest` on the
  emulator): 5 of 5 pass. The song shows; a track is chosen, soloed and muted; the whole take
  loop (arm, record, stop, delete, Undo, go again); and Bonjour's 2.
- **S1 against Tabber Studio** (`scripts/studio-check.py`): Linux Tabber Studio 0.3.27 as
  installed, on a private JACK server with no sound card (its route checked as native JACK
  before anything else). The phone took the pairing link as the camera would and was connected
  2.7 seconds later. It armed Vocals, recorded, stopped, deleted the take and brought it back
  with Undo, each step read back from Tabber Studio over the Control API (1 take, then 0, then
  1). Then Tabber Studio quit and started again, and the phone reconnected by itself.

### TA4, 2026-11-09

- **Screens**, each in its own file as on the iPhone: Tab (the staff around the cursor, the note
  values, Dot, Triplet, Rest and Delete, Previous and Next that run on while held, the fretboard
  and the piano at the iPhone's measures, the MIDI part card, a new tab track for a song of only
  audio, Undo and the tab tracks in the title's menu); the Mixer (a strip per track, then the buses
  and the master: pan, S and M, a fader on Tabber Studio's scale with its meter, + Bus); Routing
  (outputs, with a bus that would loop shown and not offered, sends with PRE, removing one, Undo);
  Flow (Studio's routing graph, fitted to the screen, pinch to zoom); Chat (opened with the phone's
  own lock, the plan, Execute, Stop, a key refused in words); and Tabber Tuner (by a helper agent
  on its own branch, merged: the iPhone's YIN detector and biquad, the microphone through
  AudioRecord with voice processing off, nothing recorded, the demo's guitar tuned string by
  string).
- **Tests:** 37 UI tests on the emulator against the demo computer pass in one run
  (`./gradlew :app:connectedDebugAndroidTest`): Tab 7, Mixer 2, Routing and Flow 3, Chat 3, Tuner
  2, and the iPhone's suites for the TA3 screens, ported now: Tracks 8, Welcome 5, the Computer
  sheet 1, the take loop 4, Bonjour 2. On the JVM: the tuner's 38 (`:app:testDebugUnitTest`) and
  RemoteKit's 78.
- **Differences from the iPhone, on purpose:**
  - The tuner's window grows until it reaches A0 (4096 samples at 44.1 and 48 kHz), so a guitar's
    low E and a bass read. The iPhone's fixed 1024 samples reach down to about 94 Hz at 48 kHz.
  - Chat opens with the phone's own lock through BiometricPrompt (a fingerprint, the face, or the
    PIN, pattern or password), as the iPhone asks for Face ID, Touch ID or the passcode.
  - Fix-it's Pair again goes back to the welcome and its camera steps: on Android the camera app,
    not the app, scans the code.
  - Android lets an app ask for the microphone again after a refusal; the tuner remembers one and
    shows the way to Settings, as the iPhone does.
- **Found and fixed**, each by a ported test or by lint:
  - A launch with `reset` kept what was on screen (the model outlives its activity, and the tests
    share one process): a Computer sheet left open showed a second fix-it card in the next session.
  - A known computer did not start its session on a launch with `reset`.
  - Start again on the Computer sheet read the times back before they were forgotten.
  - A known computer's routes now read in the iPhone's form as well as the app's own.
  - A take card outlived its session: after leaving the demo, Keep, Delete and Go again aimed at a
    take the next computer does not have.
  - Chat's unlock lacked the `USE_BIOMETRIC` permission (lint): on a phone it would have stopped
    with a security error the demo never reaches.
  - Nothing is backed up or carried to a new phone (`data_extraction_rules.xml`): the pairing
    belongs to this phone's Keystore key, so a new phone pairs again.
- **Found upstream** (the iPhone app, reported to the owner):
  - `apple/TabberSpak/Tuner/TunerModel.swift` line 119 gives the detector a 1024-sample window,
    which cannot read a guitar's low E (82.4 Hz) at 48 kHz.
  - `apple/TabberSpak/AppModel.swift`: `leaveDemo()` and `forget()` keep `lastTake`, the take card
    bug above.

### TA5, 2026-11-09

- **The icon:** `scripts/draw-icon.py` draws the iPhone's spak (the lever with Studio's teal band
  and gate) as an adaptive icon, its layers the Swift script's shapes, colours and gradients,
  scaled into Android's safe circle, with a one-colour layer for themed icons.
- **The look:** the window is Studio's screen colour while the app starts, and the status and
  navigation bars keep light icons whatever the phone's own theme (they were dark grey on dark).
- **The accessibility pass:** Google's Accessibility Test Framework on every screen, as Xcode's
  audit on the iPhone (`AccessibilityTest`, 4 tests): no findings left. It found controls under
  Android's 48 dp (S and M, Undo, the hold buttons, Send, a send's remove, the pan knob and the
  send's bar; the mixer's strips grew to 104 dp so S and M fit), and the fretboard and piano
  claiming 24 dp of the row above them for TalkBack, because their semantics sat inside the
  scrolling, in its overscroll margin; they sit on the board in view now. TalkBack hears the
  tuner's reading at most once a second, as VoiceOver reads a value that updates frequently.
- **The largest text** (200 %, `LargestTextTest`, 4 tests): a row whose words do not fit stacks,
  as the iPhone's ViewThatFits does (`FitsOr`): the note values in rows of three (in one row,
  1/16 read "1/1"), the edit chips two by two, the toggles one under another, the trainer's fields
  each on a line with its name, the fix-it buttons. The computer's view and the mixer's pages
  become a menu, the tabs' names grow to half again on one line, and the Tracks controls scroll
  with the tracks. The test's check for cut words fails with the old single row.
- **Lint:** no errors; the one warning left is the deliberate `targetSdk` 36.
- **The release:** `scripts/release-android.sh`, as Storman's: the checks (RemoteKit, the tuner,
  release lint), the signed bundle, its build number and its signer checked, and on the emulator
  the minified build itself opened and its demo connected. A local build:
  `~/tabber-spak-releases/TabberSpak-1.0-b2.aab`, 4.1 MB, signed by the upload key;
  `BUILD_NUMBER` unchanged, as the first build for Play is TA6's.
- **Tests:** 45 UI tests on the emulator pass in one run; the JVM suites pass; the Studio check
  passes against Linux Tabber Studio 0.3.27 (connected in 2.7 s, the take loop read back, a
  reconnect 5.9 s after Studio restarted).

### iOS build 18: protocol 1.10, plug-ins and wiring the Flow, 2026-11-09

- **From the iPhone repo** (merged at `95195d0`): protocol 1.10 with `plugins/1`, its schemas
  and the plugins vector; TR43 (wiring the Flow by hand) and TR44 (plug-ins on the mixer's
  strips), checked on the owner's iPhone with build 18; and the Mac side's fixes for the four
  faults found porting to Android, which Android already had.
- **Protocol 1.10 and plug-ins (TR44):** RemoteKit's `Insert`, `PluginRow` and `PluginPage`, a
  strip's inserts (none from an older computer), the client offering 1.10 only as the iPhone
  does, the catalog as a read, and an insert that may wait three minutes for its plug-in to load
  (no response time). The demo computer has Tabber's five plug-ins and two Demo Audio ones. The
  app shows each strip's INSERTS as Studio's ("● Name", "○ Name" bypassed, "+k more…",
  "＋ Plugin"; one height on every strip so the faders stay level, with Android's 48 dp rows),
  the slot's menu (Open on the computer, Bypass or Un-bypass, Remove) and the Insert Plugin
  browser (its tabs, the format filter, the search, a greyed row's reason, the loading line, a
  refusal kept on screen).
- **Wiring the Flow by hand (TR43, by a helper agent on its own branch, merged):** drag from a
  card's teal port onto a bus or the Master; a track chooses Output or Send, a bus moves its
  output or is refused in Studio's words ("Reverb would loop: Delay → Reverb → Delay."); hold a
  card for its menu (its output, Send to, Remove send), which TalkBack gets as the card's
  actions; the hint line under the diagram. A drag from a port never scrolls or zooms the
  diagram under the wire. It also found the cards' captions clipped by Material's 24 sp lines,
  fixed.
- **Different from the iPhone, on purpose:** a refusal shows Tabber Studio's own words, the
  error's `detail` ("Old Delay failed to load."), as the spec says; the iPhone shows only the
  generic "Tabber Studio could not do that.".
- **Found and fixed here:** with the plug-in state below the model's start-up, a phone that had
  paired before stopped at launch (Kotlin sets properties in the order they are written; the
  demo never starts that way). The start-up now runs last; `AppModelTest` fails with the old
  order. The accessibility pass now audits the sheets' own windows too (the Computer sheet, Go
  to, Insert Plugin), which it had not reached; every sheet's handle is 48 dp wide. The demo
  computer's error table is now the protocol's, all 38 reasons (four it throws had fallen back to
  "Tabber Studio could not do that."), checked against `errors.json`. The Chat tests press Send
  by its action: the keyboard slides it up as it opens, and a tap could miss (1 run in 13).
- **Tests:** RemoteKit's 82 on the JVM (the plugins vector round-trips exactly; the stale-event
  test from the iPhone fails under the old rule), interop 3 of 3 against Tabber Studio Linux's
  own 1.10 host (synced to macOS 0.3.29 for it, its Part 11). New UI tests: Plugins 3, Flow 5
  (the iPhone's three, a port's drag leaving a zoomed diagram where it was, TalkBack's actions),
  the Insert Plugin browser's audit and the paired start; each new test was seen to fail with
  its feature broken.
- **Found upstream** (the iPhone app, reported to the owner): the refusal's words above, and
  DemoHost.swift's error table lacks four reasons its demo throws (`chat_busy`, `routing_loop`,
  `unknown_plan`, `wrong_kind`), which it answers as the generic 1099.


### iOS build 20 and Linux Tabber Studio 0.3.29, 2026-11-09

- **iOS build 20** (merged at `1b13fe8`) is build 19's code: the iPhone's release script builds
  only committed, pushed code, and the one commit since build 19 is its build number. Nothing to
  port.
- **The Studio check** passes against Linux Tabber Studio 0.3.29 (built from its `27c6c2b6`,
  which opens recording through its Linux audio layer): paired and connected in 3.5 s, the take
  loop read back (1, then 0 after the delete, 1 after Undo), and a reconnect 9.1 s after Studio
  restarted. That time includes Studio's own relaunch.

### iOS build 22 and Linux Tabber Studio 0.3.31: drum tab, 2026-11-11

- **From the iPhone repo** (merged at `c1afb1e`): protocol 1.11 with `tab.drum/1`, its schemas
  and the `tab_drum` vector; TR45 (drum tab with Tabber Studio's Drum Map, in iOS build 22);
  `RemoteError.sentence` (`458a7b2`); Tabber Spak 1.1, which the version name follows from the
  Xcode project; builds 21 and 22 themselves are build numbers, nothing to port.
- **Drum tab (TR45):** RemoteKit offers 1.11 only, as the iPhone does, and reads a track's
  `drum_tab` (a drum track has drum tab and no tuning); `NewTrackKind.DRUMS`; `DrumMap`, GM 35
  to 59 with every GM percussion name. On a drum track the Tab screen shows "Drum Map" where
  Write with is and the Drum Map where the fretboard is: each drum a cell with its number over
  its name, lit on the cursor's beat; a tap writes it on the beat's first free line or takes it
  off. Delete says "the drum on this line", the staff speaks "line 1, 42 Closed Hi-Hat", and
  "+ Add Drum Track" and Add Track's "Drum track" appear on a computer that offers
  `tab.drum/1`. The demo's Drums is a drum track with a rock groove; the `demo_midi_drums`
  launch extra keeps TR39's MIDI kit and its card for those tests.
- **Refusals:** `RemoteError.sentence`, as the iPhone's: Studio's `host_error` reason, trimmed
  and given its full stop, the loop a `routing_loop` would close, else the message; every
  refusal and pairing failure says it. Android had shown the reason since build 18.
- **Different from the iPhone, on purpose:** the Drum Map's rows take their tallest name's
  height, so "Acoustic Bass Drum" does not leave its neighbours shorter.
- **Tests:** RemoteKit 91 on the JVM (RefusalTests 7, the demo's drum map, every vector
  including `tab_drum`), the app's 38, lint with no errors; 58 UI tests on the emulator, among
  them two new Tab screen tests and the Drum Map's accessibility audit, both new tests seen to
  fail with the Drum Map hidden; interop 3 of 3 against Tabber Studio Linux's own 1.11 host
  (synced to macOS 0.3.31, its Part 13).
- **The Studio check gains drum tab** (its step 4): against Linux Tabber Studio 0.3.31 (built
  from its `1ec00969`), paired and connected in 2.7 s, the take loop read back (1, 0, 1), then
  "+ Add Drum Track" from the phone and the Drum Map's snare written and taken off, each read
  back from the drum track's first measure over the Control API, and a reconnect 8.8 s after
  Studio restarted.
