import Foundation

/// A simulated Tabber Studio in the app, speaking the protocol over memory.
///
/// The app runs it in demo mode (App Review, screenshots, the stage fallback)
/// and every screen's tests run against it (plan: Rules, iOS). It keeps a real
/// session: a moving playhead, count-in, recording that makes takes, discard
/// and undo with step ids, markers, idempotency keys and events. It does no
/// TLS and accepts any device: it is a demo, never a host on the network.
public actor DemoHost {
    public static let hostID = "5e1f0a2b-3c4d-4e5f-8a6b-7c8d9e0f1a2b"
    public static let name = "Demo Studio"

    struct Step { var id: String; var label: String; var before: Song; var after: Song }

    struct Song: Equatable {
        var tracks: [Track]
        var markers: [Marker]
        var takes: [Take]
        var project: ProjectState
        /// Undo steps in Tabber Studio: mute, solo and tab notes. Volume and pan are not.
        var muted: Set<String> = []
        var soloed: Set<String> = []
        var tabs: [String: DemoTab] = [:]
        /// Routing, as Tabber Studio's Routing panel edits it: outputs and which
        /// sends exist are undo steps; a send's level and Pre-fader are not.
        var outputs: [String: String] = [:]      // source strip id → bus strip id; absent is the master
        var sends: Set<String> = []              // "track>bus"
    }

    final class Connection {
        let transport: MemoryTransport
        var topics: Set<String> = []
        var seq = 0
        var authed = false
        var challenge = Data()
        /// Gone quiet without a close, as a suspended app's socket does.
        var silent = false
        init(transport: MemoryTransport) { self.transport = transport }
    }

    // Session state
    private var song: Song
    private var gone: [String: Take] = [:]
    private var undo: [Step] = []
    private var undoIndex = 0
    private var tempo = 96.0
    private var scale = 1.0
    private var click = false
    private var countIn = 0
    private var loop = LoopState(enabled: false, start: nil, end: nil)
    private var playing = false
    private var anchorBeat = 0.0              // where the playhead was at anchorTime
    private var anchorTime = ContinuousClock.now
    private var recordingStart: (position: Position, at: ContinuousClock.Instant, track: String)?
    private var takeCounter = 0
    private var stepCounter = 40
    private var markerCounter = 0
    private var answers: [String: JSONValue] = [:]
    private var connections: [ObjectIdentifier: Connection] = [:]
    private var ticker: Task<Void, Never>?
    private var lastSent: [String: JSONValue] = [:]
    private let epoch = ContinuousClock.now
    /// Fader travel and pan for every strip: direct writes, as in Tabber Studio.
    private var faders: [String: (volume: Double, pan: Double)] = [:]
    private var buses: [(id: String, name: String)] = [("demo-bus-reverb", "Reverb")]
    private var busCounter = 0
    /// Each strip's INSERTS (plugins/1): the guitar plays through Tabber Amp.
    private var inserts: [String: [Insert]] = ["demo-guitar": [Insert(id: "fx-1", name: "Tabber Amp")]]
    private var insertCounter = 1
    /// The Insert Plugin browser's rows: Tabber's own, then plug-ins the demo computer has.
    static let plugins: [PluginRow] = [
        PluginRow(id: "pl-tabber-amp", name: "Tabber Amp", vendor: "Tabber", category: "Amp", kind: "effect",
                  format: "vst3", tabber: true),
        PluginRow(id: "pl-tabber-eq", name: "Tabber EQ", vendor: "Tabber", category: "EQ", kind: "effect",
                  format: "vst3", tabber: true),
        PluginRow(id: "pl-tabber-compressor", name: "Tabber Compressor", vendor: "Tabber", category: "Dynamics",
                  kind: "effect", format: "vst3", tabber: true),
        PluginRow(id: "pl-tabber-limiter", name: "Tabber Limiter", vendor: "Tabber", category: "Dynamics",
                  kind: "effect", format: "native", tabber: true),
        PluginRow(id: "pl-tabber-synth", name: "Tabber Synth", vendor: "Tabber", category: "Synthesizer",
                  kind: "instrument", format: "native", tabber: true),
        PluginRow(id: "pl-demo-plate", name: "Plate Reverb", vendor: "Demo Audio", category: "Reverb",
                  kind: "effect", format: "vst3", tabber: false),
        PluginRow(id: "pl-demo-echo", name: "Tape Echo", vendor: "Demo Audio", category: "Delay",
                  kind: "effect", format: "clap", tabber: false),
    ]
    /// Each send's level and Pre-fader: direct writes, as the mixer's send controls.
    private var sendLevels: [String: (level: Double, pre: Bool)] = [:]
    /// The chat (chat/1), answered by a few scripted words in place of the AI.
    private var chat = ChatState(available: true, state: "idle", messages: [], plan: nil)
    private var chatCounter = 0
    private var chatRequest = ""
    private var chatAction: (planID: String, track: String, solo: Bool)?
    /// What the demo computer shows (view/1), and the editor Split goes back to.
    private var view = ViewState(editor: "tab", split: false)
    /// How each MIDI track shows in the Tab editor once its "MIDI part" card
    /// was answered: "midi_tab" or "notation" (view.part/1).
    private var partShows: [String: String] = [:]
    /// MIDI tracks with a drum kit, which cannot show MIDI tab in Tabber Studio.
    private var drums: Set<String> = []
    private var preSplit = "tab"
    /// The Speed Trainer (trainer/1); its speed is the demo's tempo scale.
    private var trainer = TrainerState()
    /// Where the last tick was, to see the loop come round.
    private var lastBeat = 0.0
    /// The Tab view's cursor on each tab track, and the duration a new note gets.
    private var tabCursors: [String: TabCursor] = [:]
    private var tabDuration = NoteValue(value: 4)
    private var tabRevision = 1
    private var trackCounter = 0

    /// Tests: drop the connection after doing the next request, before answering.
    public var dropBeforeNextAnswer = false
    public private(set) var recordingsStarted = 0

    /// The protocol versions this computer speaks: another major version
    /// shows the app's Update cards (TR6).
    public let speaks: [String]

    /// The name the demo computer gives itself; a longer one checks how the
    /// app's bars fit a real computer's name.
    public let computerName: String

    /// `onlyAudio` starts with a song of only audio tracks, as one made from
    /// audio files is: no tab to write on until a tab track is added.
    /// `midiDrums` makes Drums a MIDI track with a drum kit, as one from a MIDI
    /// file is (TR39's card, no MIDI tab), instead of a drum track with drum
    /// tab, as Tabber Studio's Percussion Track and a Guitar Pro file make it (TR45).
    public init(speaks: [String] = RemoteClient.protocolVersions, computerName: String = DemoHost.name,
                onlyAudio: Bool = false, midiDrums: Bool = false) {
        self.computerName = computerName
        self.speaks = speaks
        // Tabber Studio's own track colours (core/models.py TRACK_COLORS), in its strip order.
        song = Song(
            tracks: [Track(id: "demo-guitar", name: "Guitar", kind: .midi, armed: false, monitor: .auto, selected: true,
                           color: "#50A0DC", instrument: "Acoustic Guitar (steel)", tuning: DemoTab.standard),
                     Track(id: "demo-bass", name: "Bass", kind: .midi, armed: false, monitor: .auto, selected: false,
                           color: "#64BE64", instrument: "Electric Bass (finger)", tuning: DemoTab.bass),
                     Track(id: "demo-drums", name: "Drums", kind: .midi, armed: false, monitor: .auto, selected: false,
                           color: "#DCAA3C", instrument: midiDrums ? "Standard Kit" : "Drums",
                           drumTab: midiDrums ? nil : true),
                     Track(id: "demo-lead", name: "Lead guitar", kind: .audio, armed: false, monitor: .auto, selected: false,
                           color: "#AA64D2"),
                     Track(id: "demo-vocals", name: "Vocals", kind: .audio, armed: false, monitor: .auto, selected: false,
                           color: "#DC5050")],
            markers: [Marker(id: "demo-intro", name: "Intro", bar: 1, beat: 1),
                      Marker(id: "demo-verse", name: "Verse", bar: 9, beat: 1),
                      Marker(id: "demo-chorus", name: "Chorus", bar: 25, beat: 1),
                      Marker(id: "demo-solo", name: "Solo", bar: 41, beat: 1)],
            takes: [],
            project: ProjectState(title: "Demo Song", unsaved: false, hasFile: true),
            tabs: midiDrums ? ["demo-guitar": DemoTab.demoGuitar(), "demo-bass": DemoTab.demoBass()]
                : ["demo-guitar": DemoTab.demoGuitar(), "demo-bass": DemoTab.demoBass(), "demo-drums": DemoTab.demoDrums()],
            sends: ["demo-lead>demo-bus-reverb", "demo-vocals>demo-bus-reverb"])
        sendLevels = ["demo-lead>demo-bus-reverb": (0.25, false), "demo-vocals>demo-bus-reverb": (0.5, false)]
        faders = ["demo-guitar": (0.7, -0.3), "demo-bass": (0.62, 0), "demo-drums": (0.66, 0),
                  "demo-lead": (0.7, 0.32), "demo-vocals": (0.74, 0), "demo-bus-reverb": (0.52, 0), "master": (0.7, 0)]
        if midiDrums { drums = ["demo-drums"] }
        if onlyAudio {
            song.tracks.removeAll { $0.kind == .midi }
            song.tracks[0].selected = true
            song.tabs = [:]
        }
    }

    public func setDropBeforeNextAnswer(_ value: Bool) { dropBeforeNextAnswer = value }

    /// Tests: how many session.snapshot requests the demo has answered.
    public private(set) var snapshotsServed = 0

    /// Tests: send every connection again the last event it had, with its seq:
    /// an event the phone's last snapshot or event already holds (spec 8.2).
    public func resendLastEvent() {
        for connection in connections.values where connection.authed && connection.seq > 0 {
            send(["jsonrpc": "2.0", "method": "event",
                  "params": ["topic": "undo", "seq": .number(Double(connection.seq)), "t": .number(now()),
                             "data": (try? JSONCoding.value(undoState())) ?? .null]],
                 to: connection)
        }
    }

    /// Tests: every open connection goes quiet without closing (no answers, no
    /// heartbeats), as when the phone was away; new connections work.
    public func goSilent() { for connection in connections.values { connection.silent = true } }

    /// Connections made so far, open or not.
    public private(set) var connectionsMade = 0

    /// A new connection; the phone uses the returned end.
    public func connect() -> MemoryTransport {
        let (phone, host) = MemoryTransport.pair()
        let connection = Connection(transport: host)
        connections[ObjectIdentifier(connection)] = connection
        connectionsMade += 1
        Task { await self.serve(connection) }
        Task { await self.heartbeats(connection) }
        return phone
    }

    private func serve(_ connection: Connection) async {
        while let text = try? await connection.transport.receive() {
            await handle(text, on: connection)
        }
        connections[ObjectIdentifier(connection)] = nil
    }

    private func heartbeats(_ connection: Connection) async {
        while connections[ObjectIdentifier(connection)] != nil {
            try? await Task.sleep(for: .seconds(2))
            guard connections[ObjectIdentifier(connection)] != nil else { return }
            send(["jsonrpc": "2.0", "method": "heartbeat",
                  "params": ["t": .number(now()), "seq": .number(Double(connection.seq)), "busy": false]], to: connection)
        }
    }

    private func now() -> Double { (ContinuousClock.now - epoch).seconds + 1000.0 }

    private func send(_ message: JSONValue, to connection: Connection) {
        guard !connection.silent, let text = try? JSONCoding.encode(message) else { return }
        connection.transport.sendNow(text)
    }

    // MARK: requests

    private func handle(_ text: String, on connection: Connection) async {
        guard let message = try? JSONCoding.parse(text), let id = message["id"],
              let method = message["method"]?.stringValue else { return }
        let params = message["params"] ?? [:]
        let before = topicData()
        var answer: JSONValue
        do {
            answer = ["jsonrpc": "2.0", "id": id, "result": try run(method, params, connection)]
        } catch let failure as RemoteError {
            answer = ["jsonrpc": "2.0", "id": id,
                      "error": ["code": .number(Double(failure.code)), "message": .string(failure.message),
                                "data": failure.data]]
        } catch {
            answer = errorAnswer(id, "internal_error")
        }
        if dropBeforeNextAnswer {
            dropBeforeNextAnswer = false
            connection.transport.drop()
            connections[ObjectIdentifier(connection)] = nil
        } else {
            send(answer, to: connection)
        }
        if answer["error"]?["data"]?["reason"]?.stringValue == "unsupported_version" {
            connection.transport.close(code: 4002)       // as a real host does (vector version_mismatch)
            connections[ObjectIdentifier(connection)] = nil
            return
        }
        broadcastChanges(from: before)
    }

    private func errorAnswer(_ id: JSONValue, _ reason: String) -> JSONValue {
        let failure = DemoErrors.make(reason)
        return ["jsonrpc": "2.0", "id": id, "error": ["code": .number(Double(failure.code)),
                                                      "message": .string(failure.message), "data": failure.data]]
    }

    private func run(_ method: String, _ p: JSONValue, _ connection: Connection) throws -> JSONValue {
        switch method {
        case "hello":
            let offered = p["protocol_versions"]?.arrayValue?.compactMap(\.stringValue) ?? []
            func major(_ v: String) -> Substring { v.split(separator: ".").first ?? "" }
            guard offered.contains(where: { o in speaks.contains { major($0) == major(o) } }) else {
                throw DemoErrors.make("unsupported_version", ["host_versions": .array(speaks.map { .string($0) })])
            }
            connection.challenge = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
            return ["host": ["id": .string(Self.hostID), "name": .string(computerName), "app_version": "demo"],
                    "protocol_version": "1.11",
                    "capabilities": ["transport/1", "record/1", "tempo_scale/1", "tracks/1", "tracks.monitor/1",
                                     "markers/1", "takes/1", "takes.discard/1", "takes.go_again/1", "undo/1",
                                     "save/1", "meters/1", "mixer/1", "tab/1", "routing/1", "chat/1", "view/1",
                                     "trainer/1", "tracks.add/1", "view.part/1", "tab.midi/1",
                                     "mixer.add_bus/1", "plugins/1", "tab.drum/1"],
                    "limits": ["max_frame_bytes": 65536, "requests_per_second": 20, "burst": 40,
                               "heartbeat_ms": 2000, "heartbeat_misses": 3, "connections_per_device": 2],
                    "challenge": .string(Base64URL.encode(connection.challenge))]
        case "pair":
            guard let key = p["device"]?["key"]?.stringValue, let der = Base64URL.decode(key) else {
                throw DemoErrors.make("invalid_params", ["field": "device"])
            }
            connection.authed = true
            return ["device_id": .string(RemoteCrypto.deviceID(publicKeyDER: der)),
                    "host": ["id": .string(Self.hostID), "name": .string(computerName)]]
        case "auth":
            connection.authed = true
            return ["device": ["id": p["device_id"] ?? "", "name": "Demo iPhone"]]
        default:
            break
        }
        guard connection.authed else { throw DemoErrors.make("unauthenticated") }
        if let key = p["key"]?.stringValue {
            if let stored = answers[key] { return stored }
            let value = try verb(method, p, connection)
            answers[key] = value
            return value
        }
        return try verb(method, p, connection)
    }

    private func verb(_ method: String, _ p: JSONValue, _ connection: Connection) throws -> JSONValue {
        switch method {
        case "session.subscribe":
            for topic in p["topics"]?.arrayValue ?? [] { if let t = topic.stringValue { connection.topics.insert(t) } }
            return try snapshot(seq: connection.seq)
        case "session.unsubscribe":
            for topic in p["topics"]?.arrayValue ?? [] { if let t = topic.stringValue { connection.topics.remove(t) } }
            return ["topics": .array(connection.topics.sorted().map { .string($0) })]
        case "session.snapshot":
            snapshotsServed += 1
            return try snapshot(seq: connection.seq)
        case "transport.play":
            if let from = p["from"], let bar = from["bar"]?.intValue, let beat = from["beat"]?.intValue {
                anchorBeat = Double((bar - 1) * 4 + beat - 1)
            } else {
                anchorBeat = currentBeat()
            }
            anchorTime = .now
            playing = true
            startTicker()
            return ["transport": try JSONCoding.value(transport())]
        case "transport.stop":
            let take = try stopEverything()
            return ["transport": try JSONCoding.value(transport()), "record": try JSONCoding.value(record()),
                    "take": take.map { (try? JSONCoding.value($0)) ?? .null } ?? .null]
        case "transport.record":
            let wanted = Set((p["armed_track_ids"]?.arrayValue ?? []).compactMap(\.stringValue))
            if recordingStart != nil { throw DemoErrors.make("already_recording", ["record": try JSONCoding.value(record())]) }
            if wanted != Set(song.tracks.filter(\.armed).map(\.id)) || wanted.isEmpty {
                throw DemoErrors.make("stale_target", ["tracks": try JSONCoding.value(song.tracks),
                                                       "record": try JSONCoding.value(record())])
            }
            if let bars = p["count_in_bars"]?.intValue { countIn = bars }
            try startRecording(track: song.tracks.first(where: \.armed)!.id, atBeat: playing ? currentBeat() : anchorBeat)
            return ["transport": try JSONCoding.value(transport()), "record": try JSONCoding.value(record())]
        case "transport.seek":
            guard let bar = p["to"]?["bar"]?.intValue, let beat = p["to"]?["beat"]?.intValue else {
                throw DemoErrors.make("invalid_params", ["field": "to"])
            }
            anchorBeat = Double((bar - 1) * 4 + beat - 1)
            anchorTime = .now
            return ["transport": try JSONCoding.value(transport())]
        case "transport.set_loop":
            let enabled = p["enabled"]?.boolValue ?? false
            if let start = p["start"], let end = p["end"] {
                loop = LoopState(enabled: enabled, start: try JSONCoding.decode(BarBeat.self, from: start),
                                 end: try JSONCoding.decode(BarBeat.self, from: end))
            } else {
                loop.enabled = enabled
            }
            if !enabled {                                   // as a click on Loop: the trainer goes off
                anchorBeat = currentBeat(); anchorTime = .now
                trainer.enabled = false
                scale = 1.0
            }
            return ["transport": try JSONCoding.value(transport())]
        case "transport.set_click":
            click = p["enabled"]?.boolValue ?? false
            return ["transport": try JSONCoding.value(transport())]
        case "transport.set_count_in":
            countIn = max(0, min(2, p["bars"]?.intValue ?? 0))
            return ["transport": try JSONCoding.value(transport())]
        case "transport.set_tempo_scale":
            anchorBeat = currentBeat(); anchorTime = .now
            scale = max(0.25, min(2.0, p["scale"]?.doubleValue ?? 1))
            return ["transport": try JSONCoding.value(transport())]
        case "tracks.arm":
            let id = p["track_id"]?.stringValue ?? ""
            guard let index = song.tracks.firstIndex(where: { $0.id == id }) else {
                throw DemoErrors.make("unknown_track", ["tracks": try JSONCoding.value(song.tracks)])
            }
            song.tracks[index].armed = p["armed"]?.boolValue ?? false
            if song.tracks[index].armed { startTicker() }        // an armed input shows its level at once
            return ["tracks": try JSONCoding.value(song.tracks)]
        case "tracks.select":
            let id = p["track_id"]?.stringValue ?? ""
            guard song.tracks.contains(where: { $0.id == id }) else {
                throw DemoErrors.make("unknown_track", ["tracks": try JSONCoding.value(song.tracks)])
            }
            for i in song.tracks.indices { song.tracks[i].selected = song.tracks[i].id == id }
            return ["tracks": try JSONCoding.value(song.tracks)]
        case "tracks.set_monitor":
            let id = p["track_id"]?.stringValue ?? ""
            guard let index = song.tracks.firstIndex(where: { $0.id == id }) else {
                throw DemoErrors.make("unknown_track", ["tracks": try JSONCoding.value(song.tracks)])
            }
            song.tracks[index].monitor = MonitorMode(rawValue: p["mode"]?.stringValue ?? "auto") ?? .auto
            return ["tracks": try JSONCoding.value(song.tracks)]
        case "tracks.add":
            guard let kind = p["kind"]?.stringValue.flatMap(NewTrackKind.init(rawValue:)) else {
                throw DemoErrors.make("invalid_params", ["field": "kind"])
            }
            // A new track clears the record arms in Tabber Studio, which would end the take.
            if recordingStart != nil { throw DemoErrors.make("already_recording", ["record": try JSONCoding.value(record())]) }
            let track = addTrack(kind)
            return ["track": try JSONCoding.value(track), "tracks": try JSONCoding.value(song.tracks),
                    "undo": try JSONCoding.value(undoState())]
        case "markers.go", "markers.loop":
            let id = p["marker_id"]?.stringValue ?? ""
            guard let marker = song.markers.first(where: { $0.id == id }) else {
                throw DemoErrors.make("unknown_marker", ["markers": try JSONCoding.value(song.markers)])
            }
            if method == "markers.go" {
                anchorBeat = Double((marker.bar - 1) * 4 + marker.beat - 1)
                anchorTime = .now
            } else {
                let next = song.markers.map(\.bar).filter { $0 > marker.bar }.min() ?? marker.bar + 8
                loop = LoopState(enabled: true, start: BarBeat(bar: marker.bar, beat: marker.beat), end: BarBeat(bar: next, beat: 1))
            }
            return ["transport": try JSONCoding.value(transport())]
        case "markers.add":
            guard let bar = p["at"]?["bar"]?.intValue, let beat = p["at"]?["beat"]?.intValue else {
                throw DemoErrors.make("invalid_params", ["field": "at"])
            }
            markerCounter += 1
            let marker = Marker(id: "demo-flag-\(markerCounter)", name: p["name"]?.stringValue ?? "Flag", bar: bar, beat: beat)
            edit("Add marker '\(marker.name)'") { $0.markers.append(marker); $0.markers.sort { ($0.bar, $0.beat) < ($1.bar, $1.beat) } }
            return ["marker": try JSONCoding.value(marker), "markers": try JSONCoding.value(song.markers)]
        case "takes.list":
            let id = p["track_id"]?.stringValue ?? ""
            return ["takes": try JSONCoding.value(heard(song.takes.filter { $0.trackID == id }))]
        case "takes.discard":
            let id = p["take_id"]?.stringValue ?? ""
            guard let take = song.takes.first(where: { $0.id == id }) else {
                throw DemoErrors.make("unknown_take", ["takes": try JSONCoding.value(recentTakes())])
            }
            gone[id] = take
            edit("Discard take") { $0.takes.removeAll { $0.id == id } }
            return ["takes": try JSONCoding.value(recentTakes()), "undo": try JSONCoding.value(undoState())]
        case "takes.go_again":
            let id = p["take_id"]?.stringValue ?? ""
            guard let take = song.takes.first(where: { $0.id == id }) ?? gone[id] else {
                throw DemoErrors.make("unknown_take", ["takes": try JSONCoding.value(recentTakes())])
            }
            _ = try stopEverything()
            for i in song.tracks.indices where song.tracks[i].id == take.trackID { song.tracks[i].armed = true }
            try startRecording(track: take.trackID, atBeat: Double((take.start.bar - 1) * 4 + take.start.beat - 1))
            return ["transport": try JSONCoding.value(transport()), "record": try JSONCoding.value(record())]
        case "takes.rate":
            let id = p["take_id"]?.stringValue ?? ""
            guard song.takes.contains(where: { $0.id == id }) else {
                throw DemoErrors.make("unknown_take", ["takes": try JSONCoding.value(recentTakes())])
            }
            let rating = max(0, min(5, p["rating"]?.intValue ?? 0))
            edit("Rate take") { song in
                for i in song.takes.indices where song.takes[i].id == id { song.takes[i].rating = rating }
            }
            return ["take": try JSONCoding.value(heard(song.takes.filter { $0.id == id })[0])]
        case "edit.undo", "edit.redo":
            let redo = method == "edit.redo"
            let expect = p["expect"]?.stringValue ?? ""
            let index = redo ? undoIndex : undoIndex - 1
            guard undo.indices.contains(index) else {
                throw DemoErrors.make(redo ? "nothing_to_redo" : "nothing_to_undo", ["undo": try JSONCoding.value(undoState())])
            }
            guard undo[index].id == expect else {
                throw DemoErrors.make("undo_mismatch", ["undo": try JSONCoding.value(undoState())])
            }
            song = redo ? undo[index].after : undo[index].before
            undoIndex = redo ? undoIndex + 1 : undoIndex - 1
            tabRevision += 1
            return ["undo": try JSONCoding.value(undoState())]
        case "project.save":
            song.project.unsaved = false
            return ["project": try JSONCoding.value(song.project)]
        case "mixer.state":
            return ["mixer": try JSONCoding.value(mixerState())]
        case "mixer.set_volume", "mixer.set_pan":
            let id = p["strip_id"]?.stringValue ?? ""
            guard var fader = faders[id] else {
                throw DemoErrors.make("unknown_strip", ["mixer": try JSONCoding.value(mixerState())])
            }
            let field = method == "mixer.set_volume" ? "volume" : "pan"
            guard let value = p[field]?.doubleValue else { throw DemoErrors.make("invalid_params", ["field": .string(field)]) }
            if field == "volume" { fader.volume = max(0, min(1, value)) } else { fader.pan = max(-1, min(1, value)) }
            faders[id] = fader
            return ["strip": try JSONCoding.value(strip(id)!)]
        case "mixer.set_mute", "mixer.set_solo":
            let id = p["strip_id"]?.stringValue ?? ""
            guard faders[id] != nil, id != "master" else {
                throw DemoErrors.make("unknown_strip", ["mixer": try JSONCoding.value(mixerState())])
            }
            let mute = method == "mixer.set_mute"
            let on = p[mute ? "muted" : "soloed"]?.boolValue ?? false
            let name = strip(id)?.name ?? ""
            if (mute ? song.muted : song.soloed).contains(id) != on {
                edit("\(on ? "" : "Un")\(mute ? "mute" : "solo") \(name)".capitalizedFirst) { song in
                    if mute {
                        if on { song.muted.insert(id) } else { song.muted.remove(id) }
                    } else {
                        if on { song.soloed.insert(id) } else { song.soloed.remove(id) }
                    }
                }
            }
            return ["mixer": try JSONCoding.value(mixerState()), "undo": try JSONCoding.value(undoState())]
        case "mixer.add_bus":
            // The mixer's "+ Bus" once its New Bus dialog has a name: trimmed,
            // not only spaces; no undo step, as in Tabber Studio.
            let name = (p["name"]?.stringValue ?? "").trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { throw DemoErrors.make("invalid_params", ["field": "name"]) }
            busCounter += 1
            let id = "demo-bus-\(busCounter)"
            buses.append((id, name))
            faders[id] = (0.7, 0)
            return ["strip": try JSONCoding.value(strip(id)!), "mixer": try JSONCoding.value(mixerState())]
        case "plugins.catalog":
            let offset = max(0, p["offset"]?.intValue ?? 0), limit = max(1, min(200, p["limit"]?.intValue ?? 200))
            return ["plugins": try JSONCoding.value(Array(Self.plugins.dropFirst(offset).prefix(limit))),
                    "total": .number(Double(Self.plugins.count)), "offset": .number(Double(offset))]
        case "plugins.insert":
            // The strip's "+ Plugin" and the browser's Insert: at the end of the
            // chain; an instrument becomes a MIDI track's sound source instead.
            let id = p["strip_id"]?.stringValue ?? ""
            guard strip(id) != nil else { throw DemoErrors.make("unknown_strip", ["mixer": try JSONCoding.value(mixerState())]) }
            guard let row = Self.plugins.first(where: { $0.id == p["plugin_id"]?.stringValue }) else {
                throw DemoErrors.make("host_error", ["detail": "That plug-in is not on the computer any more. Open the list again."])
            }
            if row.isInstrument {
                guard song.tracks.first(where: { $0.id == id })?.kind == .midi else {
                    throw DemoErrors.make("host_error", ["detail": "Insert this instrument on a MIDI/score track"])
                }
            } else {
                insertCounter += 1
                inserts[id, default: []].append(Insert(id: "fx-\(insertCounter)", name: row.name))
            }
            return ["strip": try JSONCoding.value(strip(id)!), "mixer": try JSONCoding.value(mixerState()),
                    "sound_source": .bool(row.isInstrument)]
        case "plugins.bypass", "plugins.remove", "plugins.open":
            let id = p["strip_id"]?.stringValue ?? ""
            guard strip(id) != nil else { throw DemoErrors.make("unknown_strip", ["mixer": try JSONCoding.value(mixerState())]) }
            guard let index = inserts[id]?.firstIndex(where: { $0.id == p["insert_id"]?.stringValue }) else {
                throw DemoErrors.make("stale_target", ["mixer": try JSONCoding.value(mixerState())])
            }
            switch method {
            case "plugins.bypass":
                inserts[id]![index].bypassed = p["bypassed"]?.boolValue ?? false
                return ["strip": try JSONCoding.value(strip(id)!)]
            case "plugins.remove":
                inserts[id]!.remove(at: index)
                return ["strip": try JSONCoding.value(strip(id)!), "mixer": try JSONCoding.value(mixerState())]
            default:
                return [:]                          // its window would open on the computer
            }
        case "trainer.state":
            return ["trainer": try JSONCoding.value(trainerState())]
        case "trainer.set":
            let enabled = p["enabled"]?.boolValue ?? trainer.enabled
            if enabled && !loop.enabled {
                throw DemoErrors.make("needs_loop", ["trainer": try JSONCoding.value(trainerState())])
            }
            if let v = p["start"]?.intValue { trainer.start = max(25, min(200, v)) }
            if let v = p["step"]?.intValue { trainer.step = max(1, min(50, v)) }
            if let v = p["target"]?.intValue { trainer.target = max(25, min(200, v)) }
            trainer.enabled = enabled
            anchorBeat = currentBeat(); anchorTime = .now
            scale = enabled ? Double(trainer.start) / 100 : 1.0     // a changed field starts again, as in Studio
            return ["trainer": try JSONCoding.value(trainerState())]
        case "view.state":
            return ["view": try JSONCoding.value(viewState())]
        case "view.set":
            if let editor = p["editor"]?.stringValue {
                guard ViewState.editors.contains(editor) else { throw DemoErrors.make("invalid_params", ["field": "editor"]) }
                view = ViewState(editor: editor, split: false)          // an editor button leaves Split, as in Studio
            }
            if let split = p["split"]?.boolValue, split != view.split {
                if split {                                           // an editor beside Arrange
                    preSplit = view.editor
                    view = ViewState(editor: view.editor == "arrange" ? "tab" : view.editor, split: true)
                } else {                                             // back to the editor before, as F8 does
                    view = ViewState(editor: preSplit, split: false)
                }
            }
            return ["view": try JSONCoding.value(viewState())]
        case "view.show_part":
            let id = p["track_id"]?.stringValue ?? ""
            guard let shows = p["as"]?.stringValue, ["midi_tab", "notation"].contains(shows) else {
                throw DemoErrors.make("invalid_params", ["field": "as"])
            }
            // The card's own buttons: only while the card waits, and MIDI tab not for drums.
            guard let part = viewState().part, part.trackID == id, part.shows == "card",
                  shows == "notation" || part.midiTab else {
                throw DemoErrors.make("stale_target", ["view": try JSONCoding.value(viewState())])
            }
            partShows[id] = shows
            if shows == "midi_tab", song.tabs[id] == nil {        // its MIDI tab, guitar strings as Studio's default
                let rest = [TabBeat(duration: NoteValue(value: 4), rest: true, notes: [])]
                song.tabs[id] = DemoTab(tuning: DemoTab.standard,
                                        bars: Array(repeating: rest, count: song.tabs.values.map(\.bars.count).max() ?? 16))
                tabRevision += 1
            }
            return ["view": try JSONCoding.value(viewState())]
        case "chat.state":
            return ["chat": try JSONCoding.value(chat)]
        case "chat.send", "chat.confirm", "chat.cancel", "chat.stop":
            try chatVerb(method, p)
            return ["chat": try JSONCoding.value(chat)]
        case "routing.state":
            return ["routing": try JSONCoding.value(routingState())]
        case "routing.set_output", "routing.set_send", "routing.remove_send":
            try routingVerb(method, p)
            return ["routing": try JSONCoding.value(routingState()), "undo": try JSONCoding.value(undoState())]
        case "tab.state":
            return ["tab": tabValue()]
        case "tab.set_cursor", "tab.move", "tab.put", "tab.put_pitch", "tab.set_duration", "tab.rest", "tab.delete":
            try tabVerb(method, p)
            return ["tab": tabValue(), "undo": try JSONCoding.value(undoState())]
        default:
            throw DemoErrors.make("method_not_found")
        }
    }

    // MARK: the mixer and the tab

    /// The fader law: 0 dB at 70 % of the travel, +2.1 dB at the top, as Tabber Studio's fader.
    static func db(_ travel: Double) -> Double? {
        guard travel > 0.001 else { return nil }
        let db = travel >= 0.7 ? (travel - 0.7) / 0.3 * 2.1 : 60 * log10(travel / 0.7)
        return (db * 10).rounded() / 10
    }

    static func panLabel(_ pan: Double) -> String {
        let value = Int((64 + pan * (pan < 0 ? 64 : 63)).rounded())
        return value == 64 ? "C" : value < 64 ? "L\(64 - value)" : "R\(value - 64)"
    }

    /// Tabber Studio's names for note values, as its undo labels say them.
    static func durationName(_ value: Int) -> String {
        [1: "WHOLE", 2: "HALF", 4: "QUARTER", 8: "EIGHTH", 16: "SIXTEENTH", 32: "THIRTY_SECOND"][value] ?? "QUARTER"
    }

    static let scale = [ScaleMark(db: 0, volume: 0.7), ScaleMark(db: -12, volume: 0.442),
                        ScaleMark(db: -24, volume: 0.279), ScaleMark(db: -48, volume: 0.111)]

    private func strip(_ id: String) -> Strip? {
        guard let fader = faders[id] else { return nil }
        let kind: String, name: String, color: String?
        if id == "master" {
            (kind, name, color) = ("master", "Master", nil)
        } else if let bus = buses.first(where: { $0.id == id }) {
            (kind, name, color) = ("bus", bus.name, nil)
        } else if let track = song.tracks.first(where: { $0.id == id }) {
            (kind, name, color) = ("track", track.name, track.color)
        } else {
            return nil
        }
        return Strip(id: id, kind: kind, name: name, color: color, volume: (fader.volume * 1000).rounded() / 1000,
                     volumeDB: Self.db(fader.volume), pan: (fader.pan * 1000).rounded() / 1000,
                     panLabel: Self.panLabel(fader.pan), muted: song.muted.contains(id), soloed: song.soloed.contains(id),
                     inserts: inserts[id] ?? [])
    }

    private func mixerState() -> MixerState {
        let ids = song.tracks.map(\.id) + buses.map(\.id) + ["master"]
        return MixerState(strips: ids.compactMap(strip), scale: Self.scale)
    }

    // MARK: the chat

    private func chatError(_ reason: String) -> Error {
        DemoErrors.make(reason, ["chat": (try? JSONCoding.value(chat)) ?? .null])
    }

    private func say(_ from: String, _ kind: String, _ text: String) {
        chatCounter += 1
        chat.messages.append(ChatMessage(id: "demo-m\(chatCounter)", from: from, kind: kind, text: text))
        if chat.messages.count > 50 { chat.messages.removeFirst(chat.messages.count - 50) }
    }

    /// Tabber Studio's chat, as the demo answers it: mute or solo a track by
    /// name, each one undo step after Execute; keys and settings refused in
    /// Tabber Studio's words; anything else, what to try.
    private func chatVerb(_ method: String, _ p: JSONValue) throws {
        switch method {
        case "chat.send":
            guard !chat.isWorking else { throw chatError("chat_busy") }
            let text = p["text"]?.stringValue ?? ""
            chat.plan = nil
            chatAction = nil
            chatRequest = text
            say("you", "text", text)
            chat.state = "thinking"
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(500))
                await self?.answerChat(text)
            }
        case "chat.confirm", "chat.cancel":
            let id = p["plan_id"]?.stringValue ?? ""
            guard chat.state == "waiting", let action = chatAction, action.planID == id else { throw chatError("unknown_plan") }
            chat.plan = nil
            chatAction = nil
            chat.state = "idle"
            guard method == "chat.confirm" else { return }
            let name = song.tracks.first { $0.id == action.track }?.name ?? "the track"
            edit("AI: \(chatRequest.prefix(40))") { song in
                if action.solo { song.soloed.insert(action.track) } else { song.muted.insert(action.track) }
            }
            say("studio", "result", "\(action.solo ? "Soloed" : "Muted") the \(name) track.")
        default:                                                   // chat.stop
            if chat.isWorking {
                chat.state = "idle"
                say("studio", "text", "Stopped.")
            }
        }
    }

    private func answerChat(_ text: String) {
        guard chat.state == "thinking", chatRequest == text else { return }
        let before = topicData()
        let lower = text.lowercased()
        let track = song.tracks.sorted { $0.name.count > $1.name.count }.first { lower.contains($0.name.lowercased()) }
        if ["key", "password", "token", "pair", "setting"].contains(where: lower.contains) {
            say("studio", "refusal", "From a phone the chat does not reach the AI's own settings, key and tools. Do that on the computer.")
            chat.state = "idle"
        } else if let track, lower.contains("mute") || lower.contains("solo") {
            let solo = !lower.contains("mute")
            chatCounter += 1
            let planID = "demo-p\(chatCounter)"
            chatAction = (planID, track.id, solo)
            chat.plan = ChatPlan(id: planID, text: "I'll \(solo ? "solo" : "mute") the \(track.name) track.",
                                 steps: [.init(text: "\(solo ? "Solo" : "Mute") track: \(track.name)")])
            chat.state = "waiting"
        } else {
            say("studio", "text", "In the demo, try: mute the drums, or solo the bass.")
            chat.state = "idle"
        }
        broadcastChanges(from: before)
    }

    // MARK: routing

    private func routingState() -> RoutingState {
        let sources = song.tracks.map { RoutingSource(stripID: $0.id, kind: "track", name: $0.name,
                                                      output: song.outputs[$0.id] ?? RoutingState.master) }
            + buses.map { RoutingSource(stripID: $0.id, kind: "bus", name: $0.name,
                                        output: song.outputs[$0.id] ?? RoutingState.master) }
        var sends: [RoutingSend] = []
        for track in song.tracks {
            for bus in buses where song.sends.contains("\(track.id)>\(bus.id)") {
                let value = sendLevels["\(track.id)>\(bus.id)"] ?? (0.5, false)
                sends.append(RoutingSend(stripID: track.id, busID: bus.id, level: (value.level * 10000).rounded() / 10000,
                                         levelDB: SendLevel.db(value.level).map { ($0 * 10).rounded() / 10 },
                                         levelLabel: SendLevel.label(value.level), preFader: value.pre))
            }
        }
        return RoutingState(sources: sources, sends: sends)
    }

    private func routingError(_ reason: String, _ extra: [String: JSONValue] = [:]) -> Error {
        var data = extra
        data["routing"] = try? JSONCoding.value(routingState())
        return DemoErrors.make(reason, data)
    }

    /// Tabber Studio's Routing panel: an output moves (one step, "Routing
    /// change"), a send is added at -6 dB or taken away (each a step), and
    /// its level and Pre-fader change without one. A loop is refused, named.
    private func routingVerb(_ method: String, _ p: JSONValue) throws {
        let isBus = { (id: String) in self.buses.contains { $0.id == id } }
        let isTrack = { (id: String) in self.song.tracks.contains { $0.id == id } }
        let id = p["strip_id"]?.stringValue ?? ""
        guard isBus(id) || isTrack(id) || id == "master" else { throw routingError("unknown_strip") }
        switch method {
        case "routing.set_output":
            let output = p["output"]?.stringValue ?? ""
            guard output == RoutingState.master || isBus(output) || isTrack(output) else { throw routingError("unknown_strip") }
            guard id != "master", output == RoutingState.master || isBus(output) else { throw routingError("wrong_kind") }
            if let loop = routingState().wouldLoop(id, into: output) {
                throw routingError("routing_loop", ["path": .array(loop.map { .string($0) })])
            }
            guard (song.outputs[id] ?? RoutingState.master) != output else { return }
            edit("Routing change") { $0.outputs[id] = output == RoutingState.master ? nil : output }
        default:
            let bus = p["bus_id"]?.stringValue ?? ""
            guard isBus(bus) || isTrack(bus) || bus == "master" else { throw routingError("unknown_strip") }
            guard isTrack(id), isBus(bus) else { throw routingError("wrong_kind") }
            let send = "\(id)>\(bus)"
            let name = buses.first { $0.id == bus }?.name ?? bus
            if method == "routing.remove_send" {
                if song.sends.contains(send) { edit("Remove send → \(name)") { $0.sends.remove(send) } }
                return
            }
            if !song.sends.contains(send) {
                sendLevels[send] = (0.5, false)                // Tabber Studio's -6 dB
                edit("Add send → \(name)") { $0.sends.insert(send) }
            }
            var value = sendLevels[send] ?? (0.5, false)
            if let level = p["level"]?.doubleValue { value.level = max(0, min(1, level)) }
            if let pre = p["pre_fader"]?.boolValue { value.pre = pre }
            sendLevels[send] = value
        }
    }

    /// The selected track, when it has tab; a MIDI track's MIDI tab only while
    /// the Tab editor shows it, as in Tabber Studio (tab.midi/1); a drum
    /// track's drum tab always (tab.drum/1).
    private func tabTrackID() -> String? {
        guard let track = song.tracks.first(where: \.selected), song.tabs[track.id] != nil else { return nil }
        if track.tuning == nil, track.drumTab != true, viewState().part?.shows != "midi_tab" { return nil }
        return track.id
    }

    private func tabValue() -> JSONValue {
        guard let id = tabTrackID(), let doc = song.tabs[id] else { return .null }
        let cursor = doc.clamp(tabCursors[id] ?? TabCursor(bar: 1, beat: 1, string: 1))
        // As Studio's toolbar shows it: the beat's own value when it has notes,
        // else the chosen one; Dot and Triplet are always the beat's.
        let beat = doc.beat(at: cursor)
        let shown = beat.map { $0.notes.isEmpty ? NoteValue(value: tabDuration.value, dotted: $0.duration.dotted,
                                                            triplet: $0.duration.triplet) : $0.duration } ?? tabDuration
        let midi = !doc.drum && song.tracks.first { $0.id == id }?.tuning == nil
        let state = TabState(trackID: id, revision: tabRevision, tuning: doc.tuning, drum: doc.drum, cursor: cursor,
                             duration: shown, barCount: doc.bars.count, bars: doc.window(around: cursor),
                             midi: midi ? true : nil)
        return (try? JSONCoding.value(state)) ?? .null
    }

    private func tabVerb(_ method: String, _ p: JSONValue) throws {
        guard let id = tabTrackID(), var doc = song.tabs[id] else {
            throw DemoErrors.make("no_tab", ["tracks": try JSONCoding.value(song.tracks)])
        }
        var cursor = doc.clamp(tabCursors[id] ?? TabCursor(bar: 1, beat: 1, string: 1))
        var label: String?
        switch method {
        case "tab.set_cursor":
            cursor = doc.clamp(TabCursor(bar: p["bar"]?.intValue ?? cursor.bar, beat: p["beat"]?.intValue ?? cursor.beat,
                                         string: p["string"]?.intValue ?? cursor.string))
        case "tab.move":
            let moved = doc.move(cursor, by: p["by"]?.intValue ?? 1, duration: tabDuration)
            if moved.changed { label = moved.cursor.bar > cursor.bar ? "Insert measure" : "Insert beat" }
            cursor = moved.cursor
        case "tab.put" where doc.drum:
            throw DemoErrors.make("host_error", ["detail": "On drum tab, choose a drum from the Drum Map."])
        case "tab.put_pitch" where doc.drum:          // a tap on the Drum Map
            guard let gm = p["pitch"]?.intValue, (0...127).contains(gm) else {
                throw DemoErrors.make("invalid_params", ["field": "pitch"])
            }
            switch doc.putDrum(gm, at: cursor, duration: tabDuration) {
            case .wrote(let line):
                label = "Set fret \(gm) on string \(line)"                  // the number typed on that line
                cursor.string = line
            case .tookOff(let line):
                label = "Delete note on string \(line)"
                cursor.string = line
            case .full:
                // Tabber Studio's own words when its staff finds no line (core/staff_percussion.py).
                throw DemoErrors.make("host_error", ["detail": "No free drum tab lane for the complete chord."])
            }
        case "tab.put":
            guard let string = p["string"]?.intValue, let fret = p["fret"]?.intValue,
                  (1...doc.tuning.count).contains(string), (0...DemoTab.maxFret).contains(fret) else {
                throw DemoErrors.make("invalid_params", ["field": "fret"])
            }
            let off = doc.note(on: string, at: cursor)?.fret == fret
            if doc.put(string: string, fret: fret, at: cursor, duration: tabDuration) {
                label = off ? "Delete note on string \(string)" : "Set fret \(fret) on string \(string)"   // Studio's own labels
            }
            cursor.string = string
        case "tab.put_pitch":
            guard let pitch = p["pitch"]?.intValue else { throw DemoErrors.make("invalid_params", ["field": "pitch"]) }
            let before = doc
            let put = doc.put(pitch: pitch, at: cursor, duration: tabDuration)
            if put.changed {
                let written = doc.note(on: put.string, at: cursor)
                label = written == nil || before.note(on: put.string, at: cursor) == written
                    ? "Delete note on string \(put.string)" : "Set fret \(written!.fret) on string \(put.string)"
            }
            cursor.string = put.string
        case "tab.set_duration":
            guard let value = p["value"]?.intValue, NoteValue.values.contains(value) else {
                throw DemoErrors.make("invalid_params", ["field": "value"])
            }
            let wanted = NoteValue(value: value, dotted: p["dotted"]?.boolValue ?? false, triplet: p["triplet"]?.boolValue ?? false)
            let old = doc.beat(at: cursor)?.duration
            tabDuration = NoteValue(value: value)            // the value sticks; Dot and Triplet are the beat's
            if doc.setDuration(wanted, at: cursor), let old {
                let changes = [old.value != wanted.value, old.dotted != wanted.dotted, old.triplet != wanted.triplet].filter { $0 }.count
                label = changes > 1 ? "Set note value"
                    : old.value != wanted.value ? "Set duration to \(Self.durationName(wanted.value))"
                    : old.dotted != wanted.dotted ? "Toggle dotted" : wanted.triplet ? "Set tuplet 3" : "Clear tuplet"
            }
        case "tab.rest":
            if doc.rest(at: cursor) { label = "Toggle rest" }
        default:
            if doc.delete(at: cursor) { label = "Delete note on string \(cursor.string)" }
        }
        if let label {
            edit(label) { $0.tabs[id] = doc }
            tabRevision += 1
        }
        tabCursors[id] = doc.clamp(cursor)
    }

    // MARK: the view

    /// What the demo computer shows, with the MIDI part its Tab editor shows:
    /// the chosen MIDI track without tab gets Tabber Studio's card until the
    /// phone or the computer answers it (view.part/1).
    private func viewState() -> ViewState {
        var shown = view
        shown.hasPart = true
        shown.part = nil
        if shown.editor == "tab", let track = song.tracks.first(where: \.selected), track.kind == .midi, track.tuning == nil,
           track.drumTab != true {
            shown.part = ViewPart(trackID: track.id, shows: partShows[track.id] ?? "card", midiTab: !drums.contains(track.id))
        }
        return shown
    }

    // MARK: adding tracks

    /// Tabber Studio's track colours (core/models.py TRACK_COLORS), in its order.
    static let palette = ["#50A0DC", "#64BE64", "#DCAA3C", "#AA64D2", "#9A86D6", "#DC5050",
                          "#DC8246", "#96BE3C", "#C864A0", "#648CC8", "#BEA064", "#D2C850"]

    /// "+ Add Track" as Tabber Studio makes each kind (ui/track_creation_controller.py):
    /// the first colour no track has; a tab or MIDI track after the last of
    /// those, before the audio, and selected; an audio track last, with the
    /// computer turning from Tab to Arrange to show it. One undo step each.
    private func addTrack(_ kind: NewTrackKind) -> Track {
        trackCounter += 1
        let sequenced = song.tracks.filter { $0.kind == .midi }.count
        let color = Self.palette.first { c in !song.tracks.contains { $0.color == c } }
            ?? Self.palette[song.tracks.count % Self.palette.count]
        let id = "demo-new-\(trackCounter)"
        let track: Track
        switch kind {
        case .tab:
            track = Track(id: id, name: "Track \(sequenced + 1)", kind: .midi, armed: false, monitor: .auto, selected: true,
                          color: color, instrument: "Acoustic Guitar (steel)", tuning: DemoTab.standard)
        case .midi:
            track = Track(id: id, name: "MIDI Track \(sequenced + 1)", kind: .midi, armed: false, monitor: .auto,
                          selected: true, color: color, instrument: "Acoustic Grand Piano")
        case .audio:
            track = Track(id: id, name: "Audio \(song.tracks.count - sequenced + 1)", kind: .audio, armed: false,
                          monitor: .auto, selected: false, color: color)
        case .drums:                                            // the New Track dialog with Percussion Track ticked
            track = Track(id: id, name: "Drums", kind: .midi, armed: false, monitor: .auto, selected: true,
                          color: color, instrument: "Drums", drumTab: true)
        }
        let bars = song.tabs.values.map(\.bars.count).max() ?? 16
        faders[id] = (0.7, 0)                                   // its mixer strip, at Studio's default
        edit(kind == .audio ? "Add audio track: \(track.name)" : "Add track: \(track.name)") { song in
            if kind == .audio {
                song.tracks.append(track)
                return
            }
            for i in song.tracks.indices { song.tracks[i].selected = false }
            song.tracks.insert(track, at: sequenced)
            if kind == .tab {
                let rest = [TabBeat(duration: NoteValue(value: 4), rest: true, notes: [])]
                song.tabs[id] = DemoTab(tuning: DemoTab.standard, bars: Array(repeating: rest, count: bars))
            } else if kind == .drums {
                song.tabs[id] = DemoTab.emptyDrums(bars: bars)
            }
        }
        if kind == .audio, !view.split, view.editor == "tab" { view.editor = "arrange" }
        if kind == .tab || kind == .drums { tabRevision += 1 }
        return track
    }

    // MARK: the session

    private func edit(_ label: String, _ change: (inout Song) -> Void) {
        let before = song
        change(&song)
        song.project.unsaved = true
        stepCounter += 1
        undo.removeSubrange(undoIndex...)
        undo.append(Step(id: "demo-u\(stepCounter)", label: label, before: before, after: song))
        undoIndex = undo.count
    }

    private func undoState() -> UndoState {
        UndoState(undo: undoIndex > 0 ? UndoStep(id: undo[undoIndex - 1].id, label: undo[undoIndex - 1].label) : nil,
                  redo: undoIndex < undo.count ? UndoStep(id: undo[undoIndex].id, label: undo[undoIndex].label) : nil)
    }

    private func currentBeat() -> Double {
        guard playing else { return anchorBeat }
        let elapsed = (ContinuousClock.now - anchorTime).seconds
        var beat = anchorBeat + elapsed * tempo / 60.0 * scale
        if loop.enabled, let start = loop.start, let end = loop.end {
            let a = Double((start.bar - 1) * 4 + start.beat - 1), b = Double((end.bar - 1) * 4 + end.beat - 1)
            if b > a, beat >= b { beat = a + (beat - a).truncatingRemainder(dividingBy: b - a) }
        }
        return max(0, beat)
    }

    private func trainerState() -> TrainerState {
        TrainerState(enabled: trainer.enabled, start: trainer.start, step: trainer.step, target: trainer.target,
                     speed: Int((scale * 100).rounded()))
    }

    /// Each time the loop comes round, the trainer steps up toward its
    /// target, as Tabber Studio's engine does on its loop's wrap.
    private func stepTrainerOnWrap() {
        let beat = currentBeat()
        defer { lastBeat = beat }
        guard trainer.enabled, loop.enabled, let start = loop.start, let end = loop.end else { return }
        let a = Double((start.bar - 1) * 4 + start.beat - 1), b = Double((end.bar - 1) * 4 + end.beat - 1)
        guard beat < lastBeat, lastBeat >= b - 1, beat < a + 1 else { return }
        let before = topicData()
        anchorBeat = beat; anchorTime = .now
        scale = min(scale + Double(trainer.step) / 100, Double(trainer.target) / 100)
        broadcastChanges(from: before)
    }

    private func position(_ beat: Double) -> Position {
        Position(bar: Int(beat / 4) + 1, beat: Int(beat.truncatingRemainder(dividingBy: 4)) + 1,
                 seconds: (beat * 60.0 / tempo * 1000).rounded() / 1000)
    }

    private func transport() -> TransportState {
        TransportState(state: playing ? .playing : .stopped, position: position(currentBeat()), tempoBPM: tempo,
                       tempoScale: scale, timeSignature: TimeSignature(beats: 4, unit: 4), loop: loop, click: click,
                       countInBars: countIn, countingIn: recordingStart.map { ContinuousClock.now < $0.at } ?? false)
    }

    private func record() -> RecordState {
        let armed = song.tracks.filter(\.armed).map(\.id)
        guard let start = recordingStart else { return RecordState(recording: false, started: nil, armedTrackIDs: armed) }
        let t = now() + (start.at - ContinuousClock.now).seconds
        return RecordState(recording: true, started: RecordStart(position: start.position, t: (t * 1000).rounded() / 1000),
                           armedTrackIDs: armed)
    }

    private func recentTakes() -> [Take] { heard(Array(song.takes.reversed().prefix(20))) }

    /// Which takes play, as Tabber Studio's take lanes decide (TR33): a pass
    /// recorded over an earlier one on its track plays where they overlap, so
    /// an earlier take plays only if some of it is outside every newer one.
    /// Discarding the newer take lets the earlier one play again.
    private func heard(_ takes: [Take]) -> [Take] {
        takes.map { take in
            var take = take
            var left = [(take.start.seconds, take.start.seconds + take.lengthSeconds)]
            let newer = song.takes.drop { $0.id != take.id }.dropFirst().filter { $0.trackID == take.trackID }
            for later in newer {
                let (lo, hi) = (later.start.seconds, later.start.seconds + later.lengthSeconds)
                left = left.flatMap { span -> [(Double, Double)] in
                    guard span.1 > lo, span.0 < hi else { return [span] }
                    return [(span.0, lo), (hi, span.1)].filter { $0.1 - $0.0 > 0.0005 }
                }
            }
            take.active = !left.isEmpty
            return take
        }
    }

    private func startRecording(track: String, atBeat beat: Double) throws {
        let leadBeats = Double(countIn * 4)
        let lead = Duration.seconds(leadBeats * 60.0 / tempo / scale)
        anchorBeat = max(0, beat - leadBeats)
        anchorTime = .now
        playing = true
        recordingStart = (position(beat), ContinuousClock.now + lead, track)
        recordingsStarted += 1
        startTicker()
    }

    private func stopEverything() throws -> Take? {
        var made: Take?
        if let start = recordingStart {
            let length = max(0, (ContinuousClock.now - start.at).seconds)
            takeCounter += 1
            let name = song.tracks.first { $0.id == start.track }?.name ?? "Take"
            let take = Take(id: "demo-take-\(takeCounter)", trackID: start.track, name: "\(name) take \(takeCounter)",
                            start: start.position, lengthSeconds: (length * 1000).rounded() / 1000, rating: 0, active: true)
            recordingStart = nil
            edit("Record take") { $0.takes.append(take) }
            made = take
        }
        anchorBeat = currentBeat()
        anchorTime = .now
        playing = false
        return made
    }

    private func snapshot(seq: Int) throws -> JSONValue {
        ["seq": .number(Double(seq)), "t": .number(now()), "project": try JSONCoding.value(song.project),
         "transport": try JSONCoding.value(transport()), "record": try JSONCoding.value(record()),
         "tracks": try JSONCoding.value(song.tracks), "markers": try JSONCoding.value(song.markers),
         "takes": try JSONCoding.value(recentTakes()), "undo": try JSONCoding.value(undoState())]
    }

    // MARK: events

    private func topicData() -> [String: JSONValue] {
        var data: [String: JSONValue] = [:]
        var transportValue = (try? JSONCoding.value(transport())) ?? .null
        if case .object(var fields) = transportValue { fields["position"] = nil; transportValue = .object(fields) }
        data["transport"] = transportValue
        data["record"] = try? JSONCoding.value(RecordState(recording: recordingStart != nil,
                                                           started: recordingStart.map { RecordStart(position: $0.position, t: 0) },
                                                           armedTrackIDs: song.tracks.filter(\.armed).map(\.id)))
        data["tracks"] = try? JSONCoding.value(song.tracks)
        data["markers"] = try? JSONCoding.value(song.markers)
        data["takes"] = try? JSONCoding.value(recentTakes())
        data["undo"] = try? JSONCoding.value(undoState())
        data["project"] = try? JSONCoding.value(song.project)
        data["mixer"] = try? JSONCoding.value(mixerState())
        data["tab"] = ["tab": tabValue()]
        data["routing"] = try? JSONCoding.value(routingState())
        data["chat"] = try? JSONCoding.value(chat)
        data["view"] = try? JSONCoding.value(viewState())
        data["trainer"] = try? JSONCoding.value(trainerState())
        return data
    }

    private func full(_ topic: String) -> JSONValue {
        switch topic {
        case "transport": return (try? JSONCoding.value(transport())) ?? .null
        case "record": return (try? JSONCoding.value(record())) ?? .null
        case "tracks": return ["tracks": (try? JSONCoding.value(song.tracks)) ?? []]
        case "markers": return ["markers": (try? JSONCoding.value(song.markers)) ?? []]
        case "takes": return ["takes": (try? JSONCoding.value(recentTakes())) ?? []]
        case "undo": return (try? JSONCoding.value(undoState())) ?? .null
        case "mixer": return (try? JSONCoding.value(mixerState())) ?? .null
        case "tab": return ["tab": tabValue()]
        case "routing": return (try? JSONCoding.value(routingState())) ?? .null
        case "chat": return (try? JSONCoding.value(chat)) ?? .null
        case "view": return (try? JSONCoding.value(viewState())) ?? .null
        case "trainer": return (try? JSONCoding.value(trainerState())) ?? .null
        default: return (try? JSONCoding.value(song.project)) ?? .null
        }
    }

    private func broadcastChanges(from before: [String: JSONValue]) {
        let after = topicData()
        for topic in ["transport", "record", "tracks", "markers", "takes", "undo", "project", "mixer", "tab", "routing", "chat", "view",
                      "trainer"]
        where before[topic] != after[topic] {
            emit(topic, full(topic))
        }
    }

    private func emit(_ topic: String, _ data: JSONValue) {
        for connection in connections.values where connection.authed && connection.topics.contains(topic) {
            connection.seq += 1
            send(["jsonrpc": "2.0", "method": "event",
                  "params": ["topic": .string(topic), "seq": .number(Double(connection.seq)), "t": .number(now()), "data": data]],
                 to: connection)
        }
    }

    private func startTicker() {
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            var tick = 0
            while let self, await self.tickOnce(tick) {
                tick += 1
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    /// Position at 10 a second, meters at 20, while playing or while an input is armed (spec 8.2).
    private func tickOnce(_ tick: Int) -> Bool {
        guard playing || song.tracks.contains(where: \.armed) else { ticker = nil; return false }
        guard playing else {                       // stopped: only the armed inputs' levels
            let level = 0.3 + 0.25 * abs(sin(Double(tick) / 2.5))
            emit("meters", ["levels": .array(song.tracks.filter(\.armed).map {
                ["track_id": .string($0.id), "peak": [.number((level * 1000).rounded() / 1000), .number((level * 900).rounded() / 1000)]]
            })])
            return true
        }
        stepTrainerOnWrap()
        let before = lastSent["counting"]
        let counting: JSONValue = .bool(transport().countingIn)
        if before != counting { lastSent["counting"] = counting; emit("transport", full("transport")) }
        if tick % 2 == 0 {
            let t = transport()
            emit("position", ["state": .string(t.state.rawValue), "position": (try? JSONCoding.value(t.position)) ?? .null])
        }
        let level = 0.35 + 0.3 * abs(sin(Double(tick) / 3.0))
        let levels: [JSONValue] = song.tracks.filter { $0.armed || $0.selected }.map {
            ["track_id": .string($0.id), "peak": [.number((level * 1000).rounded() / 1000), .number((level * 900).rounded() / 1000)]]
        }
        emit("meters", ["levels": .array(levels)])
        let strips = mixerState().strips
        let anySolo = !song.soloed.isEmpty
        var master = 0.0
        let stripLevels: [JSONValue] = strips.enumerated().map { index, strip in
            var peak = 0.0
            if !strip.isMaster {
                let audible = !strip.muted && (!anySolo || strip.soloed || strip.isBus)
                peak = audible ? (0.22 + 0.4 * abs(sin(Double(tick) / 3.0 + Double(index) * 1.7))) * min(1.3, strip.volume / 0.7) : 0
                master = max(master, peak)
            } else {
                peak = master * min(1.3, strip.volume / 0.7)
            }
            let left = (min(1, peak) * 1000).rounded() / 1000
            return ["strip_id": .string(strip.id), "peak": [.number(left), .number((left * 920).rounded() / 1000)]]
        }
        emit("mixer_meters", ["levels": .array(stripLevels)])
        return true
    }
}

extension Duration {
    var seconds: Double {
        let parts = components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}

/// The error table (spec 10), word for word.
public enum DemoErrors {
    static let table: [String: (Int, String)] = [
        "method_not_found": (-32601, "This version of Tabber Studio cannot do that."),
        "invalid_params": (-32602, "The phone sent a request the computer could not use."),
        "internal_error": (-32603, "Something went wrong in Tabber Studio."),
        "unauthenticated": (1001, "Pair this phone with the computer first."),
        "unsupported_version": (1010, "Update Tabber Studio or Tabber Spak so they can talk to each other."),
        "already_recording": (1021, "Tabber Studio is already recording."),
        "unknown_track": (1023, "That track is gone from the song."),
        "unknown_take": (1024, "That take is gone from the song."),
        "unknown_marker": (1025, "That marker is gone from the song."),
        "stale_target": (1026, "This changed on the computer. The phone now shows the new state."),
        "undo_mismatch": (1027, "The computer's newest change is a different one. Undo it there, or try again."),
        "nothing_to_undo": (1028, "There is nothing to undo."),
        "nothing_to_redo": (1029, "There is nothing to redo."),
        "unknown_strip": (1032, "That strip is gone from the mixer."),
        "no_tab": (1033, "Choose a tab track to write on first."),
        "needs_loop": (1039, "Turn Loop on first: the trainer speeds up each time the loop comes round."),
        "track_limit": (1040, "This song has as many tracks as Tabber Studio can play."),
    ]

    static func make(_ reason: String, _ data: [String: JSONValue] = [:]) -> RemoteError {
        let (code, message) = table[reason] ?? (1099, "Tabber Studio could not do that.")
        var fields = data
        fields["reason"] = .string(reason)
        return RemoteError(code: code, message: message, reason: reason, data: .object(fields))
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
