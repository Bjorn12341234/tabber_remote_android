package com.tabberspak.remotekit

// The mixer (spec 7, capability mixer/1): a strip for every track, every bus and the master, in
// Tabber Studio's mixer order. As apple/RemoteKit/Mixing.swift.

/** A channel strip. A track's strip has the track's id; the master's is "master". */
data class Strip(
    val id: String,
    /** "track", "bus" or "master". */
    val kind: String,
    val name: String,
    val color: String?,
    /** The fader's travel, 0 to 1, in the computer's own fader law. */
    val volume: Double,
    /** What the fader means; null is silence. */
    val volumeDb: Double?,
    /** -1 is hard left, 1 hard right. */
    val pan: Double,
    /** As Tabber Studio writes it: "L64", "C", "R63". */
    val panLabel: String,
    val muted: Boolean,
    val soloed: Boolean,
    /** What the computer sent (plugins/1): null when it has no plug-ins to list, so the strip reads back as it came. */
    val listedInserts: List<Insert>? = null,
) {
    val isMaster: Boolean get() = kind == "master"
    val isBus: Boolean get() = kind == "bus"

    /** The strip's INSERTS in chain order (plugins/1); none from an older computer. */
    val inserts: List<Insert> get() = listedInserts ?: emptyList()

    fun toJson(): Json = jsonObject {
        put("id", id); put("kind", kind); put("name", name); putNullable("color", color)
        put("volume", volume); putNullable("volume_db", volumeDb); put("pan", pan)
        put("pan_label", panLabel); put("muted", muted); put("soloed", soloed)
        listedInserts?.let { put("inserts", Json.of(it.map(Insert::toJson))) }
    }

    companion object {
        fun from(r: JsonReader) = Strip(
            r.string("id"), r.string("kind"), r.string("name"), r.stringOrNull("color"), r.double("volume"),
            r.doubleOrNull("volume_db"), r.double("pan"), r.string("pan_label"), r.bool("muted"), r.bool("soloed"),
            if (r.has("inserts")) r.list("inserts", Insert::from) else null,
        )
    }
}

/** A mark on the fader's scale: where a level sits on the computer's fader. */
data class ScaleMark(val db: Double, val volume: Double) {
    fun toJson(): Json = jsonObject { put("db", db); put("volume", volume) }

    companion object {
        fun from(r: JsonReader) = ScaleMark(r.double("db"), r.double("volume"))
    }
}

data class MixerState(val strips: List<Strip>, val scale: List<ScaleMark>) {
    /** The fader travel that means 0 dB, for a double tap. */
    val unity: Double get() = scale.firstOrNull { it.db == 0.0 }?.volume ?: 0.7

    fun toJson(): Json = jsonObject {
        put("strips", Json.of(strips.map(Strip::toJson)))
        put("scale", Json.of(scale.map(ScaleMark::toJson)))
    }

    companion object {
        fun from(r: JsonReader) = MixerState(r.list("strips", Strip::from), r.list("scale", ScaleMark::from))
    }
}

data class StripLevel(val stripId: String, val peak: List<Double>) {
    fun toJson(): Json = jsonObject { put("strip_id", stripId); put("peak", Json.doubles(peak)) }

    companion object {
        fun from(r: JsonReader) = StripLevel(r.string("strip_id"), r.doubles("peak"))
    }
}
