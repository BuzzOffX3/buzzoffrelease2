plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    // keep your mixed-case ID
    namespace = "com.apiit.BuzzOff"

    compileSdk = 35

    defaultConfig {
        applicationId = "com.apiit.BuzzOff"   
        minSdk = 23
        targetSdk = 35

        // pull versions from project properties set by Flutter (with safe fallbacks)
        versionCode = (project.findProperty("flutter.versionCode") as String?)?.toInt() ?: 1
        versionName = (project.findProperty("flutter.versionName") as String?) ?: "1.0"

        multiDexEnabled = true

        
        val mapsKey = (project.findProperty("MAPS_API_KEY") as String?) ?: ""
        manifestPlaceholders["MAPS_API_KEY"] = mapsKey
    }

    // Java/Kotlin 17 toolchain
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }

    buildTypes {
        release {
            // TODO: replace with a real release keystore before publishing
            signingConfig = signingConfigs.getByName("debug")
                isMinifyEnabled = true
                proguardFiles(
                   getDefaultProguardFile("proguard-android-optimize.txt"),
                   "proguard-rules.pro"
             )
        }
    }
}

flutter {
    source = "../.."
}
