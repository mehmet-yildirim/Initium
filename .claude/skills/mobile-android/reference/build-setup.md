# App module build setup (AGP 9.4, built-in Kotlin)

```kotlin
// app/build.gradle.kts
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)        // org.jetbrains.kotlin.plugin.compose
    alias(libs.plugins.kotlin.serialization)  // org.jetbrains.kotlin.plugin.serialization
    alias(libs.plugins.ksp)                   // com.google.devtools.ksp
    alias(libs.plugins.hilt)                  // com.google.dagger.hilt.android
}

android {
    namespace = "com.example.app"
    compileSdk = 37
    defaultConfig {
        applicationId = "com.example.app"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "1.0.0"
        testInstrumentationRunner = "com.example.app.HiltTestRunner"
    }
    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
    buildFeatures { compose = true }
    androidResources { generateLocaleConfig = true }
}

kotlin {
    compilerOptions { jvmTarget.set(JvmTarget.JVM_17) }
}

dependencies {
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.navigation3.runtime)
    implementation(libs.androidx.navigation3.ui)
    implementation(libs.hilt.android)
    ksp(libs.hilt.compiler)

    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
    testImplementation(libs.turbine)
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.compose.ui.test.junit4)
    debugImplementation(libs.androidx.compose.ui.test.manifest)
}
```

## Migrating an older module to AGP 9

1. Remove `org.jetbrains.kotlin.android` / `kotlin-android` from module, root, and catalog.
2. Move `android { kotlinOptions { … } }` to top-level `kotlin { compilerOptions { … } }`.
3. Replace `kapt(...)` with `ksp(...)`; for processors without KSP support apply
   `com.android.legacy-kapt` (same version as AGP) instead of `org.jetbrains.kotlin.kapt`.
4. `android.builtInKotlin=false` is a temporary escape hatch only; AGP 10 removes it.
5. KMP modules use `com.android.kotlin.multiplatform.library` instead — see `mobile-kmp`.

## Signing and secrets

- Release signing config reads from environment variables or CI secrets
  (`providers.environmentVariable("SIGNING_STORE_PASSWORD")`); never commit keystores or passwords.
- Enroll in Play App Signing; the upload key is replaceable, the app signing key stays with Google.
- API base URLs per flavor via `buildConfigField` are fine; API secrets are not — fetch them from
  your backend after authentication.

## R8

- Keep rules live next to the code they protect (`consumer-rules.pro` in libraries).
- Add rules for reflection-based libraries only when their docs require it; most modern libraries
  ship consumer rules.
- Upload `mapping.txt` to your crash reporter for every release build.
