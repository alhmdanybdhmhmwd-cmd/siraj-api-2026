plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}


val barqGoogleOidcClientId = System.getenv("BARQ_GOOGLE_OIDC_CLIENT_ID").orEmpty()
val barqAdminKeystorePath = System.getenv("BARQ_ADMIN_KEYSTORE_PATH").orEmpty()
val barqAdminKeystorePassword = System.getenv("BARQ_ADMIN_KEYSTORE_PASSWORD").orEmpty()
val barqAdminKeyAlias = System.getenv("BARQ_ADMIN_KEY_ALIAS").orEmpty()
val barqAdminKeyPassword = System.getenv("BARQ_ADMIN_KEY_PASSWORD").orEmpty()
val hasBarqAdminReleaseSigning = listOf(
    barqAdminKeystorePath,
    barqAdminKeystorePassword,
    barqAdminKeyAlias,
    barqAdminKeyPassword
).all { it.isNotBlank() }

val barqGoogleOidcRedirectScheme =
    if (barqGoogleOidcClientId.endsWith(".apps.googleusercontent.com")) {
        "com.googleusercontent.apps." + barqGoogleOidcClientId.substringBefore(".")
    } else {
        "com.barq.admin.auth"
    }

android {
    namespace = "com.barq.admin"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.barq.admin"
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
        manifestPlaceholders["appAuthRedirectScheme"] = barqGoogleOidcRedirectScheme
    }

    signingConfigs {
        if (hasBarqAdminReleaseSigning) {
            create("barqAdminRelease") {
                storeFile = file(barqAdminKeystorePath)
                storePassword = barqAdminKeystorePassword
                keyAlias = barqAdminKeyAlias
                keyPassword = barqAdminKeyPassword
            }
        }
    }

    buildTypes {
        release {
            check(hasBarqAdminReleaseSigning) {
                "BARQ Admin release builds require the stable BARQ_ADMIN signing keystore and credentials."
            }
            signingConfig = signingConfigs.getByName("barqAdminRelease")
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
