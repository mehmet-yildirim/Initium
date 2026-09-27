# KMP Gradle setup

## Version catalog (verified September 2026)

```toml
[versions]
kotlin = "2.4.20"
agp = "9.4.0"
ksp = "2.3.12"
coroutines = "1.11.0"
serialization = "1.11.0"
ktor = "3.6.0"
sqldelight = "2.4.0"
room3 = "3.0.3"
sqlite = "2.7.1"
datastore = "1.2.1"
settings = "1.3.0"
koin = "4.2.2"
kermit = "2.2.0"
compose-multiplatform = "1.12.1"
compose-material3 = "1.9.0"          # stable; 1.12.0-alpha03 for Expressive
jetbrains-lifecycle = "2.11.0"
jetbrains-navigation3 = "1.1.2"
skie = "0.10.15"
mokkery = "3.5.0"
turbine = "1.2.1"

[libraries]
kotlinx-coroutines-core = { module = "org.jetbrains.kotlinx:kotlinx-coroutines-core", version.ref = "coroutines" }
kotlinx-coroutines-swing = { module = "org.jetbrains.kotlinx:kotlinx-coroutines-swing", version.ref = "coroutines" }
kotlinx-coroutines-test = { module = "org.jetbrains.kotlinx:kotlinx-coroutines-test", version.ref = "coroutines" }
kotlinx-serialization-json = { module = "org.jetbrains.kotlinx:kotlinx-serialization-json", version.ref = "serialization" }
ktor-client-core = { module = "io.ktor:ktor-client-core", version.ref = "ktor" }
ktor-client-content-negotiation = { module = "io.ktor:ktor-client-content-negotiation", version.ref = "ktor" }
ktor-client-logging = { module = "io.ktor:ktor-client-logging", version.ref = "ktor" }
ktor-client-okhttp = { module = "io.ktor:ktor-client-okhttp", version.ref = "ktor" }
ktor-client-darwin = { module = "io.ktor:ktor-client-darwin", version.ref = "ktor" }
ktor-client-mock = { module = "io.ktor:ktor-client-mock", version.ref = "ktor" }
ktor-serialization-kotlinx-json = { module = "io.ktor:ktor-serialization-kotlinx-json", version.ref = "ktor" }
sqldelight-coroutines-extensions = { module = "app.cash.sqldelight:coroutines-extensions", version.ref = "sqldelight" }
sqldelight-android-driver = { module = "app.cash.sqldelight:android-driver", version.ref = "sqldelight" }
sqldelight-native-driver = { module = "app.cash.sqldelight:native-driver", version.ref = "sqldelight" }
sqldelight-sqlite-driver = { module = "app.cash.sqldelight:sqlite-driver", version.ref = "sqldelight" }
androidx-room3-runtime = { module = "androidx.room3:room3-runtime", version.ref = "room3" }
androidx-room3-compiler = { module = "androidx.room3:room3-compiler", version.ref = "room3" }
androidx-sqlite-bundled = { module = "androidx.sqlite:sqlite-bundled", version.ref = "sqlite" }
androidx-datastore-preferences = { module = "androidx.datastore:datastore-preferences", version.ref = "datastore" }
multiplatform-settings = { module = "com.russhwolf:multiplatform-settings", version.ref = "settings" }
koin-core = { module = "io.insert-koin:koin-core", version.ref = "koin" }
koin-compose-viewmodel = { module = "io.insert-koin:koin-compose-viewmodel", version.ref = "koin" }
kermit = { module = "co.touchlab:kermit", version.ref = "kermit" }
jetbrains-lifecycle-viewmodel-compose = { module = "org.jetbrains.androidx.lifecycle:lifecycle-viewmodel-compose", version.ref = "jetbrains-lifecycle" }
jetbrains-navigation3-ui = { module = "org.jetbrains.androidx.navigation3:navigation3-ui", version.ref = "jetbrains-navigation3" }
kotlin-test = { module = "org.jetbrains.kotlin:kotlin-test", version.ref = "kotlin" }
turbine = { module = "app.cash.turbine:turbine", version.ref = "turbine" }

[plugins]
kotlin-multiplatform = { id = "org.jetbrains.kotlin.multiplatform", version.ref = "kotlin" }
kotlin-serialization = { id = "org.jetbrains.kotlin.plugin.serialization", version.ref = "kotlin" }
kotlin-compose = { id = "org.jetbrains.kotlin.plugin.compose", version.ref = "kotlin" }
android-application = { id = "com.android.application", version.ref = "agp" }
android-kotlin-multiplatform-library = { id = "com.android.kotlin.multiplatform.library", version.ref = "agp" }
compose-multiplatform = { id = "org.jetbrains.compose", version.ref = "compose-multiplatform" }
ksp = { id = "com.google.devtools.ksp", version.ref = "ksp" }
sqldelight = { id = "app.cash.sqldelight", version.ref = "sqldelight" }
room3 = { id = "androidx.room3", version.ref = "room3" }
skie = { id = "co.touchlab.skie", version.ref = "skie" }
mokkery = { id = "dev.mokkery", version.ref = "mokkery" }
```

Compiler plugins (KSP, SKIE, Mokkery, Compose compiler) are tied to Kotlin versions — bump them in
the same PR as `kotlin`, and check each project's compatibility notes first.

## Android app module (AGP 9)

```kotlin
// androidApp/build.gradle.kts — no kotlin-android plugin: AGP 9 has built-in Kotlin
plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
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
    }
    buildFeatures { compose = true }
}

dependencies {
    implementation(projects.shared)
}
```

- Namespaces must differ between `androidApp` and the shared module.
- The Android-KMP library plugin has a single variant (no build types or flavors): keep
  debug-only tooling in `androidApp`, and pass environment differences in via `AppConfig`.
- Host tests: `withHostTest {}` → `src/androidHostTest`; device tests: `withDeviceTest {}` →
  `src/androidDeviceTest`.

## KSP in KMP (Room 3 and other processors)

The shared `ksp(...)` configuration is deprecated in KMP; add processors per target:

```kotlin
dependencies {
    add("kspAndroid", libs.androidx.room3.compiler)
    add("kspIosArm64", libs.androidx.room3.compiler)
    add("kspIosSimulatorArm64", libs.androidx.room3.compiler)
    add("kspJvm", libs.androidx.room3.compiler)
}
```

## SQLDelight database declaration

```kotlin
sqldelight {
    databases {
        create("AppDatabase") {
            packageName.set("com.example.shared.db")
            schemaOutputDirectory.set(file("src/commonMain/sqldelight/databases"))
            verifyMigrations.set(true)
        }
    }
}
```

## CI tasks

```bash
./gradlew :shared:allTests                                  # every target's tests
./gradlew :shared:linkDebugFrameworkIosSimulatorArm64       # macOS runner
./gradlew :shared:iosSimulatorArm64Test                     # macOS runner
./gradlew :androidApp:assembleRelease :androidApp:lintRelease
./gradlew :shared:verifySqlDelightMigration                 # if SQLDelight migrations exist
```

- Run iOS jobs on Apple silicon macOS runners with the Xcode version the app ships with.
- Cache `~/.gradle/caches`, `~/.gradle/wrapper`, and `~/.konan`.
