import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

val requestedReleaseBuild = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}

fun requiredSigningProperty(name: String): String {
    val value = keystoreProperties.getProperty(name)?.trim()
    if (value.isNullOrEmpty() || value == "CHANGE_ME") {
        throw GradleException("Missing Android release signing property: $name")
    }
    return value
}

if (requestedReleaseBuild && !keystorePropertiesFile.exists()) {
    throw GradleException(
        "Android release signing is not configured. Run tools/configure_android_upload_key.sh first."
    )
}

if (requestedReleaseBuild && keystorePropertiesFile.exists()) {
    val configuredAlias = requiredSigningProperty("keyAlias")
    val configuredStore = requiredSigningProperty("storeFile")
    if (configuredAlias.equals("androiddebugkey", ignoreCase = true) ||
        configuredStore.endsWith("debug.keystore")) {
        throw GradleException(
            "Android release builds must use the dedicated upload key, not the debug keystore."
        )
    }
}

android {
    namespace = "com.codeword.codeword"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.codeword.codeword"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    flavorDimensions += "distribution"
    productFlavors {
        create("github") {
            dimension = "distribution"
        }
        create("play") {
            dimension = "distribution"
        }
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = requiredSigningProperty("keyAlias")
                keyPassword = requiredSigningProperty("keyPassword")
                storeFile = file(requiredSigningProperty("storeFile")).also {
                    if (requestedReleaseBuild && !it.isFile) {
                        throw GradleException("Android release keystore does not exist: $it")
                    }
                }
                storePassword = requiredSigningProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

flutter {
    source = "../.."
}
