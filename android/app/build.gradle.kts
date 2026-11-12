import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.ksp)
}

// google-services.json is not in git (like GoogleService-Info.plist on iOS). Without it the app
// still builds and runs; sign-in then reports that Firebase is not set up.
if (file("google-services.json").exists()) {
    apply(plugin = libs.plugins.google.services.get().pluginId)
}

// Release signing for Google Play. keystore.properties (not in git) points to the upload key and
// holds its passwords. Without it, release builds are simply unsigned.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("keystore.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

// A release build without either of those still succeeds, and that is how iOS 1.6.1 reached users:
// it built fine and crashed at launch. Debug builds stay forgiving; any release build stops here.
val missingReleaseInputs: List<String> = buildList {
    if (!file("google-services.json").exists()) {
        add("android/app/google-services.json (Firebase config; without it sign-in does not work)")
    }
    val storeFile = keystoreProperties.getProperty("storeFile")
    if (storeFile == null) {
        add("android/keystore.properties with storeFile, storePassword, keyAlias, keyPassword (upload key)")
    } else if (!file(storeFile).exists()) {
        add("the upload keystore named in keystore.properties: $storeFile")
    }
}

// preReleaseBuild runs before every release variant task (bundleRelease, assembleRelease, ...).
tasks.matching { it.name == "preReleaseBuild" }.configureEach {
    // A plain String: the configuration cache cannot store Kotlin's buildList collections.
    val missing: String = missingReleaseInputs.joinToString("\n") { "  - $it" }
    doFirst {
        if (missing.isNotEmpty()) {
            throw GradleException("Release build refused. Missing:\n$missing\nSee docs/release-checklist.md.")
        }
    }
}

android {
    namespace = "com.arthurrios.finova"
    compileSdk = 36

    defaultConfig {
        // Permanent once the app is on Google Play.
        applicationId = "com.arthurrios.finova"
        minSdk = 26
        targetSdk = 36
        // Kept in step with the iOS feature line this build ports (release/v1.6.0).
        versionCode = 8
        versionName = "1.6.2"
    }

    signingConfigs {
        if (keystoreProperties.containsKey("storeFile")) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
    }
}

kotlin {
    jvmToolchain(17)
}

ksp {
    // Room writes the schema here so later migrations can be checked against it.
    arg("room.schemaLocation", "$projectDir/schemas")
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.work.runtime.ktx)
    implementation(libs.play.app.update.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.graphics)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.material.icons.extended)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.navigation.compose)
    implementation(libs.androidx.biometric)
    // BiometricPrompt needs a FragmentActivity; this keeps it on a current Fragment release.
    implementation(libs.androidx.fragment.ktx)
    implementation(libs.androidx.core.splashscreen)
    implementation(platform(libs.firebase.bom))
    implementation(libs.firebase.auth)
    implementation(libs.androidx.credentials)
    implementation(libs.androidx.credentials.play.services.auth)
    implementation(libs.googleid)
    implementation(libs.kotlinx.coroutines.play.services)
    implementation(libs.androidx.room.runtime)
    implementation(libs.androidx.room.ktx)
    ksp(libs.androidx.room.compiler)
    debugImplementation(libs.androidx.compose.ui.tooling)

    testImplementation(libs.junit)
}
