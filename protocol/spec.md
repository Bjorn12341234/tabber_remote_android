# Tabber Remote Protocol, version 1.0

This is the contract between a remote (Tabber Spak on iPhone, later Android)
and a host (Tabber Studio on macOS, later Windows and Linux). Read
`../guiding_principles_remote.md` first: when this spec and a principle
disagree, the principle wins and this spec is fixed.

The schemas in `schemas/` and the vectors in `vectors/` are part of the spec.
A host or a remote is correct when it passes every vector. A change to this
file ships with its schemas and vectors in the same commit.

## 1. Words

- **Host:** Tabber Studio with the remote turned on.
- **Remote:** a phone app that speaks this protocol.
- **Device:** one installed remote, known to the host by its device key.
- **Verb:** a method the remote calls. Only the remote calls methods.
- **Event:** a change the host pushes.
- **b64url:** base64url without padding (RFC 4648, section 5).
- **Host time:** seconds on the host's monotonic clock, as a JSON number. It
  has no relation to wall-clock time and never goes backwards.

Bars and beats are counted from 1, as musicians count them. Bar 1 beat 1 is
the start of the song. (Tabber Studio's Control API counts from 0; the host
converts.)

## 2. Transport

- **WebSocket over TLS 1.3 over TCP.** Plain `ws://` is never accepted, at home
  too (principle 2).
- **The host's port:** TCP 9474 when free, otherwise any free port. Bonjour,
  the QR code and every remembered route carry the real port.
- **The request path is `/`.** A host accepts any path.
- **Subprotocol:** the remote offers `tabber-remote.v1` (and the names for any
  other major versions it speaks). The host picks one. A host that shares no
  major version with the remote picks none and closes with code 4002.
- **Text frames** carry one JSON-RPC message each, UTF-8, at most 65,536 bytes.
  A bigger frame closes the connection with code 1009.
- **Binary frames** are reserved for audio (Tabber Spak 1.2). A version 1.0
  host closes on a binary frame with code 1003.

### Trust

The remote accepts the TLS session only when the SHA-256 of the host's DER
SubjectPublicKeyInfo equals the pin it holds for that host. No certificate
authority, host name check or expiry check is involved; the certificate only
carries the key. A remote that has no pin yet (the 6-digit path, section 4.4)
trusts the key it sees for that one connection, and the human comparison of
the code protects it.

## 3. Finding the host

1. **Bonjour:** service type `_tabber-remote._tcp`, domain `local.`. The TXT
   record holds exactly `v=1` (the protocol major versions, comma-separated)
   and `id=<host id>`. Nothing else: no names of songs, users or devices.
   The service name is the computer's name.
2. **The QR code's routes** (section 4.2).
3. **A typed address**, `host:port`, for VPNs and Tailscale, where multicast
   does not reach.

A remote that knows a host's id connects to the first route that answers, and
checks the pin on every route.

## 4. Identity, pairing and authentication

### 4.1 Keys and ids

- **Host key:** ECDSA P-256, made once when the remote is first turned on,
  kept until "Forget all and make new keys". The host serves it in a
  self-signed X.509 certificate.
- **Host id:** a random UUID (version 4), lowercase, made with the host key.
- **Pin:** b64url(SHA-256(host key's DER SubjectPublicKeyInfo)). 43 characters.
- **Device key:** ECDSA P-256, made on the device. On an iPhone it lives in the
  Secure Enclave. A simulator or emulator uses a software key instead.
- **Device key encoding:** b64url(DER SubjectPublicKeyInfo).
- **Device id:** b64url(SHA-256(device key's DER SubjectPublicKeyInfo)).
- **Signatures:** ECDSA P-256 with SHA-256, DER-encoded (X9.62
  ECDSA-Sig-Value), sent as b64url.
- **Challenge:** 32 random bytes from the host, sent as b64url in the `hello`
  result. One challenge serves one `pair` or `auth` attempt and expires 60
  seconds after it is sent.

### 4.2 The QR code

```
tabber-remote://pair?v=1&id=<host id>&name=<computer name>&spki=<pin>&tok=<token>&hosts=<route>,<route>
```

- `v`: the protocol major versions the host speaks, comma-separated.
- `id`: the host id.
- `name`: the computer's name, percent-encoded, shown while connecting.
- `spki`: the pin.
- `tok`: the pairing token: 16 random bytes, b64url. Single use, valid for five
  minutes. The pairing dialog renews it before it runs out.
- `hosts`: the routes in order of preference, comma-separated. A route is
  `name:port`, `ipv4:port` or `[ipv6]:port`. The first is the Bonjour host
  name (`studio-mac.local:9474`). Link-local IPv6 addresses are left out:
  the phone cannot know their zone.

Values are percent-encoded as RFC 3986 query components. The parameters may
come in any order; a remote ignores parameters it does not know. In the
Simulator, the same link is delivered with
`xcrun simctl openurl booted '<link>'`; it comes from the Control API's
`remote.pair`.

### 4.3 Pairing with the QR code

1. The remote connects to a route, pinned to `spki`.
2. `hello` (section 6).
3. `pair` with `mode: "token"`, the token, the device's name and key, and a
   signature over:

   ```
   "tabber-remote pair v1" || 0x00 || pin hash (32 bytes) || challenge (32 bytes) || token (16 bytes)
   ```

   The pin hash is the raw SHA-256 (the 32 bytes the pin encodes), not its
   text. The challenge and token are their raw bytes.
4. The host checks the token, the challenge and the signature, stores the
   device and answers with the device id. The connection is now
   authenticated, and the computer says on screen that the phone was paired.

QR pairing needs no Allow click: the token is on the computer's screen, single
use and short-lived (plan decision 6).

### 4.4 Pairing with the 6-digit code

For a remote that cannot scan the QR code. The remote finds the host with
Bonjour, connects without a pin and keeps the host key it sees.

1. `hello`.
2. `pair` with `mode: "code"`, the device's name and key, and a signature over
   the bytes of section 4.3 with an empty token.
3. Both sides show the same six digits:

   ```
   digest = SHA-256("tabber-remote code v1" || 0x00 || pin hash || device id hash || challenge)
   code   = (first 4 bytes of digest, as a big-endian unsigned integer) mod 1,000,000
   ```

   written with six digits, leading zeros kept. The device id hash is the raw
   SHA-256 the device id encodes. The remote computes the pin hash from the
   key it saw in TLS.
4. The user compares the codes and clicks Allow on the computer. The host
   answers the `pair` request then, or after 120 seconds with
   `pairing_timeout`, or at once with `pairing_declined`. The remote keeps the
   pin it saw.

A host that does not offer this path lacks the `pair.code/1` capability.

### 4.5 Authenticating a paired device

1. `hello`.
2. `auth` with the device id and a signature over:

   ```
   "tabber-remote auth v1" || 0x00 || pin hash (32 bytes) || challenge (32 bytes)
   ```

A removed device gets `unknown_device` and must pair again. A challenge is
never accepted twice.

## 5. Messages

Messages are JSON-RPC 2.0 with these limits:

- **Only the remote sends requests.** The host sends responses and two
  notifications: `event` and `heartbeat`. The remote sends one notification,
  `heartbeat`.
- **`params` is always an object.** `id` is an integer or a string the remote
  chooses, unique on the connection.
- **No batches.** An array is answered with `invalid_request`.
- **Responses may come in any order.** The remote matches them by `id`.
- **Every request gets exactly one response,** unless the connection drops
  first.

### 5.1 Changes are safe to resend

Every verb that changes something has a required `key`: a UUID the remote makes
once per user action. When the connection drops before the answer arrives, the
remote resends the same request, with the same key, on the next connection.
The host keeps each device's keys for 10 minutes (at least the newest 256) and
answers a repeated key with the response it gave the first time, without doing
anything again. A press of Record never records twice.

A request refused before it ran (`unauthenticated`, `rate_limited`, `busy`,
`invalid_params`, `method_not_found`) does not store its key: the next
request with that key is the first.

### 5.2 Edits name their targets

Every edit names what it acts on: a track id, a take id, a marker id, a bar
and beat, the armed tracks, the undo step. If the host's state no longer
matches (the armed tracks changed on the computer, or the newest undo step is
a different one), the host refuses with `stale_target` or `undo_mismatch` and
the current state, and does nothing. A click on the computer can never
redirect what the phone does (principle 3).

### 5.3 Answers are the confirmed state

The result of every change is the state the host confirmed after making it,
read back from Tabber Studio, not an echo of the request.

## 6. A connection, in order

1. **TLS and WebSocket** (section 2).
2. **`hello`.** The remote sends its app name, version, build and platform, and
   the protocol versions it speaks. The host answers with its id, name and
   Tabber Studio version, the chosen protocol version, its capabilities, its
   limits and a challenge.
3. **`pair` or `auth`.** Before it succeeds, only `hello`, `pair`, `auth` and
   `heartbeat` are accepted. Anything else is answered with
   `unauthenticated`. Three failed attempts close the connection with 1008.
4. **`session.subscribe`** with the topics the remote shows. The result is a
   snapshot.
5. **Events and requests,** until either side closes.
6. **Heartbeats** from the moment the WebSocket is open, in both directions.

### 6.1 Heartbeats

Both sides send a `heartbeat` notification every 2 seconds (the host's
`limits.heartbeat_ms`). The host's heartbeat carries the host time, the
sequence number of the newest event it has sent on this connection, and
whether Tabber Studio is busy:

```json
{"jsonrpc": "2.0", "method": "heartbeat", "params": {"t": 8123.41, "seq": 57, "busy": false}}
```

- **Busy** means the host's main thread has not run a queued request for more
  than a second (a project loading, a render). Heartbeats come from the
  host's network thread, so they keep coming while it is busy. The remote
  says "Tabber Studio is busy".
- **Three missed heartbeats** (6 seconds) mean the connection is gone. The
  remote shows "Reconnecting" and stops showing live state as live. The host
  closes the connection with 4004.
- **A heartbeat whose `seq` is newer** than the newest event the remote has
  seen means events were lost: the remote asks for a snapshot.

### 6.2 Close codes

| Code | Meaning |
|---|---|
| 1000 | Normal close |
| 1003 | Binary frame on a 1.0 connection |
| 1008 | Policy: three failed `pair` or `auth` attempts |
| 1009 | Frame bigger than 65,536 bytes |
| 4000 | The remote was turned off on the computer, or Tabber Studio is quitting |
| 4001 | This device was removed on the computer |
| 4002 | No shared protocol version |
| 4003 | Too many connections from this device (more than two) |
| 4004 | No heartbeat for 6 seconds |

## 7. Versions and capabilities

- **The protocol version** is `major.minor`. `hello` lists what the remote
  speaks (`"protocol_versions": ["1.5"]`, one entry per major, the highest
  minor it knows); the host answers with the version it chose: the major
  both speak, and the lower of the two minors. It lists only that version's
  capabilities, refuses the verbs of any other with `not_supported` and
  their topics with `invalid_params`, so a 1.0 remote sees exactly the 1.0
  host it knew.
- **An additive change** (a new verb, field, event topic or error) raises the
  minor version and adds a capability. Remotes ignore fields they do not know.
- **A breaking change** raises the major version. The host keeps serving the
  previous major version for at least one more Tabber Studio release.
- **Capabilities** name what this host can do. The remote shows only what the
  host lists. When a feature needs a newer host, it says so in plain words
  ("Update Tabber Studio to use Tab").

Version 1.0 capabilities:

| Capability | Gives |
|---|---|
| `transport/1` | `transport.play`, `transport.stop`, `transport.seek`, `transport.set_loop`, `transport.set_click`, the `transport` and `position` topics |
| `record/1` | `transport.record`, `transport.set_count_in`, the `record` topic |
| `tempo_scale/1` | `transport.set_tempo_scale` |
| `tracks/1` | `tracks.arm`, `tracks.select`, the `tracks` topic |
| `tracks.monitor/1` | `tracks.set_monitor` |
| `markers/1` | `markers.go`, `markers.loop`, `markers.add`, the `markers` topic |
| `takes/1` | `takes.list`, `takes.rate`, the `takes` topic |
| `takes.discard/1` | `takes.discard` |
| `takes.go_again/1` | `takes.go_again` |
| `undo/1` | `edit.undo`, `edit.redo`, the `undo` topic |
| `save/1` | `project.save`, the `project` topic |
| `meters/1` | the `meters` topic |
| `pair.code/1` | 6-digit pairing (section 4.4) |

Version 1.1 adds two capabilities. A 1.1 remote works with a 1.0 host and
shows these screens only when the host lists them:

| Capability | Gives |
|---|---|
| `mixer/1` | `mixer.state`, `mixer.set_volume`, `mixer.set_pan`, `mixer.set_mute`, `mixer.set_solo`, the `mixer` and `mixer_meters` topics, and `instrument` on tab and MIDI tracks |
| `tab/1` | `tab.state`, `tab.set_cursor`, `tab.move`, `tab.put`, `tab.put_pitch`, `tab.set_duration`, `tab.rest`, `tab.delete`, the `tab` topic, and `tuning` on tab tracks |

Version 1.2 adds one capability. A 1.2 remote works with a 1.1 or 1.0 host
and shows Routing only when the host lists it:

| Capability | Gives |
|---|---|
| `routing/1` | `routing.state`, `routing.set_output`, `routing.set_send`, `routing.remove_send`, the `routing` topic |

Version 1.3 adds one capability. A 1.3 remote works with any 1.x host and
shows Chat only when the host lists it:

| Capability | Gives |
|---|---|
| `chat/1` | `chat.state`, `chat.send`, `chat.confirm`, `chat.cancel`, `chat.stop`, the `chat` topic |

Version 1.4 adds one capability. A 1.4 remote works with any 1.x host and
shows the view buttons only when the host lists it:

| Capability | Gives |
|---|---|
| `view/1` | `view.state`, `view.set`, the `view` topic |

Version 1.5 adds one capability. A 1.5 remote works with any 1.x host and
shows the Speed Trainer only when the host lists it:

| Capability | Gives |
|---|---|
| `trainer/1` | `trainer.state`, `trainer.set`, the `trainer` topic |

## 8. Snapshot and events

### 8.1 The snapshot

`session.subscribe` and `session.snapshot` return the whole session in one
object (`schemas/snapshot.json`):

- `seq`: the newest event already reflected in it
- `t`: host time when it was taken
- `project`: title, unsaved, whether it has a file yet
- `transport`: state, position, tempo, time signature, tempo scale, loop,
  click, count-in, whether a count-in is running
- `record`: recording or not, when and where the take started, the armed track
  ids
- `tracks`: every track, in Tabber Studio's strip order
- `markers`: every marker, in song order
- `takes`: the newest takes on any track, newest first, at most 20
- `undo`: the next undo and redo steps

The mixer, the tab, the routing, the chat, the view and the Speed Trainer
are not in the snapshot. A remote that subscribes to `mixer`, `tab`,
`routing`, `chat`, `view` or `trainer` reads them once with `mixer.state`,
`tab.state`, `routing.state`, `chat.state`, `view.state` and
`trainer.state`, then follows their topics; it reads them again after every
new snapshot.

### 8.2 Events

```json
{"jsonrpc": "2.0", "method": "event", "params": {"topic": "transport", "seq": 58, "t": 8123.52, "data": { }}}
```

- **`seq`** counts every event on this connection, from 1, with no gaps. A gap
  means something was lost: the remote asks for `session.snapshot` and
  ignores events whose `seq` is not newer than the snapshot's.
- **`t`** is the host time when the change happened.
- **`data` replaces the whole topic.** An event for `tracks` carries every
  track; there are no partial updates in 1.0. Only `position` and `meters`
  carry their own small shapes.

| Topic | `data` | Sent |
|---|---|---|
| `transport` | the snapshot's `transport` | on every change |
| `position` | `{state, position}` | while playing or recording, at most 10 a second |
| `record` | the snapshot's `record` | on every change |
| `tracks` | `{tracks: [...]}` | on every change |
| `markers` | `{markers: [...]}` | on every change |
| `takes` | `{takes: [...]}` (newest 20) | on every change |
| `undo` | the snapshot's `undo` | on every change |
| `project` | the snapshot's `project` | on every change |
| `meters` | `{levels: [{track_id, peak}]}` | at most 20 a second, armed and selected tracks only, only while subscribed |
| `mixer` | `{strips, scale}` (mixer/1) | on every change |
| `mixer_meters` | `{levels: [{strip_id, peak}]}` (mixer/1) | at most 20 a second, every strip and the master, only while subscribed: a remote subscribes while its mixer is on screen |
| `tab` | `{tab}`, the selected track's tab or null (tab/1) | on every change, the cursor's included |
| `routing` | `{sources, sends}` (routing/1) | on every change |
| `chat` | `{available, state, messages, plan}` (chat/1) | on every change |
| `view` | `{editor, split}` (view/1) | on every change |
| `trainer` | `{enabled, start, step, target, speed}` (trainer/1) | on every change, each step of the speed included |

`position` and `meters` are sent only to remotes that subscribed to them, and
the host does no meter work at all while nobody is subscribed (principle 7).
Between `position` events the remote moves the playhead itself from the tempo
and the tempo scale.

## 9. Verbs

Schemas for every verb are in `schemas/methods/`. Every verb with a `key`
changes something (section 5.1). "Control API" names what the host runs
through Tabber Studio's dispatcher, so a remote verb has exactly the menu's
effect. Names marked TR1 are added to the Control API in sprint TR1.

### Connection

| Verb | Params | Result | Control API |
|---|---|---|---|
| `hello` | `app {name, version, build, platform}`, `protocol_versions` | `host {id, name, app_version}`, `protocol_version`, `capabilities`, `limits`, `challenge` | none (remote host) |
| `pair` | `mode`, `token` (token mode), `device {name, model, key}`, `signature` | `device_id`, `host {id, name}` | none (remote host) |
| `auth` | `device_id`, `signature` | `device {id, name}` | none (remote host) |
| `session.subscribe` | `topics` | a snapshot | `session.snapshot` (TR1) |
| `session.unsubscribe` | `topics` | `topics` still subscribed | none |
| `session.snapshot` | none | a snapshot | `session.snapshot` (TR1) |

### Transport and recording

| Verb | Params | Result | Control API |
|---|---|---|---|
| `transport.play` | `key`, `from` (bar and beat, optional) | `transport` | `transport.play` |
| `transport.stop` | `key` | `transport`, `record`, `take` (when a recording stopped, else null) | `recording.stop` while recording, then `transport.stop`, as the UI's Stop button does |
| `transport.record` | `key`, `armed_track_ids`, `count_in_bars` (optional) | `transport`, `record` | `recording.set_count_in`, `recording.start` |
| `transport.seek` | `key`, `to` | `transport` | `transport.seek` |
| `transport.set_loop` | `key`, `enabled`, `start` and `end` (optional) | `transport` | `transport.set_loop` |
| `transport.set_click` | `key`, `enabled` | `transport` | `transport.set_metronome` |
| `transport.set_count_in` | `key`, `bars` (0, 1 or 2) | `transport` | `recording.set_count_in` |
| `transport.set_tempo_scale` | `key`, `scale` (0.25 to 2.0) | `transport` | `transport.set_tempo_scale` |

`transport.record` records on the tracks the remote shows as armed. When
`armed_track_ids` differs from the host's armed tracks, it refuses with
`stale_target` and the current tracks. With nothing armed, the remote says
"Arm a track first" itself and sends nothing.

### Tracks

| Verb | Params | Result | Control API |
|---|---|---|---|
| `tracks.arm` | `key`, `track_id`, `armed` | `tracks` | `recording.arm_audio_track` (TR1) for audio, `recording.arm_track` for MIDI |
| `tracks.select` | `key`, `track_id` | `tracks` | `tracks.select` |
| `tracks.set_monitor` | `key`, `track_id`, `mode` (`off`, `auto`, `on`) | `tracks` | `recording.set_monitor` for MIDI; audio tracks as TR8 finds |

### Markers

| Verb | Params | Result | Control API |
|---|---|---|---|
| `markers.go` | `key`, `marker_id` | `transport` | `markers.go` (TR1) |
| `markers.loop` | `key`, `marker_id` | `transport` | `markers.list` (TR1), `transport.set_loop` |
| `markers.add` | `key`, `at` (bar and beat), `name` (optional) | `marker`, `markers` | `markers.add` (TR1) |

`markers.loop` loops from the marker to the next marker, or to the end of the
song after the last one. `markers.add` names the bar the remote showed when
the user tapped, never "wherever the playhead is now".

### Takes

A take is one recorded pass: what one recording placed on one track. In
Tabber Studio a linear recording is one audio clip, and the take's id is the
clip's id. A pass recorded over an earlier one on its track joins it in take
lanes, and the newest plays where they overlap: every pass is still listed,
and `active` says whether any of it plays. Loop-record takes are not listed
in 1.x.

| Verb | Params | Result | Control API |
|---|---|---|---|
| `takes.list` | `track_id` | `takes` (every take on the track, newest first) | `takes.passes` (TR1) |
| `takes.discard` | `key`, `take_id` | `takes`, `undo` | `takes.discard` (TR1) |
| `takes.go_again` | `key`, `take_id` | `transport`, `record` | `takes.go_again` (TR1) |
| `takes.rate` | `key`, `take_id`, `rating` (0 to 5, 0 unrated) | `take` | `takes.rate_pass` (TR1) |

- **`takes.discard`** removes the take from its track as one undo step. Its
  audio file stays on disk, so Undo on either device brings it back. The
  result's `undo` names the step, for the remote's Undo button.
- **`takes.go_again`** stops if needed, goes back to where the named take
  started, uses the same count-in and records on the same tracks. The take may
  be one that was just discarded.

### Edits and the project

| Verb | Params | Result | Control API |
|---|---|---|---|
| `edit.undo` | `key`, `expect` (an undo step id) | `undo` | `project.undo` with `expect` (TR1) |
| `edit.redo` | `key`, `expect` (a redo step id) | `undo` | `project.redo` with `expect` (TR1) |
| `project.save` | `key` | `project` | `project.save` |

`edit.undo` undoes only the step it names. When the newest step on the computer
is a different one, the host refuses with `undo_mismatch` and the current
`undo`. `project.save` saves only a song that already has a file; a new song
gets `needs_save_location` (the computer chooses where files go, never the
phone).

### Mixer (mixer/1)

A strip for every track, in strip order, then every bus, then the master,
whose id is `master`. A track's strip has the track's id.

| Verb | Params | Result | Control API |
|---|---|---|---|
| `mixer.state` | none | `mixer` | `mixer.get_all_strips`, `buses.list` |
| `mixer.set_volume` | `key`, `strip_id`, `volume` (0 to 1) | `strip` | `mixer.set_volume`, `buses.set_gain`, `mixer.set_master_gain` |
| `mixer.set_pan` | `key`, `strip_id`, `pan` (-1 to 1) | `strip` | `mixer.set_pan`, `buses.set_pan` |
| `mixer.set_mute` | `key`, `strip_id`, `muted` | `mixer`, `undo` | `mixer.set_mute`, `buses.set_mute` |
| `mixer.set_solo` | `key`, `strip_id`, `soloed` | `mixer`, `undo` | `mixer.set_solo`, `buses.set_solo` |

- **`volume` is the fader's travel** in the host's own fader law, so the
  phone's fader sits where the computer's does. `volume_db` says what it
  means (null is silence), and `scale` gives the marks to draw beside the
  fader.
- **Mute and solo are undo steps,** as in Tabber Studio. Volume and pan are
  not, there or here.
- **A fader drag is many `mixer.set_volume` calls.** The remote sends the
  newest value only, one at a time, within the rate limit.
- The master has no mute or solo: those are refused with `unknown_strip`.

### Tab (tab/1)

The selected track's tab, edited as Tabber Studio's Tab view edits it. The
remote chooses the track with `tracks.select`; the tab follows. `tab` is
null while the selected track has none (an audio track, a drum or a
plain MIDI track).

| Verb | Params | Result | In Tabber Studio |
|---|---|---|---|
| `tab.state` | none | `tab` | the main score scene's cursor and bars |
| `tab.set_cursor` | `key`, `bar`, `beat`, `string` | `tab`, `undo` | a click on the tab |
| `tab.move` | `key`, `by` (1 or -1) | `tab`, `undo` | the right and left arrow keys |
| `tab.put` | `key`, `string`, `fret` | `tab`, `undo` | a fretboard tap |
| `tab.put_pitch` | `key`, `pitch` (a MIDI note) | `tab`, `undo` | a piano key on guitar tab |
| `tab.set_duration` | `key`, `value` (1, 2, 4, 8, 16, 32), `dotted`, `triplet` | `tab`, `undo` | the note value toolbar, Dot and Triplet |
| `tab.rest` | `key` | `tab`, `undo` | the R key |
| `tab.delete` | `key` | `tab`, `undo` | the Delete key |

- **Strings count from 1, the highest.** `tuning` lists the open strings as
  MIDI notes, highest first. Beats are the rhythmic slots of a bar, from 1.
- **Each verb is the Tab view's own action,** so each change is the same undo
  step with Tabber Studio's own label ("Set fret 3 on string 2", "Toggle
  rest", "Insert beat"), undone with `edit.undo`.
- **`tab.put` is a fretboard tap.** It writes that fret on that string at
  the cursor's beat, replacing another fret on the same string, or takes it
  off when it is already there. The cursor stays, so more taps make a chord,
  and the chosen note value applies only to an empty beat. Tabber Studio
  plays the beat, as its fretboard does.
- **`tab.put_pitch` is a piano key on guitar tab.** It does the same, on the
  string that plays the pitch at the lowest fret, with the capo counted.
- **`tab.set_duration`** sets the beat's value and the value of new notes,
  then Dot and Triplet for the beat. When more than one of them changes,
  that is one undo step.
- **`duration` in `tab`** is what the toolbar shows: the beat's own value
  when it has notes, else the chosen one, with the beat's dot and triplet.
- **`tab.move` forward** past the last beat fills the bar with a rest beat
  of the chosen value, or goes to the next bar, adding one at the end.
- **`tab.rest`** turns a beat with notes into a rest, and a rest into an
  empty beat. **`tab.delete`** takes the note on the cursor's string, and a
  beat left with none is a rest.
- **`bars` holds the cursor's bar and its neighbours,** one before and three
  after, so an answer stays small whatever the song's length. `revision`
  changes whenever they do.
- **No tab, no edits.** With no tab on the selected track (an audio, drum or
  plain MIDI track), every verb but `tab.state` is refused with `no_tab`.

### Routing (routing/1)

Where each track and bus sends its sound, as Tabber Studio's Routing panel
shows it. Ids are the mixer's strip ids: a track's id, a bus's strip id, and
`master`.

| Verb | Params | Result | In Tabber Studio |
|---|---|---|---|
| `routing.state` | none | `routing` | the Routing panel's matrix |
| `routing.set_output` | `key`, `strip_id` (a track or a bus), `output` (`master` or a bus) | `routing`, `undo` | a click in the matrix's route column |
| `routing.set_send` | `key`, `strip_id` (a track), `bus_id`, `level` (0 to 1, optional), `pre_fader` (optional) | `routing`, `undo` | Alt+click on an empty cell, then the mixer's send level and Pre-fader |
| `routing.remove_send` | `key`, `strip_id`, `bus_id` | `routing`, `undo` | Alt+click on a send |

- **Every track and bus has one output,** the master by default. Choosing
  another moves it there, as the matrix does, and it is one undo step,
  "Routing change".
- **A send taps a track's sound into a bus,** beside its output. Adding one
  is an undo step ("Add send → Reverb") and starts it where Tabber Studio
  does, at -6 dB. Its level and Pre-fader are not undo steps, there or here,
  like the mixer's faders. A slider drag is many `routing.set_send` calls:
  the remote sends the newest value only, one at a time.
- **`level` is the send's gain,** 0 to 1, as the host stores it. `level_db`
  says what it means (null is silence) and `level_label` is how Tabber Studio
  writes it ("-6.0 dB").
- **A bus cannot feed itself.** An output that would close a loop is refused
  with `routing_loop`. `path` names the loop and nothing changes.
- **Only tracks have sends, and the master has no output.** A send from a
  bus, an output for the master, or an output to a track is refused with
  `wrong_kind`.

### Chat (chat/1)

Tabber Studio's own chat, from the phone (plan decision 21): the same AI,
the same plan to confirm, the same single undo step. The phone sends words
and gets words back. The AI and its key stay on the computer.

| Verb | Params | Result | In Tabber Studio |
|---|---|---|---|
| `chat.state` | none | `chat` | the chat's conversation |
| `chat.send` | `key`, `text` (1 to 2000 characters) | `chat` | typing a request and Send |
| `chat.confirm` | `key`, `plan_id` | `chat` | Execute under a plan |
| `chat.cancel` | `key`, `plan_id` | `chat` | Cancel under a plan |
| `chat.stop` | `key` | `chat` | Stop while it works |

- **An answer comes in its own time.** `chat.send` returns at once, with
  the request in `messages` and `state` "thinking". The answer follows on
  the `chat` topic: a message, or a `plan` and `state` "waiting".
- **Nothing changes before Confirm.** A plan lists its steps in words.
  `chat.confirm` runs it as the chat's Execute does: the AI may take more
  steps on its own to finish the request, each checked as below. The whole
  request is one undo step ("AI: mute the drums"), undone with `edit.undo`.
  `chat.cancel` drops the plan, and `chat.stop` stops a request that is
  still working.
- **What the chat does not do from a phone** (decision 21):
  - read or change the AI's settings or key, the remote's pairing and
    devices, preferences, macros, shells, scripts or downloads;
  - reach files outside the song's own folder;
  - open or start another song over unsaved changes;
  - load a plug-in that is not installed.

  A request that needs one is answered in words, and nothing runs.
- **No secrets reach the phone.** Every message is filtered on the
  computer: anything that looks like a key, a token or a password reads
  "[hidden]".
- **At most 10 chat requests a minute** come from each phone (`chat.send`
  and `chat.confirm`). The 11th is refused with `rate_limited`.
- **The computer shows every request** and every action it runs, as it
  shows the remote's other actions.
- **`available` is false** when Tabber Studio has no AI set up. `chat.send`
  is then refused with `chat_unavailable`.

### The computer's view (view/1)

What Tabber Studio shows on the computer's screen, switched as its own view
buttons switch it: Arrange, Tab or Piano Roll, and Split beside them.

| Verb | Params | Result | In Tabber Studio |
|---|---|---|---|
| `view.state` | none | `view` | the view buttons |
| `view.set` | `key`, `editor` (`arrange`, `tab` or `piano_roll`, optional), `split` (optional) | `view` | Arrange, Tab or Piano Roll; Split (F8) |

- **`editor`** is the editor on screen. In Split it is the one beside
  Arrange, Tab or Piano Roll.
- **`split`** turns Split on, or off again back to the editor shown before.
- A view change is not an undo step, there or here.

### Practice speed (trainer/1)

Tabber Studio's Speed Trainer, set as its own Trainer button and fields set
it: with Loop on, the song plays from `start` percent, and each time the loop
comes round the speed goes up by `step` until it reaches `target`.

| Verb | Params | Result | In Tabber Studio |
|---|---|---|---|
| `trainer.state` | none | `trainer` | the Trainer button and its fields |
| `trainer.set` | `key`, `enabled`, `start` (25 to 200), `step` (1 to 50), `target` (25 to 200), each optional | `trainer` | Trainer, start, step and target |

- **`speed`** is the speed now, in percent. The topic sends each step as the
  loop comes round.
- **Loop comes first,** as on the computer, where the trainer shows only
  while Loop is on. Turning it on with Loop off is refused with
  `needs_loop`, and Loop turned off turns the trainer off.
- Setting the trainer is not an undo step, there or here.

### Not in the vocabulary

A remote cannot reach Control API methods by name, file paths, scripts, app
settings, plug-ins (until Tabber Spak 1.4) or anything else not listed here.
Any other method name, including every raw Control API name, is answered with
`method_not_found`.

## 10. Errors

An error is a JSON-RPC error object. `data.reason` is the stable string a
remote acts on; `message` is a sentence a musician can read, in English; the
remote may show its own translation instead. Some errors carry the current
state in `data`, as listed.

| Code | Reason | Message | `data` |
|---|---|---|---|
| -32700 | `parse_error` | The phone sent something the computer could not read. | |
| -32600 | `invalid_request` | The phone sent a request the computer could not read. | |
| -32601 | `method_not_found` | This version of Tabber Studio cannot do that. | |
| -32602 | `invalid_params` | The phone sent a request the computer could not use. | `field` |
| -32603 | `internal_error` | Something went wrong in Tabber Studio. | |
| 1001 | `unauthenticated` | Pair this phone with the computer first. | |
| 1002 | `pairing_closed` | Pairing is not open. Click Pair iPhone in Tabber Studio. | |
| 1003 | `pairing_token_invalid` | This pairing code does not work. Scan the code on the computer again. | |
| 1004 | `pairing_token_expired` | This pairing code has expired. Scan the new one on the computer. | |
| 1005 | `pairing_declined` | Pairing was declined on the computer. | |
| 1006 | `pairing_timeout` | Nobody allowed the pairing on the computer in time. | |
| 1007 | `unknown_device` | This phone is no longer paired with this computer. Pair it again. | |
| 1008 | `signature_invalid` | The phone's key did not check out. Pair it again. | |
| 1009 | `challenge_invalid` | The connection took too long to start. Connecting again. | |
| 1010 | `unsupported_version` | Update Tabber Studio or Tabber Spak so they can talk to each other. | `host_versions` |
| 1011 | `rate_limited` | Too many requests at once. Try again in a moment. | `retry_after_ms` |
| 1012 | `busy` | Tabber Studio is busy. Try again in a moment. | |
| 1013 | `no_song` | Open a song in Tabber Studio first. | |
| 1021 | `already_recording` | Tabber Studio is already recording. | `record` |
| 1023 | `unknown_track` | That track is gone from the song. | `tracks` |
| 1024 | `unknown_take` | That take is gone from the song. | `takes` |
| 1025 | `unknown_marker` | That marker is gone from the song. | `markers` |
| 1026 | `stale_target` | This changed on the computer. The phone now shows the new state. | the current state of the topic |
| 1027 | `undo_mismatch` | The computer's newest change is a different one. Undo it there, or try again. | `undo` |
| 1028 | `nothing_to_undo` | There is nothing to undo. | `undo` |
| 1029 | `nothing_to_redo` | There is nothing to redo. | `undo` |
| 1030 | `needs_save_location` | Save this song on the computer first, so it has a file. | |
| 1031 | `not_supported` | This version of Tabber Studio cannot do that. Update Tabber Studio. | |
| 1032 | `unknown_strip` | That strip is gone from the mixer. | `mixer` or `routing` |
| 1033 | `no_tab` | Choose a tab track to write on first. | `tracks` |
| 1034 | `routing_loop` | That route would make a feedback loop. | `path`, `routing` |
| 1035 | `wrong_kind` | That strip cannot be routed that way. | `routing` |
| 1036 | `chat_unavailable` | Set up the AI in Tabber Studio first, in Preferences › AI. | `chat` |
| 1037 | `chat_busy` | The chat is still working on the last request. | `chat` |
| 1038 | `unknown_plan` | That plan is gone. Ask again. | `chat` |
| 1039 | `needs_loop` | Turn Loop on first: the trainer speeds up each time the loop comes round. | `trainer` |
| 1099 | `host_error` | Tabber Studio could not do that. | `detail` |

`schemas/errors.json` holds this table; the validator checks every error in
every vector against it.

## 11. Limits

`hello` returns the host's limits. Version 1.0 hosts use:

| Limit | Value |
|---|---|
| `max_frame_bytes` | 65,536 |
| `requests_per_second` | 20 per device, with bursts of 40 (`burst`) |
| `heartbeat_ms` | 2,000 |
| `heartbeat_misses` | 3 |
| `connections_per_device` | 2 |
| Pairing attempts | 3 failed per connection, then close |
| Challenge lifetime | 60 seconds |
| Token lifetime | 5 minutes |
| Idempotency memory | 10 minutes, at least the newest 256 keys per device |

A request over the rate gets `rate_limited` and is not run.

## 12. What the host keeps out of reach and out of logs

- **No raw Control API,** no paths, scripts or settings (section 9).
- **Tokens, challenges, signatures and keys never reach a log.** The remote log
  (`~/.tabber_studio/logs/remote.log`) records device names, verbs and
  outcomes.
- **Every remote action is shown on the computer** ("Sam's iPhone started
  recording").
- **Bonjour carries only `v` and `id`.**

## 13. Vectors

`vectors/` holds two kinds of file, both checked by `tools/validate_vectors.py`:

- **`vectors/exchanges/*.json`:** message sequences between a remote and a
  host. Each step names its sender and holds one message, a raw frame, a
  close or a reconnect. An answer marked `lost` was sent by the host but never
  reached the remote; it shows what the host keeps under the request's key. The validator checks
  each message against the envelope and its method or topic schema, checks
  that every response answers an earlier request, that event `seq` numbers
  have no gaps unless the vector says it shows one, that every error matches
  `schemas/errors.json`, and that together the vectors use every verb, topic
  and error at least once.
- **`vectors/crypto/*.json`:** pins, device ids, the bytes that get signed,
  signatures and 6-digit codes, from fixed test keys in `vectors/keys/`. The
  validator recomputes every derived value and verifies every signature.
  The test keys are public on purpose and never used outside tests.

Hosts and remotes run the same files in their own tests: the Python host in
Tabber Studio's `tests/remote/` (from a pinned copy), the Swift remote in
RemoteKit's tests, and later the Kotlin remote.
