# Tabber Spak Guiding Principles

Tabber Spak is the phone remote for Tabber Studio. It lets you run a
session from anywhere in the room: start and stop takes, throw away a bad one
and go again, loop a section, write a riff, pick a tone, or use the phone as a
microphone. Tabber Studio on the computer does the real work.

It is built for two people: the musician recording themselves (at the drum
kit, in the booth, on the couch with a guitar) and the engineer who wants to
watch the singer or guitarist instead of a screen.

Judge every feature, screen, protocol change and release against these
principles, in order. A change that breaks an earlier principle is not
acceptable because it improves a later one. Inside Tabber Studio (the remote
host), Tabber Studio's own `docs/plans/guiding_principles.md` applies in full:
nothing here outranks its stability, audio quality or performance.

## 1. The computer owns the session, and the remote can never hurt it

Tabber Studio is the single source of truth. The project, the undo history,
the audio, the plug-ins and every take live on the computer. The phone shows
what the computer reports and asks it to make changes. It never keeps a second
copy of the project that could disagree.

The remote must never cost a take or a clean playback. If the Wi-Fi drops in
the middle of a take, the computer keeps recording. Remote work never runs on
the real-time audio thread. A discarded take comes back with undo. Audio
recorded on the phone stays on the phone until the computer confirms it has
the complete file.

## 2. Private and safe by default

Remote control is off until the user turns it on. Only paired devices can
connect, and every connection is encrypted, at home too. A remote reaches a
fixed list of musician commands and nothing else: no file system, no scripts,
no app settings. The computer lists every paired device and removes one with a
single click. There are no accounts, no cloud and no tracking. Nothing leaves
the user's own network.

## 3. Honest and instant

Every tap answers at once with a haptic and a visible press. The state the app
shows is the state the computer confirmed: the red record light means the
computer is recording. A command on its way looks pending, and a failed
command says so. When speed and truth disagree, truth wins. Connection status
is always visible, and stale state is never shown as live.

Every edit names its target (track, bar, beat), so a click on the computer can
never redirect what the phone is editing.

## 4. It just works

Setup is one QR scan. After that the phone finds the computer by itself and
reconnects whenever both are on the same network and Tabber Studio is open,
even when the address changes. The normal path has no accounts, IP addresses
or port numbers. When something blocks the connection (local network access
turned off, guest Wi-Fi, a VPN, Tabber Studio closed), the app says what is
wrong in plain words and how to fix it.

## 5. Eyes on the performer, hands on the instrument

The app works without looking at it. Record, stop and "go again" sit in fixed
places and never move. Each has its own haptic, and the recording state reads
from across the room. Targets are big enough for one thumb. Destructive
actions are protected against accidental taps without slowing down the take
loop. The most common path (arm, record, stop, keep or discard, go again)
takes the fewest taps of anything in the app.

## 6. Modern, native and sleek

The app looks and feels like it belongs on the current iPhone: SwiftUI, the
system design language, SF Symbols, system type and haptics, smooth motion,
Dark Mode, Dynamic Type and VoiceOver. Its character comes from the music
(meters, tab, markers, Tabber's colours), not from decoration. It opens
straight into the last session. Few screens, no settings maze.

## 7. Light on the computer, light on the battery

When remote control is off it costs nothing: no listening socket, no thread,
nothing added to Tabber Studio's startup. When it is on, updates are
rate-limited and sent only to devices that show them. The phone animates the
playhead and meters locally from compact updates instead of asking for a flood
of messages, and it stops work it does not need in the background.

## 8. One protocol, every platform

Phone and computer speak one documented, versioned protocol, with example
exchanges that every implementation must pass. The same iPhone app will work
with Tabber Studio on macOS, Windows and Linux. An Android app is another
client for the same protocol, not a new design. Platform code (discovery,
audio capture, screens) stays behind small boundaries. Versions meet
gracefully: a newer phone app hides what an older Tabber Studio cannot do
instead of failing.

## 9. Same commands, provable without a phone

The remote is a surface on Tabber Studio's Control API, not a second
implementation. A remote command produces the same result as the menu or the
AI chat: the same undo step, dirty state and visible panels. Every remote
feature can be driven and verified headlessly by a scripted client before
anyone picks up a phone, and the phone app can be built and tested against a
scripted stand-in for Tabber Studio.
