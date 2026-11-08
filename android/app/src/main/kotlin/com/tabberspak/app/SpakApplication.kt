package com.tabberspak.app

import android.app.Application
import android.content.Context
import android.content.SharedPreferences
import com.tabberspak.remotekit.Json
import com.tabberspak.remotekit.JsonReader
import com.tabberspak.remotekit.KnownHost

/** The app's one session lives here, so it outlives a rotated or recreated activity. */
class SpakApplication : Application() {
    val model: AppModel by lazy { AppModel(this) }
}

/** The app's small settings, as the iPhone keeps them in UserDefaults. */
class Prefs(context: Context) {
    private val prefs: SharedPreferences = context.getSharedPreferences("tabber-spak", Context.MODE_PRIVATE)

    fun bool(key: String, default: Boolean = false): Boolean = prefs.getBoolean(key, default)
    fun set(key: String, value: Boolean) = prefs.edit().putBoolean(key, value).apply()
    fun string(key: String): String? = prefs.getString(key, null)
    fun set(key: String, value: String?) = prefs.edit().apply { if (value == null) remove(key) else putString(key, value) }.apply()
    fun remove(key: String) = prefs.edit().remove(key).apply()
}

/** The paired computer, kept on this phone: no secrets, as the key stays in the Keystore. */
class HostStore(private val prefs: Prefs) {
    fun load(): KnownHost? = prefs.string(KEY)?.let { text ->
        runCatching { KnownHost.from(JsonReader(Json.parse(text))) }.getOrNull()
    }

    fun save(host: KnownHost) = prefs.set(KEY, host.toJson().encode())

    fun clear() = prefs.remove(KEY)

    companion object {
        private const val KEY = "known-host"
    }
}
