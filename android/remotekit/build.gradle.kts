// RemoteKit for Android: the protocol, the connection, pairing and the session, with no UI and no
// Android API, as apple/RemoteKit is. Its tests run every protocol vector (spec 13).
plugins {
    id("org.jetbrains.kotlin.jvm")
}

kotlin {
    jvmToolchain(17)
}

dependencies {
    // The WebSocket over TLS (owner's choice, 2026-11-08): Android has no WebSocket client.
    api("com.squareup.okhttp3:okhttp:5.5.1")
    // Kotlin's own concurrency, as Swift's is RemoteKit's there; Compose runs on it too.
    api("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.2")
    testImplementation(kotlin("test"))
    testImplementation("junit:junit:4.13.2")
}

tasks.test {
    // The vectors are the repository's own protocol/vectors, shared with the iPhone app and
    // Tabber Studio's pinned copy.
    systemProperty("tabber.vectors", rootDir.parentFile.resolve("protocol/vectors").absolutePath)
    // REMOTE_INTEROP (tools/interop_host.py's line) turns on the test against a real host.
    // A new host line (a new port each run) reruns the test instead of reusing a pass.
    val interop = System.getenv("REMOTE_INTEROP")
    inputs.property("interop", interop ?: "")
    interop?.let { environment("REMOTE_INTEROP", it) }
    testLogging { events("failed"); exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL }
}
