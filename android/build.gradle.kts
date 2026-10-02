allprojects {
    repositories {
        google()
        mavenCentral()
        maven {
            url = uri(File(rootProject.projectDir, "../packages/flutter_torrent_server/android/repo"))
        }
    }
}

/**
 * Centralized Project Settings
 * These versions are enforced across the app and all plugins.
 */
// A platform hash rather than an API level: Google publishes API 37 only as
// `android-37.0` (and 37.1, 37.2 ...), and AGP 8.13 turns a bare 37 into
// `android-37`, a package that no longer exists - locally or for CI to fetch.
extra["projectCompileSdk"] = "android-37.0"
extra["projectTargetSdk"] = 36
// Pinned rather than inherited from `flutter.ndkVersion` (28.2.13676358).
// GitHub removes NDK 28 from every runner image on 2026-10-01; r29 is what they
// keep alongside r27. r29 also emits 16 KB-aligned LOAD segments by default,
// which r27 does not - hence the explicit max-page-size linker flags this repo
// carries for the libraries it compiles itself.
//
// It is set on every subproject below, not just :app, because AGP otherwise
// gives each plugin its own default: before this pin, :app and :jni built
// against r28 while 21 other subprojects - including :vlc_player, :flutter_js
// and :flutter_torrent_server - built against r27.
extra["projectNdk"] = "29.0.14206865"
val projectJvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17

// The engine revision of the Flutter SDK this build runs on. Flutter's Gradle plugin
// constrains every io.flutter:flutter_embedding_* request to exactly "1.0.0-<this>";
// the bridge hook inside `subprojects` below needs the same string. Read the way
// settings.gradle.kts finds the SDK; null (no rewrite) if the file is ever not there.
val flutterEmbeddingVersion: String? =
    runCatching {
        val props = java.util.Properties()
        rootProject.file("local.properties").inputStream().use { props.load(it) }
        File(props.getProperty("flutter.sdk"), "bin/internal/engine.version")
            .readText()
            .trim()
            .takeIf { it.isNotEmpty() }
            ?.let { "1.0.0-$it" }
    }.getOrNull()

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    // Standardize subproject build directories
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)

    // Ensure :app is evaluated first for dependency resolution
    project.evaluationDependsOn(":app")

    /**
     * anymex_extension_runtime_bridge's Android plugin
     *
     * Its android/build.gradle was written to build inside the AnymeX app and leans on
     * that build for two things this one does not provide:
     *
     *  1. It declares `compileOnly io.flutter:flutter_embedding_debug:1.0.0-<hash>`, the
     *     engine of whichever Flutter it was last built with (ef0cd00... in v2.6.0).
     *     Flutter's Gradle plugin puts a *strict* constraint on that artifact at this
     *     SDK's own engine, and a pinned, different version beside a strict constraint
     *     is a resolution failure, not a preference - the build stops at
     *     :anymex_extension_runtime_bridge:compileDebugKotlin. Every request for the
     *     embedding is therefore rewritten to this SDK's engine. It is compile-only API
     *     in the plugin, and the plugin uses nothing that has moved.
     *  2. Its Kotlin imports kotlinx.coroutines (a CoroutineScope is built in the
     *     plugin's constructor, so registration itself needs the classes at runtime)
     *     and its build script declares no dependency on it.
     */
    configurations.configureEach {
        resolutionStrategy.eachDependency {
            if (requested.group == "io.flutter" &&
                requested.name.startsWith("flutter_embedding_")
            ) {
                flutterEmbeddingVersion?.let { useVersion(it) }
            }
        }
    }
    if (project.name == "anymex_extension_runtime_bridge") {
        pluginManager.withPlugin("com.android.library") {
            dependencies.add(
                "implementation",
                "org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2",
            )
        }
    }

    /**
     * Unified SDK & Toolchain Enforcement
     * This logic forces all subprojects (including plugins) to use consistent SDKs.
     */
    val configureAction: (Project) -> Unit = { project ->
        if (project.hasProperty("android")) {
            project.extensions.configure<com.android.build.gradle.BaseExtension>("android") {
                // Force API 37 to satisfy permission_handler_android and modern AndroidX dependencies
                val wanted = rootProject.extra["projectCompileSdk"] as String
                // Only where it differs: :app has already set this and been
                // configured by the time this runs for it, and AGP refuses a
                // second write of a platform hash once it has been read.
                if (compileSdkVersion != wanted) compileSdkVersion(wanted)
                ndkVersion = rootProject.extra["projectNdk"] as String
                defaultConfig {
                    @Suppress("DEPRECATION")
                    targetSdkVersion(rootProject.extra["projectTargetSdk"] as Int)
                }
            }
        }

        // Standardize Kotlin JVM Target to 17
        project.tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinJvmCompile>().configureEach {
            compilerOptions {
                jvmTarget.set(projectJvmTarget)
            }
        }
    }

    /**
     * Resilient Configuration Hook
     * We use afterEvaluate to ensure we have the "last word" on versions, 
     * while checking state.executed to avoid "already evaluated" crashes.
     */
    if (state.executed) {
        configureAction(this)
    } else {
        afterEvaluate { configureAction(this) }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
