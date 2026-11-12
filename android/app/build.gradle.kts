import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.oobleck.oobleck"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "dev.oobleck.oobleck"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Release key: from env vars (CI secrets) or android/key.properties (git-ignored).
    // Without either, release builds fall back to the debug key, which cannot
    // update an install signed with the release key.
    val keyProps = Properties().apply {
        val f = rootProject.file("key.properties")
        if (f.exists()) f.inputStream().use { load(it) }
    }
    fun keyValue(env: String, prop: String): String? =
        System.getenv(env)?.takeIf { it.isNotBlank() } ?: keyProps.getProperty(prop)
    val releaseStore = keyValue("OOBLECK_KEYSTORE", "storeFile")
    val releasePassword = keyValue("OOBLECK_KEYSTORE_PASSWORD", "storePassword")

    signingConfigs {
        if (releaseStore != null && releasePassword != null && file(releaseStore).exists()) {
            create("release") {
                storeFile = file(releaseStore)
                storeType = "PKCS12"
                storePassword = releasePassword
                keyAlias = keyValue("OOBLECK_KEY_ALIAS", "keyAlias") ?: "oobleck"
                keyPassword = releasePassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
