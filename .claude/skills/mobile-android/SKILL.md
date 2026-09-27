---
name: mobile-android
description: Native Android standards for Kotlin 2.4, AGP 9.4 (built-in Kotlin), Jetpack Compose (BOM 2026.09), Navigation 3, Hilt, Room, DataStore, WorkManager, and KSP — plus Play requirements (targetSdk 36, 16 KB pages, Data safety), edge-to-edge, predictive back, R8, Baseline Profiles, Keystore-backed storage, and JUnit/Compose testing. Use when writing, reviewing, or configuring an Android app module, its manifest, resources, or Gradle build.
paths:
  - "**/AndroidManifest.xml"
  - "**/src/main/res/**"
  - "**/app/build.gradle.kts"
---

# Android Development Standards

Kotlin language rules: `lang-kotlin`. Shared KMP code: `mobile-kmp`. Visual design (color roles,
type, adaptive layouts, motion): `design-material3`.

## Baseline

- Kotlin 2.4.x (2.4.20 current), AGP 9.4 with Gradle 9.6, JDK 17.
- AGP 9 compiles Kotlin itself: do **not** apply `org.jetbrains.kotlin.android`; configure the
  compiler with top-level `kotlin { compilerOptions { … } }`, not `android.kotlinOptions`.
- Compose via the BOM (`androidx.compose:compose-bom:2026.09.00`) and the
  `org.jetbrains.kotlin.plugin.compose` plugin at the Kotlin version. Compose 1.12 requires
  `compileSdk = 37`.
- `targetSdk = 36` minimum (Play requires it for new apps and updates since 2026-08-31); move to
  37 once tested. `minSdk` is a product decision; never raise it without one.
- Annotation processing with KSP (`com.google.devtools.ksp`, 2.3.x). kapt is in maintenance mode
  and incompatible with built-in Kotlin; use `com.android.legacy-kapt` only for processors
  without KSP support (e.g. Data Binding).
- Version catalog (`gradle/libs.versions.toml`) for every dependency and plugin; no inline versions.

Read `reference/build-setup.md` when creating or migrating `app/build.gradle.kts` (AGP 9, built-in
Kotlin, KSP, R8, signing).

## Toolchain

- Format/lint: ktlint (or Spotless + ktlint), detekt, Android Lint with `warningsAsErrors` in CI,
  and Compose lint rules. Commit a lint baseline only as a migration step.
- Compose compiler reports (`composeCompiler { reportsDestination = … }`) to catch unstable types.
- Dependencies: Dependabot or Renovate on the version catalog; fail CI on known high/critical CVEs.
- Release builds: R8 full mode with `isMinifyEnabled` + `isShrinkResources`; keep rules committed
  and exercised by a release-variant UI test. ProGuard is not used separately.

## Structure

Feature modules, hexagonal inside each feature:

```
feature/orders/
  domain/     # entities, use cases, repository + gateway ports (pure Kotlin, no android.*)
  data/       # Room/Retrofit/DataStore adapters implementing the ports, DTO ↔ domain mappers
  ui/         # ViewModel, UiState, stateless composables, *Screen entry composable
core/         # shared ports (Logger, CrashReporter, Analytics, Clock) and their adapters
app/          # Application, MainActivity, DI graph, NavDisplay
```

- Domain and data never import Compose or Activity types. ViewModels depend on use cases or ports.
- Wrap every vendor SDK (Firebase, analytics, payments, maps, push, crash reporting) in an adapter
  behind a port in `core/`; feature code never imports `com.google.firebase.*`.
- Hilt (`com.google.dagger:hilt-android` 2.60.x, KSP): `@HiltAndroidApp`, `@AndroidEntryPoint`,
  `@HiltViewModel`; `@Binds` interfaces to implementations in per-feature `@Module`s.
- Room: `androidx.room3` 3.0 (KSP-only, coroutine APIs, `SQLiteDriver`) for new code;
  `androidx.room` 2.8 for existing apps. Commit exported schemas; write explicit migrations and test
  them with `MigrationTestHelper`.
- DataStore (Preferences or typed) for key-value data — not `SharedPreferences`; access only via a
  repository.
- Networking: Retrofit or Ktor over OkHttp with `kotlinx.serialization`; timeouts set explicitly;
  auth via an interceptor that reads from the token store port.

## UI State and Compose

- One ViewModel per screen exposing a single `StateFlow<UiState>` (immutable data class or sealed
  interface). Collect with `collectAsStateWithLifecycle()`.
- Model one-off events (snackbar, navigation after save) as **state** the UI consumes and then
  reports back — not as `SharedFlow`/`Channel` events that can be lost across configuration changes.
- Screen composable (`*Screen`) takes the ViewModel; everything below receives state + lambdas and a
  `modifier: Modifier = Modifier` parameter. Stateless composables have previews.
- `rememberSaveable` for UI state that must survive process death; `key = { it.id }` in lazy lists;
  `derivedStateOf` for values derived from frequently changing state.
- Never hardcode colors, dimensions, or strings in composables — theme tokens and `stringResource`.

```kotlin
data class UserListUiState(
    val isLoading: Boolean = false,
    val users: List<User> = emptyList(),
    val error: UserError? = null,
)

@HiltViewModel
class UserListViewModel @Inject constructor(
    private val getUsers: GetUsersUseCase,
) : ViewModel() {
    private val _uiState = MutableStateFlow(UserListUiState(isLoading = true))
    val uiState: StateFlow<UserListUiState> = _uiState.asStateFlow()

    init { refresh() }

    fun refresh() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true) }
            when (val result = getUsers()) {
                is Outcome.Ok -> _uiState.update { it.copy(isLoading = false, users = result.value) }
                is Outcome.Err -> _uiState.update { it.copy(isLoading = false, error = result.error) }
            }
        }
    }

    fun errorShown() = _uiState.update { it.copy(error = null) }
}

@Composable
fun UserListScreen(viewModel: UserListViewModel = hiltViewModel(), onUserClick: (String) -> Unit) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val snackbarHostState = remember { SnackbarHostState() }
    state.error?.let { error ->
        val message = stringResource(error.messageRes)
        LaunchedEffect(error) {
            snackbarHostState.showSnackbar(message)
            viewModel.errorShown()
        }
    }
    UserListContent(state, snackbarHostState, onUserClick, onRefresh = viewModel::refresh)
}
```

## Navigation

- New apps: Navigation 3 (`androidx.navigation3` 1.2, stable) — `@Serializable` keys implementing
  `NavKey`, `rememberNavBackStack`, `NavDisplay` with an `entryProvider`. Existing Nav 2 apps:
  type-safe routes (Navigation 2.8+, current 2.10) with `composable<Route>` and `toRoute()`.
- No string routes, no `!!` on arguments, no manual fragment back stacks.
- Deep links are validated and mapped to keys in one place; never trust deep-link parameters.

Read `reference/navigation.md` when setting up Navigation 3, adaptive list-detail scenes, or
migrating from Nav 2.

## Errors

- Domain errors are sealed types (`sealed interface UserError`); repositories return
  `Outcome<T, E>` (or Arrow `Either`) — no exceptions for expected failures.
- Map transport errors (HTTP status, `IOException`, `SQLiteException`) to domain errors in the
  data adapter; the UI maps domain errors to string resources.
- `runCatching` also catches `CancellationException` — rethrow it (or catch specific exceptions) in
  any `suspend` code.
- Never swallow: unexpected errors go to the `Logger`/`CrashReporter` ports before being mapped.

```kotlin
sealed interface Outcome<out T, out E> {
    data class Ok<T>(val value: T) : Outcome<T, Nothing>
    data class Err<E>(val error: E) : Outcome<Nothing, E>
}

sealed interface UserError {
    data object Offline : UserError
    data object NotFound : UserError
}

// ui layer
@get:StringRes
val UserError.messageRes: Int
    get() = when (this) {
        UserError.Offline -> R.string.error_offline
        UserError.NotFound -> R.string.error_user_not_found
    }
```

## Concurrency

- Coroutines + Flow only (no RxJava, no `AsyncTask`, no `GlobalScope`). Inject dispatchers
  (`@IoDispatcher`) instead of hardcoding `Dispatchers.IO` so tests can replace them.
- `viewModelScope` for UI work; `WorkManager` (`CoroutineWorker`, Hilt-injected via
  `androidx.hilt:hilt-work`) for deferrable or guaranteed background work with constraints and
  exponential backoff. Foreground services only with the matching `foregroundServiceType`.
- `stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), initial)` for derived flows.

## Platform Requirements

- **Edge-to-edge:** enforced when targeting 35+, no opt-out at 36. Call `enableEdgeToEdge()` in
  every Activity and handle `WindowInsets` (system bars, IME, cutout) on every screen.
- **Predictive back:** on by default at targetSdk 36. Use `BackHandler`/`PredictiveBackHandler` or
  `OnBackPressedCallback`; never override `onBackPressed()`.
- **Large screens:** at targetSdk 36, orientation/resizability/aspect-ratio locks are ignored on
  displays ≥ 600 dp (opt-out removed at 37). Layouts must adapt — see `design-material3`.
- **16 KB page size:** Play requires 16 KB-aligned native libraries for apps targeting Android 15+.
  Build with NDK r28+, check APK Analyzer alignment, and replace SDKs that ship 4 KB `.so` files.
- **Notifications:** request `POST_NOTIFICATIONS` at runtime (API 33+) in context; FCM behind a
  `PushMessaging` port; send the token to the backend over an authenticated call.
- **App Links:** `android:autoVerify="true"` intent filters plus `/.well-known/assetlinks.json` on
  each host; verify with `adb shell pm get-app-links`.
- **Localization:** per-app language via `generateLocaleConfig` + `res/resources.properties`
  (`unqualifiedResLocale=en`); all strings in resources; RTL-safe `start`/`end` layouts; test a
  pseudo-locale (`en-XA`, `ar-XB`) build.
- **Baseline Profiles** (`androidx.baselineprofile` plugin + Macrobenchmark module) for startup
  and critical journeys; track cold start and jank in CI.

Read `reference/platform-features.md` for push, WorkManager, App Links, locale, and Baseline Profile
recipes.

## Security

- Tokens and secrets at rest: Android Keystore key → Tink AEAD → DataStore. EncryptedSharedPreferences
  (`androidx.security:security-crypto`) is deprecated — do not use it in new code; migrate existing data.
- Exclude encrypted files from Auto Backup (`android:dataExtractionRules`): Keystore keys do not
  restore, so backed-up ciphertext becomes unreadable.
- `network_security_config.xml`: no cleartext; pin only with a backup pin and an expiry plan.
- Verify device/app integrity server-side with the Play Integrity API (Standard requests) for
  sensitive actions; never trust client-only checks.
- No API keys or secrets in `BuildConfig`, resources, or the repo; signing keys and
  `keystore.properties` come from CI secrets. Play App Signing enabled.
- Exported components are explicit (`android:exported`), protected by permissions, and validate
  every `Intent` extra. `PendingIntent` uses `FLAG_IMMUTABLE`.

Read `reference/security-storage.md` for the Keystore + Tink + DataStore token store.

## Store Compliance

- Play Data safety form matches actual collection, including every third-party SDK; update it
  with each SDK change. Provide in-app and web account deletion if accounts exist.
- Declare only needed permissions; sensitive ones (location, SMS, all-files) need policy review.
- Ship `.aab` via Play App Signing; staged rollouts with crash/ANR thresholds (Android vitals).

## Accessibility

- Touch targets ≥ 48×48 dp; `contentDescription` or text on every actionable element;
  `Modifier.semantics { heading() }` for headings; merge descendants for compound rows.
- Works at 200% font scale and with TalkBack, Switch Access, and keyboard navigation.

## Observability

- A `Logger` port backed by Timber (or Kermit) with a release tree that drops debug logs and never
  logs tokens or PII; no `println`/`Log.d` in feature code.
- Crash and ANR reporting (e.g. Firebase Crashlytics, Sentry) behind a `CrashReporter` port; upload
  R8 mapping files in CI. Use the OpenTelemetry Android agent or vendor SDK behind an adapter for traces.

## Testing

- Local unit tests (`src/test`): JUnit 4 by default; JUnit 5 only via the `android-junit5` Gradle
  plugin. Coroutines with `kotlinx-coroutines-test` (`runTest`, `StandardTestDispatcher`, a
  `MainDispatcherRule`), Flows with Turbine, fakes for ports (MockK only for awkward types).
- Compose UI tests use JUnit 4 rules (`createComposeRule`, `createAndroidComposeRule`) — run them
  instrumented or under Robolectric; select nodes via `Modifier.testTag` / text / semantics.
- Hilt integration tests with `@HiltAndroidTest` + `HiltAndroidRule`; Room migrations with
  `MigrationTestHelper`; screenshot tests for design-system components.
- Macrobenchmark for startup and scroll; release-variant smoke test to catch R8 issues.

Read `reference/testing.md` for ViewModel, Flow, and Compose test templates.

_Versions verified September 2026._
