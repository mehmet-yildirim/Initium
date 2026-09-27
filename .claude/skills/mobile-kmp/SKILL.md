---
name: mobile-kmp
description: Kotlin Multiplatform (KMP) standards — shared business logic targeting Android, iOS, Desktop, and Web. Ktor, kotlinx.serialization, SQLDelight, Koin, Compose Multiplatform. Use when writing or reviewing Kotlin Multiplatform shared code.
paths:
  - "**/commonMain/**/*.kt"
  - "**/commonTest/**/*.kt"
  - "**/iosMain/**/*.kt"
  - "**/androidMain/**/*.kt"
  - "**/desktopMain/**/*.kt"
  - "**/wasmJsMain/**/*.kt"
  - "**/shared/**/*.kt"
  - "**/shared/build.gradle.kts"
  - "**/composeApp/**/*.kt"
  - "**/composeApp/build.gradle.kts"
---

# Kotlin Multiplatform (KMP) Standards

## What to Share vs. What to Keep Native

```
┌──────────────────────────────────────────────────┐
│              Shared (commonMain)                 │
│  Domain: entities, use cases, repository interfaces│
│  Data: repository implementations, DTOs         │
│  Network: Ktor client, API services             │
│  Storage: SQLDelight, multiplatform-settings    │
│  ViewModel / Presentation logic (KMP ViewModel) │
│  Business rules and validation                  │
└──────────────┬───────────────────────────────────┘
               │  expect / actual
    ┌──────────┴──────────┐
    ▼                     ▼
 androidMain           iosMain / iosSimulatorArm64Main
 (Hilt if needed,      (Swift/Obj-C interop,
  Room fallback,        MainThread dispatching)
  Android Context)
```

**Share:** business logic, networking, serialization, local DB schema, ViewModels, state.
**Keep native:** UI (unless using Compose Multiplatform), platform APIs, DI wiring, app lifecycle.

---

## Project Structure

```
project/
├── shared/
│   ├── build.gradle.kts         # KMP module definition
│   └── src/
│       ├── commonMain/kotlin/   # All platform-shared code
│       ├── commonTest/kotlin/   # Platform-agnostic tests
│       ├── androidMain/kotlin/  # Android actuals + Android-only code
│       ├── iosMain/kotlin/      # iOS actuals
│       └── desktopMain/kotlin/  # JVM desktop actuals (if targeting desktop)
├── composeApp/                  # Compose Multiplatform UI (optional)
│   └── src/
│       ├── commonMain/kotlin/   # Shared Compose UI
│       ├── androidMain/kotlin/  # Android-specific composables / resources
│       └── iosMain/kotlin/      # iOS-specific composables
├── androidApp/                  # Android entry point (if separate from composeApp)
└── iosApp/                      # Xcode project wrapping the KMP framework
```

---

## Gradle Configuration

```kotlin
// shared/build.gradle.kts
plugins {
    alias(libs.plugins.kotlinMultiplatform)
    alias(libs.plugins.kotlinSerialization)
    alias(libs.plugins.sqldelight)
}

kotlin {
    androidTarget {
        compilations.all {
            kotlinOptions { jvmTarget = "17" }
        }
    }
    listOf(
        iosX64(),
        iosArm64(),
        iosSimulatorArm64()
    ).forEach { iosTarget ->
        iosTarget.binaries.framework {
            baseName = "Shared"
            isStatic = true
        }
    }
    // Desktop target (optional)
    jvm("desktop")

    sourceSets {
        commonMain.dependencies {
            implementation(libs.kotlinx.coroutines.core)
            implementation(libs.kotlinx.serialization.json)
            implementation(libs.ktor.client.core)
            implementation(libs.ktor.client.contentNegotiation)
            implementation(libs.ktor.serialization.kotlinx.json)
            implementation(libs.sqldelight.runtime)
            implementation(libs.koin.core)
        }
        commonTest.dependencies {
            implementation(libs.kotlin.test)
            implementation(libs.kotlinx.coroutines.test)
        }
        androidMain.dependencies {
            implementation(libs.ktor.client.android)
            implementation(libs.sqldelight.android.driver)
            implementation(libs.koin.android)
        }
        iosMain.dependencies {
            implementation(libs.ktor.client.darwin)
            implementation(libs.sqldelight.native.driver)
        }
    }
}
```

---

## expect / actual

The `expect` / `actual` mechanism is KMP's primary tool for platform variance.

```kotlin
// commonMain — declare the contract
expect class PlatformContext

expect fun platformDispatcher(): CoroutineDispatcher

expect fun createDatabase(context: PlatformContext): AppDatabase
```

```kotlin
// androidMain — Android implementation
actual class PlatformContext(val context: android.content.Context)

actual fun platformDispatcher(): CoroutineDispatcher = Dispatchers.IO

actual fun createDatabase(context: PlatformContext): AppDatabase =
    AppDatabase(AndroidSqliteDriver(AppDatabase.Schema, context.context, "app.db"))
```

```kotlin
// iosMain — iOS implementation
actual class PlatformContext  // no constructor parameters needed on iOS

actual fun platformDispatcher(): CoroutineDispatcher = Dispatchers.Default

actual fun createDatabase(context: PlatformContext): AppDatabase =
    AppDatabase(NativeSqliteDriver(AppDatabase.Schema, "app.db"))
```

**Rules:**
- Keep `expect` declarations minimal — the less platform-specific surface, the better
- Never leak Android/iOS imports into `commonMain`
- Prefer interfaces + DI over `expect/actual` when the contract is complex
- `expect class` is appropriate for platform wrappers (`Logger`, `PlatformContext`, `Database`)

---

## Networking (Ktor)

Use Ktor — the only HTTP client with a true multiplatform engine.
**Never use Retrofit in shared code** — it is Android/JVM only.

```kotlin
// commonMain
class HttpClientFactory(private val json: Json = Json { ignoreUnknownKeys = true }) {

    fun create(): HttpClient = HttpClient {
        install(ContentNegotiation) { json(json) }
        install(HttpTimeout) {
            requestTimeoutMillis = 30_000
            connectTimeoutMillis = 15_000
        }
        install(Logging) {
            level = LogLevel.HEADERS
            logger = object : Logger {
                override fun log(message: String) { /* use platform logger */ }
            }
        }
        defaultRequest {
            contentType(ContentType.Application.Json)
            header("X-App-Version", BuildConfig.APP_VERSION)
        }
    }
}

// API service in commonMain
class UserApiService(private val client: HttpClient, private val baseUrl: String) {

    suspend fun getUser(id: String): Result<UserDto> = runCatching {
        client.get("$baseUrl/users/$id").body<UserDto>()
    }

    suspend fun createUser(request: CreateUserRequest): Result<UserDto> = runCatching {
        client.post("$baseUrl/users") {
            setBody(request)
        }.body<UserDto>()
    }
}
```

**Ktor engine per platform:**
- Android: `ktor-client-android` (OkHttp-based)
- iOS: `ktor-client-darwin` (NSURLSession-based)
- Desktop: `ktor-client-java` or `ktor-client-okhttp`

---

## Serialization (kotlinx.serialization)

**Only `kotlinx.serialization` works in commonMain.** Do not use Gson or Moshi in shared code.

```kotlin
@Serializable
data class UserDto(
    val id: String,
    val name: String,
    val email: String,
    @SerialName("created_at") val createdAt: Long
)

@Serializable
data class CreateUserRequest(
    val name: String,
    val email: String
)

// Enum serialization
@Serializable
enum class UserRole {
    @SerialName("admin") ADMIN,
    @SerialName("user") USER,
    @SerialName("guest") GUEST
}
```

- `@SerialName` for snake_case JSON keys
- `@Transient` to exclude a field from serialization
- `@Required` to enforce a field is present during deserialization
- Use `Json { ignoreUnknownKeys = true; coerceInputValues = true }` for resilient parsing

---

## Local Storage (SQLDelight)

SQLDelight generates type-safe Kotlin code from `.sq` SQL files and runs on all platforms.
**Never use Room in commonMain** — it is Android-only.

```sql
-- commonMain/sqldelight/com/example/app/User.sq

CREATE TABLE User (
    id TEXT NOT NULL PRIMARY KEY,
    name TEXT NOT NULL,
    email TEXT NOT NULL,
    created_at INTEGER NOT NULL
);

selectAll:
SELECT * FROM User ORDER BY created_at DESC;

selectById:
SELECT * FROM User WHERE id = :id;

insert:
INSERT OR REPLACE INTO User(id, name, email, created_at)
VALUES (?, ?, ?, ?);

deleteById:
DELETE FROM User WHERE id = :id;
```

```kotlin
// commonMain — repository using generated queries
class UserLocalDataSource(private val database: AppDatabase) {

    fun getAllUsers(): Flow<List<User>> =
        database.userQueries.selectAll()
            .asFlow()
            .mapToList(Dispatchers.Default)

    suspend fun insertUser(user: User) {
        withContext(Dispatchers.Default) {
            database.userQueries.insert(user.id, user.name, user.email, user.createdAt)
        }
    }
}
```

- `asFlow()` extension from `sqldelight-coroutines-extensions`
- `mapToList` / `mapToOne` / `mapToOneOrNull` for Flow transformations
- Migrations in numbered `.sqm` files alongside `.sq` files
- Always test migrations before applying to production

**Simple key-value storage:**
```kotlin
// Use multiplatform-settings for preferences/flags (not SharedPreferences)
val settings: Settings = // provided per-platform via expect/actual or factory
settings["user_id"] = userId
val theme: String = settings["theme"] ?: "system"
```

---

## Dependency Injection (Koin)

Hilt is Android-only. Use **Koin** for shared DI in KMP, or manual DI for small projects.

```kotlin
// commonMain — shared module definitions
val dataModule = module {
    single { HttpClientFactory().create() }
    single { UserApiService(get(), BASE_URL) }
    single { UserLocalDataSource(get()) }
    single<UserRepository> { UserRepositoryImpl(get(), get()) }
}

val domainModule = module {
    factory { GetUsersUseCase(get()) }
    factory { CreateUserUseCase(get()) }
}

val viewModelModule = module {
    viewModelOf(::UserListViewModel)
}
```

```kotlin
// androidMain — Android-specific Koin startup
fun initKoin(context: android.content.Context) = startKoin {
    androidContext(context)
    modules(dataModule, domainModule, viewModelModule, androidModule)
}

// iosMain — iOS Koin startup (called from Swift AppDelegate)
fun initKoin() = startKoin {
    modules(dataModule, domainModule, viewModelModule)
}
```

---

## ViewModel (KMP ViewModel)

Use `androidx.lifecycle:lifecycle-viewmodel` — it now supports KMP (since 2.8.x):

```kotlin
// commonMain
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope

class UserListViewModel(
    private val getUsersUseCase: GetUsersUseCase
) : ViewModel() {

    private val _uiState = MutableStateFlow<UiState<List<User>>>(UiState.Loading)
    val uiState: StateFlow<UiState<List<User>>> = _uiState.asStateFlow()

    init { loadUsers() }

    fun refresh() { loadUsers() }

    private fun loadUsers() {
        viewModelScope.launch {
            _uiState.value = UiState.Loading
            getUsersUseCase()
                .onSuccess { _uiState.value = UiState.Success(it) }
                .onFailure { _uiState.value = UiState.Error(it.message ?: "Unknown error", it) }
        }
    }
}
```

**Alternative — manual ViewModel lifecycle for iOS if not using lifecycle-viewmodel:**
```kotlin
// commonMain — manual scope management for iOS Swift consumers
class UserListViewModel(getUsersUseCase: GetUsersUseCase) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    val uiState: StateFlow<UiState<List<User>>> = ...

    // Called from Swift deinit / ARC deallocation
    fun onCleared() { scope.cancel() }
}
```

---

## Coroutines in KMP

```kotlin
// commonMain — safe dispatcher usage
suspend fun fetchData() = withContext(Dispatchers.Default) {
    // CPU-bound work: safe on all platforms
}

// NOT this in commonMain — Dispatchers.IO does not exist on iOS
// suspend fun fetchData() = withContext(Dispatchers.IO) { ... }  ← WRONG
```

- `Dispatchers.Default` — available on all platforms (thread pool)
- `Dispatchers.Main` — available on Android and iOS (via `kotlinx-coroutines-main`)
- `Dispatchers.IO` — Android/JVM only; **do not use in commonMain**
- Use `expect fun ioDispatcher(): CoroutineDispatcher` if IO dispatcher is needed in common code

```kotlin
// Structured concurrency in shared code
class DataSyncService(...) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    fun startSync() {
        scope.launch {
            try {
                performSync()
            } catch (e: CancellationException) { throw e }  // always re-throw
              catch (e: Exception) { handleError(e) }
        }
    }

    fun cancel() = scope.cancel()
}
```

---

## Compose Multiplatform (shared UI)

When using Compose Multiplatform (`org.jetbrains.compose`), the composable code lives in `commonMain`:

```kotlin
// commonMain/composeApp — shared composable
@Composable
fun UserListScreen(
    viewModel: UserListViewModel = koinViewModel(),
    onUserClick: (String) -> Unit
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()

    when (val s = state) {
        is UiState.Loading -> CircularProgressIndicator()
        is UiState.Error -> Text("Error: ${s.message}")
        is UiState.Success -> LazyColumn {
            items(s.data, key = { it.id }) { user ->
                UserCard(user = user, onClick = { onUserClick(user.id) })
            }
        }
    }
}
```

**Platform-specific composables via expect/actual:**
```kotlin
// commonMain
@Composable
expect fun PlatformDatePicker(onDateSelected: (Long) -> Unit)

// androidMain
@Composable
actual fun PlatformDatePicker(onDateSelected: (Long) -> Unit) {
    // Android Material3 DatePicker
}

// iosMain
@Composable
actual fun PlatformDatePicker(onDateSelected: (Long) -> Unit) {
    // iOS UIKit DatePicker bridge
}
```

**Resources in Compose Multiplatform:**
- Use `compose.resources` DSL for fonts, images, strings — not `R.drawable`
- `Res.drawable.icon`, `Res.string.app_name` via the resources API
- Place assets in `composeApp/src/commonMain/composeResources/`

---

## Swift Interop

KMP compiles shared code to an Xcode framework. Swift calls it natively:

```swift
// Swift — consuming KMP ViewModel
import Shared  // the compiled KMP framework

class UserListViewController: UIViewController {
    private let viewModel = UserListViewModel(getUsersUseCase: KoinHelper().getUsersUseCase())

    override func viewDidLoad() {
        super.viewDidLoad()
        // Collect StateFlow as async sequence
        Task {
            for await state in viewModel.uiState {
                render(state: state)
            }
        }
    }
}
```

**SKIE (Swift Kotlin Interface Enhancer):** Use the SKIE Gradle plugin for dramatically better Swift interop:
- Kotlin `Flow<T>` → Swift `AsyncSequence<T>` (no manual bridging)
- Kotlin sealed classes → Swift enums with `switch` exhaustiveness
- Kotlin `suspend` functions → Swift `async` functions

```kotlin
// build.gradle.kts
plugins {
    id("co.touchlab.skie") version "..."
}
```

---

## Testing

```kotlin
// commonTest — pure shared logic tests (no platform dependencies)
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlinx.coroutines.test.runTest

class UserRepositoryTest {

    @Test
    fun `returns cached users when network is unavailable`() = runTest {
        val fakeLocal = FakeUserLocalDataSource(listOf(User.mock))
        val fakeRemote = FakeUserApiService(Result.failure(IOException("offline")))
        val repository = UserRepositoryImpl(fakeLocal, fakeRemote)

        val result = repository.getUsers()

        assertEquals(listOf(User.mock), result.getOrNull())
    }
}
```

```kotlin
// Shared test doubles in commonTest
class FakeUserApiService(
    private val response: Result<List<UserDto>> = Result.success(emptyList())
) : UserApiService {
    var callCount = 0
    override suspend fun getUsers(): Result<List<UserDto>> {
        callCount++
        return response
    }
}
```

- `kotlin.test` for assertions — works on all platforms without JUnit dependency
- `kotlinx.coroutines.test.runTest` for testing coroutines (replaces test dispatcher)
- Use fakes over mocks in commonTest — Mockk and Mockito are JVM-only
- Platform-specific tests in `androidTest` / `iosTest` source sets for integration testing

---

## Architecture — Shared Clean Architecture

```
commonMain/
└── com.example.app/
    ├── domain/
    │   ├── model/           # Pure Kotlin domain entities (no Android/iOS dependencies)
    │   │   └── User.kt
    │   ├── repository/      # Repository interfaces
    │   │   └── UserRepository.kt
    │   └── usecase/         # Use cases / interactors
    │       └── GetUsersUseCase.kt
    ├── data/
    │   ├── remote/          # Ktor API services, DTOs, mappers
    │   ├── local/           # SQLDelight data sources, entity mappers
    │   └── repository/      # Repository implementations
    └── presentation/        # ViewModels, UI state classes
        └── userlist/
            ├── UserListViewModel.kt
            └── UserListUiState.kt
```

**Rules:**
- Domain layer has zero external dependencies — only Kotlin stdlib and coroutines
- Data layer depends on domain; presentation depends on domain; never the reverse
- DTOs exist only in the data layer — domain models are not serialization-annotated
- Map DTOs → domain models at the repository boundary

---

## Naming Conventions

Same as Android Kotlin, plus KMP-specific:
- Source sets: `commonMain`, `androidMain`, `iosMain` (camelCase with capital platform name)
- `expect` declarations live in `commonMain`; `actual` in platform source sets
- Platform-specific classes not exposed to common code: prefix with `Android` / `Ios` / `Desktop`
- Shared module: `shared` (or by feature for large projects: `feature-auth`, `feature-orders`)
- Framework basename matches module: `baseName = "Shared"` in Gradle

---

## Build & CI

```yaml
# GitHub Actions — build all KMP targets
- name: Build shared module
  run: ./gradlew :shared:build

- name: Build Android app
  run: ./gradlew :androidApp:assembleDebug  # or :composeApp:assembleDebug

- name: Build iOS framework
  run: ./gradlew :shared:linkDebugFrameworkIosSimulatorArm64

- name: Run shared tests
  run: ./gradlew :shared:allTests

- name: Run iOS tests (requires macOS runner)
  run: ./gradlew :shared:iosSimulatorArm64Test
  # or: xcodebuild test -workspace iosApp.xcworkspace ...
```

- Use `macos-latest` runner in CI for iOS builds (Xcode requirement)
- Cache Gradle and Kotlin Native caches aggressively — KMP builds are slow
- Run `commonTest` on every PR; run platform tests before release
- `konan.data.dir` Gradle property to redirect Kotlin Native toolchain cache

---

## Security

- Secrets must never be in `commonMain` — inject via DI or `expect/actual`
- Use platform Keystore / Keychain via `expect/actual` for sensitive storage
- Ktor SSL certificate pinning: configure per-platform in `androidMain` / `iosMain`
- `multiplatform-settings-secure` for encrypted settings on Android (EncryptedSharedPreferences) and iOS (Keychain)
- Validate all data at network boundary before mapping to domain models
