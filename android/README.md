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
- For the interop and pairing checks: a Tabber Studio checkout beside this repository
  (`../tabber_studio_linux` or `../tabber_studio`) with its venv; it provides the real
  `remote_host`.
- A phone with USB debugging, or the emulator: `android/scripts/emulator.sh start`.

## Commands

```bash
cd android
./gradlew :remotekit:test          # every protocol vector, the crypto and the JSON, on the JVM
scripts/interop.sh                 # RemoteKit against Tabber Studio's real host (TLS 1.3, pinned)
scripts/emulator.sh start          # the test phone, headless and without audio
scripts/pair-check.sh              # the debug app pairs with the real host on the emulator
./gradlew :app:assembleDebug       # app-debug.apk: com.tabberspak.app.debug, beside a Play build
scripts/emulator.sh stop
```

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
- **Signing:** the Google Play upload key and its passwords live in `~/.gradle/gradle.properties`
  as `TABBERSPAK_UPLOAD_*` and the key in `~/.android-keys/`, never in this repository, as for
  the owner's other Android apps.

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
  and said so on screen (`shots/pair-check.png`, not committed).
- **Found:** `apple/RemoteKit/Tests/RemoteKitTests/InteropTests.swift` still expects
  `protocol_version` "1.0", but its client now offers only "1.9", and the current host answers
  "1.9". The Kotlin test expects the version the client offers. The Swift test belongs to
  upstream (the Mac); reported to the owner.
