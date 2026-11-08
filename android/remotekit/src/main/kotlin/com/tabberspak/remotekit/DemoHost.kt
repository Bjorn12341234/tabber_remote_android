package com.tabberspak.remotekit

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.security.SecureRandom
import java.text.BreakIterator
import kotlin.math.abs
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sign
import kotlin.math.sin
import kotlin.math.truncate

/**
 * A simulated Tabber Studio in the app, speaking the protocol over memory, as
 * apple/RemoteKit/DemoHost.swift.
 *
 * The app runs it in demo mode (store review, screenshots, the stage fallback) and every screen's
 * tests run against it. It keeps a real session: a moving playhead, count-in, recording that makes
 * takes, discard and undo with step ids, markers, idempotency keys and events. It does no TLS and
 * accepts any device: it is a demo, never a host on the network.
 *
 * As the Swift actor, its state is touched on one thread only: every request, event and tick runs
 * on [confined].
 *
 * @param speaks the protocol versions this computer speaks: another major version shows the app's
 *   Update cards (TR6).
 * @param computerName the name the demo computer gives itself; a longer one checks how the app's
 *   bars fit a real computer's name.
 * @param onlyAudio starts with a song of only audio tracks, as one made from audio files is: no tab
 *   to write on until a tab track is added.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class DemoHost(
    val speaks: List<String> = RemoteClient.PROTOCOL_VERSIONS,
    val computerName: String = NAME,
    onlyAudio: Boolean = false,
) {
    private class Step(val id: String, val label: String, val before: Song, val after: Song)

    private data class Song(
        val tracks: List<Track>,
        val markers: List<Marker>,
        val takes: List<Take>,
        val project: ProjectState,
        /** Undo steps in Tabber Studio: mute, solo and tab notes. Volume and pan are not. */
        val muted: Set<String> = emptySet(),
        val soloed: Set<String> = emptySet(),
        val tabs: Map<String, DemoTab> = emptyMap(),
        /**
         * Routing, as Tabber Studio's Routing panel edits it: outputs and which sends exist are undo
         * steps; a send's level and Pre-fader are not. Source strip id to bus strip id; absent is
         * the master.
         */
        val outputs: Map<String, String> = emptyMap(),
        /** "track>bus". */
        val sends: Set<String> = emptySet(),
    )

    private class Connection(val transport: MemoryTransport) {
        val topics = mutableSetOf<String>()
        var seq = 0
        var authed = false
        var challenge = ByteArray(0)
        /** Gone quiet without a close, as a suspended app's socket does. */
        var silent = false
    }

    private data class Fader(val volume: Double, val pan: Double)
    private data class Bus(val id: String, val name: String)
    private data class SendValue(val level: Double, val pre: Boolean)
    private data class RecordingStart(val position: Position, val at: Long, val track: String)
    private data class ChatAction(val planId: String, val track: String, val solo: Boolean)

    private val confined = Dispatchers.Default.limitedParallelism(1)
    private val scope = CoroutineScope(SupervisorJob() + confined)
    private val random = SecureRandom()

    // Session state. Instants are System.nanoTime().
    private var song: Song
    private val gone = HashMap<String, Take>()
    private val undo = ArrayList<Step>()
    private var undoIndex = 0
    private val tempo = 96.0
    private var scale = 1.0
    private var click = false
    private var countIn = 0
    private var loop = LoopState(enabled = false, start = null, end = null)
    private var playing = false
    /** Where the playhead was at [anchorTime]. */
    private var anchorBeat = 0.0
    private var anchorTime = System.nanoTime()
    private var recordingStart: RecordingStart? = null
    private var takeCounter = 0
    private var stepCounter = 40
    private var markerCounter = 0
    private val answers = HashMap<String, Json>()
    private val connections = LinkedHashSet<Connection>()
    private var ticker: Job? = null
    private val lastSent = HashMap<String, Json>()
    private val epoch = System.nanoTime()
    /** Fader travel and pan for every strip: direct writes, as in Tabber Studio. */
    private val faders = HashMap<String, Fader>()
    private val buses = mutableListOf(Bus("demo-bus-reverb", "Reverb"))
    private var busCounter = 0
    /** Each send's level and Pre-fader: direct writes, as the mixer's send controls. */
    private val sendLevels = HashMap<String, SendValue>()
    /** The chat (chat/1), answered by a few scripted words in place of the AI. */
    private var chat = ChatState(available = true, state = "idle", messages = emptyList(), plan = null)
    private var chatCounter = 0
    private var chatRequest = ""
    private var chatAction: ChatAction? = null
    /** What the demo computer shows (view/1), and the editor Split goes back to. */
    private var view = ViewState(editor = "tab", split = false)
    /** How each MIDI track shows in the Tab editor once its "MIDI part" card was answered: "midi_tab" or "notation" (view.part/1). */
    private val partShows = HashMap<String, String>()
    /** Tracks that cannot show MIDI tab, as drums cannot in Tabber Studio. */
    private val drums = setOf("demo-drums")
    private var preSplit = "tab"
    /** The Speed Trainer (trainer/1); its speed is the demo's tempo scale. */
    private var trainer = TrainerState()
    /** Where the last tick was, to see the loop come round. */
    private var lastBeat = 0.0
    /** The Tab view's cursor on each tab track, and the duration a new note gets. */
    private val tabCursors = HashMap<String, TabCursor>()
    private var tabDuration = NoteValue(4)
    private var tabRevision = 1
    private var trackCounter = 0

    private var dropBeforeNextAnswer = false
    private var startedRecordings = 0
    private var madeConnections = 0

    init {
        // Tabber Studio's own track colours (core/models.py TRACK_COLORS), in its strip order.
        song = Song(
            tracks = listOf(
                Track("demo-guitar", "Guitar", TrackKind.MIDI, armed = false, monitor = MonitorMode.AUTO, selected = true,
                    color = "#50A0DC", instrument = "Acoustic Guitar (steel)", tuning = DemoTab.STANDARD),
                Track("demo-bass", "Bass", TrackKind.MIDI, armed = false, monitor = MonitorMode.AUTO, selected = false,
                    color = "#64BE64", instrument = "Electric Bass (finger)", tuning = DemoTab.BASS),
                Track("demo-drums", "Drums", TrackKind.MIDI, armed = false, monitor = MonitorMode.AUTO, selected = false,
                    color = "#DCAA3C", instrument = "Standard Kit"),
                Track("demo-lead", "Lead guitar", TrackKind.AUDIO, armed = false, monitor = MonitorMode.AUTO, selected = false,
                    color = "#AA64D2"),
                Track("demo-vocals", "Vocals", TrackKind.AUDIO, armed = false, monitor = MonitorMode.AUTO, selected = false,
                    color = "#DC5050"),
            ),
            markers = listOf(
                Marker("demo-intro", "Intro", 1, 1),
                Marker("demo-verse", "Verse", 9, 1),
                Marker("demo-chorus", "Chorus", 25, 1),
                Marker("demo-solo", "Solo", 41, 1),
            ),
            takes = emptyList(),
            project = ProjectState(title = "Demo Song", unsaved = false, hasFile = true),
            tabs = mapOf("demo-guitar" to DemoTab.demoGuitar(), "demo-bass" to DemoTab.demoBass()),
            sends = setOf("demo-lead>demo-bus-reverb", "demo-vocals>demo-bus-reverb"),
        )
        sendLevels["demo-lead>demo-bus-reverb"] = SendValue(0.25, false)
        sendLevels["demo-vocals>demo-bus-reverb"] = SendValue(0.5, false)
        faders["demo-guitar"] = Fader(0.7, -0.3)
        faders["demo-bass"] = Fader(0.62, 0.0)
        faders["demo-drums"] = Fader(0.66, 0.0)
        faders["demo-lead"] = Fader(0.7, 0.32)
        faders["demo-vocals"] = Fader(0.74, 0.0)
        faders["demo-bus-reverb"] = Fader(0.52, 0.0)
        faders["master"] = Fader(0.7, 0.0)
        if (onlyAudio) {
            val audio = song.tracks.filter { it.kind != TrackKind.MIDI }
            song = song.copy(
                tracks = audio.mapIndexed { index, track -> if (index == 0) track.copy(selected = true) else track },
                tabs = emptyMap(),
            )
        }
    }

    /** Tests: drop the connection after doing the next request, before answering. */
    suspend fun setDropBeforeNextAnswer(value: Boolean) = withContext(confined) { dropBeforeNextAnswer = value }

    /** Recordings started so far, by Record or Go Again. */
    suspend fun recordingsStarted(): Int = withContext(confined) { startedRecordings }

    /** Connections made so far, open or not. */
    suspend fun connectionsMade(): Int = withContext(confined) { madeConnections }

    /**
     * Tests: every open connection goes quiet without closing (no answers, no heartbeats), as when
     * the phone was away; new connections work.
     */
    suspend fun goSilent() = withContext(confined) { for (connection in connections) connection.silent = true }

    /** A new connection; the phone uses the returned end. */
    suspend fun connect(): MemoryTransport = withContext(confined) {
        val (phone, host) = MemoryTransport.pair()
        val connection = Connection(host)
        connections.add(connection)
        madeConnections += 1
        scope.launch { serve(connection) }
        scope.launch { heartbeats(connection) }
        phone
    }

    /**
     * Ends the demo for good: serving, heartbeats, the playhead and the chat stop. Swift's DemoHost
     * stops once the app lets go of it; on the JVM its running tasks would keep it going.
     */
    fun close() = scope.cancel()

    private suspend fun serve(connection: Connection) {
        try {
            while (true) {
                val text = try {
                    connection.transport.receive()
                } catch (failure: CancellationException) {
                    throw failure
                } catch (_: Exception) {
                    null
                } ?: break
                handle(text, connection)
            }
        } finally {
            connections.remove(connection)
        }
    }

    private suspend fun heartbeats(connection: Connection) {
        while (connection in connections) {
            delay(2000)
            if (connection !in connections) return
            send(jsonObject {
                put("jsonrpc", "2.0"); put("method", "heartbeat")
                put("params", jsonObject { put("t", now()); put("seq", connection.seq); put("busy", false) })
            }, connection)
        }
    }

    private fun now(): Double = (System.nanoTime() - epoch) / 1e9 + 1000.0

    private fun send(message: Json, connection: Connection) {
        if (connection.silent) return
        val text = runCatching { message.encode() }.getOrNull() ?: return
        connection.transport.sendNow(text)
    }

    // Requests

    private fun handle(text: String, connection: Connection) {
        val message = runCatching { Json.parse(text) }.getOrNull() ?: return
        val id = message["id"] ?: return
        val method = message["method"]?.string ?: return
        val params = message["params"] ?: Json.Obj(emptyMap())
        val before = topicData()
        val answer: Json = try {
            val result = run(method, params, connection)
            jsonObject { put("jsonrpc", "2.0"); put("id", id); put("result", result) }
        } catch (failure: RemoteError) {
            jsonObject {
                put("jsonrpc", "2.0"); put("id", id)
                put("error", jsonObject { put("code", failure.code); put("message", failure.message); put("data", failure.data) })
            }
        } catch (_: Exception) {
            errorAnswer(id, "internal_error")
        }
        if (dropBeforeNextAnswer) {
            dropBeforeNextAnswer = false
            connection.transport.drop()
            connections.remove(connection)
        } else {
            send(answer, connection)
        }
        if (answer["error"]?.get("data")?.get("reason")?.string == "unsupported_version") {
            connection.transport.close(4002) // as a real host does (vector version_mismatch)
            connections.remove(connection)
            return
        }
        broadcastChanges(before)
    }

    private fun errorAnswer(id: Json, reason: String): Json {
        val failure = DemoErrors.make(reason)
        return jsonObject {
            put("jsonrpc", "2.0"); put("id", id)
            put("error", jsonObject { put("code", failure.code); put("message", failure.message); put("data", failure.data) })
        }
    }

    private fun run(method: String, p: Json, connection: Connection): Json {
        when (method) {
            "hello" -> {
                val offered = p["protocol_versions"]?.array?.mapNotNull { it.string } ?: emptyList()
                // Swift's split(separator:) leaves out empty pieces.
                fun major(version: String) = version.split('.').firstOrNull { it.isNotEmpty() } ?: ""
                if (offered.none { o -> speaks.any { major(it) == major(o) } }) {
                    throw DemoErrors.make("unsupported_version", mapOf("host_versions" to Json.strings(speaks)))
                }
                connection.challenge = ByteArray(32).also(random::nextBytes)
                return jsonObject {
                    put("host", jsonObject { put("id", HOST_ID); put("name", computerName); put("app_version", "demo") })
                    put("protocol_version", "1.9")
                    put("capabilities", Json.strings(CAPABILITIES))
                    put("limits", jsonObject {
                        put("max_frame_bytes", 65536); put("requests_per_second", 20); put("burst", 40)
                        put("heartbeat_ms", 2000); put("heartbeat_misses", 3); put("connections_per_device", 2)
                    })
                    put("challenge", Base64Url.encode(connection.challenge))
                }
            }
            "pair" -> {
                val der = p["device"]?.get("key")?.string?.let(Base64Url::decode)
                    ?: throw DemoErrors.make("invalid_params", mapOf("field" to Json.Str("device")))
                connection.authed = true
                return jsonObject {
                    put("device_id", RemoteCrypto.deviceId(der))
                    put("host", jsonObject { put("id", HOST_ID); put("name", computerName) })
                }
            }
            "auth" -> {
                connection.authed = true
                return jsonObject {
                    put("device", jsonObject { put("id", p["device_id"] ?: Json.Str("")); put("name", "Demo phone") })
                }
            }
        }
        if (!connection.authed) throw DemoErrors.make("unauthenticated")
        val key = p["key"]?.string ?: return verb(method, p, connection)
        answers[key]?.let { return it }
        val value = verb(method, p, connection)
        answers[key] = value
        return value
    }

    private fun verb(method: String, p: Json, connection: Connection): Json = when (method) {
        "session.subscribe" -> {
            for (topic in p["topics"]?.array ?: emptyList()) topic.string?.let { connection.topics.add(it) }
            snapshot(connection.seq)
        }
        "session.unsubscribe" -> {
            for (topic in p["topics"]?.array ?: emptyList()) topic.string?.let { connection.topics.remove(it) }
            jsonObject { put("topics", Json.strings(connection.topics.sorted())) }
        }
        "session.snapshot" -> snapshot(connection.seq)
        "transport.play" -> {
            val from = p["from"]
            val bar = from?.get("bar")?.int
            val beat = from?.get("beat")?.int
            anchorBeat = if (bar != null && beat != null) beatAt(bar, beat) else currentBeat()
            anchorTime = System.nanoTime()
            playing = true
            startTicker()
            jsonObject { put("transport", transport().toJson()) }
        }
        "transport.stop" -> {
            val take = stopEverything()
            jsonObject {
                put("transport", transport().toJson()); put("record", record().toJson())
                putNullable("take", take?.toJson())
            }
        }
        "transport.record" -> {
            val wanted = (p["armed_track_ids"]?.array ?: emptyList()).mapNotNull { it.string }.toSet()
            if (recordingStart != null) throw DemoErrors.make("already_recording", mapOf("record" to record().toJson()))
            if (wanted != song.tracks.filter { it.armed }.map { it.id }.toSet() || wanted.isEmpty()) {
                throw DemoErrors.make("stale_target", mapOf("tracks" to tracksJson(), "record" to record().toJson()))
            }
            p["count_in_bars"]?.int?.let { countIn = it }
            startRecording(song.tracks.first { it.armed }.id, if (playing) currentBeat() else anchorBeat)
            jsonObject { put("transport", transport().toJson()); put("record", record().toJson()) }
        }
        "transport.seek" -> {
            val bar = p["to"]?.get("bar")?.int
            val beat = p["to"]?.get("beat")?.int
            if (bar == null || beat == null) throw DemoErrors.make("invalid_params", mapOf("field" to Json.Str("to")))
            anchorBeat = beatAt(bar, beat)
            anchorTime = System.nanoTime()
            jsonObject { put("transport", transport().toJson()) }
        }
        "transport.set_loop" -> {
            val enabled = p["enabled"]?.bool ?: false
            val start = p["start"]
            val end = p["end"]
            loop = if (start != null && end != null) {
                LoopState(enabled, BarBeat.from(JsonReader(start, "start")), BarBeat.from(JsonReader(end, "end")))
            } else {
                loop.copy(enabled = enabled)
            }
            if (!enabled) { // as a click on Loop: the trainer goes off
                anchorBeat = currentBeat(); anchorTime = System.nanoTime()
                trainer = trainer.copy(enabled = false)
                scale = 1.0
            }
            jsonObject { put("transport", transport().toJson()) }
        }
        "transport.set_click" -> {
            click = p["enabled"]?.bool ?: false
            jsonObject { put("transport", transport().toJson()) }
        }
        "transport.set_count_in" -> {
            countIn = (p["bars"]?.int ?: 0).coerceIn(0, 2)
            jsonObject { put("transport", transport().toJson()) }
        }
        "transport.set_tempo_scale" -> {
            anchorBeat = currentBeat(); anchorTime = System.nanoTime()
            scale = (p["scale"]?.double ?: 1.0).coerceIn(0.25, 2.0)
            jsonObject { put("transport", transport().toJson()) }
        }
        "tracks.arm" -> {
            val index = trackIndex(p)
            val armed = p["armed"]?.bool ?: false
            song = song.copy(tracks = song.tracks.mapIndexed { i, track -> if (i == index) track.copy(armed = armed) else track })
            if (armed) startTicker() // an armed input shows its level at once
            jsonObject { put("tracks", tracksJson()) }
        }
        "tracks.select" -> {
            val id = p["track_id"]?.string ?: ""
            if (song.tracks.none { it.id == id }) throw DemoErrors.make("unknown_track", mapOf("tracks" to tracksJson()))
            song = song.copy(tracks = song.tracks.map { it.copy(selected = it.id == id) })
            jsonObject { put("tracks", tracksJson()) }
        }
        "tracks.set_monitor" -> {
            val index = trackIndex(p)
            val wire = p["mode"]?.string ?: "auto"
            val mode = MonitorMode.entries.firstOrNull { it.wire == wire } ?: MonitorMode.AUTO
            song = song.copy(tracks = song.tracks.mapIndexed { i, track -> if (i == index) track.copy(monitor = mode) else track })
            jsonObject { put("tracks", tracksJson()) }
        }
        "tracks.add" -> {
            val wire = p["kind"]?.string
            val kind = NewTrackKind.entries.firstOrNull { it.wire == wire }
                ?: throw DemoErrors.make("invalid_params", mapOf("field" to Json.Str("kind")))
            // A new track clears the record arms in Tabber Studio, which would end the take.
            if (recordingStart != null) throw DemoErrors.make("already_recording", mapOf("record" to record().toJson()))
            val track = addTrack(kind)
            jsonObject { put("track", track.toJson()); put("tracks", tracksJson()); put("undo", undoState().toJson()) }
        }
        "markers.go", "markers.loop" -> {
            val id = p["marker_id"]?.string ?: ""
            val marker = song.markers.firstOrNull { it.id == id }
                ?: throw DemoErrors.make("unknown_marker", mapOf("markers" to markersJson()))
            if (method == "markers.go") {
                anchorBeat = beatAt(marker.bar, marker.beat)
                anchorTime = System.nanoTime()
            } else {
                val next = song.markers.map { it.bar }.filter { it > marker.bar }.minOrNull() ?: (marker.bar + 8)
                loop = LoopState(enabled = true, start = BarBeat(marker.bar, marker.beat), end = BarBeat(next, 1))
            }
            jsonObject { put("transport", transport().toJson()) }
        }
        "markers.add" -> {
            val bar = p["at"]?.get("bar")?.int
            val beat = p["at"]?.get("beat")?.int
            if (bar == null || beat == null) throw DemoErrors.make("invalid_params", mapOf("field" to Json.Str("at")))
            markerCounter += 1
            val marker = Marker("demo-flag-$markerCounter", p["name"]?.string ?: "Flag", bar, beat)
            edit("Add marker '${marker.name}'") { s ->
                s.copy(markers = (s.markers + marker).sortedWith(compareBy<Marker>({ it.bar }, { it.beat })))
            }
            jsonObject { put("marker", marker.toJson()); put("markers", markersJson()) }
        }
        "takes.list" -> {
            val id = p["track_id"]?.string ?: ""
            jsonObject { put("takes", takesJson(heard(song.takes.filter { it.trackId == id }))) }
        }
        "takes.discard" -> {
            val id = p["take_id"]?.string ?: ""
            val take = song.takes.firstOrNull { it.id == id }
                ?: throw DemoErrors.make("unknown_take", mapOf("takes" to takesJson(recentTakes())))
            gone[id] = take
            edit("Discard take") { s -> s.copy(takes = s.takes.filter { it.id != id }) }
            jsonObject { put("takes", takesJson(recentTakes())); put("undo", undoState().toJson()) }
        }
        "takes.go_again" -> {
            val id = p["take_id"]?.string ?: ""
            val take = song.takes.firstOrNull { it.id == id } ?: gone[id]
                ?: throw DemoErrors.make("unknown_take", mapOf("takes" to takesJson(recentTakes())))
            stopEverything()
            song = song.copy(tracks = song.tracks.map { if (it.id == take.trackId) it.copy(armed = true) else it })
            startRecording(take.trackId, beatAt(take.start.bar, take.start.beat))
            jsonObject { put("transport", transport().toJson()); put("record", record().toJson()) }
        }
        "takes.rate" -> {
            val id = p["take_id"]?.string ?: ""
            if (song.takes.none { it.id == id }) {
                throw DemoErrors.make("unknown_take", mapOf("takes" to takesJson(recentTakes())))
            }
            val rating = (p["rating"]?.int ?: 0).coerceIn(0, 5)
            edit("Rate take") { s -> s.copy(takes = s.takes.map { if (it.id == id) it.copy(rating = rating) else it }) }
            jsonObject { put("take", heard(song.takes.filter { it.id == id })[0].toJson()) }
        }
        "edit.undo", "edit.redo" -> {
            val redo = method == "edit.redo"
            val expect = p["expect"]?.string ?: ""
            val index = if (redo) undoIndex else undoIndex - 1
            if (index !in undo.indices) {
                throw DemoErrors.make(if (redo) "nothing_to_redo" else "nothing_to_undo", mapOf("undo" to undoState().toJson()))
            }
            if (undo[index].id != expect) throw DemoErrors.make("undo_mismatch", mapOf("undo" to undoState().toJson()))
            song = if (redo) undo[index].after else undo[index].before
            undoIndex = if (redo) undoIndex + 1 else undoIndex - 1
            tabRevision += 1
            jsonObject { put("undo", undoState().toJson()) }
        }
        "project.save" -> {
            song = song.copy(project = song.project.copy(unsaved = false))
            jsonObject { put("project", song.project.toJson()) }
        }
        "mixer.state" -> jsonObject { put("mixer", mixerState().toJson()) }
        "mixer.set_volume", "mixer.set_pan" -> {
            val id = p["strip_id"]?.string ?: ""
            val fader = faders[id] ?: throw DemoErrors.make("unknown_strip", mapOf("mixer" to mixerState().toJson()))
            val field = if (method == "mixer.set_volume") "volume" else "pan"
            val value = p[field]?.double ?: throw DemoErrors.make("invalid_params", mapOf("field" to Json.Str(field)))
            faders[id] = if (field == "volume") {
                fader.copy(volume = value.coerceIn(0.0, 1.0))
            } else {
                fader.copy(pan = value.coerceIn(-1.0, 1.0))
            }
            jsonObject { put("strip", strip(id)!!.toJson()) }
        }
        "mixer.set_mute", "mixer.set_solo" -> {
            val id = p["strip_id"]?.string ?: ""
            if (faders[id] == null || id == "master") {
                throw DemoErrors.make("unknown_strip", mapOf("mixer" to mixerState().toJson()))
            }
            val mute = method == "mixer.set_mute"
            val on = p[if (mute) "muted" else "soloed"]?.bool ?: false
            val name = strip(id)?.name ?: ""
            if ((if (mute) song.muted else song.soloed).contains(id) != on) {
                edit("${if (on) "" else "Un"}${if (mute) "mute" else "solo"} $name".capitalizedFirst()) { s ->
                    if (mute) {
                        s.copy(muted = if (on) s.muted + id else s.muted - id)
                    } else {
                        s.copy(soloed = if (on) s.soloed + id else s.soloed - id)
                    }
                }
            }
            jsonObject { put("mixer", mixerState().toJson()); put("undo", undoState().toJson()) }
        }
        "mixer.add_bus" -> {
            // The mixer's "+ Bus" once its New Bus dialog has a name: trimmed, not only spaces; no
            // undo step, as in Tabber Studio.
            val name = (p["name"]?.string ?: "").trimSpaces()
            if (name.isEmpty()) throw DemoErrors.make("invalid_params", mapOf("field" to Json.Str("name")))
            busCounter += 1
            val id = "demo-bus-$busCounter"
            buses.add(Bus(id, name))
            faders[id] = Fader(0.7, 0.0)
            jsonObject { put("strip", strip(id)!!.toJson()); put("mixer", mixerState().toJson()) }
        }
        "trainer.state" -> jsonObject { put("trainer", trainerState().toJson()) }
        "trainer.set" -> {
            val enabled = p["enabled"]?.bool ?: trainer.enabled
            if (enabled && !loop.enabled) throw DemoErrors.make("needs_loop", mapOf("trainer" to trainerState().toJson()))
            p["start"]?.int?.let { trainer = trainer.copy(start = it.coerceIn(25, 200)) }
            p["step"]?.int?.let { trainer = trainer.copy(step = it.coerceIn(1, 50)) }
            p["target"]?.int?.let { trainer = trainer.copy(target = it.coerceIn(25, 200)) }
            trainer = trainer.copy(enabled = enabled)
            anchorBeat = currentBeat(); anchorTime = System.nanoTime()
            scale = if (enabled) trainer.start / 100.0 else 1.0 // a changed field starts again, as in Studio
            jsonObject { put("trainer", trainerState().toJson()) }
        }
        "view.state" -> jsonObject { put("view", viewState().toJson()) }
        "view.set" -> {
            val editor = p["editor"]?.string
            if (editor != null) {
                if (editor !in ViewState.editors) throw DemoErrors.make("invalid_params", mapOf("field" to Json.Str("editor")))
                view = ViewState(editor, split = false) // an editor button leaves Split, as in Studio
            }
            val split = p["split"]?.bool
            if (split != null && split != view.split) {
                view = if (split) { // an editor beside Arrange
                    preSplit = view.editor
                    ViewState(if (view.editor == "arrange") "tab" else view.editor, split = true)
                } else { // back to the editor before, as F8 does
                    ViewState(preSplit, split = false)
                }
            }
            jsonObject { put("view", viewState().toJson()) }
        }
        "view.show_part" -> {
            val id = p["track_id"]?.string ?: ""
            val shows = p["as"]?.string
            if (shows == null || shows !in listOf("midi_tab", "notation")) {
                throw DemoErrors.make("invalid_params", mapOf("field" to Json.Str("as")))
            }
            // The card's own buttons: only while the card waits, and MIDI tab not for drums.
            val part = viewState().part
            if (part == null || part.trackId != id || part.shows != "card" || !(shows == "notation" || part.midiTab)) {
                throw DemoErrors.make("stale_target", mapOf("view" to viewState().toJson()))
            }
            partShows[id] = shows
            if (shows == "midi_tab" && song.tabs[id] == null) { // its MIDI tab, guitar strings as Studio's default
                val rest = listOf(TabBeat(NoteValue(4), rest = true, notes = emptyList()))
                val count = song.tabs.values.maxOfOrNull { it.bars.size } ?: 16
                song = song.copy(tabs = song.tabs + (id to DemoTab(DemoTab.STANDARD, List(count) { rest })))
                tabRevision += 1
            }
            jsonObject { put("view", viewState().toJson()) }
        }
        "chat.state" -> jsonObject { put("chat", chat.toJson()) }
        "chat.send", "chat.confirm", "chat.cancel", "chat.stop" -> {
            chatVerb(method, p)
            jsonObject { put("chat", chat.toJson()) }
        }
        "routing.state" -> jsonObject { put("routing", routingState().toJson()) }
        "routing.set_output", "routing.set_send", "routing.remove_send" -> {
            routingVerb(method, p)
            jsonObject { put("routing", routingState().toJson()); put("undo", undoState().toJson()) }
        }
        "tab.state" -> jsonObject { put("tab", tabValue()) }
        "tab.set_cursor", "tab.move", "tab.put", "tab.put_pitch", "tab.set_duration", "tab.rest", "tab.delete" -> {
            tabVerb(method, p)
            jsonObject { put("tab", tabValue()); put("undo", undoState().toJson()) }
        }
        else -> throw DemoErrors.make("method_not_found")
    }

    /** The index of the track a request names, or the refusal with the tracks as they are. */
    private fun trackIndex(p: Json): Int {
        val id = p["track_id"]?.string ?: ""
        val index = song.tracks.indexOfFirst { it.id == id }
        if (index < 0) throw DemoErrors.make("unknown_track", mapOf("tracks" to tracksJson()))
        return index
    }

    private fun tracksJson(): Json = Json.of(song.tracks.map(Track::toJson))
    private fun markersJson(): Json = Json.of(song.markers.map(Marker::toJson))
    private fun takesJson(takes: List<Take>): Json = Json.of(takes.map(Take::toJson))

    // The mixer

    private fun strip(id: String): Strip? {
        val fader = faders[id] ?: return null
        val kind: String
        val name: String
        val color: String?
        val bus = buses.firstOrNull { it.id == id }
        val track = song.tracks.firstOrNull { it.id == id }
        when {
            id == "master" -> { kind = "master"; name = "Master"; color = null }
            bus != null -> { kind = "bus"; name = bus.name; color = null }
            track != null -> { kind = "track"; name = track.name; color = track.color }
            else -> return null
        }
        return Strip(
            id, kind, name, color, volume = rounded(fader.volume * 1000) / 1000, volumeDb = db(fader.volume),
            pan = rounded(fader.pan * 1000) / 1000, panLabel = panLabel(fader.pan),
            muted = id in song.muted, soloed = id in song.soloed,
        )
    }

    private fun mixerState(): MixerState {
        val ids = song.tracks.map { it.id } + buses.map { it.id } + "master"
        return MixerState(ids.mapNotNull(::strip), SCALE)
    }

    // The chat

    private fun chatError(reason: String): RemoteError = DemoErrors.make(reason, mapOf("chat" to chat.toJson()))

    private fun say(from: String, kind: String, text: String) {
        chatCounter += 1
        val messages = chat.messages + ChatMessage("demo-m$chatCounter", from, kind, text)
        chat = chat.copy(messages = if (messages.size > 50) messages.drop(messages.size - 50) else messages)
    }

    /**
     * Tabber Studio's chat, as the demo answers it: mute or solo a track by name, each one undo
     * step after Execute; keys and settings refused in Tabber Studio's words; anything else, what
     * to try.
     */
    private fun chatVerb(method: String, p: Json) {
        when (method) {
            "chat.send" -> {
                if (chat.isWorking) throw chatError("chat_busy")
                val text = p["text"]?.string ?: ""
                chat = chat.copy(plan = null)
                chatAction = null
                chatRequest = text
                say("you", "text", text)
                chat = chat.copy(state = "thinking")
                scope.launch {
                    delay(500)
                    answerChat(text)
                }
            }
            "chat.confirm", "chat.cancel" -> {
                val id = p["plan_id"]?.string ?: ""
                val action = chatAction
                if (chat.state != "waiting" || action == null || action.planId != id) throw chatError("unknown_plan")
                chat = chat.copy(plan = null)
                chatAction = null
                chat = chat.copy(state = "idle")
                if (method != "chat.confirm") return
                val name = song.tracks.firstOrNull { it.id == action.track }?.name ?: "the track"
                edit("AI: ${characterPrefix(chatRequest, 40)}") { s ->
                    if (action.solo) s.copy(soloed = s.soloed + action.track) else s.copy(muted = s.muted + action.track)
                }
                say("studio", "result", "${if (action.solo) "Soloed" else "Muted"} the $name track.")
            }
            else -> { // chat.stop
                if (chat.isWorking) {
                    chat = chat.copy(state = "idle")
                    say("studio", "text", "Stopped.")
                }
            }
        }
    }

    private fun answerChat(text: String) {
        if (chat.state != "thinking" || chatRequest != text) return
        val before = topicData()
        val lower = text.lowercase()
        val track = song.tracks.sortedByDescending { it.name.length }.firstOrNull { lower.contains(it.name.lowercase()) }
        if (listOf("key", "password", "token", "pair", "setting").any { lower.contains(it) }) {
            say("studio", "refusal", "From a phone the chat does not reach the AI's own settings, key and tools. Do that on the computer.")
            chat = chat.copy(state = "idle")
        } else if (track != null && (lower.contains("mute") || lower.contains("solo"))) {
            val solo = !lower.contains("mute")
            chatCounter += 1
            val planId = "demo-p$chatCounter"
            chatAction = ChatAction(planId, track.id, solo)
            chat = chat.copy(
                plan = ChatPlan(
                    planId, "I'll ${if (solo) "solo" else "mute"} the ${track.name} track.",
                    listOf(ChatPlan.Step("${if (solo) "Solo" else "Mute"} track: ${track.name}")),
                ),
            )
            chat = chat.copy(state = "waiting")
        } else {
            say("studio", "text", "In the demo, try: mute the drums, or solo the bass.")
            chat = chat.copy(state = "idle")
        }
        broadcastChanges(before)
    }

    // Routing

    private fun routingState(): RoutingState {
        val sources = song.tracks.map { RoutingSource(it.id, "track", it.name, song.outputs[it.id] ?: RoutingState.MASTER) } +
            buses.map { RoutingSource(it.id, "bus", it.name, song.outputs[it.id] ?: RoutingState.MASTER) }
        val sends = ArrayList<RoutingSend>()
        for (track in song.tracks) {
            for (bus in buses) {
                val send = "${track.id}>${bus.id}"
                if (send !in song.sends) continue
                val value = sendLevels[send] ?: SendValue(0.5, false)
                sends.add(
                    RoutingSend(
                        track.id, bus.id, level = rounded(value.level * 10000) / 10000,
                        levelDb = SendLevel.db(value.level)?.let { rounded(it * 10) / 10 },
                        levelLabel = SendLevel.label(value.level), preFader = value.pre,
                    ),
                )
            }
        }
        return RoutingState(sources, sends)
    }

    private fun routingError(reason: String, extra: Map<String, Json> = emptyMap()): RemoteError =
        DemoErrors.make(reason, extra + ("routing" to routingState().toJson()))

    /**
     * Tabber Studio's Routing panel: an output moves (one step, "Routing change"), a send is added
     * at -6 dB or taken away (each a step), and its level and Pre-fader change without one. A loop
     * is refused, named.
     */
    private fun routingVerb(method: String, p: Json) {
        fun isBus(id: String) = buses.any { it.id == id }
        fun isTrack(id: String) = song.tracks.any { it.id == id }
        val id = p["strip_id"]?.string ?: ""
        if (!(isBus(id) || isTrack(id) || id == "master")) throw routingError("unknown_strip")
        when (method) {
            "routing.set_output" -> {
                val output = p["output"]?.string ?: ""
                if (!(output == RoutingState.MASTER || isBus(output) || isTrack(output))) throw routingError("unknown_strip")
                if (id == "master" || !(output == RoutingState.MASTER || isBus(output))) throw routingError("wrong_kind")
                val loop = routingState().wouldLoop(id, output)
                if (loop != null) throw routingError("routing_loop", mapOf("path" to Json.strings(loop)))
                if ((song.outputs[id] ?: RoutingState.MASTER) == output) return
                edit("Routing change") { s ->
                    s.copy(outputs = if (output == RoutingState.MASTER) s.outputs - id else s.outputs + (id to output))
                }
            }
            else -> {
                val bus = p["bus_id"]?.string ?: ""
                if (!(isBus(bus) || isTrack(bus) || bus == "master")) throw routingError("unknown_strip")
                if (!(isTrack(id) && isBus(bus))) throw routingError("wrong_kind")
                val send = "$id>$bus"
                val name = buses.firstOrNull { it.id == bus }?.name ?: bus
                if (method == "routing.remove_send") {
                    if (send in song.sends) edit("Remove send → $name") { s -> s.copy(sends = s.sends - send) }
                    return
                }
                if (send !in song.sends) {
                    sendLevels[send] = SendValue(0.5, false) // Tabber Studio's -6 dB
                    edit("Add send → $name") { s -> s.copy(sends = s.sends + send) }
                }
                var value = sendLevels[send] ?: SendValue(0.5, false)
                p["level"]?.double?.let { value = value.copy(level = it.coerceIn(0.0, 1.0)) }
                p["pre_fader"]?.bool?.let { value = value.copy(pre = it) }
                sendLevels[send] = value
            }
        }
    }

    // The tab

    /**
     * The selected track, when it has tab; a MIDI track's MIDI tab only while the Tab editor shows
     * it, as in Tabber Studio (tab.midi/1).
     */
    private fun tabTrackId(): String? {
        val track = song.tracks.firstOrNull { it.selected } ?: return null
        if (song.tabs[track.id] == null) return null
        if (track.tuning == null && viewState().part?.shows != "midi_tab") return null
        return track.id
    }

    private fun tabValue(): Json {
        val id = tabTrackId() ?: return Json.Null
        val doc = song.tabs[id] ?: return Json.Null
        val cursor = doc.clamp(tabCursors[id] ?: TabCursor(1, 1, 1))
        // As Studio's toolbar shows it: the beat's own value when it has notes, else the chosen
        // one; Dot and Triplet are always the beat's.
        val beat = doc.beat(cursor)
        val shown = beat?.let {
            if (it.notes.isEmpty()) NoteValue(tabDuration.value, it.duration.dotted, it.duration.triplet) else it.duration
        } ?: tabDuration
        val midi = song.tracks.firstOrNull { it.id == id }?.tuning == null
        val state = TabState(
            trackId = id, revision = tabRevision, tuning = doc.tuning, drum = false, cursor = cursor, duration = shown,
            barCount = doc.bars.size, bars = doc.window(cursor), midi = if (midi) true else null,
        )
        return state.toJson()
    }

    private fun tabVerb(method: String, p: Json) {
        val noTab = { DemoErrors.make("no_tab", mapOf("tracks" to tracksJson())) }
        val id = tabTrackId() ?: throw noTab()
        val doc = song.tabs[id]?.copy() ?: throw noTab()
        var cursor = doc.clamp(tabCursors[id] ?: TabCursor(1, 1, 1))
        var label: String? = null
        when (method) {
            "tab.set_cursor" -> cursor = doc.clamp(
                TabCursor(p["bar"]?.int ?: cursor.bar, p["beat"]?.int ?: cursor.beat, p["string"]?.int ?: cursor.string),
            )
            "tab.move" -> {
                val moved = doc.move(cursor, by = p["by"]?.int ?: 1, duration = tabDuration)
                if (moved.changed) label = if (moved.cursor.bar > cursor.bar) "Insert measure" else "Insert beat"
                cursor = moved.cursor
            }
            "tab.put" -> {
                val string = p["string"]?.int
                val fret = p["fret"]?.int
                if (string == null || fret == null || string !in 1..doc.tuning.size || fret !in 0..DemoTab.MAX_FRET) {
                    throw DemoErrors.make("invalid_params", mapOf("field" to Json.Str("fret")))
                }
                val off = doc.note(string, cursor)?.fret == fret
                if (doc.put(string = string, fret = fret, at = cursor, duration = tabDuration)) {
                    label = if (off) "Delete note on string $string" else "Set fret $fret on string $string" // Studio's own labels
                }
                cursor = cursor.copy(string = string)
            }
            "tab.put_pitch" -> {
                val pitch = p["pitch"]?.int ?: throw DemoErrors.make("invalid_params", mapOf("field" to Json.Str("pitch")))
                val before = doc.copy()
                val put = doc.put(pitch = pitch, at = cursor, duration = tabDuration)
                if (put.changed) {
                    val written = doc.note(put.string, cursor)
                    label = if (written == null || before.note(put.string, cursor) == written) {
                        "Delete note on string ${put.string}"
                    } else {
                        "Set fret ${written.fret} on string ${put.string}"
                    }
                }
                cursor = cursor.copy(string = put.string)
            }
            "tab.set_duration" -> {
                val value = p["value"]?.int
                if (value == null || value !in NoteValue.values) {
                    throw DemoErrors.make("invalid_params", mapOf("field" to Json.Str("value")))
                }
                val wanted = NoteValue(value, p["dotted"]?.bool ?: false, p["triplet"]?.bool ?: false)
                val old = doc.beat(cursor)?.duration
                tabDuration = NoteValue(value) // the value sticks; Dot and Triplet are the beat's
                if (doc.setDuration(wanted, cursor) && old != null) {
                    val changes = listOf(old.value != wanted.value, old.dotted != wanted.dotted, old.triplet != wanted.triplet).count { it }
                    label = when {
                        changes > 1 -> "Set note value"
                        old.value != wanted.value -> "Set duration to ${durationName(wanted.value)}"
                        old.dotted != wanted.dotted -> "Toggle dotted"
                        wanted.triplet -> "Set tuplet 3"
                        else -> "Clear tuplet"
                    }
                }
            }
            "tab.rest" -> if (doc.rest(cursor)) label = "Toggle rest"
            else -> if (doc.delete(cursor)) label = "Delete note on string ${cursor.string}"
        }
        if (label != null) {
            edit(label) { s -> s.copy(tabs = s.tabs + (id to doc)) }
            tabRevision += 1
        }
        tabCursors[id] = doc.clamp(cursor)
    }

    // The view

    /**
     * What the demo computer shows, with the MIDI part its Tab editor shows: the chosen MIDI track
     * without tab gets Tabber Studio's card until the phone or the computer answers it (view.part/1).
     */
    private fun viewState(): ViewState {
        val track = song.tracks.firstOrNull { it.selected }
        val part = if (view.editor == "tab" && track != null && track.kind == TrackKind.MIDI && track.tuning == null) {
            ViewPart(track.id, partShows[track.id] ?: "card", midiTab = track.id !in drums)
        } else {
            null
        }
        return ViewState(view.editor, view.split, part, hasPart = true)
    }

    // Adding tracks

    /**
     * "+ Add Track" as Tabber Studio makes each kind (ui/track_creation_controller.py): the first
     * colour no track has; a tab or MIDI track after the last of those, before the audio, and
     * selected; an audio track last, with the computer turning from Tab to Arrange to show it. One
     * undo step each.
     */
    private fun addTrack(kind: NewTrackKind): Track {
        trackCounter += 1
        val sequenced = song.tracks.count { it.kind == TrackKind.MIDI }
        val color = PALETTE.firstOrNull { c -> song.tracks.none { it.color == c } } ?: PALETTE[song.tracks.size % PALETTE.size]
        val id = "demo-new-$trackCounter"
        val track = when (kind) {
            NewTrackKind.TAB -> Track(
                id, "Track ${sequenced + 1}", TrackKind.MIDI, armed = false, monitor = MonitorMode.AUTO, selected = true,
                color = color, instrument = "Acoustic Guitar (steel)", tuning = DemoTab.STANDARD,
            )
            NewTrackKind.MIDI -> Track(
                id, "MIDI Track ${sequenced + 1}", TrackKind.MIDI, armed = false, monitor = MonitorMode.AUTO,
                selected = true, color = color, instrument = "Acoustic Grand Piano",
            )
            NewTrackKind.AUDIO -> Track(
                id, "Audio ${song.tracks.size - sequenced + 1}", TrackKind.AUDIO, armed = false,
                monitor = MonitorMode.AUTO, selected = false, color = color,
            )
        }
        val bars = song.tabs.values.maxOfOrNull { it.bars.size } ?: 16
        faders[id] = Fader(0.7, 0.0) // its mixer strip, at Studio's default
        edit(if (kind == NewTrackKind.AUDIO) "Add audio track: ${track.name}" else "Add track: ${track.name}") { s ->
            if (kind == NewTrackKind.AUDIO) return@edit s.copy(tracks = s.tracks + track)
            val tracks = s.tracks.map { it.copy(selected = false) }.toMutableList()
            tracks.add(sequenced, track)
            var tabs = s.tabs
            if (kind == NewTrackKind.TAB) {
                val rest = listOf(TabBeat(NoteValue(4), rest = true, notes = emptyList()))
                tabs = tabs + (id to DemoTab(DemoTab.STANDARD, List(bars) { rest }))
            }
            s.copy(tracks = tracks, tabs = tabs)
        }
        if (kind == NewTrackKind.AUDIO && !view.split && view.editor == "tab") view = view.copy(editor = "arrange")
        if (kind == NewTrackKind.TAB) tabRevision += 1
        return track
    }

    // The session

    private fun edit(label: String, change: (Song) -> Song) {
        val before = song
        song = change(song)
        song = song.copy(project = song.project.copy(unsaved = true))
        stepCounter += 1
        undo.subList(undoIndex, undo.size).clear()
        undo.add(Step("demo-u$stepCounter", label, before, song))
        undoIndex = undo.size
    }

    private fun undoState(): UndoState = UndoState(
        undo = if (undoIndex > 0) UndoStep(undo[undoIndex - 1].id, undo[undoIndex - 1].label) else null,
        redo = if (undoIndex < undo.size) UndoStep(undo[undoIndex].id, undo[undoIndex].label) else null,
    )

    private fun currentBeat(): Double {
        if (!playing) return anchorBeat
        val elapsed = (System.nanoTime() - anchorTime) / 1e9
        var beat = anchorBeat + elapsed * tempo / 60.0 * scale
        val start = loop.start
        val end = loop.end
        if (loop.enabled && start != null && end != null) {
            val a = beatAt(start.bar, start.beat)
            val b = beatAt(end.bar, end.beat)
            if (b > a && beat >= b) beat = a + (beat - a) % (b - a)
        }
        return max(0.0, beat)
    }

    private fun trainerState(): TrainerState = TrainerState(
        enabled = trainer.enabled, start = trainer.start, step = trainer.step, target = trainer.target,
        speed = rounded(scale * 100).toInt(),
    )

    /**
     * Each time the loop comes round, the trainer steps up toward its target, as Tabber Studio's
     * engine does on its loop's wrap.
     */
    private fun stepTrainerOnWrap() {
        val beat = currentBeat()
        try {
            val start = loop.start
            val end = loop.end
            if (!trainer.enabled || !loop.enabled || start == null || end == null) return
            val a = beatAt(start.bar, start.beat)
            val b = beatAt(end.bar, end.beat)
            if (!(beat < lastBeat && lastBeat >= b - 1 && beat < a + 1)) return
            val before = topicData()
            anchorBeat = beat; anchorTime = System.nanoTime()
            scale = min(scale + trainer.step / 100.0, trainer.target / 100.0)
            broadcastChanges(before)
        } finally {
            lastBeat = beat
        }
    }

    private fun position(beat: Double): Position =
        Position((beat / 4).toInt() + 1, (beat % 4).toInt() + 1, rounded(beat * 60.0 / tempo * 1000) / 1000)

    private fun transport(): TransportState = TransportState(
        state = if (playing) PlayState.PLAYING else PlayState.STOPPED, position = position(currentBeat()),
        tempoBpm = tempo, tempoScale = scale, timeSignature = TimeSignature(4, 4), loop = loop, click = click,
        countInBars = countIn, countingIn = recordingStart?.let { System.nanoTime() - it.at < 0 } ?: false,
    )

    private fun armedIds(): List<String> = song.tracks.filter { it.armed }.map { it.id }

    private fun record(): RecordState {
        val armed = armedIds()
        val start = recordingStart ?: return RecordState(recording = false, started = null, armedTrackIds = armed)
        val t = now() + (start.at - System.nanoTime()) / 1e9
        return RecordState(recording = true, started = RecordStart(start.position, rounded(t * 1000) / 1000), armedTrackIds = armed)
    }

    private fun recentTakes(): List<Take> = heard(song.takes.asReversed().take(20))

    /**
     * Which takes play, as Tabber Studio's take lanes decide (TR33): a pass recorded over an
     * earlier one on its track plays where they overlap, so an earlier take plays only if some of
     * it is outside every newer one. Discarding the newer take lets the earlier one play again.
     */
    private fun heard(takes: List<Take>): List<Take> = takes.map { take ->
        var left = listOf(take.start.seconds to take.start.seconds + take.lengthSeconds)
        val newer = song.takes.dropWhile { it.id != take.id }.drop(1).filter { it.trackId == take.trackId }
        for (later in newer) {
            val lo = later.start.seconds
            val hi = later.start.seconds + later.lengthSeconds
            left = left.flatMap { span ->
                if (!(span.second > lo && span.first < hi)) {
                    listOf(span)
                } else {
                    listOf(span.first to lo, hi to span.second).filter { it.second - it.first > 0.0005 }
                }
            }
        }
        take.copy(active = left.isNotEmpty())
    }

    private fun startRecording(track: String, atBeat: Double) {
        val leadBeats = (countIn * 4).toDouble()
        val lead = (leadBeats * 60.0 / tempo / scale * 1e9).toLong()
        anchorBeat = max(0.0, atBeat - leadBeats)
        anchorTime = System.nanoTime()
        playing = true
        recordingStart = RecordingStart(position(atBeat), System.nanoTime() + lead, track)
        startedRecordings += 1
        startTicker()
    }

    private fun stopEverything(): Take? {
        var made: Take? = null
        val start = recordingStart
        if (start != null) {
            val length = max(0.0, (System.nanoTime() - start.at) / 1e9)
            takeCounter += 1
            val name = song.tracks.firstOrNull { it.id == start.track }?.name ?: "Take"
            val take = Take(
                "demo-take-$takeCounter", start.track, "$name take $takeCounter", start.position,
                lengthSeconds = rounded(length * 1000) / 1000, rating = 0, active = true,
            )
            recordingStart = null
            edit("Record take") { s -> s.copy(takes = s.takes + take) }
            made = take
        }
        anchorBeat = currentBeat()
        anchorTime = System.nanoTime()
        playing = false
        return made
    }

    private fun snapshot(seq: Int): Json = jsonObject {
        put("seq", seq); put("t", now()); put("project", song.project.toJson())
        put("transport", transport().toJson()); put("record", record().toJson())
        put("tracks", tracksJson()); put("markers", markersJson())
        put("takes", takesJson(recentTakes())); put("undo", undoState().toJson())
    }

    // Events

    private fun topicData(): Map<String, Json> {
        val data = HashMap<String, Json>()
        data["transport"] = Json.Obj(transport().toJson().obj.orEmpty() - "position")
        data["record"] = RecordState(
            recording = recordingStart != null, started = recordingStart?.let { RecordStart(it.position, 0.0) },
            armedTrackIds = armedIds(),
        ).toJson()
        data["tracks"] = tracksJson()
        data["markers"] = markersJson()
        data["takes"] = takesJson(recentTakes())
        data["undo"] = undoState().toJson()
        data["project"] = song.project.toJson()
        data["mixer"] = mixerState().toJson()
        data["tab"] = jsonObject { put("tab", tabValue()) }
        data["routing"] = routingState().toJson()
        data["chat"] = chat.toJson()
        data["view"] = viewState().toJson()
        data["trainer"] = trainerState().toJson()
        return data
    }

    private fun full(topic: String): Json = when (topic) {
        "transport" -> transport().toJson()
        "record" -> record().toJson()
        "tracks" -> jsonObject { put("tracks", tracksJson()) }
        "markers" -> jsonObject { put("markers", markersJson()) }
        "takes" -> jsonObject { put("takes", takesJson(recentTakes())) }
        "undo" -> undoState().toJson()
        "mixer" -> mixerState().toJson()
        "tab" -> jsonObject { put("tab", tabValue()) }
        "routing" -> routingState().toJson()
        "chat" -> chat.toJson()
        "view" -> viewState().toJson()
        "trainer" -> trainerState().toJson()
        else -> song.project.toJson()
    }

    private fun broadcastChanges(before: Map<String, Json>) {
        val after = topicData()
        for (topic in TOPICS) {
            if (before[topic] != after[topic]) emit(topic, full(topic))
        }
    }

    private fun emit(topic: String, data: Json) {
        for (connection in connections) {
            if (!connection.authed || topic !in connection.topics) continue
            connection.seq += 1
            send(jsonObject {
                put("jsonrpc", "2.0"); put("method", "event")
                put("params", jsonObject { put("topic", topic); put("seq", connection.seq); put("t", now()); put("data", data) })
            }, connection)
        }
    }

    private fun startTicker() {
        if (ticker != null) return
        ticker = scope.launch {
            var tick = 0
            while (tickOnce(tick)) {
                tick += 1
                delay(50)
            }
        }
    }

    private fun peaks(level: Double): Json = Json.doubles(listOf(rounded(level * 1000) / 1000, rounded(level * 900) / 1000))

    /** Position at 10 a second, meters at 20, while playing or while an input is armed (spec 8.2). */
    private fun tickOnce(tick: Int): Boolean {
        if (!playing && song.tracks.none { it.armed }) {
            ticker = null
            return false
        }
        if (!playing) { // stopped: only the armed inputs' levels
            val level = 0.3 + 0.25 * abs(sin(tick / 2.5))
            emit("meters", jsonObject {
                put("levels", Json.of(song.tracks.filter { it.armed }.map { track ->
                    jsonObject { put("track_id", track.id); put("peak", peaks(level)) }
                }))
            })
            return true
        }
        stepTrainerOnWrap()
        val before = lastSent["counting"]
        val counting = Json.Bool(transport().countingIn)
        if (before != counting) {
            lastSent["counting"] = counting
            emit("transport", full("transport"))
        }
        if (tick % 2 == 0) {
            val t = transport()
            emit("position", jsonObject { put("state", t.state.wire); put("position", t.position.toJson()) })
        }
        val level = 0.35 + 0.3 * abs(sin(tick / 3.0))
        val levels = song.tracks.filter { it.armed || it.selected }.map { track ->
            jsonObject { put("track_id", track.id); put("peak", peaks(level)) }
        }
        emit("meters", jsonObject { put("levels", Json.of(levels)) })
        val strips = mixerState().strips
        val anySolo = song.soloed.isNotEmpty()
        var master = 0.0
        val stripLevels = strips.mapIndexed { index, strip ->
            val peak: Double
            if (!strip.isMaster) {
                val audible = !strip.muted && (!anySolo || strip.soloed || strip.isBus)
                peak = if (audible) (0.22 + 0.4 * abs(sin(tick / 3.0 + index * 1.7))) * min(1.3, strip.volume / 0.7) else 0.0
                master = max(master, peak)
            } else {
                peak = master * min(1.3, strip.volume / 0.7)
            }
            val left = rounded(min(1.0, peak) * 1000) / 1000
            jsonObject { put("strip_id", strip.id); put("peak", Json.doubles(listOf(left, rounded(left * 920) / 1000))) }
        }
        emit("mixer_meters", jsonObject { put("levels", Json.of(stripLevels)) })
        return true
    }

    companion object {
        const val HOST_ID = "5e1f0a2b-3c4d-4e5f-8a6b-7c8d9e0f1a2b"
        const val NAME = "Demo Studio"

        internal val CAPABILITIES = listOf(
            "transport/1", "record/1", "tempo_scale/1", "tracks/1", "tracks.monitor/1",
            "markers/1", "takes/1", "takes.discard/1", "takes.go_again/1", "undo/1",
            "save/1", "meters/1", "mixer/1", "tab/1", "routing/1", "chat/1", "view/1",
            "trainer/1", "tracks.add/1", "view.part/1", "tab.midi/1",
            "mixer.add_bus/1",
        )

        /** The fader law: 0 dB at 70 % of the travel, +2.1 dB at the top, as Tabber Studio's fader. */
        internal fun db(travel: Double): Double? {
            if (!(travel > 0.001)) return null
            val db = if (travel >= 0.7) (travel - 0.7) / 0.3 * 2.1 else 60 * log10(travel / 0.7)
            return rounded(db * 10) / 10
        }

        internal fun panLabel(pan: Double): String {
            val value = rounded(64 + pan * (if (pan < 0) 64 else 63)).toInt()
            return if (value == 64) "C" else if (value < 64) "L${64 - value}" else "R${value - 64}"
        }

        /** Tabber Studio's names for note values, as its undo labels say them. */
        internal fun durationName(value: Int): String =
            mapOf(1 to "WHOLE", 2 to "HALF", 4 to "QUARTER", 8 to "EIGHTH", 16 to "SIXTEENTH", 32 to "THIRTY_SECOND")[value] ?: "QUARTER"

        internal val SCALE = listOf(ScaleMark(0.0, 0.7), ScaleMark(-12.0, 0.442), ScaleMark(-24.0, 0.279), ScaleMark(-48.0, 0.111))

        /** Tabber Studio's track colours (core/models.py TRACK_COLORS), in its order. */
        internal val PALETTE = listOf(
            "#50A0DC", "#64BE64", "#DCAA3C", "#AA64D2", "#9A86D6", "#DC5050",
            "#DC8246", "#96BE3C", "#C864A0", "#648CC8", "#BEA064", "#D2C850",
        )

        /** The topics a change can touch, in the order their events go out. */
        private val TOPICS = listOf(
            "transport", "record", "tracks", "markers", "takes", "undo", "project", "mixer", "tab", "routing", "chat", "view",
            "trainer",
        )
    }
}

/** The error table (spec 10), word for word. */
object DemoErrors {
    internal val table: Map<String, Pair<Int, String>> = mapOf(
        "method_not_found" to (-32601 to "This version of Tabber Studio cannot do that."),
        "invalid_params" to (-32602 to "The phone sent a request the computer could not use."),
        "internal_error" to (-32603 to "Something went wrong in Tabber Studio."),
        "unauthenticated" to (1001 to "Pair this phone with the computer first."),
        "unsupported_version" to (1010 to "Update Tabber Studio or Tabber Spak so they can talk to each other."),
        "already_recording" to (1021 to "Tabber Studio is already recording."),
        "unknown_track" to (1023 to "That track is gone from the song."),
        "unknown_take" to (1024 to "That take is gone from the song."),
        "unknown_marker" to (1025 to "That marker is gone from the song."),
        "stale_target" to (1026 to "This changed on the computer. The phone now shows the new state."),
        "undo_mismatch" to (1027 to "The computer's newest change is a different one. Undo it there, or try again."),
        "nothing_to_undo" to (1028 to "There is nothing to undo."),
        "nothing_to_redo" to (1029 to "There is nothing to redo."),
        "unknown_strip" to (1032 to "That strip is gone from the mixer."),
        "no_tab" to (1033 to "Choose a tab track to write on first."),
        "needs_loop" to (1039 to "Turn Loop on first: the trainer speeds up each time the loop comes round."),
        "track_limit" to (1040 to "This song has as many tracks as Tabber Studio can play."),
    )

    internal fun make(reason: String, data: Map<String, Json> = emptyMap()): RemoteError {
        val (code, message) = table[reason] ?: (1099 to "Tabber Studio could not do that.")
        return RemoteError(code, message, reason, Json.Obj(data + ("reason" to Json.Str(reason))))
    }
}

/** Swift's rounded(): to the nearest whole number, halves away from zero (Kotlin's round() takes halves to even). */
private fun rounded(x: Double): Double {
    if (!x.isFinite()) return x
    val whole = truncate(x)
    return if (abs(x - whole) >= 0.5) whole + sign(x) else whole
}

/** The playhead's beat, from 0, at a bar and beat counted from 1 in 4/4. */
private fun beatAt(bar: Int, beat: Int): Double = (bar - 1) * 4.0 + (beat - 1)

/** The first letter in upper case, as Swift's capitalizedFirst. */
private fun String.capitalizedFirst(): String = take(1).uppercase() + drop(1)

/** Without the spaces and tabs at either end, as Swift's trimmingCharacters(in: .whitespaces): line breaks stay. */
private fun String.trimSpaces(): String = trim { it == '\t' || it.category == CharCategory.SPACE_SEPARATOR }

/** The first [count] characters as a reader counts them, as Swift's prefix on a String, never half of one. */
private fun characterPrefix(text: String, count: Int): String {
    val breaks = BreakIterator.getCharacterInstance()
    breaks.setText(text)
    var end = 0
    repeat(count) {
        val next = breaks.next()
        if (next == BreakIterator.DONE) return text
        end = next
    }
    return text.substring(0, end)
}
