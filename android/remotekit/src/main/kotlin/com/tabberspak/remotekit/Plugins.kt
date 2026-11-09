package com.tabberspak.remotekit

// Plug-ins (spec 9, capability plugins/1): each strip's INSERTS, as Tabber Studio's mixer strip
// lists them, and the rows of its Insert Plugin browser. As apple/RemoteKit/Plugins.swift.

/** One plug-in in a strip's INSERTS. */
data class Insert(
    val id: String,
    val name: String,
    /** The strip's hollow dot: the sound passes it by. */
    val bypassed: Boolean = false,
    /** Tabber Studio bypassed it itself, because it took too long. */
    val autoBypassed: Boolean = false,
) {
    fun toJson(): Json = jsonObject { put("id", id); put("name", name); put("bypassed", bypassed); put("auto_bypassed", autoBypassed) }

    companion object {
        fun from(r: JsonReader) = Insert(r.string("id"), r.string("name"), r.bool("bypassed"), r.bool("auto_bypassed"))
    }
}

/** A row of the Insert Plugin browser: its Name, Vendor, Category, Type and Format. */
data class PluginRow(
    val id: String,
    val name: String,
    val vendor: String,
    val category: String,
    /** "effect" or "instrument". */
    val kind: String,
    /** "native" (one of Tabber's own devices), "vst3" or "clap". */
    val format: String,
    /** In the browser's Tabber Plugins tab; otherwise its Plugins tab. */
    val tabber: Boolean,
    val available: Boolean = true,
    /** Why it can't be inserted, in the browser's words. */
    val reason: String? = null,
) {
    val isInstrument: Boolean get() = kind == "instrument"

    /** The browser's Type column. */
    val typeLabel: String get() = if (isInstrument) "Instrument" else "Effect"

    /** The browser's Format column, short. */
    val formatLabel: String get() = if (format == "native") "Tabber" else format.uppercase()

    fun toJson(): Json = jsonObject {
        put("id", id); put("name", name); put("vendor", vendor); put("category", category); put("kind", kind)
        put("format", format); put("tabber", tabber); put("available", available)
        putNullable("reason", reason) // null when it can be inserted, as the protocol has it
    }

    companion object {
        fun from(r: JsonReader) = PluginRow(
            r.string("id"), r.string("name"), r.string("vendor"), r.string("category"), r.string("kind"),
            r.string("format"), r.bool("tabber"), r.bool("available"), r.stringOrNull("reason"),
        )
    }
}

/** A page of the browser's rows: at most 200, since a message is at most 64 KB. */
data class PluginPage(val plugins: List<PluginRow>, val total: Int, val offset: Int) {
    fun toJson(): Json = jsonObject {
        put("plugins", Json.of(plugins.map(PluginRow::toJson))); put("total", total); put("offset", offset)
    }

    companion object {
        fun from(r: JsonReader) = PluginPage(r.list("plugins", PluginRow::from), r.int("total"), r.int("offset"))
    }
}
