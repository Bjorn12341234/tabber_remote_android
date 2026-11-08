package com.tabberspak.remotekit

// What Tabber Studio shows on the computer (view/1), Tabber Studio's chat (chat/1) and its Speed
// Trainer (trainer/1). As apple/RemoteKit's View.swift, Chat.swift and Trainer.swift.

/**
 * The editor Tabber Studio shows, Arrange, Tab or Piano Roll, and whether Split is on beside it;
 * and, from hosts with view.part/1, the MIDI part the Tab editor shows.
 */
class ViewState(
    /** "arrange", "tab" or "piano_roll"; in Split, the one beside Arrange. */
    val editor: String,
    val split: Boolean,
    /** The chosen MIDI track as the Tab editor shows it; null when it shows none. */
    val part: ViewPart? = null,
    /** Whether the host sent `part` at all, even as null: a view from an older host keeps it absent. */
    hasPart: Boolean = false,
) {
    val hasPart: Boolean = hasPart || part != null

    fun copy(editor: String = this.editor, split: Boolean = this.split, part: ViewPart? = this.part) =
        ViewState(editor, split, part, hasPart)

    /** The same view on the computer: whether `part` came as null or not at all is only how it was written. */
    override fun equals(other: Any?): Boolean =
        other is ViewState && other.editor == editor && other.split == split && other.part == part

    override fun hashCode(): Int = listOf(editor, split, part).hashCode()

    override fun toString(): String = "ViewState(editor=$editor, split=$split, part=$part)"

    fun toJson(): Json = jsonObject {
        put("editor", editor); put("split", split)
        if (hasPart) putNullable("part", part?.toJson()) // null when there is none
    }

    companion object {
        val editors = listOf("arrange", "tab", "piano_roll")

        fun from(r: JsonReader) = ViewState(r.string("editor"), r.bool("split"), r.objOrNull("part", ViewPart::from), r.has("part"))
    }
}

/**
 * Tabber Studio's "MIDI part" card and what follows it (view.part/1): the card waits with Show
 * standard notation, and for a melodic MIDI track Show MIDI tab; then the track shows as MIDI tab
 * or in standard notation.
 */
data class ViewPart(
    val trackId: String,
    /** "card", "midi_tab" or "notation". */
    val shows: String,
    /** Whether the track can show MIDI tab: a melodic MIDI track, not drums. */
    val midiTab: Boolean,
) {
    fun toJson(): Json = jsonObject { put("track_id", trackId); put("shows", shows); put("midi_tab", midiTab) }

    companion object {
        fun from(r: JsonReader) = ViewPart(r.string("track_id"), r.string("shows"), r.bool("midi_tab"))
    }
}

/** One line of the conversation with Tabber Studio's chat. */
data class ChatMessage(
    val id: String,
    /** "you" or "studio". */
    val from: String,
    /** "text", "result", "refusal" or "error". */
    val kind: String,
    val text: String,
) {
    val isYou: Boolean get() = from == "you"

    fun toJson(): Json = jsonObject { put("id", id); put("from", from); put("kind", kind); put("text", text) }

    companion object {
        fun from(r: JsonReader) = ChatMessage(r.string("id"), r.string("from"), r.string("kind"), r.string("text"))
    }
}

/** What the AI means to do, waiting for Execute. */
data class ChatPlan(val id: String, val text: String, val steps: List<Step>) {
    data class Step(val text: String)

    fun toJson(): Json = jsonObject {
        put("id", id); put("text", text)
        put("steps", Json.of(steps.map { step -> jsonObject { put("text", step.text) } }))
    }

    companion object {
        fun from(r: JsonReader) = ChatPlan(r.string("id"), r.string("text"), r.list("steps") { Step(it.string("text")) })
    }
}

/** Tabber Studio's chat as the phone sees it: words only. The AI and its key stay on the computer. */
data class ChatState(
    /** False when Tabber Studio has no AI set up. */
    val available: Boolean,
    /** "idle", "thinking", "waiting" (a plan waits for Execute) or "running". */
    val state: String,
    val messages: List<ChatMessage>,
    /** No plan is an explicit null, as the computer sends it. */
    val plan: ChatPlan?,
) {
    val isWorking: Boolean get() = state == "thinking" || state == "running"

    fun toJson(): Json = jsonObject {
        put("available", available); put("state", state)
        put("messages", Json.of(messages.map(ChatMessage::toJson))); putNullable("plan", plan?.toJson())
    }

    companion object {
        fun from(r: JsonReader) = ChatState(
            r.bool("available"), r.string("state"), r.list("messages", ChatMessage::from), r.objOrNull("plan", ChatPlan::from),
        )
    }
}

/**
 * Tabber Studio's Speed Trainer (trainer/1): with Loop on, the song plays from [start] percent,
 * and each time the loop comes round the speed goes up by [step] until it reaches [target].
 * [speed] is the speed now.
 */
data class TrainerState(
    val enabled: Boolean = false,
    val start: Int = 50,
    val step: Int = 5,
    val target: Int = 100,
    val speed: Int = 100,
) {
    fun toJson(): Json = jsonObject {
        put("enabled", enabled); put("start", start); put("step", step); put("target", target); put("speed", speed)
    }

    companion object {
        /** What the phone offers for each field, in percent; a value set on the computer is offered too. */
        val starts = listOf(50, 60, 70, 75, 80, 85, 90, 100)
        val steps = listOf(1, 2, 3, 5, 10)
        val targets = listOf(80, 90, 100, 110, 120)

        fun choices(base: List<Int>, current: Int): List<Int> = if (current in base) base else (base + current).sorted()

        fun from(r: JsonReader) = TrainerState(r.bool("enabled"), r.int("start"), r.int("step"), r.int("target"), r.int("speed"))
    }
}
