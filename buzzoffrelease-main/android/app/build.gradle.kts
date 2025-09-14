plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.apiit.BuzzOff"

    // Compile against Android 15 (API 35) for the plugins you're using
    compileSdk = 35

    defaultConfig {
        applicationId = "com.apiit.BuzzOff"

        // Firebase Auth requires 23+
        minSdk = 23
        // OK to keep target at 35 (runtime behavior)
        targetSdk = 35

        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Helpful with many deps
        multiDexEnabled = true
    }

    // Java/Kotlin toolchains (avoid JDK 8 issues)
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }

    buildTypes {
        release {
            // TODO: replace with your release signing when ready
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
