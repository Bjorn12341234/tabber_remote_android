package com.tabberspak.remotekit

/**
 * Any JSON value, as apple/RemoteKit's JSONValue. Params and results travel as this; the typed
 * models decode from it. A number is a Double, so 8120 and 8120.0 are the same value, and an
 * object compares by its fields, in any order.
 */
sealed interface Json {
    data object Null : Json
    data class Bool(val value: Boolean) : Json
    data class Num(val value: Double) : Json
    data class Str(val value: String) : Json
    data class Arr(val items: List<Json>) : Json
    data class Obj(val fields: Map<String, Json>) : Json

    operator fun get(key: String): Json? = (this as? Obj)?.fields?.get(key)

    val string: String? get() = (this as? Str)?.value
    val bool: Boolean? get() = (this as? Bool)?.value
    val double: Double? get() = (this as? Num)?.value
    val int: Int?
        get() {
            val n = (this as? Num)?.value ?: return null
            return if (n == Math.rint(n) && Math.abs(n) < 2.147483647E9) n.toInt() else null
        }
    val long: Long?
        get() {
            val n = (this as? Num)?.value ?: return null
            return if (n == Math.rint(n) && Math.abs(n) < 9.0e15) n.toLong() else null
        }
    val array: List<Json>? get() = (this as? Arr)?.items
    val obj: Map<String, Json>? get() = (this as? Obj)?.fields

    /** One line of JSON, keys sorted, as the Swift client writes it. */
    fun encode(): String = StringBuilder().also { JsonWriter.write(this, it) }.toString()

    companion object {
        fun parse(text: String): Json = JsonParser(text).parseDocument()

        fun of(value: String?): Json = if (value == null) Null else Str(value)
        fun of(value: Boolean): Json = Bool(value)
        fun of(value: Int): Json = Num(value.toDouble())
        fun of(value: Long): Json = Num(value.toDouble())
        fun of(value: Double): Json = Num(value)
        fun of(values: List<Json>): Json = Arr(values)
        fun strings(values: List<String>): Json = Arr(values.map(::Str))
        fun ints(values: List<Int>): Json = Arr(values.map { Num(it.toDouble()) })
        fun doubles(values: List<Double>): Json = Arr(values.map(::Num))
    }
}

/** A message that does not have the shape its model needs. */
class JsonShapeException(message: String) : Exception(message)

/** Builds an object field by field, so every model says which empty fields are null and which are absent. */
class JsonObjectBuilder {
    private val fields = LinkedHashMap<String, Json>()

    fun put(key: String, value: Json) { fields[key] = value }
    fun put(key: String, value: String) { fields[key] = Json.Str(value) }
    fun put(key: String, value: Boolean) { fields[key] = Json.Bool(value) }
    fun put(key: String, value: Int) { fields[key] = Json.Num(value.toDouble()) }
    fun put(key: String, value: Long) { fields[key] = Json.Num(value.toDouble()) }
    fun put(key: String, value: Double) { fields[key] = Json.Num(value) }

    /** An absent value is written as an explicit null, as the computer sends it. */
    fun putNullable(key: String, value: Json?) { fields[key] = value ?: Json.Null }
    fun putNullable(key: String, value: String?) { fields[key] = Json.of(value) }
    fun putNullable(key: String, value: Double?) { fields[key] = value?.let(Json::Num) ?: Json.Null }

    /** An absent value is left out, as older hosts leave it out. */
    fun putIfPresent(key: String, value: Json?) { if (value != null) fields[key] = value }
    fun putIfPresent(key: String, value: String?) { if (value != null) fields[key] = Json.Str(value) }
    fun putIfPresent(key: String, value: Boolean?) { if (value != null) fields[key] = Json.Bool(value) }
    fun putIfPresent(key: String, value: Double?) { if (value != null) fields[key] = Json.Num(value) }

    fun build(): Json.Obj = Json.Obj(fields)
}

fun jsonObject(build: JsonObjectBuilder.() -> Unit): Json.Obj = JsonObjectBuilder().apply(build).build()

/** Reads one object's fields; every miss names its path, so a host bug is easy to find. */
class JsonReader(private val value: Json, private val path: String = "$") {
    private val fields: Map<String, Json> =
        value.obj ?: throw JsonShapeException("$path: expected an object, found ${kind(value)}")

    fun has(key: String): Boolean = fields.containsKey(key)

    private fun field(key: String): Json =
        fields[key] ?: throw JsonShapeException("$path.$key: missing")

    fun string(key: String): String =
        field(key).string ?: throw JsonShapeException("$path.$key: expected a string, found ${kind(field(key))}")

    fun bool(key: String): Boolean =
        field(key).bool ?: throw JsonShapeException("$path.$key: expected true or false, found ${kind(field(key))}")

    fun double(key: String): Double =
        field(key).double ?: throw JsonShapeException("$path.$key: expected a number, found ${kind(field(key))}")

    fun int(key: String): Int =
        field(key).int ?: throw JsonShapeException("$path.$key: expected a whole number, found ${kind(field(key))}")

    fun json(key: String): Json = field(key)

    /** Missing or null reads as null. */
    fun stringOrNull(key: String): String? = optional(key)?.let { it.string ?: wrong(key, "a string", it) }
    fun doubleOrNull(key: String): Double? = optional(key)?.let { it.double ?: wrong(key, "a number", it) }
    fun intOrNull(key: String): Int? = optional(key)?.let { it.int ?: wrong(key, "a whole number", it) }
    fun boolOrNull(key: String): Boolean? = optional(key)?.let { it.bool ?: wrong(key, "true or false", it) }

    fun <T> obj(key: String, decode: (JsonReader) -> T): T = decode(JsonReader(field(key), "$path.$key"))

    fun <T> objOrNull(key: String, decode: (JsonReader) -> T): T? =
        optional(key)?.let { decode(JsonReader(it, "$path.$key")) }

    fun <T> list(key: String, decode: (JsonReader) -> T): List<T> = items(key).mapIndexed { index, item ->
        decode(JsonReader(item, "$path.$key[$index]"))
    }

    fun strings(key: String): List<String> = items(key).mapIndexed { index, item ->
        item.string ?: throw JsonShapeException("$path.$key[$index]: expected a string, found ${kind(item)}")
    }

    fun ints(key: String): List<Int> = items(key).mapIndexed { index, item ->
        item.int ?: throw JsonShapeException("$path.$key[$index]: expected a whole number, found ${kind(item)}")
    }

    fun doubles(key: String): List<Double> = items(key).mapIndexed { index, item ->
        item.double ?: throw JsonShapeException("$path.$key[$index]: expected a number, found ${kind(item)}")
    }

    fun intsOrNull(key: String): List<Int>? = optional(key)?.let { ints(key) }

    private fun items(key: String): List<Json> =
        field(key).array ?: throw JsonShapeException("$path.$key: expected a list, found ${kind(field(key))}")

    private fun optional(key: String): Json? = fields[key]?.takeUnless { it == Json.Null }

    private fun wrong(key: String, expected: String, found: Json): Nothing =
        throw JsonShapeException("$path.$key: expected $expected, found ${kind(found)}")

    companion object {
        fun kind(value: Json): String = when (value) {
            Json.Null -> "null"
            is Json.Bool -> "true or false"
            is Json.Num -> "a number"
            is Json.Str -> "a string"
            is Json.Arr -> "a list"
            is Json.Obj -> "an object"
        }
    }
}

/** Reads a list of objects at the top level, for topics whose data is a list. */
fun <T> decodeList(value: Json, path: String, decode: (JsonReader) -> T): List<T> =
    (value.array ?: throw JsonShapeException("$path: expected a list, found ${JsonReader.kind(value)}"))
        .mapIndexed { index, item -> decode(JsonReader(item, "$path[$index]")) }

internal object JsonWriter {
    fun write(value: Json, out: StringBuilder) {
        when (value) {
            Json.Null -> out.append("null")
            is Json.Bool -> out.append(if (value.value) "true" else "false")
            is Json.Num -> writeNumber(value.value, out)
            is Json.Str -> writeString(value.value, out)
            is Json.Arr -> {
                out.append('[')
                value.items.forEachIndexed { index, item ->
                    if (index > 0) out.append(',')
                    write(item, out)
                }
                out.append(']')
            }
            is Json.Obj -> {
                out.append('{')
                value.fields.keys.sorted().forEachIndexed { index, key ->
                    if (index > 0) out.append(',')
                    writeString(key, out)
                    out.append(':')
                    write(value.fields.getValue(key), out)
                }
                out.append('}')
            }
        }
    }

    private fun writeNumber(n: Double, out: StringBuilder) {
        require(n.isFinite()) { "JSON has no $n" }
        if (n == Math.rint(n) && Math.abs(n) < 9.0e15) out.append(n.toLong()) else out.append(n.toString())
    }

    private fun writeString(s: String, out: StringBuilder) {
        out.append('"')
        for (c in s) {
            when (c) {
                '"' -> out.append("\\\"")
                '\\' -> out.append("\\\\")
                '\n' -> out.append("\\n")
                '\r' -> out.append("\\r")
                '\t' -> out.append("\\t")
                '\b' -> out.append("\\b")
                '\u000C' -> out.append("\\f")
                else -> if (c < ' ') out.append(String.format("\\u%04x", c.code)) else out.append(c)
            }
        }
        out.append('"')
    }
}

/** RFC 8259, strictly: one value, nothing after it. */
internal class JsonParser(private val text: String) {
    private var at = 0

    fun parseDocument(): Json {
        val value = parseValue()
        skipSpace()
        if (at != text.length) fail("text after the value")
        return value
    }

    private fun parseValue(): Json {
        skipSpace()
        if (at >= text.length) fail("unexpected end")
        return when (val c = text[at]) {
            '{' -> parseObject()
            '[' -> parseArray()
            '"' -> Json.Str(parseString())
            't' -> literal("true", Json.Bool(true))
            'f' -> literal("false", Json.Bool(false))
            'n' -> literal("null", Json.Null)
            else -> if (c == '-' || c in '0'..'9') parseNumber() else fail("unexpected '$c'")
        }
    }

    private fun parseObject(): Json {
        at++ // {
        val fields = LinkedHashMap<String, Json>()
        skipSpace()
        if (peek() == '}') { at++; return Json.Obj(fields) }
        while (true) {
            skipSpace()
            if (peek() != '"') fail("expected a key")
            val key = parseString()
            skipSpace()
            if (peek() != ':') fail("expected ':'")
            at++
            fields[key] = parseValue()
            skipSpace()
            when (peek()) {
                ',' -> at++
                '}' -> { at++; return Json.Obj(fields) }
                else -> fail("expected ',' or '}'")
            }
        }
    }

    private fun parseArray(): Json {
        at++ // [
        val items = ArrayList<Json>()
        skipSpace()
        if (peek() == ']') { at++; return Json.Arr(items) }
        while (true) {
            items.add(parseValue())
            skipSpace()
            when (peek()) {
                ',' -> at++
                ']' -> { at++; return Json.Arr(items) }
                else -> fail("expected ',' or ']'")
            }
        }
    }

    private fun parseString(): String {
        at++ // opening quote
        val out = StringBuilder()
        while (true) {
            if (at >= text.length) fail("unterminated string")
            val c = text[at++]
            when {
                c == '"' -> return out.toString()
                c == '\\' -> {
                    if (at >= text.length) fail("unterminated escape")
                    when (val e = text[at++]) {
                        '"' -> out.append('"')
                        '\\' -> out.append('\\')
                        '/' -> out.append('/')
                        'b' -> out.append('\b')
                        'f' -> out.append('\u000C')
                        'n' -> out.append('\n')
                        'r' -> out.append('\r')
                        't' -> out.append('\t')
                        'u' -> {
                            if (at + 4 > text.length) fail("short \\u escape")
                            val hex = text.substring(at, at + 4)
                            out.append(hex.toIntOrNull(16)?.toChar() ?: fail("bad \\u escape"))
                            at += 4
                        }
                        else -> fail("bad escape '\\$e'")
                    }
                }
                c < ' ' -> fail("control character in a string")
                else -> out.append(c)
            }
        }
    }

    private fun parseNumber(): Json {
        val start = at
        if (peek() == '-') at++
        if (peek() == '0') at++ else digits()
        if (peek() == '.') { at++; digits() }
        if (peek() == 'e' || peek() == 'E') {
            at++
            if (peek() == '+' || peek() == '-') at++
            digits()
        }
        val number = text.substring(start, at).toDoubleOrNull() ?: fail("bad number")
        return Json.Num(number)
    }

    private fun digits() {
        val start = at
        while (at < text.length && text[at] in '0'..'9') at++
        if (at == start) fail("expected a digit")
    }

    private fun literal(word: String, value: Json): Json {
        if (!text.startsWith(word, at)) fail("unexpected token")
        at += word.length
        return value
    }

    private fun skipSpace() {
        while (at < text.length && (text[at] == ' ' || text[at] == '\n' || text[at] == '\r' || text[at] == '\t')) at++
    }

    private fun peek(): Char = if (at < text.length) text[at] else '\u0000'

    private fun fail(why: String): Nothing = throw JsonShapeException("JSON at $at: $why")
}
