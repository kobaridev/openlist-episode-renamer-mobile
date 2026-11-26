pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        // Seeded local repo (~/workspace/local-maven): holds the kotlin-dsl
        // 6.5.7 plugin marker + implementation, which the Flutter Gradle
        // plugin needs but Gradle's HTTP client cannot fetch from
        // plugins.gradle.org through this VM's egress proxy (connections
        // get reset; curl works). Checked inline: pluginManagement cannot
        // see top-level vals. Harmless elsewhere: skipped when the dir
        // does not exist.
        if (File("/home/hatch/workspace/local-maven").exists()) {
            maven { url = uri("/home/hatch/workspace/local-maven") }
        }
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.3.1" apply false
    id("org.jetbrains.kotlin.android") version "2.4.20" apply false
}

include(":app")
