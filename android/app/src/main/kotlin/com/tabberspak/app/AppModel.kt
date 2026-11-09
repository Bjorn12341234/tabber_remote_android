package com.tabberspak.app

import android.content.Context
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.tabberspak.remotekit.AppInfo
import com.tabberspak.remotekit.BarBeat
import com.tabberspak.remotekit.ChatPlan
import com.tabberspak.remotekit.DemoHost
import com.tabberspak.remotekit.DeviceSigner
import com.tabberspak.remotekit.Json
import com.tabberspak.remotekit.JsonReader
import com.tabberspak.remotekit.KnownHost
import com.tabberspak.remotekit.LinkState
import com.tabberspak.remotekit.Marker
import com.tabberspak.remotekit.NewTrackKind
import com.tabberspak.remotekit.OkHttpTransport
import com.tabberspak.remotekit.PairingLink
import com.tabberspak.remotekit.PlayState
import com.tabberspak.remotekit.PluginRow
import com.tabberspak.remotekit.PluginPage
import com.tabberspak.remotekit.Insert
import com.tabberspak.remotekit.RacingTransport
import com.tabberspak.remotekit.RemoteClient
import com.tabberspak.remotekit.RemoteError
import com.tabberspak.remotekit.RemoteSession
import com.tabberspak.remotekit.ResponseTimes
import com.tabberspak.remotekit.Route
import com.tabberspak.remotekit.RouteBook
import com.tabberspak.remotekit.RoutingSend
import com.tabberspak.remotekit.RoutingSource
import com.tabberspak.remotekit.SessionState
import com.tabberspak.remotekit.Strip
import com.tabberspak.remotekit.Take
import com.tabberspak.remotekit.Track
import com.tabberspak.remotekit.TransportFailure
import com.tabberspak.remotekit.jsonObject
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.math.roundToLong
import kotlin.time.Duration.Companion.seconds

/**
 * The app's one session, on the main thread for Compose, as the iPhone's AppModel: the computer's
 * confirmed state, what each control is waiting for, the take loop, and every verb the screens
 * send. Its properties are Compose state, so the screens redraw when they change.
 */
class AppModel(private val context: Context, private val scope: CoroutineScope = MainScope()) {
    private val prefs = Prefs(context)
    private val hosts = HostStore(prefs)
    private val discovery = Discovery(context)

    var state by mutableStateOf(SessionState())
        private set

    /** What the transport bar shows. It changes only when one of these does (principle 7). */
    var bar by mutableStateOf(TransportSummary())
        private set

    data class TransportSummary(
        val connected: Boolean = false,
        val recording: Boolean = false,
        val playing: Boolean = false,
        val armed: List<String> = emptyList(),
        val hasTake: Boolean = false,
        val hasSession: Boolean = false,
        /** The readout's bar and beat; null while recording, when the take's time shows instead. */
        val position: BarBeat? = null,
        /** When the take's time started, on this phone's clock (System.currentTimeMillis). */
        val recordingSince: Long? = null,
        val countingIn: Boolean = false,
    )

    var problem by mutableStateOf<String?>(null)
        private set

    /** Controls whose command is on its way: they look pending until confirmed (principle 3). */
    var pending by mutableStateOf(setOf<String>())
        private set

    /** The take the newest Stop made: the take card shows it (TR8). */
    var lastTake by mutableStateOf<Take?>(null)

    enum class Feedback { TAP, RECORD, STOP, GO_AGAIN, DISCARD, FAILURE }

    /** Bumped on every confirmed action, for haptics. */
    var feedback by mutableStateOf(Feedback.TAP to 0)
        private set

    var keepAwake: Boolean
        get() = keepAwakeState
        set(value) {
            keepAwakeState = value
            prefs.set("keepAwake", value)
        }
    private var keepAwakeState by mutableStateOf(prefs.bool("keepAwake", default = true))

    var isDemo by mutableStateOf(false)
        private set
    var known by mutableStateOf(hosts.load())
        private set

    private var session: RemoteSession? = null
    /** The demo computer, while the demo runs: closed when it is replaced, or its playhead would tick on. */
    private var demoHost: DemoHost? = null
    private var listener: Job? = null
    /** The paired computer's addresses, and Bonjour when they all fail (TR6). */
    private var book: RouteBook? = null

    /** Pairing: what the phone is doing, the six digits to compare, or why it stopped. */
    sealed interface Pairing {
        data object Idle : Pairing
        data class Working(val name: String) : Pairing
        data class Code(val name: String, val code: String) : Pairing
        data class Failed(val message: String) : Pairing
    }

    var pairing by mutableStateOf<Pairing>(Pairing.Idle)
        private set

    /** The Computer sheet, opened from the computer's name at the top of each screen. */
    var showingComputer by mutableStateOf(false)

    /** Go to: the start or a marker, from the transport's position. */
    var choosingPlace by mutableStateOf(false)

    enum class Screen { TRACKS, TAB, MIXER, TUNER, CHAT }

    var screen by mutableStateOf(Screen.TRACKS)

    /** After a discard or a new track: Undo for five seconds, naming the step it undoes (spec 9). */
    data class UndoOffer(val stepId: String, val text: String, val until: Long)

    var undoOffer by mutableStateOf<UndoOffer?>(null)
        private set

    /** The track or bus just added from this phone, for the screens to show it. */
    var addedTrackId by mutableStateOf<String?>(null)
        private set
    var addedBusId by mutableStateOf<String?>(null)
        private set

    private var demoSpeaks = RemoteClient.PROTOCOL_VERSIONS
    private var demoName = DemoHost.NAME
    private var demoOnlyAudio = false

    val app = AppInfo(version = BuildConfig.VERSION_NAME, build = BuildConfig.VERSION_CODE.toString())

    /**
     * Launch options for tests, screenshots and scripts, as the iPhone's launch arguments:
     * `reset` (a fresh install), `known_host` (paired with that computer, JSON), `demo`,
     * `demo_speaks`, `demo_name`, `demo_only_audio`, `screen`, `pair_link`.
     */
    fun launch(extras: Bundle?) {
        extras ?: return
        if (extras.getBoolean("reset")) {
            hosts.clear()
            prefs.remove("explainedLocalNetwork")
            prefs.remove("tabInput")
            forget()
            freshScreens()
        }
        extras.getString("known_host")?.let { text ->
            runCatching { KnownHost.from(JsonReader(Json.parse(text))) }.getOrNull()?.let {
                hosts.save(it)
                known = it
            }
        }
        extras.getString("screen")?.let { name -> Screen.entries.firstOrNull { it.name.equals(name, ignoreCase = true) }?.let { screen = it } }
        extras.getString("demo_name")?.let { demoName = it }
        demoOnlyAudio = extras.getBoolean("demo_only_audio")
        val pairLink = extras.getString("pair_link")?.let(PairingLink::parse)
        when {
            pairLink != null -> scope.launch { pair(pairLink) }
            extras.getBoolean("demo") -> startDemo()
            extras.getString("demo_speaks") != null -> startDemo(listOf(extras.getString("demo_speaks")!!))
            // A known computer starts its session, after a reset too (the iPhone's -reset -known-host).
            extras.containsKey("known_host") -> known?.let { host -> signer()?.let { start(host, it) } }
            extras.getBoolean("reset") -> Unit
        }
    }

    /**
     * What a fresh install shows, for `reset`. On the iPhone each launch is a new process; here the
     * model outlives its activity (and the UI tests share one process), so a reset clears what is
     * on screen too: the Tracks screen, with no sheet, card or message left open from before.
     */
    private fun freshScreens() {
        screen = Screen.TRACKS
        showingComputer = false
        choosingPlace = false
        lastTake = null
        problem = null
        undoOffer = null
        pairing = Pairing.Idle
        pending = emptySet()
        addedTrackId = null
        addedBusId = null
        wanted.clear()
        edits.clear()
        demoName = DemoHost.NAME
        demoSpeaks = RemoteClient.PROTOCOL_VERSIONS
    }

    private fun signer(): DeviceSigner? = runCatching { KeystoreSigner.loadOrCreate() }.getOrNull()

    fun startDemo(speaks: List<String> = RemoteClient.PROTOCOL_VERSIONS) {
        isDemo = true
        demoSpeaks = speaks
        book = null
        val host = DemoHost(speaks = speaks, computerName = demoName, onlyAudio = demoOnlyAudio)
        attach(RemoteSession(RemoteSession.Credentials.Demo, app) { host.connect() })
        demoHost = host
    }

    /** Start over after a stop (the Update cards' Try again). */
    fun retry() {
        if (isDemo) {
            startDemo(demoSpeaks)
        } else {
            val host = known ?: return
            signer()?.let { start(host, it) }
        }
    }

    /** Back on the screen: reconnect at once if the line went quiet (TR6, under a second). */
    fun wake() {
        val session = session ?: return
        scope.launch { session.wake() }
    }

    /** Pairs from the QR code's link, as the phone's camera hands it over. */
    suspend fun pair(link: PairingLink) {
        problem = null
        pairing = Pairing.Working(link.name)
        val signer = signer() ?: run {
            pairing = Pairing.Failed("This phone could not make its key. Restart Tabber Spak and scan again.")
            return
        }
        // Every address in the code at once; the first to answer pairs.
        val book = RouteBook(link.routes, link.hostId)
        val client = RemoteClient(RacingTransport(link.routes, { OkHttpTransport(it, link.pin) }, { book.use(it) }))
        client.start()
        try {
            withContext(Dispatchers.IO) {
                client.sayHello(app, timeout = 6.seconds)
                client.pair(link.token, link.pin, signer, name = deviceName(), model = deviceModel())
            }
            client.close()
            val routes = book.connected() ?: link.routes
            val host = KnownHost(link.hostId, link.name, link.pin, routes)
            hosts.save(host)
            known = host
            isDemo = false
            pairing = Pairing.Idle
            start(host, signer)
        } catch (failure: Exception) {
            client.close()
            pairing = Pairing.Failed(explainPairing(failure, link.name))
        }
    }

    /**
     * Pairs without the QR code (spec 4.4): connect to a computer Bonjour found, show the six
     * digits Tabber Studio shows too, and wait for Allow there.
     */
    suspend fun pairWithCode(found: FoundComputer) {
        problem = null
        val route = found.route ?: run {
            pairing = Pairing.Failed("Can't reach ${found.name} yet. Wait a moment, then try again.")
            return
        }
        pairing = Pairing.Working(found.name)
        val signer = signer() ?: run {
            pairing = Pairing.Failed("This phone could not make its key. Restart Tabber Spak and try again.")
            return
        }
        val transport = OkHttpTransport(route, pin = null)
        val client = RemoteClient(transport)
        client.start()
        try {
            val hello = withContext(Dispatchers.IO) { client.sayHello(app, timeout = 6.seconds) }
            if ("pair.code/1" !in hello.capabilities) {
                client.close()
                pairing = Pairing.Failed(
                    "In Tabber Studio on ${found.name}, open Preferences › Remote and choose Pair. Then try again here, or scan its code with your camera.",
                )
                return
            }
            val pin = transport.observedPin ?: throw TransportFailure.Unreachable("no key")
            pairing = Pairing.Code(found.name, client.pairingCode(pin, signer))
            withContext(Dispatchers.IO) { client.pairWithCode(pin, signer, name = deviceName(), model = deviceModel()) }
            client.close()
            val host = KnownHost(hello.host.id, hello.host.name, pin, listOf(route))
            hosts.save(host)
            known = host
            isDemo = false
            pairing = Pairing.Idle
            start(host, signer)
        } catch (failure: Exception) {
            client.close()
            pairing = Pairing.Failed(explainPairing(failure, found.name))
        }
    }

    fun clearPairing() {
        pairing = Pairing.Idle
    }

    private fun start(host: KnownHost, signer: DeviceSigner) {
        val book = RouteBook(host.routes, host.id) { discovery.lookup(it) }
        this.book = book
        // Every remembered address at once, so away from the Wi-Fi the phone reaches the
        // computer's Tailscale address without waiting out the local ones first.
        attach(RemoteSession(RemoteSession.Credentials.Paired(host, signer), app) { attempt ->
            RacingTransport(book.candidates(attempt), { OkHttpTransport(it, host.pin) }, { book.use(it) })
        })
    }

    /** The address that connected goes first; a computer that moved is found there next time. */
    private suspend fun remember(book: RouteBook) {
        val routes = book.connected() ?: return
        val host = known ?: return
        if (this.book !== book) return
        val moved = host.copy(routes = routes)
        known = moved
        hosts.save(moved)
    }

    private fun attach(next: RemoteSession) {
        listener?.cancel()
        session?.let { old -> scope.launch { old.stop(); old.close() } }
        demoHost?.close()
        demoHost = null
        forgetComputerState()
        session = next
        listener = scope.launch {
            next.start()
            var wasConnected = false
            next.updates.collect { update ->
                if (update.link is LinkState.Connected) {
                    if (!wasConnected) book?.let { remember(it) }
                    wasConnected = true
                } else {
                    wasConnected = false
                }
                state = update
                summarize(update)
            }
        }
    }

    private fun summarize(update: SessionState) {
        val seconds = update.recordedSeconds
        var since: Long? = null
        var countingIn = false
        if (seconds != null) {
            if (seconds >= 0) {
                val now = System.currentTimeMillis() - (seconds * 1000).roundToLong()
                val kept = bar.recordingSince
                since = if (kept != null && kotlin.math.abs(kept - now) < 500) kept else now // steady, so the timer never jumps
            } else {
                countingIn = true
            }
        }
        val summary = TransportSummary(
            connected = update.link is LinkState.Connected,
            recording = update.record.recording,
            playing = update.transport?.state == PlayState.PLAYING,
            armed = update.tracks.filter { it.armed }.map { it.name },
            hasTake = update.takes.isNotEmpty(),
            hasSession = update.transport != null,
            position = if (update.record.recording) null else update.transport?.position?.barBeat,
            recordingSince = since,
            countingIn = countingIn,
        )
        if (summary != bar) bar = summary
    }

    /** Back from the demo to the paired computer, if there is one. */
    fun leaveDemo() {
        isDemo = false
        detach()
        known?.let { host -> signer()?.let { start(host, it) } }
    }

    fun forget() {
        hosts.clear()
        known = null
        isDemo = false
        book = null
        detach()
    }

    private fun detach() {
        listener?.cancel()
        session?.let { old -> scope.launch { old.stop(); old.close() } }
        demoHost?.close()
        demoHost = null
        forgetComputerState()
        session = null
        state = SessionState()
        bar = TransportSummary()
    }

    /**
     * What belonged to the computer just left (the demo left, a computer forgotten or paired): its
     * take card and Undo offer, which would aim at a take or a step the next computer does not
     * have, and its plug-in list, as the iPhone's forgetComputerState.
     */
    private fun forgetComputerState() {
        lastTake = null
        undoOffer = null
        catalog = emptyList()
        loadingPlugin = null
        pluginNotice = null
    }

    val isConnected: Boolean get() = state.link is LinkState.Connected

    /** How long the computer took to answer this phone's taps (the Computer sheet; TR7's gate). */
    fun responseTimes(): ResponseTimes = session?.responseTimes ?: ResponseTimes()

    /** Measure from now on, as for a run with AirDrop on after one with it off. Returns once the times are forgotten. */
    suspend fun startResponseTimesAgain() {
        session?.resetResponseTimes()
    }

    /** The computer's name for the screen: as it says, as remembered, or in general words. */
    val computerName: String get() = state.host?.name ?: known?.name ?: if (isDemo) DemoHost.NAME else "your computer"

    /**
     * Runs a verb for a control: pending until the computer confirms, then a haptic; a refusal is
     * shown in words (spec 10).
     */
    fun act(control: String, method: String, params: Json = Json.Obj(emptyMap()), feel: Feedback = Feedback.TAP, then: ((Json) -> Unit)? = null) {
        val session = session ?: return
        if (control in pending) return
        pending = pending + control
        scope.launch {
            try {
                val result = session.perform(method, params)
                pending = pending - control
                problem = null
                feedback = feel to feedback.second + 1
                then?.invoke(result)
            } catch (failure: kotlinx.coroutines.CancellationException) {
                pending = pending - control
                throw failure
            } catch (failure: Exception) {
                pending = pending - control
                problem = explain(failure)
                feedback = Feedback.FAILURE to feedback.second + 1
            }
        }
    }

    // The take loop (plan: The app, screens 1 and 2)

    val armedIds: List<String> get() = state.tracks.filter { it.armed }.map { it.id }

    fun record() {
        lastTake = null // recording again keeps the take
        when {
            state.record.recording -> stop()
            armedIds.isNotEmpty() -> act("record", "transport.record", jsonObject { put("armed_track_ids", Json.strings(armedIds)) }, Feedback.RECORD)
            else -> {
                problem = "Arm a track first: tap ○ on the track you want to record on."
                feedback = Feedback.FAILURE to feedback.second + 1
            }
        }
    }

    fun clearProblem() {
        problem = null
    }

    /** Once: Tabber Spak is a remote, so Play is heard on the computer. */
    private fun tellWhereSoundPlays() {
        if (isDemo || prefs.bool("toldWhereSoundPlays")) return
        prefs.set("toldWhereSoundPlays", true)
        problem = "The sound plays on $computerName, not on this phone."
    }

    fun stop() {
        act("stop", "transport.stop", feel = Feedback.STOP) { result ->
            val take = result["take"]
            if (take != null && take != Json.Null) runCatching { Take.from(JsonReader(take)) }.getOrNull()?.let { lastTake = it }
        }
    }

    fun playOrStop() {
        if (state.transport?.state == PlayState.PLAYING) stop() else act("play", "transport.play") { tellWhereSoundPlays() }
    }

    fun keep() {
        lastTake = null
    }

    /** Delete a take: one tap, then Undo for five seconds. Tabber Studio keeps the audio file (spec 9). */
    fun delete(take: Take) {
        act("delete-${take.id}", "takes.discard", jsonObject { put("take_id", take.id) }, Feedback.DISCARD) { result ->
            if (lastTake?.id == take.id) lastTake = null
            offerUndo(result, "${take.name} deleted")
        }
    }

    /** Undo for five seconds, for the step a verb's result names. */
    private fun offerUndo(result: Json, text: String) {
        val step = result["undo"]?.get("undo")?.get("id")?.string ?: return
        val offer = UndoOffer(step, text, System.currentTimeMillis() + 5000)
        undoOffer = offer
        scope.launch {
            delay(5.seconds)
            if (undoOffer == offer) undoOffer = null
        }
    }

    fun undoOffered() {
        val offer = undoOffer ?: return
        undoOffer = null
        act("undo", "edit.undo", jsonObject { put("expect", offer.stepId) }, Feedback.GO_AGAIN)
    }

    // Tracks (the Tracks screen: choose, arm, listen alone, mute)

    val mixerAvailable: Boolean get() = "mixer/1" in state.capabilities
    val tabAvailable: Boolean get() = "tab/1" in state.capabilities

    fun select(track: Track) {
        if (track.selected) return
        act("select-${track.id}", "tracks.select", jsonObject { put("track_id", track.id) })
    }

    fun arm(track: Track) {
        act("arm-${track.id}", "tracks.arm", jsonObject { put("track_id", track.id); put("armed", !track.armed) })
    }

    /** Tabber Studio's "+ Add Track", on a computer that offers it to phones (tracks.add/1). */
    val addTrackAvailable: Boolean get() = "tracks.add/1" in state.capabilities

    fun addTrack(kind: NewTrackKind) {
        act("add-track", "tracks.add", jsonObject { put("kind", kind.wire) }) { result ->
            val track = result["track"]?.let { runCatching { Track.from(JsonReader(it)) }.getOrNull() } ?: return@act
            addedTrackId = track.id
            offerUndo(result, "${track.name} added")
        }
    }

    fun strip(id: String): Strip? = state.mixer?.strips?.firstOrNull { it.id == id }

    fun solo(id: String) {
        act("solo-$id", "mixer.set_solo", jsonObject { put("strip_id", id); put("soloed", !(strip(id)?.soloed ?: false)) })
    }

    fun mute(id: String) {
        act("mute-$id", "mixer.set_mute", jsonObject { put("strip_id", id); put("muted", !(strip(id)?.muted ?: false)) })
    }

    /** Whether a strip is heard now: not muted, and soloed if anything is. */
    fun audible(id: String): Boolean {
        val mixer = state.mixer ?: return true
        val strip = strip(id) ?: return true
        val soloing = mixer.strips.any { it.soloed }
        return !strip.muted && (!soloing || strip.soloed)
    }

    // Faders and pan: the newest value wins; at most one change in flight, so a drag stays inside
    // the computer's rate limit (spec 6: 20 a second).
    private val wanted = LinkedHashMap<String, Pair<String, Json>>()
    private var draining = false

    fun setVolume(id: String, volume: Double) =
        send("volume-$id", "mixer.set_volume", jsonObject { put("strip_id", id); put("volume", Math.round(volume * 1000) / 1000.0) })

    fun setPan(id: String, pan: Double) =
        send("pan-$id", "mixer.set_pan", jsonObject { put("strip_id", id); put("pan", Math.round(pan * 1000) / 1000.0) })

    private fun send(key: String, method: String, params: Json) {
        wanted[key] = method to params
        val session = session ?: return
        if (draining) return
        draining = true
        scope.launch {
            while (wanted.isNotEmpty()) {
                val first = wanted.keys.first()
                val (nextMethod, nextParams) = wanted.remove(first)!!
                runCatching { session.perform(nextMethod, nextParams, patience = 2.seconds) }
                delay(60)
            }
            draining = false
        }
    }

    // The computer's view (view/1): Studio's own Arrange, Tab, Piano Roll and Split.

    val viewAvailable: Boolean get() = "view/1" in state.capabilities

    fun showEditor(editor: String) = act("view-$editor", "view.set", jsonObject { put("editor", editor) })

    fun toggleSplit() = act("view-split", "view.set", jsonObject { put("split", !(state.view?.split ?: false)) })

    /** Tabber Studio's mixer "+ Bus", on a computer that offers it to phones (mixer.add_bus/1). */
    val addBusAvailable: Boolean get() = "mixer.add_bus/1" in state.capabilities

    fun addBus(name: String) {
        act("add-bus", "mixer.add_bus", jsonObject { put("name", name) }) { result ->
            result["strip"]?.let { runCatching { Strip.from(JsonReader(it)) }.getOrNull() }?.let { addedBusId = it.id }
        }
    }

    /** Tabber Studio's "MIDI part" card, on a computer that offers it to phones (view.part/1). */
    val partAvailable: Boolean get() = "view.part/1" in state.capabilities

    fun showPart(trackId: String, shows: String) =
        act("show-part", "view.show_part", jsonObject { put("track_id", trackId); put("as", shows) })

    /** Tabber Studio's Speed Trainer, on a computer that offers it to phones (trainer/1). */
    val trainerAvailable: Boolean get() = "trainer/1" in state.capabilities

    fun toggleTrainer() = act("trainer", "trainer.set", jsonObject { put("enabled", !(state.trainer?.enabled ?: false)) })

    /** One of the trainer's fields: "start", "step" or "target", in percent. */
    fun setTrainer(field: String, percent: Int) = act("trainer-$field", "trainer.set", jsonObject { put(field, percent) })

    /**
     * One step of a held Previous or Next: the next beat written, or once held a while the next
     * bar, adding none. False at the song's first or last beat, which ends the hold.
     */
    suspend fun fastStep(by: Int, bars: Boolean): Boolean {
        val session = session ?: return false
        val tab = state.tab ?: return false
        val target = (if (bars) tab.barStep(by) else tab.neighbour(by)) ?: return false
        return try {
            session.perform(
                "tab.set_cursor",
                jsonObject { put("bar", target.bar); put("beat", target.beat); put("string", target.string) },
                patience = 2.seconds,
            )
            true
        } catch (failure: Exception) {
            problem = explain(failure)
            false
        }
    }

    // Chat (chat/1): words to the computer's chat, a plan back, Execute to run it.

    val chatAvailable: Boolean get() = "chat/1" in state.capabilities

    fun chatSend(text: String) = act("chat-send", "chat.send", jsonObject { put("text", text.take(2000)) })
    fun chatConfirm(plan: ChatPlan) = act("chat-execute", "chat.confirm", jsonObject { put("plan_id", plan.id) }, Feedback.GO_AGAIN)
    fun chatCancel(plan: ChatPlan) = act("chat-cancel", "chat.cancel", jsonObject { put("plan_id", plan.id) })
    fun chatStop() = act("chat-stop", "chat.stop")

    // Routing (the Mixer's Routing view, routing/1)

    val routingAvailable: Boolean get() = "routing/1" in state.capabilities

    /** Where a track's or bus's sound goes: one undo step on the computer. */
    fun setOutput(source: RoutingSource, output: String) {
        if (output == source.output) return
        act("output-${source.stripId}", "routing.set_output", jsonObject { put("strip_id", source.stripId); put("output", output) })
    }

    /** A new send, at Tabber Studio's -6 dB: an undo step. */
    fun addSend(track: String, bus: String) =
        act("send-$track>$bus", "routing.set_send", jsonObject { put("strip_id", track); put("bus_id", bus) })

    /** A send's level: no undo step, as the mixer's send controls; the newest value only. */
    fun setSendLevel(send: RoutingSend, level: Double) = send(
        "sendlevel-${send.id}", "routing.set_send",
        jsonObject {
            put("strip_id", send.stripId); put("bus_id", send.busId)
            put("level", Math.round(level.coerceIn(0.0, 1.0) * 10000) / 10000.0)
        },
    )

    fun setPreFader(send: RoutingSend, on: Boolean) = act(
        "pre-${send.id}", "routing.set_send",
        jsonObject { put("strip_id", send.stripId); put("bus_id", send.busId); put("pre_fader", on) },
    )

    fun removeSend(send: RoutingSend) =
        act("remove-${send.id}", "routing.remove_send", jsonObject { put("strip_id", send.stripId); put("bus_id", send.busId) })

    // Plug-ins (each strip's INSERTS, plugins/1)

    val pluginsAvailable: Boolean get() = "plugins/1" in state.capabilities

    /** The Insert Plugin browser's rows, read when the browser opens. */
    var catalog by mutableStateOf<List<PluginRow>>(emptyList())
        private set
    var catalogLoading by mutableStateOf(false)
        private set

    /** The plug-in loading on the computer now: its strip's id and its name. */
    var loadingPlugin by mutableStateOf<Pair<String, String>?>(null)
        private set

    /** Said for a while once an instrument became a track's sound source. */
    var pluginNotice by mutableStateOf<String?>(null)
        private set

    /** The browser's rows, a page at a time, as the computer has them now. */
    fun loadCatalog() {
        val session = session ?: return
        if (catalogLoading) return
        catalogLoading = true
        scope.launch {
            try {
                val rows = ArrayList<PluginRow>()
                var offset = 0
                while (true) {
                    val page = PluginPage.from(JsonReader(session.perform("plugins.catalog", jsonObject { put("offset", offset); put("limit", 200) })))
                    rows += page.plugins
                    offset = page.offset + page.plugins.size
                    if (page.plugins.isEmpty() || offset >= page.total) break
                }
                catalog = rows
                problem = null
            } catch (failure: kotlinx.coroutines.CancellationException) {
                throw failure
            } catch (failure: Exception) {
                problem = explain(failure)
            } finally {
                catalogLoading = false
            }
        }
    }

    /**
     * The strip's "+ Plugin" and the browser's Insert. The computer answers once the plug-in has
     * loaded, which can take a while, and opens its window there, as it does for a click.
     */
    fun insertPlugin(row: PluginRow, strip: Strip, done: (Boolean) -> Unit) {
        val session = session ?: return
        if (loadingPlugin != null) return
        loadingPlugin = strip.id to row.name
        scope.launch {
            try {
                val result = session.perform(
                    "plugins.insert", jsonObject { put("strip_id", strip.id); put("plugin_id", row.id) }, timeout = 185.seconds,
                )
                loadingPlugin = null
                problem = null
                feedback = Feedback.TAP to feedback.second + 1
                if (result["sound_source"]?.bool == true) say("${row.name} is now the sound source of ${strip.name}.")
                done(true)
            } catch (failure: kotlinx.coroutines.CancellationException) {
                loadingPlugin = null
                throw failure
            } catch (failure: Exception) {
                loadingPlugin = null
                problem = explain(failure)
                feedback = Feedback.FAILURE to feedback.second + 1
                done(false)
            }
        }
    }

    private fun say(notice: String) {
        pluginNotice = notice
        scope.launch {
            delay(6.seconds)
            if (pluginNotice == notice) pluginNotice = null
        }
    }

    /** A slot's Bypass or Un-bypass. */
    fun bypassInsert(insert: Insert, strip: Strip) = act(
        "bypass-${insert.id}", "plugins.bypass",
        jsonObject { put("strip_id", strip.id); put("insert_id", insert.id); put("bypassed", !insert.bypassed) },
    )

    /** A slot's Remove. */
    fun removeInsert(insert: Insert, strip: Strip) =
        act("remove-${insert.id}", "plugins.remove", jsonObject { put("strip_id", strip.id); put("insert_id", insert.id) })

    /** A slot's Open UI: the plug-in's own window, on the computer. */
    fun openInsert(insert: Insert, strip: Strip) =
        act("open-${insert.id}", "plugins.open", jsonObject { put("strip_id", strip.id); put("insert_id", insert.id) })

    /** The Mixer's meters, only while it is on screen (plan: TR25). */
    fun watchMixerMeters(on: Boolean) {
        val session = session ?: return
        scope.launch { session.watch("mixer_meters", on) }
    }

    // Tab (the Tab screen): edits go one after another, in the order tapped.
    private val edits = ArrayDeque<Pair<String, Json>>()
    private var editing = false

    fun tab(method: String, params: Json = Json.Obj(emptyMap())) {
        edits.addLast(method to params)
        val session = session ?: return
        if (editing) return
        editing = true
        scope.launch {
            while (edits.isNotEmpty()) {
                val (nextMethod, nextParams) = edits.removeFirst()
                try {
                    session.perform(nextMethod, nextParams)
                    problem = null
                } catch (failure: Exception) {
                    problem = explain(failure)
                    feedback = Feedback.FAILURE to feedback.second + 1
                    edits.clear()
                }
            }
            editing = false
        }
    }

    /** Undo the computer's newest step, naming it so nothing else is undone (spec 9). */
    fun undo() {
        val step = state.undo.undo ?: return
        act("undo", "edit.undo", jsonObject { put("expect", step.id) }, Feedback.GO_AGAIN)
    }

    // The transport's toggles and Go to

    fun toggleLoop() {
        val transport = state.transport ?: return
        act("loop", "transport.set_loop", jsonObject { put("enabled", !transport.loop.enabled) })
    }

    fun toggleCountIn() {
        val transport = state.transport ?: return
        val on = transport.countInBars == 0
        act("count-in", "transport.set_count_in", jsonObject { put("bars", if (on) 1 else 0) }) { if (on) tellCountInIsForRecording() }
    }

    /** Once: Count-in is Tabber Studio's recording count-in, so Play starts at once. */
    private fun tellCountInIsForRecording() {
        if (isDemo || prefs.bool("toldCountInIsForRecording")) return
        prefs.set("toldCountInIsForRecording", true)
        problem = "Count-in counts one bar in before recording (●). Play starts at once, as in Tabber Studio."
    }

    fun toggleClick() {
        val transport = state.transport ?: return
        act("click", "transport.set_click", jsonObject { put("enabled", !transport.click) })
    }

    fun go(marker: Marker) = act("goto", "markers.go", jsonObject { put("marker_id", marker.id) })

    fun goToStart() = act("goto", "transport.seek", jsonObject { put("to", jsonObject { put("bar", 1); put("beat", 1) }) })

    /** Stop, and when already stopped, back to the start, as a DAW's Stop does. */
    fun stopButton() {
        if (state.record.recording || state.transport?.state == PlayState.PLAYING) stop() else goToStart()
    }

    fun goAgain() {
        val take = lastTake ?: state.takes.firstOrNull() ?: return
        lastTake = null
        act("goagain", "takes.go_again", jsonObject { put("take_id", take.id) }, Feedback.GO_AGAIN)
    }

    /** Run a verb; a refusal is shown in words (spec 10). */
    fun perform(method: String, params: Json = Json.Obj(emptyMap())) {
        val session = session ?: return
        scope.launch {
            try {
                session.perform(method, params)
                problem = null
            } catch (failure: Exception) {
                problem = explain(failure)
            }
        }
    }

    fun preference(key: String): String? = prefs.string(key)
    fun setPreference(key: String, value: String?) = prefs.set(key, value)

    private fun deviceName(): String =
        Settings.Global.getString(context.contentResolver, Settings.Global.DEVICE_NAME)?.takeIf { it.isNotBlank() } ?: Build.MODEL

    private fun deviceModel(): String = if (Build.FINGERPRINT.contains("generic") || Build.MODEL.contains("sdk")) "Emulator" else "Android"

    // Last in the class: the session it starts touches the properties above, which Kotlin sets in
    // the order they are written (a paired phone would otherwise start against unset state).
    init {
        known?.let { host -> signer()?.let { start(host, it) } }
    }

    companion object {
        /** A pairing that did not work, in words that say what to do (spec 10). */
        fun explainPairing(error: Throwable?, name: String): String = when {
            error is RemoteError -> error.message
            error is TransportFailure.WrongKey -> "The computer that answered is not the one that showed this code. Scan the code again."
            error is TransportFailure.Closed && error.code == 4002 -> "$name runs a newer Tabber Studio. Update Tabber Spak, then scan again."
            else -> "Can't reach $name. Check that this phone is on the same Wi-Fi as the computer, or that Tailscale is on, on both, and that Tabber Studio is open, then scan again."
        }

        fun explain(error: Throwable?): String = when {
            error is RemoteError && error.reason == "routing_loop" -> {
                val path = error.data["path"]?.array?.mapNotNull { it.string } ?: emptyList()
                if (path.isEmpty()) error.message else "${error.message} ${path.joinToString(" → ")}."
            }
            // A refusal in Tabber Studio's own words, when it gives them (spec 10: host_error's detail).
            error is RemoteError && error.reason == "host_error" && !error.data["detail"]?.string.isNullOrBlank() ->
                error.data["detail"]!!.string!!
            error is RemoteError -> error.message
            error is TransportFailure.WrongKey -> "This is not the computer you paired with."
            error is TransportFailure.Closed -> "Tabber Studio closed the connection."
            error != null -> "Could not reach Tabber Studio (${error.message})."
            else -> "Could not reach Tabber Studio."
        }
    }
}
