---
name: mobile-kmp
description: Kotlin Multiplatform standards for Kotlin 2.4 shared code on Android, iOS, and desktop — the AGP 9 Android-KMP library plugin, Ktor 3, kotlinx.serialization, SQLDelight 2 or Room 3, DataStore, Koin 4.2 or Metro, lifecycle ViewModel, Compose Multiplatform 1.12 with Navigation 3, SKIE vs Swift Export, and kotlin.test/Mokkery testing. Use when writing, reviewing, or configuring commonMain/androidMain/iosMain code, expect/actual declarations, or KMP Gradle modules.
paths:
  - "**/src/commonMain/**"
  - "**/src/iosMain/**"
  - "**/src/androidMain/**"
  - "**/src/commonTest/**"
---

# Kotlin Multiplatform Standards

Kotlin language rules: `lang-kotlin`. Android app module, manifest, Play rules: `mobile-android`.
Native iOS app code: `mobile-ios`. Visual design: `design-material3` / `design-apple-hig`.

## Baseline

- Kotlin 2.4.x (2.4.20 current); AGP 9.4; Gradle 9.6; JDK 17; Xcode 26+ on Apple silicon.
- Android target: `com.android.kotlin.multiplatform.library` configured in `kotlin { android { … } }`.
  `com.android.library`/`com.android.application` are incompatible with the KMP plugin on AGP 9,
  and `androidLibrary { }` is deprecated since AGP 9.1.
- The Android app entry point (`MainActivity`, `com.android.application`) lives in a separate
  `androidApp` module that depends on the shared module.
- Apple targets: `iosArm64()` + `iosSimulatorArm64()`. Drop `iosX64()`/`macosX64()` — deprecated in
  Kotlin and removed from Compose Multiplatform. Kotlin 2.4 defaults to iOS 15.0 minimum.
- Library line-up (verify compatibility with your Kotlin version before bumping): kotlinx.coroutines
  1.11, kotlinx.serialization, Ktor 3.6, SQLDelight 2.4 or Room 3.0 (`androidx.room3`), DataStore 1.2,
  multiplatform-settings 1.3, Koin 4.2 or Metro 1.x, `androidx.lifecycle` 2.11 ViewModel,
  Compose Multiplatform 1.12, SKIE 0.10.x, Mokkery 3.5.
- Compiler options with `compilerOptions { … }` only; `kotlinOptions` is an error in Kotlin 2.x.

```kotlin
// shared/build.gradle.kts
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    alias(libs.plugins.kotlin.multiplatform)
    alias(libs.plugins.android.kotlin.multiplatform.library)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.sqldelight)
}

kotlin {
    android {
        namespace = "com.example.shared"
        compileSdk = 37
        minSdk = 26
        compilerOptions { jvmTarget.set(JvmTarget.JVM_17) }
        withHostTest {}
    }
    listOf(iosArm64(), iosSimulatorArm64()).forEach { target ->
        target.binaries.framework {
            baseName = "Shared"
            isStatic = true
        }
    }
    jvm()

    sourceSets {
        commonMain.dependencies {
            implementation(libs.kotlinx.coroutines.core)
            implementation(libs.kotlinx.serialization.json)
            implementation(libs.ktor.client.core)
            implementation(libs.ktor.client.content.negotiation)
            implementation(libs.ktor.serialization.kotlinx.json)
            implementation(libs.sqldelight.coroutines.extensions)
            implementation(libs.koin.core)
            implementation(libs.kermit)
        }
        commonTest.dependencies {
            implementation(libs.kotlin.test)
            implementation(libs.kotlinx.coroutines.test)
            implementation(libs.turbine)
        }
        androidMain.dependencies {
            implementation(libs.ktor.client.okhttp)
            implementation(libs.sqldelight.android.driver)
        }
        iosMain.dependencies {
            implementation(libs.ktor.client.darwin)
            implementation(libs.sqldelight.native.driver)
        }
        jvmMain.dependencies {
            implementation(libs.ktor.client.okhttp)
            implementation(libs.sqldelight.sqlite.driver)
        }
    }
}
```

Read `reference/gradle-setup.md` for the version catalog, KSP per-target configurations, the
`androidApp` module, Compose Multiplatform plugins, and CI tasks.

## Toolchain

- ktlint/detekt on all source sets; Android Lint runs on `androidMain` via the Android-KMP plugin.
- Build every target in CI: `./gradlew :shared:allTests`, `:shared:linkDebugFrameworkIosSimulatorArm64`
  (macOS runner), and the Android/desktop apps. Cache Gradle and `~/.konan`.
- Dependencies via the version catalog with Renovate/Dependabot; bump Kotlin, KSP, SKIE, Mokkery,
  and Compose Multiplatform together — compiler plugins are pinned to Kotlin versions.
- Binary compatibility validator (`abiValidation` in KGP) for shared modules published as libraries.

## Structure

```
shared/src/commonMain/kotlin/com/example/
  orders/domain/        # entities, use cases, ports (OrderRepository, Clock, SecureStore)
  orders/data/          # Ktor + SQLDelight/Room adapters, DTOs, mappers
  orders/presentation/  # ViewModels + UiState (if presentation is shared)
  core/                 # Logger, CrashReporter, AppConfig ports; DI modules
shared/src/androidMain  # actuals / adapters needing Context, Keystore, Android SDKs
shared/src/iosMain      # actuals / adapters over Foundation, Security, UIKit
androidApp/ iosApp/ desktopApp/   # platform entry points only
```

- Share domain, data, and presentation logic; keep platform UI native unless using Compose
  Multiplatform. Entry points and app lifecycle stay per platform.
- `commonMain` imports no `android.*`, `platform.*`, `java.*`, or vendor SDKs. Vendor SDKs
  (Firebase, analytics, payments) sit behind ports implemented in platform source sets or Swift.
- Prefer interfaces + DI over `expect`/`actual`. Use `expect fun`/`expect object` for small
  platform facts; `expect class` needs `-Xexpect-actual-classes` and is rarely worth it.
- `BuildConfig` is Android-only: pass app version, base URL, and flavor into shared code through
  an `AppConfig` data class built by each entry point.
- DTOs (`@Serializable`) stay in the data layer; map to domain models at the repository boundary.

## Data and Networking

- Ktor only in shared code (no Retrofit/OkHttp APIs in `commonMain`). Engines: `ktor-client-okhttp`
  on Android and JVM, `ktor-client-darwin` on iOS. Set timeouts, `expectSuccess = true`, and map
  `ResponseException`/`IOException` to domain errors in the adapter.
- `kotlinx.serialization` only (`Json { ignoreUnknownKeys = true }`); validate decoded payloads
  (ranges, required business fields) before mapping to domain.
- Database: **SQLDelight 2** (SQL-first, `.sq` files, `.sqm` migrations) or **Room 3** (`androidx.room3`,
  annotation DAOs, KSP, `BundledSQLiteDriver`). Both are KMP-ready; pick one per app.
  Room 2.8 (`androidx.room`) also supports KMP for existing Room codebases.
- Key-value: DataStore Preferences (`PreferenceDataStoreFactory.createWithPath`) or
  multiplatform-settings for simple flags. Neither is encrypted.

Read `reference/data-and-networking.md` for Ktor client, SQLDelight, Room 3, and DataStore setup.

## Concurrency

- Suspend functions and `Flow` in shared APIs. Inject dispatchers (`AppDispatchers(io, default, main)`)
  rather than referencing them inside classes.
- `Dispatchers.IO` exists on JVM and Native (in shared Native code add `import kotlinx.coroutines.IO`);
  it does not exist on JS/Wasm. If those targets are present, inject an IO dispatcher per platform.
- `Dispatchers.Main`: Android and iOS provide it; desktop needs `kotlinx-coroutines-swing` (Compose
  Desktop pulls it in).
- `viewModelScope` (lifecycle ViewModel) or an injected scope that the owner cancels; never
  `GlobalScope`. Always rethrow `CancellationException`; `runCatching` swallows it.

## Presentation

- Shared ViewModels extend `androidx.lifecycle.ViewModel` (KMP since 2.8) and expose one
  `StateFlow<UiState>`; one-off events are state the UI acknowledges.
- Swift consumption: SKIE (`co.touchlab.skie`) turns `Flow` into `AsyncSequence`, sealed types into
  exhaustive enums, and `suspend` into `async` with cancellation. Pin the SKIE release that supports
  your Kotlin version (0.10.15 supports 2.4.20).
- Swift Export is Alpha in Kotlin 2.4: direct integration only, generics erased, and it cannot be
  combined with SKIE or the Objective-C export. Evaluate it in a spike; keep production on
  Obj-C export + SKIE until it stabilizes.
- Without SKIE or Swift Export, `for await` over a Kotlin `StateFlow` does not work — expose a
  callback-based `watch(onEach:)` wrapper returning a cancellable handle.

Read `reference/swift-interop.md` for SKIE setup, the no-SKIE wrapper, and Swift Export configuration.

## Compose Multiplatform

- CMP 1.12.1 (`org.jetbrains.compose` + `org.jetbrains.kotlin.plugin.compose`); iOS has been stable
  since 1.8. Minimums: Android API 21, iOS 14 (Kotlin 2.4 defaults to 15).
- Navigation 3 via `org.jetbrains.androidx.navigation3:navigation3-ui`; `@Serializable` `NavKey`s
  shared in `commonMain`. Lifecycle/ViewModel via `org.jetbrains.androidx.lifecycle`.
- Resources through `composeResources/` and the generated `Res` accessors, never `R.*` in common
  code; enable `androidResources { enable = true }` in the `android {}` target.
- Platform widgets (maps, camera, date pickers) via an interface or `expect`/`actual` composable
  wrapping `AndroidView`/`UIKitView`. Respect iOS back-swipe and Android predictive back.

Read `reference/compose-multiplatform.md` for the CMP module setup and Navigation 3 sample.

## Dependency Injection

- Koin 4.2 (`koin-core`, `koin-compose-viewmodel`) — runtime DSL, KMP-native, Navigation 3 support;
  or Metro 1.x (`dev.zacsweers.metro`) — compile-time validated graphs via a compiler plugin.
- Declare modules in `commonMain`; platform modules provide `Context`, drivers, secure storage.
  Start the graph from each entry point (Android `Application`, iOS `@main` app init).
- Hilt is Android-only — confine it to `androidApp` if used at all.

## Errors

- Sealed domain errors + `Outcome<T, E>` (or Arrow `Either`) returned from repositories; no
  exceptions for expected failures, and exceptions never cross into Swift unannotated.
- Kotlin exceptions reaching Swift crash unless the function is `@Throws(...)`; SKIE/Swift Export
  still require you to model failures as values at the boundary.
- Map transport and storage exceptions to domain errors in adapters; log unexpected ones via the
  `Logger`/`CrashReporter` ports.

## Security

- Secrets never live in `commonMain` or the repo; API keys that must ship are restricted
  server-side (package/bundle ID) and treated as public.
- Tokens: a `SecureStore` port. Android actual: Keystore + Tink + DataStore (see `mobile-android`).
  iOS actual: Keychain (`kSecClassGenericPassword`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`)
  via `platform.Security`, or multiplatform-settings `KeychainSettings` (marked experimental).
- There is no `multiplatform-settings-secure` artifact; do not add EncryptedSharedPreferences-based
  wrappers (deprecated).
- Certificate pinning per engine: OkHttp `CertificatePinner` in `androidMain`, Darwin
  `handleChallenge` in `iosMain`; ship backup pins.
- Validate every network payload and deep-link parameter before mapping to domain types.

## Observability

- Kermit (`co.touchlab:kermit`) or a `Logger` port with platform sinks (Logcat, OSLog); no
  `println`. Strip debug logs in release; never log tokens or PII.
- Crash reporting behind a `CrashReporter` port (e.g. Crashlytics via CrashKiOS, Sentry Kotlin
  Multiplatform); upload R8 mappings and dSYMs from CI.

## Testing

- `commonTest` with `kotlin.test`, `kotlinx-coroutines-test` (`runTest`, `StandardTestDispatcher`),
  and Turbine for Flows. Tests run on every target via `allTests`.
- Fakes for ports first; Mokkery (compiler plugin, all KMP targets) when a mock is warranted. MockK
  and Mockito are JVM-only — use them only in `androidHostTest`/`jvmTest`.
- Android host tests live in `androidHostTest` and device tests in `androidDeviceTest` (Android-KMP
  plugin); iOS tests via `iosSimulatorArm64Test` on macOS runners.
- Database tests with in-memory drivers; migration tests for every `.sqm` / Room schema version.
- Ktor adapters tested with `MockEngine`; no real network in unit tests.

Read `reference/testing.md` for commonTest, Mokkery, and MockEngine templates.

_Versions verified September 2026._
