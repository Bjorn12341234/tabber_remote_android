// Tabber Spak for Android (android/README.md). AGP 9 compiles the app's Kotlin itself, with the
// Kotlin it bundles (2.2.10); RemoteKit is a plain Kotlin library on the same Kotlin, so the
// protocol and its vectors run on the JVM without Android, as RemoteKit runs in `swift test`.
plugins {
    id("com.android.application") version "9.2.1" apply false
    id("org.jetbrains.kotlin.jvm") version "2.2.10" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.2.10" apply false
}
