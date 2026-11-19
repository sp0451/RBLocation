pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    // The Flutter Gradle plugin is itself an included build with its own settings.
    // Register before including it so its Kotlin/tooling dependencies use mirrors too.
    if (providers.gradleProperty("clocation.useChinaMirrors").map { it.toBoolean() }.getOrElse(true)) {
        gradle.beforeSettings {
            pluginManagement.repositories {
                maven("https://maven.aliyun.com/repository/google")
                maven("https://maven.aliyun.com/repository/gradle-plugin")
                maven("https://maven.aliyun.com/repository/public")
                gradlePluginPortal()
            }
            dependencyResolutionManagement.repositories {
                maven("https://maven.aliyun.com/repository/google")
                maven("https://maven.aliyun.com/repository/public")
            }
        }
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        if (providers.gradleProperty("clocation.useChinaMirrors").map { it.toBoolean() }.getOrElse(true)) {
            maven("https://maven.aliyun.com/repository/google")
            maven("https://maven.aliyun.com/repository/gradle-plugin")
            maven("https://maven.aliyun.com/repository/public")
        }
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.0.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}

include(":app")
