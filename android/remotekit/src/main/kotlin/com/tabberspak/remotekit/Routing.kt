package com.tabberspak.remotekit

import kotlin.math.log10

// Routing (routing/1): each track or bus and the one place its sound goes, the master or a bus,
// and its sends. Ids are the mixer's strip ids. As apple/RemoteKit/Routing.swift.

data class RoutingSource(
    val stripId: String,
    /** "track" or "bus". */
    val kind: String,
    val name: String,
    /** "master" or a bus's strip id. */
    val output: String,
) {
    val id: String get() = stripId
    val isBus: Boolean get() = kind == "bus"

    fun toJson(): Json = jsonObject { put("strip_id", stripId); put("kind", kind); put("name", name); put("output", output) }

    companion object {
        fun from(r: JsonReader) = RoutingSource(r.string("strip_id"), r.string("kind"), r.string("name"), r.string("output"))
    }
}

/** A track's sound tapped into a bus beside its output. */
data class RoutingSend(
    val stripId: String,
    val busId: String,
    /** The send's gain, 0 to 1, as Tabber Studio stores it. */
    val level: Double,
    /** Silence is an explicit null, as the computer sends it. */
    val levelDb: Double?,
    /** As Tabber Studio writes it: "-6.0 dB". */
    val levelLabel: String,
    val preFader: Boolean,
) {
    val id: String get() = "$stripId>$busId"

    fun toJson(): Json = jsonObject {
        put("strip_id", stripId); put("bus_id", busId); put("level", level)
        putNullable("level_db", levelDb); put("level_label", levelLabel); put("pre_fader", preFader)
    }

    companion object {
        fun from(r: JsonReader) = RoutingSend(
            r.string("strip_id"), r.string("bus_id"), r.double("level"), r.doubleOrNull("level_db"),
            r.string("level_label"), r.bool("pre_fader"),
        )
    }
}

/** Where each track and bus sends its sound, as Tabber Studio's Routing panel shows it. */
data class RoutingState(val sources: List<RoutingSource>, val sends: List<RoutingSend>) {
    val tracks: List<RoutingSource> get() = sources.filterNot { it.isBus }
    val buses: List<RoutingSource> get() = sources.filter { it.isBus }

    fun source(stripId: String): RoutingSource? = sources.firstOrNull { it.stripId == stripId }

    /** The name of where a source's sound goes. */
    fun outputName(of: RoutingSource): String =
        if (of.output == MASTER) "Master" else source(of.output)?.name ?: "Master"

    fun sendsFrom(stripId: String): List<RoutingSend> = sends.filter { it.stripId == stripId }

    /** What feeds a bus: the tracks and buses that output to it, then the sends into it. */
    fun feeding(busId: String): Pair<List<RoutingSource>, List<RoutingSend>> =
        sources.filter { it.output == busId } to sends.filter { it.busId == busId }

    /** The buses a source can output to: every bus but itself. */
    fun outputsFor(of: RoutingSource): List<RoutingSource> = buses.filter { it.stripId != of.stripId }

    /**
     * Whether routing bus [source] into bus [dest] would close a loop: [dest]'s outputs already
     * lead back to [source] (Tabber Studio's rule). Returns the loop by name, from the source back
     * to it, as Tabber Studio names it.
     */
    fun wouldLoop(source: String, dest: String): List<String>? {
        if (dest == MASTER) return null
        fun name(id: String) = source(id)?.name ?: id
        if (source == dest) return listOf(name(source), name(source))
        val path = mutableListOf(source, dest)
        val seen = mutableSetOf(source, dest)
        var at = dest
        while (true) {
            val next = source(at)?.output ?: return null
            if (next == MASTER) return null
            path.add(next)
            if (next == source) return path.map(::name)
            if (!seen.add(next)) return null // a loop elsewhere, not through the source
            at = next
        }
    }

    fun toJson(): Json = jsonObject {
        put("sources", Json.of(sources.map(RoutingSource::toJson)))
        put("sends", Json.of(sends.map(RoutingSend::toJson)))
    }

    companion object {
        const val MASTER = "master"

        fun from(r: JsonReader) = RoutingState(r.list("sources", RoutingSource::from), r.list("sends", RoutingSend::from))
    }
}

/** How Tabber Studio writes a send level (ui/routing_matrix_view.py format_send_db). */
object SendLevel {
    fun db(level: Double): Double? {
        if (level <= 0) return null
        val db = 20 * log10(level)
        return if (db <= -60) null else db
    }

    fun label(level: Double): String {
        val db = db(level) ?: return "-∞ dB"
        return String.format(java.util.Locale.ROOT, "%+.1f dB", db)
    }
}
