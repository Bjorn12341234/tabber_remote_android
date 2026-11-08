package com.tabberspak.remotekit

// Tab on the phone (spec 7, capability tab/1): the selected tab track's bars around the edit
// cursor, and the cursor itself, as Tabber Studio's Tab view has them. Strings count from 1, the
// highest; beats are the rhythmic slots of a bar, counted from 1. As apple/RemoteKit/Tablature.swift.

/** A note value: 1 whole, 2 half, 4 quarter, 8, 16, 32. */
data class NoteValue(val value: Int, val dotted: Boolean = false, val triplet: Boolean = false) {
    /** Its length in quarter notes. */
    val quarters: Double
        get() {
            var q = 4.0 / value
            if (dotted) q *= 1.5
            if (triplet) q *= 2.0 / 3.0
            return q
        }

    fun toJson(): Json = jsonObject { put("value", value); put("dotted", dotted); put("triplet", triplet) }

    companion object {
        val values = listOf(1, 2, 4, 8, 16, 32)

        fun from(r: JsonReader) = NoteValue(r.int("value"), r.bool("dotted"), r.bool("triplet"))
    }
}

data class TabNote(
    val string: Int,
    val fret: Int,
    /** MIDI tab only (tab.midi/1): below its open string or past the last fret; the fret can be negative. */
    val virtual: Boolean? = null,
) {
    fun toJson(): Json = jsonObject { put("string", string); put("fret", fret); putIfPresent("virtual", virtual) }

    companion object {
        fun from(r: JsonReader) = TabNote(r.int("string"), r.int("fret"), r.boolOrNull("virtual"))
    }
}

data class TabBeat(val duration: NoteValue, val rest: Boolean, val notes: List<TabNote>) {
    fun toJson(): Json = jsonObject {
        put("duration", duration.toJson()); put("rest", rest); put("notes", Json.of(notes.map(TabNote::toJson)))
    }

    companion object {
        fun from(r: JsonReader) = TabBeat(r.obj("duration", NoteValue::from), r.bool("rest"), r.list("notes", TabNote::from))
    }
}

data class TabBar(val bar: Int, val timeSignature: TimeSignature, val beats: List<TabBeat>) {
    /** The bar's length in quarter notes. */
    val capacity: Double get() = timeSignature.beats * 4.0 / timeSignature.unit
    val filled: Double get() = beats.sumOf { it.duration.quarters }

    fun toJson(): Json = jsonObject {
        put("bar", bar); put("time_signature", timeSignature.toJson()); put("beats", Json.of(beats.map(TabBeat::toJson)))
    }

    companion object {
        fun from(r: JsonReader) = TabBar(r.int("bar"), r.obj("time_signature", TimeSignature::from), r.list("beats", TabBeat::from))
    }
}

data class TabCursor(val bar: Int, val beat: Int, val string: Int) {
    fun toJson(): Json = jsonObject { put("bar", bar); put("beat", beat); put("string", string) }

    companion object {
        fun from(r: JsonReader) = TabCursor(r.int("bar"), r.int("beat"), r.int("string"))
    }
}

data class TabState(
    val trackId: String,
    val revision: Int,
    /** The open strings as MIDI notes, highest first. */
    val tuning: List<Int>,
    val drum: Boolean,
    val cursor: TabCursor,
    /** What a new note gets. */
    val duration: NoteValue,
    val barCount: Int,
    /** The cursor's bar and its neighbours. */
    val bars: List<TabBar>,
    /** A melodic MIDI track's MIDI tab (tab.midi/1); null from hosts before it. */
    val midi: Boolean? = null,
) {
    /** Whether this is a MIDI track's MIDI tab rather than a tab track's tab. */
    val isMidiTab: Boolean get() = midi ?: false
    val strings: Int get() = tuning.size
    val cursorBar: TabBar? get() = bars.firstOrNull { it.bar == cursor.bar }
    val cursorBeat: TabBeat? get() = cursorBar?.beats?.getOrNull(cursor.beat - 1)

    /** The beat after (or before) the cursor among the beats written, adding none: null at the song's ends. */
    fun neighbour(by: Int): TabCursor? {
        val bar = cursorBar ?: return null
        if (by > 0) {
            if (cursor.beat < bar.beats.size) return cursor.copy(beat = cursor.beat + 1)
            if (cursor.bar >= barCount) return null
            return TabCursor(cursor.bar + 1, 1, cursor.string)
        }
        if (cursor.beat > 1) return cursor.copy(beat = cursor.beat - 1)
        if (cursor.bar <= 1) return null
        val previous = bars.firstOrNull { it.bar == cursor.bar - 1 }
        return TabCursor(cursor.bar - 1, maxOf(1, previous?.beats?.size ?: 1), cursor.string)
    }

    /** The first beat of the next (or previous) bar: null past the song's ends. */
    fun barStep(by: Int): TabCursor? {
        val target = cursor.bar + if (by > 0) 1 else -1
        if (target !in 1..maxOf(1, barCount)) return null
        return TabCursor(target, 1, cursor.string)
    }

    /** The pitch a fret on a string sounds. */
    fun pitch(string: Int, fret: Int): Int? = tuning.getOrNull(string - 1)?.plus(fret)

    fun toJson(): Json = jsonObject {
        put("track_id", trackId); put("revision", revision); put("tuning", Json.ints(tuning)); put("drum", drum)
        put("cursor", cursor.toJson()); put("duration", duration.toJson()); put("bar_count", barCount)
        put("bars", Json.of(bars.map(TabBar::toJson))); putIfPresent("midi", midi)
    }

    companion object {
        fun from(r: JsonReader) = TabState(
            trackId = r.string("track_id"),
            revision = r.int("revision"),
            tuning = r.ints("tuning"),
            drum = r.bool("drum"),
            cursor = r.obj("cursor", TabCursor::from),
            duration = r.obj("duration", NoteValue::from),
            barCount = r.int("bar_count"),
            bars = r.list("bars", TabBar::from),
            midi = r.boolOrNull("midi"),
        )
    }
}
