package com.tabberspak.remotekit

// The protocol's shapes (protocol/spec.md, schemas/common.json), as apple/RemoteKit/Models.swift.
// Bars and beats count from 1. Optional fields that the protocol sends as null are written as
// null, and the ones older hosts leave out stay out, so every message round-trips exactly.

private fun unknown(path: String, what: String, value: String): Nothing =
    throw JsonShapeException("$path: unknown $what \"$value\"")

data class BarBeat(val bar: Int, val beat: Int) {
    fun toJson(): Json = jsonObject { put("bar", bar); put("beat", beat) }

    companion object {
        fun from(r: JsonReader) = BarBeat(r.int("bar"), r.int("beat"))
    }
}

data class Position(val bar: Int, val beat: Int, val seconds: Double) {
    val barBeat: BarBeat get() = BarBeat(bar, beat)

    fun toJson(): Json = jsonObject { put("bar", bar); put("beat", beat); put("seconds", seconds) }

    companion object {
        fun from(r: JsonReader) = Position(r.int("bar"), r.int("beat"), r.double("seconds"))
    }
}

enum class PlayState(val wire: String) {
    STOPPED("stopped"), PLAYING("playing"), PAUSED("paused");

    companion object {
        fun from(text: String, path: String) = entries.firstOrNull { it.wire == text } ?: unknown(path, "state", text)
    }
}

data class TimeSignature(val beats: Int, val unit: Int) {
    fun toJson(): Json = jsonObject { put("beats", beats); put("unit", unit) }

    companion object {
        fun from(r: JsonReader) = TimeSignature(r.int("beats"), r.int("unit"))
    }
}

data class LoopState(val enabled: Boolean, val start: BarBeat?, val end: BarBeat?) {
    fun toJson(): Json = jsonObject {
        put("enabled", enabled)
        putNullable("start", start?.toJson())
        putNullable("end", end?.toJson())
    }

    companion object {
        fun from(r: JsonReader) = LoopState(r.bool("enabled"), r.objOrNull("start", BarBeat::from), r.objOrNull("end", BarBeat::from))
    }
}

data class TransportState(
    val state: PlayState,
    val position: Position,
    val tempoBpm: Double,
    val tempoScale: Double,
    val timeSignature: TimeSignature,
    val loop: LoopState,
    val click: Boolean,
    val countInBars: Int,
    val countingIn: Boolean,
) {
    fun toJson(): Json = jsonObject {
        put("state", state.wire)
        put("position", position.toJson())
        put("tempo_bpm", tempoBpm)
        put("tempo_scale", tempoScale)
        put("time_signature", timeSignature.toJson())
        put("loop", loop.toJson())
        put("click", click)
        put("count_in_bars", countInBars)
        put("counting_in", countingIn)
    }

    companion object {
        fun from(r: JsonReader) = TransportState(
            state = PlayState.from(r.string("state"), "transport.state"),
            position = r.obj("position", Position::from),
            tempoBpm = r.double("tempo_bpm"),
            tempoScale = r.double("tempo_scale"),
            timeSignature = r.obj("time_signature", TimeSignature::from),
            loop = r.obj("loop", LoopState::from),
            click = r.bool("click"),
            countInBars = r.int("count_in_bars"),
            countingIn = r.bool("counting_in"),
        )
    }
}

data class RecordStart(val position: Position, val t: Double) {
    fun toJson(): Json = jsonObject { put("position", position.toJson()); put("t", t) }

    companion object {
        fun from(r: JsonReader) = RecordStart(r.obj("position", Position::from), r.double("t"))
    }
}

data class RecordState(val recording: Boolean, val started: RecordStart?, val armedTrackIds: List<String>) {
    fun toJson(): Json = jsonObject {
        put("recording", recording)
        putNullable("started", started?.toJson())
        put("armed_track_ids", Json.strings(armedTrackIds))
    }

    companion object {
        fun from(r: JsonReader) = RecordState(r.bool("recording"), r.objOrNull("started", RecordStart::from), r.strings("armed_track_ids"))
    }
}

enum class TrackKind(val wire: String) {
    AUDIO("audio"), MIDI("midi");

    companion object {
        fun from(text: String, path: String) = entries.firstOrNull { it.wire == text } ?: unknown(path, "kind", text)
    }
}

/** What Tabber Studio's "+ Add Track" chooser makes (tracks.add/1). */
enum class NewTrackKind(val wire: String) { TAB("tab"), MIDI("midi"), AUDIO("audio") }

enum class MonitorMode(val wire: String) {
    OFF("off"), AUTO("auto"), ON("on");

    companion object {
        fun from(text: String, path: String) = entries.firstOrNull { it.wire == text } ?: unknown(path, "monitor", text)
    }
}

data class Track(
    val id: String,
    val name: String,
    val kind: TrackKind,
    val armed: Boolean,
    val monitor: MonitorMode,
    val selected: Boolean,
    val color: String?,
    /** The instrument a tab or MIDI track plays; hosts with tab/1 send it. */
    val instrument: String? = null,
    /** A tab track's open strings as MIDI notes, highest first; null when it has no tab (tab/1). */
    val tuning: List<Int>? = null,
) {
    /** A track the phone can write tab on. */
    val hasTab: Boolean get() = tuning != null

    fun toJson(): Json = jsonObject {
        put("id", id); put("name", name); put("kind", kind.wire)
        put("armed", armed); put("monitor", monitor.wire)
        put("selected", selected); putNullable("color", color)
        putIfPresent("instrument", instrument) // absent from 1.0 hosts, and kept absent
        putIfPresent("tuning", tuning?.let(Json::ints))
    }

    companion object {
        fun from(r: JsonReader) = Track(
            id = r.string("id"),
            name = r.string("name"),
            kind = TrackKind.from(r.string("kind"), "track.kind"),
            armed = r.bool("armed"),
            monitor = MonitorMode.from(r.string("monitor"), "track.monitor"),
            selected = r.bool("selected"),
            color = r.stringOrNull("color"),
            instrument = r.stringOrNull("instrument"),
            tuning = r.intsOrNull("tuning"),
        )
    }
}

data class Marker(val id: String, val name: String, val bar: Int, val beat: Int) {
    fun toJson(): Json = jsonObject { put("id", id); put("name", name); put("bar", bar); put("beat", beat) }

    companion object {
        fun from(r: JsonReader) = Marker(r.string("id"), r.string("name"), r.int("bar"), r.int("beat"))
    }
}

data class Take(
    val id: String,
    val trackId: String,
    val name: String,
    val start: Position,
    val lengthSeconds: Double,
    val rating: Int,
    val active: Boolean,
) {
    fun toJson(): Json = jsonObject {
        put("id", id); put("track_id", trackId); put("name", name)
        put("start", start.toJson()); put("length_seconds", lengthSeconds)
        put("rating", rating); put("active", active)
    }

    companion object {
        fun from(r: JsonReader) = Take(
            r.string("id"), r.string("track_id"), r.string("name"), r.obj("start", Position::from),
            r.double("length_seconds"), r.int("rating"), r.bool("active"),
        )
    }
}

data class UndoStep(val id: String, val label: String) {
    fun toJson(): Json = jsonObject { put("id", id); put("label", label) }

    companion object {
        fun from(r: JsonReader) = UndoStep(r.string("id"), r.string("label"))
    }
}

data class UndoState(val undo: UndoStep?, val redo: UndoStep?) {
    fun toJson(): Json = jsonObject { putNullable("undo", undo?.toJson()); putNullable("redo", redo?.toJson()) }

    companion object {
        fun from(r: JsonReader) = UndoState(r.objOrNull("undo", UndoStep::from), r.objOrNull("redo", UndoStep::from))
    }
}

data class ProjectState(val title: String, val unsaved: Boolean, val hasFile: Boolean) {
    fun toJson(): Json = jsonObject { put("title", title); put("unsaved", unsaved); put("has_file", hasFile) }

    companion object {
        fun from(r: JsonReader) = ProjectState(r.string("title"), r.bool("unsaved"), r.bool("has_file"))
    }
}

data class Snapshot(
    val seq: Int,
    val t: Double,
    val project: ProjectState,
    val transport: TransportState,
    val record: RecordState,
    val tracks: List<Track>,
    val markers: List<Marker>,
    val takes: List<Take>,
    val undo: UndoState,
) {
    fun toJson(): Json = jsonObject {
        put("seq", seq); put("t", t)
        put("project", project.toJson()); put("transport", transport.toJson()); put("record", record.toJson())
        put("tracks", Json.of(tracks.map(Track::toJson)))
        put("markers", Json.of(markers.map(Marker::toJson)))
        put("takes", Json.of(takes.map(Take::toJson)))
        put("undo", undo.toJson())
    }

    companion object {
        fun from(r: JsonReader) = Snapshot(
            seq = r.int("seq"),
            t = r.double("t"),
            project = r.obj("project", ProjectState::from),
            transport = r.obj("transport", TransportState::from),
            record = r.obj("record", RecordState::from),
            tracks = r.list("tracks", Track::from),
            markers = r.list("markers", Marker::from),
            takes = r.list("takes", Take::from),
            undo = r.obj("undo", UndoState::from),
        )
    }
}

data class HostInfo(val id: String, val name: String, val appVersion: String?) {
    fun toJson(): Json = jsonObject { put("id", id); put("name", name); putIfPresent("app_version", appVersion) }

    companion object {
        fun from(r: JsonReader) = HostInfo(r.string("id"), r.string("name"), r.stringOrNull("app_version"))
    }
}

data class Limits(
    val maxFrameBytes: Int,
    val requestsPerSecond: Int,
    val burst: Int,
    val heartbeatMs: Int,
    val heartbeatMisses: Int,
    val connectionsPerDevice: Int,
) {
    fun toJson(): Json = jsonObject {
        put("max_frame_bytes", maxFrameBytes); put("requests_per_second", requestsPerSecond); put("burst", burst)
        put("heartbeat_ms", heartbeatMs); put("heartbeat_misses", heartbeatMisses)
        put("connections_per_device", connectionsPerDevice)
    }

    companion object {
        fun from(r: JsonReader) = Limits(
            r.int("max_frame_bytes"), r.int("requests_per_second"), r.int("burst"),
            r.int("heartbeat_ms"), r.int("heartbeat_misses"), r.int("connections_per_device"),
        )
    }
}

data class HelloResult(
    val host: HostInfo,
    val protocolVersion: String,
    val capabilities: List<String>,
    val limits: Limits,
    val challenge: String,
) {
    fun toJson(): Json = jsonObject {
        put("host", host.toJson()); put("protocol_version", protocolVersion)
        put("capabilities", Json.strings(capabilities)); put("limits", limits.toJson()); put("challenge", challenge)
    }

    companion object {
        fun from(r: JsonReader) = HelloResult(
            r.obj("host", HostInfo::from), r.string("protocol_version"), r.strings("capabilities"),
            r.obj("limits", Limits::from), r.string("challenge"),
        )
    }
}

data class PairResult(val deviceId: String, val host: HostInfo) {
    fun toJson(): Json = jsonObject { put("device_id", deviceId); put("host", host.toJson()) }

    companion object {
        fun from(r: JsonReader) = PairResult(r.string("device_id"), r.obj("host", HostInfo::from))
    }
}

data class AuthResult(val device: Device) {
    data class Device(val id: String, val name: String)

    fun toJson(): Json = jsonObject { put("device", jsonObject { put("id", device.id); put("name", device.name) }) }

    companion object {
        fun from(r: JsonReader) = AuthResult(r.obj("device") { Device(it.string("id"), it.string("name")) })
    }
}

data class MeterLevel(val trackId: String, val peak: List<Double>) {
    fun toJson(): Json = jsonObject { put("track_id", trackId); put("peak", Json.doubles(peak)) }

    companion object {
        fun from(r: JsonReader) = MeterLevel(r.string("track_id"), r.doubles("peak"))
    }
}

data class Heartbeat(val t: Double, val seq: Int, val busy: Boolean) {
    fun toJson(): Json = jsonObject { put("t", t); put("seq", seq); put("busy", busy) }

    companion object {
        fun from(r: JsonReader) = Heartbeat(r.double("t"), r.int("seq"), r.bool("busy"))
    }
}

data class Event(val topic: String, val seq: Int, val t: Double, val data: Json)

/** A protocol error: [reason] is the stable code the app acts on, [message] a sentence a musician reads. */
class RemoteError(val code: Int, override val message: String, val reason: String, val data: Json = Json.Obj(emptyMap())) :
    Exception(message) {
    companion object {
        fun from(json: Json): RemoteError? {
            val code = json["code"]?.int ?: return null
            val message = json["message"]?.string ?: return null
            return RemoteError(code, message, json["data"]?.get("reason")?.string ?: "", json["data"] ?: Json.Obj(emptyMap()))
        }
    }
}

/** Where a connection stands, for the badge that is always visible (principle 3). */
sealed interface LinkState {
    data object Idle : LinkState
    data object Connecting : LinkState
    data class Connected(val busy: Boolean) : LinkState
    data object Reconnecting : LinkState
    data class Failed(val why: String) : LinkState
}
