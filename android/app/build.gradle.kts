// Tabber Spak for Android: Jetpack Compose screens over RemoteKit (android/README.md).
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
}

// The version is the iPhone app's MARKETING_VERSION, so both phones say the same; the build
// number is android/BUILD_NUMBER, the last build uploaded to Play, which
// scripts/release-android.sh counts up (Play calls it versionCode).
val repo: File = rootDir.parentFile
val spakVersion: String = Regex("MARKETING_VERSION = ([0-9.]+);")
    .find(repo.resolve("apple/TabberSpak.xcodeproj/project.pbxproj").readText())
    ?.groupValues?.get(1) ?: error("no MARKETING_VERSION in the iPhone project")
val buildNumber = rootDir.resolve("BUILD_NUMBER").readText().trim().toInt()

// The upload key for Google Play (Play re-signs with the app key). It and its passwords live in
// ~/.gradle/gradle.properties as TABBERSPAK_UPLOAD_*, never in the repository. Without them a
// release build is unsigned, and scripts/release-android.sh refuses to build.
val uploadStore = findProperty("TABBERSPAK_UPLOAD_STORE_FILE") as String?

android {
    namespace = "com.tabberspak.app"
    // The Compose 2026.09 libraries compile against Android 37; the app still targets 36 (Play's level).
    compileSdk = 37

    defaultConfig {
        // The Play Console's app record (created by the owner, 2026-11-08): permanent.
        applicationId = "com.tabberspak.app"
        // Android 10: Tabber Studio's host speaks TLS 1.3 only, which Android has from 10.
        minSdk = 29
        targetSdk = 36
        versionCode = maxOf(buildNumber, 1)
        versionName = spakVersion
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    signingConfigs {
        if (uploadStore != null) {
            create("upload") {
                storeFile = file(uploadStore)
                storePassword = findProperty("TABBERSPAK_UPLOAD_STORE_PASSWORD") as String?
                keyAlias = findProperty("TABBERSPAK_UPLOAD_KEY_ALIAS") as String?
                keyPassword = findProperty("TABBERSPAK_UPLOAD_KEY_PASSWORD") as String?
            }
        }
    }

    buildTypes {
        debug {
            // Beside a build from Play on the same phone, not instead of it.
            applicationIdSuffix = ".debug"
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            if (uploadStore != null) signingConfig = signingConfigs.getByName("upload")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }
}

dependencies {
    implementation(project(":remotekit"))
    implementation(platform("androidx.compose:compose-bom:2026.09.00"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    // Studio's symbols for the tabs and the transport (R8 keeps only the ones used).
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.activity:activity-compose:1.13.0")
    implementation("androidx.core:core-ktx:1.19.1")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.11.0")
    debugImplementation("androidx.compose.ui:ui-tooling")
    debugImplementation("androidx.compose.ui:ui-test-manifest")
    // The tuner's pitch detection and its arithmetic, on the JVM (./gradlew :app:testDebugUnitTest).
    testImplementation("junit:junit:4.13.2")
    // Every screen's tests run in the emulator against the demo computer, as the iPhone's UI tests
    // run against DemoHost (plan: Rules for every sprint).
    androidTestImplementation(platform("androidx.compose:compose-bom:2026.09.00"))
    androidTestImplementation("androidx.compose.ui:ui-test-junit4")
    // The accessibility pass (TA5): Google's Accessibility Test Framework on every screen, as the iPhone's audit.
    androidTestImplementation("androidx.compose.ui:ui-test-junit4-accessibility")
    // The sheets' own windows for that pass.
    androidTestImplementation("androidx.test.espresso:espresso-core:3.7.0")
    androidTestImplementation("androidx.test:runner:1.7.0")
    androidTestImplementation("androidx.test.ext:junit:1.3.0")
}
