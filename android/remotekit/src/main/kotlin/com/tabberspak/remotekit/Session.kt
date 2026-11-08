package com.tabberspak.remotekit

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.util.UUID
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.nanoseconds
import kotlin.time.Duration.Companion.seconds

/** A paired computer, as the phone remembers it. */
data class KnownHost(val id: String, val name: String, val pin: String, val routes: List<Route>) {
    fun toJson(): Json = jsonObject {
        put("id", id); put("name", name); put("pin", pin)
        put("routes", Json.strings(routes.map(Route::toString)))
    }

    companion object {
        fun from(r: JsonReader) = KnownHost(r.string("id"), r.string("name"), r.string("pin"), r.strings("routes").mapNotNull(Route::parse))
    }
}

/**
 * Why the phone cannot work with its computer, in a form the app turns into a fix-it card (plan:
 * TR6). Null while connected, and while a reconnect is still young.
 */
sealed interface Trouble {
    /** Nothing answered at any of the computer's addresses for a while. */
    data object Unreachable : Trouble
    /** The phone keeps Tabber Spak off the local network (Android 17's permission). */
    data object LocalNetworkDenied : Trouble
    /** The computer speaks only older protocol versions than this phone. */
    data class UpdateStudio(val hostVersions: List<String>) : Trouble
    /** The computer speaks only newer protocol versions than this phone. */
    data class UpdateSpak(val hostVersions: List<String>) : Trouble
    /** The computer no longer knows this phone (removed in Settings › Remote). */
    data object Forgotten : Trouble
    /** A different computer answers at the remembered address. */
    data object OtherComputer : Trouble

    companion object {
        /** Which side must update, from the versions the computer speaks (spec 7). */
        fun versions(hostVersions: List<String>, phone: List<String> = RemoteClient.PROTOCOL_VERSIONS): Trouble {
            fun major(version: String) = version.substringBefore('.').toIntOrNull() ?: 0
            val hostNewest = hostVersions.maxOfOrNull(::major) ?: 0
            val phoneNewest = phone.maxOfOrNull(::major) ?: 0
            return if (hostNewest > phoneNewest) UpdateSpak(hostVersions) else UpdateStudio(hostVersions)
        }
    }
}

/** What the app shows: the computer's confirmed state (principle 3). */
data class SessionState(
    val link: LinkState = LinkState.Idle,
    /** Why the computer cannot be used, once that is clear (TR6's fix-it cards). */
    val trouble: Trouble? = null,
    val host: HostInfo? = null,
    val capabilities: Set<String> = emptySet(),
    val project: ProjectState = ProjectState("", unsaved = false, hasFile = false),
    val transport: TransportState? = null,
    val record: RecordState = RecordState(recording = false, started = null, armedTrackIds = emptyList()),
    val tracks: List<Track> = emptyList(),
    val markers: List<Marker> = emptyList(),
    val takes: List<Take> = emptyList(),
    val undo: UndoState = UndoState(null, null),
    val meters: Map<String, List<Double>> = emptyMap(),
    /** Every strip, bus and the master (mixer/1); null when the computer has no mixer for phones. */
    val mixer: MixerState? = null,
    /** Strip levels while the Mixer is on screen (the mixer_meters topic). */
    val stripMeters: Map<String, List<Double>> = emptyMap(),
    /** The selected tab track's bars around the cursor (tab/1); null when the selected track has no tab. */
    val tab: TabState? = null,
    /** Each track's and bus's output and every send (routing/1). */
    val routing: RoutingState? = null,
    /** Tabber Studio's chat (chat/1). */
    val chat: ChatState? = null,
    /** What the computer shows (view/1). */
    val view: ViewState? = null,
    /** The Speed Trainer (trainer/1). */
    val trainer: TrainerState? = null,
    val seq: Int = 0,
    /** The host time of the newest message, and when it arrived here (System.nanoTime). */
    val hostTime: Double = 0.0,
    val receivedAt: Long = System.nanoTime(),
    /** When the playhead in [transport] was last confirmed, to count on from it. */
    val positionAt: Long = System.nanoTime(),
) {
    /** The host's clock now, from the newest message (spec 1, host time). */
    val hostNow: Double get() = hostTime + (System.nanoTime() - receivedAt) / 1e9

    /** The playhead's seconds now: counted on locally while playing (spec 8.2). */
    val playheadSeconds: Double
        get() {
            val t = transport ?: return 0.0
            if (t.state != PlayState.PLAYING) return t.position.seconds
            val elapsed = (System.nanoTime() - positionAt) / 1e9
            return t.position.seconds + minOf(elapsed, 1.0) * t.tempoScale
        }

    /** Seconds recorded so far; negative while the count-in runs. */
    val recordedSeconds: Double?
        get() {
            if (!record.recording) return null
            val started = record.started ?: return null
            return hostNow - started.t
        }
}

/**
 * Keeps one computer connected, applies its events, and resends changes with the same key after a
 * drop (spec 5.1), so Record never records twice. As apple/RemoteKit's RemoteSession actor: its
 * state changes on one thread only.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class RemoteSession(
    private val credentials: Credentials,
    private val app: AppInfo,
    private val connector: suspend (attempt: Int) -> RemoteTransport,
) {
    sealed interface Credentials {
        data object Demo : Credentials
        data class Paired(val host: KnownHost, val signer: DeviceSigner) : Credentials
    }

    private val confined = Dispatchers.Default.limitedParallelism(1)
    private val scope = CoroutineScope(SupervisorJob() + confined)
    private val flow = MutableStateFlow(SessionState())
    private var client: RemoteClient? = null
    private var supervisor: Job? = null
    private var nap: CompletableDeferred<Unit>? = null
    /** Topics a screen asked for while it shows (the Mixer's meters), kept across reconnects. */
    private val extraTopics = sortedSetOf<String>()
    private var times = ResponseTimes()

    /** The newest confirmed state; the app collects it. */
    val updates: StateFlow<SessionState> get() = flow
    val state: SessionState get() = flow.value

    /** Snapshots read again after a real gap in the events, for diagnostics and tests. */
    @Volatile var resnapshots = 0
        private set

    /** How long each change took to be answered, across reconnects (plan: TR7's gate). */
    val responseTimes: ResponseTimes get() = times

    fun start() {
        scope.launch {
            if (supervisor == null) supervisor = scope.launch { supervise() }
        }
    }

    suspend fun stop() = withContext(confined) {
        supervisor?.cancel()
        supervisor = null
        client?.close()
        client = null
        setLink(LinkState.Idle)
    }

    /** Ends the session for good: nothing more runs. */
    fun close() {
        client?.close()
        scope.cancel()
    }

    /** Start measuring again, as for a run with AirDrop on after one with it off. */
    suspend fun resetResponseTimes() = withContext(confined) { times = ResponseTimes() }

    private fun update(change: (SessionState) -> SessionState) {
        flow.value = change(flow.value)
    }

    private fun setLink(link: LinkState) = update { it.copy(link = link) }

    private suspend fun supervise() {
        var attempt = 0
        var failingSince: Long? = null
        while (scope.isActive) {
            setLink(if (attempt == 0) LinkState.Connecting else LinkState.Reconnecting)
            try {
                connectOnce(attempt)
                attempt = 0
                failingSince = null
                consume()
            } catch (failure: RemoteError) {
                when (failure.reason) {
                    "unknown_device", "signature_invalid" -> return fail(failure.reason, Trouble.Forgotten)
                    "unsupported_version" -> {
                        val versions = failure.data["host_versions"]?.array?.mapNotNull { it.string } ?: emptyList()
                        return fail(failure.reason, Trouble.versions(versions))
                    }
                    else -> failingSince = failingSince ?: System.nanoTime()
                }
            } catch (failure: TransportFailure) {
                when {
                    // No shared major version at all: this phone offers only 1.x (spec 2).
                    failure is TransportFailure.Closed && failure.code == 4002 ->
                        return fail("unsupported_version", Trouble.UpdateSpak(emptyList()))
                    failure is TransportFailure.WrongKey -> return fail("wrong_key", Trouble.OtherComputer)
                    failure is TransportFailure.LocalNetworkDenied -> {
                        failingSince = failingSince ?: System.nanoTime()
                        update { it.copy(trouble = Trouble.LocalNetworkDenied) } // keep trying: it may be allowed in Settings
                    }
                    else -> failingSince = failingSince ?: System.nanoTime()
                }
            } catch (failure: kotlinx.coroutines.CancellationException) {
                throw failure
            } catch (_: Exception) {
                failingSince = failingSince ?: System.nanoTime()
            }
            if (!scope.isActive) return
            attempt += 1
            val since = failingSince
            if (since != null && (System.nanoTime() - since).nanoseconds >= PATIENCE && state.trouble == null) {
                update { it.copy(trouble = Trouble.Unreachable) }
            }
            setLink(LinkState.Reconnecting)
            val wait = CompletableDeferred<Unit>()
            nap = wait
            withTimeoutOrNull(backoff(attempt)) { wait.await() }
            nap = null
        }
    }

    private fun fail(reason: String, trouble: Trouble) {
        update { it.copy(trouble = trouble, link = LinkState.Failed(reason)) }
    }

    /**
     * The app is back on the screen (TR6: reconnected within a second). A connection that went
     * quiet while the app was away is dropped and made again at once; a reconnect waiting out its
     * backoff tries now.
     */
    suspend fun wake() = withContext(confined) {
        nap?.complete(Unit)
        if (state.link is LinkState.Connected && client != null && silentFor() > 2.5) client?.close()
    }

    private suspend fun connectOnce(attempt: Int) {
        val transport = connector(attempt)
        val client = RemoteClient(transport)
        client.start()
        val hello = try {
            client.sayHello(app, timeout = CONNECT_TIMEOUT)
        } catch (failure: Exception) {
            client.close()
            throw failure
        }
        try {
            when (val c = credentials) {
                Credentials.Demo -> client.pair(
                    Base64Url.encode(ByteArray(16)), Base64Url.encode(ByteArray(32)), SoftwareSigner.generate(),
                    name = "Demo phone", model = "demo",
                )
                is Credentials.Paired -> client.authenticate(c.host.pin, c.signer)
            }
            val capabilities = hello.capabilities.toSet()
            val extra = if ("mixer/1" in capabilities) extraTopics.toList() else emptyList()
            val snapshot = client.subscribe(topics(capabilities) + extra)
            this.client = client
            update { it.copy(host = hello.host, capabilities = capabilities) }
            apply(snapshot)
            readExtras(client)
            update { it.copy(trouble = null) }
            setLink(LinkState.Connected(busy = false))
        } catch (failure: Exception) {
            client.close()
            throw failure
        }
    }

    private suspend fun consume() {
        val client = client ?: return
        val watchdog = scope.launch {
            while (isActive) {
                delay(1.seconds)
                if (silentFor() > 6.0) {
                    client.close()
                    return@launch
                }
            }
        }
        try {
            for (message in client.incoming) {
                when (message) {
                    is Incoming.EventArrived -> {
                        val seq = message.event.seq
                        when {
                            // Sent before the snapshot that is applied, so already in it: a snapshot
                            // names the newest seq sent, and events up to it are ignored (spec 8.2).
                            // Taking them for gaps asked for snapshot after snapshot while events
                            // kept coming, as meters do 20 times a second once a track is armed.
                            seq <= state.seq -> Unit
                            seq == state.seq + 1 -> {
                                update { it.copy(seq = seq) }
                                apply(message.event)
                            }
                            else -> {
                                resnapshots += 1
                                resnapshot()
                            }
                        }
                    }
                    is Incoming.HeartbeatArrived -> {
                        val beat = message.heartbeat
                        update { it.copy(hostTime = beat.t, receivedAt = System.nanoTime()) }
                        val link = state.link
                        if (link is LinkState.Connected && link.busy != beat.busy) setLink(LinkState.Connected(beat.busy))
                        if (beat.seq > state.seq) resnapshot()
                    }
                    is Incoming.Closed -> break
                }
            }
        } finally {
            watchdog.cancel()
            this.client = null
        }
    }

    private fun silentFor(): Double = (System.nanoTime() - state.receivedAt) / 1e9

    private suspend fun resnapshot() {
        val client = client ?: return
        val snapshot = runCatching { client.call("session.snapshot", Json.Obj(emptyMap()), decode = Snapshot::from) }.getOrNull() ?: return
        apply(snapshot)
        readExtras(client)
    }

    /** The mixer, the tab and the rest are not in the snapshot: read once, then followed by their topics. */
    private suspend fun readExtras(client: RemoteClient) {
        val capabilities = state.capabilities
        for ((capability, method) in EXTRAS) {
            if (capability in capabilities) {
                runCatching { client.call(method) }.getOrNull()?.let(::applyResult)
            } else {
                update {
                    when (capability) {
                        "mixer/1" -> it.copy(mixer = null)
                        "view/1" -> it.copy(view = null)
                        "trainer/1" -> it.copy(trainer = null)
                        "chat/1" -> it.copy(chat = null)
                        "routing/1" -> it.copy(routing = null)
                        "tab/1" -> it.copy(tab = null)
                        else -> it
                    }
                }
            }
        }
    }

    /** Follows a topic while a screen shows it (the Mixer's meters), or stops. */
    suspend fun watch(topic: String, on: Boolean) = withContext(confined) {
        if (on) extraTopics.add(topic) else extraTopics.remove(topic)
        if (!on && topic == "mixer_meters") update { it.copy(stripMeters = emptyMap()) }
        val client = client ?: return@withContext
        if ("mixer/1" !in state.capabilities) return@withContext
        val params = jsonObject { put("topics", Json.strings(listOf(topic))) }
        if (on) {
            runCatching { client.call("session.subscribe", params, decode = Snapshot::from) }.getOrNull()?.let(::apply)
        } else {
            runCatching { client.call("session.unsubscribe", params) }
        }
    }

    private fun apply(snapshot: Snapshot) = update {
        it.copy(
            seq = snapshot.seq, hostTime = snapshot.t, receivedAt = System.nanoTime(), project = snapshot.project,
            transport = snapshot.transport, positionAt = System.nanoTime(), record = snapshot.record,
            tracks = snapshot.tracks, markers = snapshot.markers, takes = snapshot.takes, undo = snapshot.undo,
        )
    }

    private fun <T> decode(value: Json?, path: String, read: (JsonReader) -> T): T? =
        value?.let { runCatching { read(JsonReader(it, path)) }.getOrNull() }

    private fun <T> decodeItems(value: Json?, path: String, read: (JsonReader) -> T): List<T>? =
        value?.let { runCatching { decodeList(it, path, read) }.getOrNull() }

    private fun apply(event: Event) {
        val data = event.data
        update { it.copy(hostTime = event.t, receivedAt = System.nanoTime()) }
        update { s ->
            when (event.topic) {
                "transport" -> decode(data, "transport", TransportState::from)?.let { s.copy(transport = it, positionAt = System.nanoTime()) }
                "position" -> {
                    val position = decode(data["position"], "position", Position::from)
                    val play = data["state"]?.string?.let { text -> PlayState.entries.firstOrNull { it.wire == text } }
                    val transport = s.transport
                    if (position != null && play != null && transport != null) {
                        s.copy(transport = transport.copy(position = position, state = play), positionAt = System.nanoTime())
                    } else null
                }
                "record" -> decode(data, "record", RecordState::from)?.let { s.copy(record = it) }
                "tracks" -> decodeItems(data["tracks"] ?: Json.Arr(emptyList()), "tracks", Track::from)?.let { s.copy(tracks = it) }
                "markers" -> decodeItems(data["markers"] ?: Json.Arr(emptyList()), "markers", Marker::from)?.let { s.copy(markers = it) }
                "takes" -> decodeItems(data["takes"] ?: Json.Arr(emptyList()), "takes", Take::from)?.let { s.copy(takes = it) }
                "undo" -> decode(data, "undo", UndoState::from)?.let { s.copy(undo = it) }
                "project" -> decode(data, "project", ProjectState::from)?.let { s.copy(project = it) }
                "meters" -> decodeItems(data["levels"] ?: Json.Arr(emptyList()), "levels", MeterLevel::from)
                    ?.let { levels -> s.copy(meters = levels.associate { it.trackId to it.peak }) }
                "mixer" -> decode(data, "mixer", MixerState::from)?.let { s.copy(mixer = it) }
                "mixer_meters" -> decodeItems(data["levels"] ?: Json.Arr(emptyList()), "levels", StripLevel::from)
                    ?.let { levels -> s.copy(stripMeters = levels.associate { it.stripId to it.peak }) }
                "tab" -> data["tab"]?.let { value ->
                    s.copy(tab = if (value == Json.Null) null else decode(value, "tab", TabState::from))
                }
                "routing" -> decode(data, "routing", RoutingState::from)?.let { s.copy(routing = it) }
                "chat" -> decode(data, "chat", ChatState::from)?.let { s.copy(chat = it) }
                "view" -> decode(data, "view", ViewState::from)?.let { s.copy(view = it) }
                "trainer" -> decode(data, "trainer", TrainerState::from)?.let { s.copy(trainer = it) }
                else -> null
            } ?: s
        }
    }

    /** Applies the confirmed state a verb returned (spec 5.3). */
    private fun applyResult(result: Json) = update { start ->
        var s = start
        decode(result["transport"], "transport", TransportState::from)?.let { s = s.copy(transport = it, positionAt = System.nanoTime()) }
        decode(result["record"], "record", RecordState::from)?.let { s = s.copy(record = it) }
        decodeItems(result["tracks"], "tracks", Track::from)?.let { s = s.copy(tracks = it) }
        decodeItems(result["markers"], "markers", Marker::from)?.let { s = s.copy(markers = it) }
        decode(result["undo"], "undo", UndoState::from)?.let { s = s.copy(undo = it) }
        decode(result["project"], "project", ProjectState::from)?.let { s = s.copy(project = it) }
        decode(result["mixer"], "mixer", MixerState::from)?.let { s = s.copy(mixer = it) }
        decode(result["strip"], "strip", Strip::from)?.let { strip ->
            val mixer = s.mixer
            if (mixer != null && mixer.strips.any { it.id == strip.id }) {
                s = s.copy(mixer = mixer.copy(strips = mixer.strips.map { if (it.id == strip.id) strip else it }))
            }
        }
        result["tab"]?.let { value -> s = s.copy(tab = if (value == Json.Null) null else decode(value, "tab", TabState::from)) }
        decode(result["routing"], "routing", RoutingState::from)?.let { s = s.copy(routing = it) }
        decode(result["chat"], "chat", ChatState::from)?.let { s = s.copy(chat = it) }
        decode(result["view"], "view", ViewState::from)?.let { s = s.copy(view = it) }
        decode(result["trainer"], "trainer", TrainerState::from)?.let { s = s.copy(trainer = it) }
        s
    }

    private suspend fun waitForConnection(timeout: Duration): Boolean {
        val deadline = System.nanoTime() + timeout.inWholeNanoseconds
        while (System.nanoTime() < deadline) {
            if (state.link is LinkState.Connected && client != null) return true
            if (state.link is LinkState.Failed) return false
            delay(50.milliseconds)
        }
        return state.link is LinkState.Connected && client != null
    }

    /**
     * Runs a verb on the computer. A change gets a key once, and is resent with it after a drop
     * until the computer answers or [patience] runs out.
     */
    suspend fun perform(method: String, params: Json = Json.Obj(emptyMap()), patience: Duration = 10.seconds): Json =
        withContext(confined) {
            val fields = params.obj
            val sent = if (method !in READS && fields != null && "key" !in fields) {
                Json.Obj(fields + ("key" to Json.Str(UUID.randomUUID().toString().lowercase())))
            } else params
            val deadline = System.nanoTime() + patience.inWholeNanoseconds
            while (true) {
                val left = (deadline - System.nanoTime()).nanoseconds
                if (!waitForConnection(left)) throw TransportFailure.Unreachable("Tabber Studio is not connected.")
                val client = client ?: throw TransportFailure.Unreachable("Tabber Studio is not connected.")
                try {
                    val began = System.nanoTime()
                    val result = client.call(method, sent)
                    applyResult(result)
                    if (ResponseTimes.counts(method)) times = times.adding((System.nanoTime() - began).nanoseconds)
                    return@withContext result
                } catch (failure: RemoteError) {
                    throw failure
                } catch (failure: kotlinx.coroutines.CancellationException) {
                    throw failure
                } catch (failure: Exception) {
                    if (System.nanoTime() >= deadline) throw failure
                    delay(100.milliseconds)
                }
            }
            @Suppress("UNREACHABLE_CODE")
            Json.Null
        }

    companion object {
        val READS = setOf(
            "takes.list", "session.snapshot", "mixer.state", "tab.state", "routing.state", "chat.state", "view.state", "trainer.state",
        )
        val TOPICS = listOf("transport", "position", "record", "tracks", "markers", "takes", "undo", "project", "meters")

        /** How long reconnecting may fail before the app is told the computer is unreachable. */
        val PATIENCE: Duration = 4.seconds

        /** How long a dead address may hold up a reconnect (the hello's timeout). */
        val CONNECT_TIMEOUT: Duration = 3.seconds

        private val EXTRAS = listOf(
            "mixer/1" to "mixer.state", "view/1" to "view.state", "trainer/1" to "trainer.state",
            "chat/1" to "chat.state", "routing/1" to "routing.state", "tab/1" to "tab.state",
        )

        /** The topics to follow on a computer with these capabilities: a 1.0 host refuses a topic it does not know. */
        fun topics(capabilities: Set<String>): List<String> = TOPICS + listOf(
            "mixer/1" to "mixer", "tab/1" to "tab", "routing/1" to "routing", "chat/1" to "chat",
            "view/1" to "view", "trainer/1" to "trainer",
        ).filter { it.first in capabilities }.map { it.second }

        private fun backoff(attempt: Int): Duration = minOf(2000L, 250L * (1L shl minOf(attempt - 1, 3))).milliseconds
    }
}
