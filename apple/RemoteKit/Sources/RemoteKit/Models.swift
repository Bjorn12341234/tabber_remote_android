import Foundation

// The protocol's shapes (protocol/spec.md, schemas/common.json). Bars and
// beats count from 1. Optional fields that the protocol sends as null are
// encoded as null, so a DemoHost message matches a real host's.

public struct BarBeat: Codable, Sendable, Hashable {
    public var bar: Int
    public var beat: Int
    public init(bar: Int, beat: Int) { self.bar = bar; self.beat = beat }
}

public struct Position: Codable, Sendable, Hashable {
    public var bar: Int
    public var beat: Int
    public var seconds: Double
    public init(bar: Int, beat: Int, seconds: Double) { self.bar = bar; self.beat = beat; self.seconds = seconds }
    public var barBeat: BarBeat { BarBeat(bar: bar, beat: beat) }
}

public enum PlayState: String, Codable, Sendable { case stopped, playing, paused }

public struct TimeSignature: Codable, Sendable, Hashable {
    public var beats: Int
    public var unit: Int
    public init(beats: Int, unit: Int) { self.beats = beats; self.unit = unit }
}

public struct LoopState: Codable, Sendable, Hashable {
    public var enabled: Bool
    public var start: BarBeat?
    public var end: BarBeat?
    public init(enabled: Bool, start: BarBeat?, end: BarBeat?) { self.enabled = enabled; self.start = start; self.end = end }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(start, forKey: .start)
        try c.encode(end, forKey: .end)
    }
}

public struct TransportState: Codable, Sendable, Hashable {
    public var state: PlayState
    public var position: Position
    public var tempoBPM: Double
    public var tempoScale: Double
    public var timeSignature: TimeSignature
    public var loop: LoopState
    public var click: Bool
    public var countInBars: Int
    public var countingIn: Bool

    enum CodingKeys: String, CodingKey {
        case state, position, loop, click
        case tempoBPM = "tempo_bpm", tempoScale = "tempo_scale", timeSignature = "time_signature"
        case countInBars = "count_in_bars", countingIn = "counting_in"
    }

    public init(state: PlayState, position: Position, tempoBPM: Double, tempoScale: Double,
                timeSignature: TimeSignature, loop: LoopState, click: Bool, countInBars: Int, countingIn: Bool) {
        self.state = state; self.position = position; self.tempoBPM = tempoBPM; self.tempoScale = tempoScale
        self.timeSignature = timeSignature; self.loop = loop; self.click = click
        self.countInBars = countInBars; self.countingIn = countingIn
    }
}

public struct RecordStart: Codable, Sendable, Hashable {
    public var position: Position
    public var t: Double
    public init(position: Position, t: Double) { self.position = position; self.t = t }
}

public struct RecordState: Codable, Sendable, Hashable {
    public var recording: Bool
    public var started: RecordStart?
    public var armedTrackIDs: [String]

    enum CodingKeys: String, CodingKey { case recording, started, armedTrackIDs = "armed_track_ids" }

    public init(recording: Bool, started: RecordStart?, armedTrackIDs: [String]) {
        self.recording = recording; self.started = started; self.armedTrackIDs = armedTrackIDs
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(recording, forKey: .recording)
        try c.encode(started, forKey: .started)
        try c.encode(armedTrackIDs, forKey: .armedTrackIDs)
    }
}

public enum TrackKind: String, Codable, Sendable { case audio, midi }

/// What Tabber Studio's "+ Add Track" chooser makes (tracks.add/1): a tab
/// track arrives as a MIDI track with a tuning; a MIDI track has none.
/// What "+ Add Track" makes; `drums` is Tab with Percussion Track ticked (tab.drum/1).
public enum NewTrackKind: String, CaseIterable, Sendable { case tab, midi, audio, drums }
public enum MonitorMode: String, Codable, Sendable { case off, auto, on }

public struct Track: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var kind: TrackKind
    public var armed: Bool
    public var monitor: MonitorMode
    public var selected: Bool
    public var color: String?
    /// The instrument a tab or MIDI track plays ("Acoustic Guitar (steel)"); hosts with tab/1 send it.
    public var instrument: String?
    /// A tab track's open strings as MIDI notes, highest first; nil when it has no tab (tab/1).
    public var tuning: [Int]?
    /// A drum track with drum tab, written with the Drum Map (tab.drum/1); it has no tuning.
    public var drumTab: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, kind, armed, monitor, selected, color, instrument, tuning
        case drumTab = "drum_tab"
    }

    public init(id: String, name: String, kind: TrackKind, armed: Bool, monitor: MonitorMode,
                selected: Bool, color: String?, instrument: String? = nil, tuning: [Int]? = nil, drumTab: Bool? = nil) {
        self.id = id; self.name = name; self.kind = kind; self.armed = armed
        self.monitor = monitor; self.selected = selected; self.color = color
        self.instrument = instrument; self.tuning = tuning; self.drumTab = drumTab
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(name, forKey: .name); try c.encode(kind, forKey: .kind)
        try c.encode(armed, forKey: .armed); try c.encode(monitor, forKey: .monitor)
        try c.encode(selected, forKey: .selected); try c.encode(color, forKey: .color)
        try c.encodeIfPresent(instrument, forKey: .instrument)       // absent from 1.0 hosts, and kept absent
        try c.encodeIfPresent(tuning, forKey: .tuning)
        try c.encodeIfPresent(drumTab, forKey: .drumTab)
    }

    /// A track the phone can write tab on: a tab track, or a drum track's drum tab.
    public var hasTab: Bool { tuning != nil || drumTab == true }
}

public struct Marker: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var bar: Int
    public var beat: Int
    public init(id: String, name: String, bar: Int, beat: Int) { self.id = id; self.name = name; self.bar = bar; self.beat = beat }
}

public struct Take: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var trackID: String
    public var name: String
    public var start: Position
    public var lengthSeconds: Double
    public var rating: Int
    public var active: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, start, rating, active
        case trackID = "track_id", lengthSeconds = "length_seconds"
    }

    public init(id: String, trackID: String, name: String, start: Position, lengthSeconds: Double,
                rating: Int, active: Bool) {
        self.id = id; self.trackID = trackID; self.name = name; self.start = start
        self.lengthSeconds = lengthSeconds; self.rating = rating; self.active = active
    }
}

public struct UndoStep: Codable, Sendable, Hashable {
    public var id: String
    public var label: String
    public init(id: String, label: String) { self.id = id; self.label = label }
}

public struct UndoState: Codable, Sendable, Hashable {
    public var undo: UndoStep?
    public var redo: UndoStep?
    public init(undo: UndoStep?, redo: UndoStep?) { self.undo = undo; self.redo = redo }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(undo, forKey: .undo)
        try c.encode(redo, forKey: .redo)
    }
}

public struct ProjectState: Codable, Sendable, Hashable {
    public var title: String
    public var unsaved: Bool
    public var hasFile: Bool
    enum CodingKeys: String, CodingKey { case title, unsaved, hasFile = "has_file" }
    public init(title: String, unsaved: Bool, hasFile: Bool) { self.title = title; self.unsaved = unsaved; self.hasFile = hasFile }
}

public struct Snapshot: Codable, Sendable, Hashable {
    public var seq: Int
    public var t: Double
    public var project: ProjectState
    public var transport: TransportState
    public var record: RecordState
    public var tracks: [Track]
    public var markers: [Marker]
    public var takes: [Take]
    public var undo: UndoState
}

public struct HostInfo: Codable, Sendable, Hashable {
    public var id: String
    public var name: String
    public var appVersion: String?
    enum CodingKeys: String, CodingKey { case id, name, appVersion = "app_version" }
}

public struct Limits: Codable, Sendable, Hashable {
    public var maxFrameBytes: Int
    public var requestsPerSecond: Int
    public var burst: Int
    public var heartbeatMS: Int
    public var heartbeatMisses: Int
    public var connectionsPerDevice: Int
    enum CodingKeys: String, CodingKey {
        case burst
        case maxFrameBytes = "max_frame_bytes", requestsPerSecond = "requests_per_second"
        case heartbeatMS = "heartbeat_ms", heartbeatMisses = "heartbeat_misses"
        case connectionsPerDevice = "connections_per_device"
    }
}

public struct HelloResult: Codable, Sendable, Hashable {
    public var host: HostInfo
    public var protocolVersion: String
    public var capabilities: [String]
    public var limits: Limits
    public var challenge: String
    enum CodingKeys: String, CodingKey {
        case host, capabilities, limits, challenge
        case protocolVersion = "protocol_version"
    }
}

public struct PairResult: Codable, Sendable, Hashable {
    public var deviceID: String
    public var host: HostInfo
    enum CodingKeys: String, CodingKey { case host, deviceID = "device_id" }
}

public struct AuthResult: Codable, Sendable, Hashable {
    public struct Device: Codable, Sendable, Hashable { public var id: String; public var name: String }
    public var device: Device
}

public struct MeterLevel: Codable, Sendable, Hashable {
    public var trackID: String
    public var peak: [Double]
    enum CodingKeys: String, CodingKey { case peak, trackID = "track_id" }
}

public struct Heartbeat: Codable, Sendable, Hashable {
    public var t: Double
    public var seq: Int
    public var busy: Bool
}

public struct Event: Sendable, Hashable {
    public var topic: String
    public var seq: Int
    public var t: Double
    public var data: JSONValue
}

/// A protocol error: `reason` is the stable code the app acts on.
public struct RemoteError: Error, Sendable, Hashable {
    public var code: Int
    public var message: String
    public var reason: String
    public var data: JSONValue

    public init(code: Int, message: String, reason: String, data: JSONValue = [:]) {
        self.code = code; self.message = message; self.reason = reason; self.data = data
    }

    init?(json: JSONValue) {
        guard let code = json["code"]?.intValue, let message = json["message"]?.stringValue else { return nil }
        self.init(code: code, message: message, reason: json["data"]?["reason"]?.stringValue ?? "",
                  data: json["data"] ?? [:])
    }

    /// What the phone says about this refusal (spec 10). A `host_error` with
    /// a `detail` is Tabber Studio's own reason ("That plug-in is not on the
    /// computer any more. Open the list again."), shown in place of the
    /// general "Tabber Studio could not do that."; a `routing_loop` names
    /// the loop. Anything else is its message.
    public var sentence: String {
        switch reason {
        case "host_error":
            let detail = data["detail"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return detail.isEmpty ? message : Self.withFullStop(detail)
        case "routing_loop":
            let path = data["path"]?.arrayValue?.compactMap(\.stringValue) ?? []
            return path.isEmpty ? message : "\(message) \(path.joined(separator: " → "))."
        default:
            return message
        }
    }

    /// The app's sentences end with a full stop, and some of Studio's reasons
    /// leave it off ("Insert this instrument on a MIDI/score track").
    static func withFullStop(_ text: String) -> String {
        let last = text.reversed().first { !"\"')]\u{201D}\u{2019}".contains($0) }
        return last.map { ".!?…".contains($0) } == true ? text : text + "."
    }
}

/// Where a connection stands, for the badge that is always visible (principle 3).
public enum LinkState: Sendable, Hashable {
    case idle
    case connecting
    case connected(busy: Bool)
    case reconnecting
    case failed(String)
}

/// Why the phone cannot work with its computer, in a form the app turns into
/// a fix-it card (plan: TR6). nil while connected, and while a reconnect is
/// still young.
public enum Trouble: Sendable, Hashable {
    /// Nothing answered at any of the computer's addresses for a while.
    case unreachable
    /// iOS keeps Tabber Spak off the local network (Settings › Tabber Spak).
    case localNetworkDenied
    /// The computer speaks only older protocol versions than this phone.
    case updateStudio(hostVersions: [String])
    /// The computer speaks only newer protocol versions than this phone.
    case updateSpak(hostVersions: [String])
    /// The computer no longer knows this phone (removed in Settings › Remote).
    case forgotten
    /// A different computer answers at the remembered address.
    case otherComputer

    /// Which side must update, from the versions the computer speaks (spec 7).
    public static func versions(_ hostVersions: [String], phone: [String] = RemoteClient.protocolVersions) -> Trouble {
        func major(_ version: String) -> Int { Int(version.split(separator: ".").first ?? "") ?? 0 }
        let hostNewest = hostVersions.map(major).max() ?? 0
        let phoneNewest = phone.map(major).max() ?? 0
        return hostNewest > phoneNewest ? .updateSpak(hostVersions: hostVersions) : .updateStudio(hostVersions: hostVersions)
    }
}
