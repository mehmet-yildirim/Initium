---
name: mobile-android
description: Android development standards — Kotlin, Jetpack Compose, Clean Architecture, Hilt, Coroutines, Material 3. Use when writing or reviewing native Android code.
globs:
  - "**/*.kt"
  - "**/*.kts"
  - "**/AndroidManifest.xml"
  - "**/build.gradle.kts"
  - "**/build.gradle"
  - "**/res/**"
  - "**/proguard-rules.pro"
alwaysApply: false
---
<!-- Generated from .claude/skills by .initium/scripts/sync-skills.mjs — edit the skill, not this file. -->

# Android Development Standards

Visual and interaction design (color roles, type scale, adaptive layouts, motion): `design-material3`.

## Kotlin Language

### Modern Kotlin (1.9+)
- Coroutines + Flow for all async and reactive work — no RxJava in new code
- `suspend` functions for sequential async; `Flow<T>` for streams of values
- `StateFlow` and `SharedFlow` — not `LiveData` for new ViewModels
- Sealed classes / sealed interfaces for exhaustive state modeling
- Data classes for DTOs and value objects; `copy()` for immutable updates
- Extension functions for adding behavior without inheritance
- `inline`, `reified`, and `@JvmInline value class` where appropriate
- Kotlin DSL for Gradle (`build.gradle.kts`) — not Groovy

```kotlin
// Preferred: sealed state + StateFlow
sealed interface UiState<out T> {
    data object Loading : UiState<Nothing>
    data class Success<T>(val data: T) : UiState<T>
    data class Error(val message: String, val cause: Throwable? = null) : UiState<Nothing>
}
```

### Naming Conventions
- Classes / Interfaces / Objects / Enums: `PascalCase`
- Functions / properties / local variables: `camelCase`
- Constants (companion object, top-level): `SCREAMING_SNAKE_CASE`
- Private properties: `camelCase` (no underscore prefix — Kotlin convention)
- Composables: `PascalCase` (they are functions but act like components)
- ViewModel suffix: `UserViewModel`, not `UserVM` or `VMUser`
- Repository suffix: `UserRepository`; implementation: `UserRepositoryImpl`

### Null Safety
- Never use `!!` (non-null assertion) in production code
- `?.` safe-call and `?:` Elvis operator for null handling
- `requireNotNull()` / `checkNotNull()` with meaningful error messages at system boundaries
- `@NonNull` / `@Nullable` on Java interop APIs

## Jetpack Compose

### Composable Design
- Composables are functions — `PascalCase`, no `@` prefix in name
- Keep composables small and focused (single responsibility)
- Stateless composables receive data and callbacks — not ViewModel references
- Stateful composables (screen-level) hold state and inject ViewModel

```kotlin
// Stateless leaf composable — maximally reusable
@Composable
fun UserCard(
    user: User,
    onFavoriteClick: (User) -> Unit,
    modifier: Modifier = Modifier
) { ... }

// Stateful screen composable — holds ViewModel
@Composable
fun UserListScreen(
    viewModel: UserListViewModel = hiltViewModel(),
    onUserClick: (String) -> Unit
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    UserListContent(state = state, onUserClick = onUserClick, onRefresh = viewModel::refresh)
}
```

### State Management
- `remember` for local transient state (animation values, focus)
- `rememberSaveable` for state that survives recomposition AND process death
- `collectAsStateWithLifecycle()` (not `collectAsState()`) for Flow — lifecycle-aware
- Unidirectional Data Flow (UDF): events up, state down
- Never pass ViewModel into composable below screen level — pass lambdas/data

### Side Effects
- `LaunchedEffect(key)` — for coroutines tied to composition lifecycle
- `SideEffect` — sync Compose state to non-Compose code
- `DisposableEffect` — cleanup-required effects (listeners, observers)
- `rememberCoroutineScope()` — for coroutines triggered by user events (not on composition)

### Performance
- `key(id)` in `LazyColumn` items to preserve state across reorderings
- Avoid reading unstable state inside lambdas — use `derivedStateOf`
- `@Stable` and `@Immutable` annotations on custom types for smart recomposition
- Prefer `LazyColumn` / `LazyRow` over `Column` with `forEach` for lists
- Profile with Layout Inspector + Composition tracing before optimizing

### Theming (Material 3)
- Use `MaterialTheme.colorScheme`, `MaterialTheme.typography`, `MaterialTheme.shapes`
- Never hardcode colors — reference theme tokens
- Support dark theme and dynamic color (Android 12+)
- Custom `CompositionLocalProvider` for app-level design tokens

## Architecture — Clean + MVVM

```
UI Layer (Composables + ViewModel)
    ↓ collects StateFlow / calls events
Domain Layer (UseCases — optional for simple projects)
    ↓ orchestrates
Data Layer (Repositories — interface + implementation)
    ↓
Data Sources (Remote: Retrofit | Local: Room | Preferences: DataStore)
```

### ViewModel
- One ViewModel per screen (not per composable)
- Expose state as `StateFlow<UiState>` — single stream, not multiple `LiveData`
- Expose one-off events as `SharedFlow` (navigation, snackbars)
- `viewModelScope` for coroutines — auto-cancelled when ViewModel is cleared
- No Android framework dependencies in domain / data layers

```kotlin
@HiltViewModel
class UserListViewModel @Inject constructor(
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

## Dependency Injection (Hilt)

- `@HiltAndroidApp` on `Application` subclass
- `@AndroidEntryPoint` on Activities and Fragments (if still using them)
- `@HiltViewModel` on ViewModels
- `@Singleton` for app-scoped dependencies; `@ViewModelScoped` for VM-scoped
- Provide interfaces — not implementations — at injection sites
- Separate `@Module` per feature; use `@InstallIn` to scope modules

## Networking (Retrofit + OkHttp)

```kotlin
interface UserApi {
    @GET("users/{id}")
    suspend fun getUser(@Path("id") id: String): UserResponse

    @POST("users")
    suspend fun createUser(@Body request: CreateUserRequest): UserResponse
}
```

- All API functions are `suspend` — no `Call<T>` wrappers
- `kotlinx.serialization` or Gson/Moshi for JSON deserialization
- OkHttp interceptors for: auth headers, logging, retry
- `Result<T>` wrapping in repository to prevent coroutine exception propagation to UI

## Local Storage

### Room (SQL)
```kotlin
@Entity(tableName = "users")
data class UserEntity(
    @PrimaryKey val id: String,
    val name: String,
    val email: String,
    val createdAt: Long
)

@Dao
interface UserDao {
    @Query("SELECT * FROM users ORDER BY createdAt DESC")
    fun getAllUsers(): Flow<List<UserEntity>>  // Flow for reactive queries

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertUser(user: UserEntity)
}
```

- Return `Flow<T>` from DAO for reactive queries
- `suspend` for write operations
- TypeConverters for complex types (Date, UUID, enums)
- Migrations: numbered, code-reviewed, never auto-migrate in production

### DataStore (Preferences)
- `PreferencesDataStore` for key-value storage — not SharedPreferences
- `ProtoDataStore` for typed, schema-validated preferences
- Always access via repository — not directly in ViewModel

## Navigation (Jetpack Compose Navigation)

```kotlin
@Composable
fun AppNavHost(navController: NavHostController) {
    NavHost(navController, startDestination = "home") {
        composable("home") { HomeScreen(onUserClick = { id -> navController.navigate("user/$id") }) }
        composable("user/{id}", arguments = listOf(navArgument("id") { type = NavType.StringType })) {
            UserDetailScreen(userId = it.arguments?.getString("id")!!)
        }
    }
}
```

- Type-safe navigation with Navigation 2.8+ (`@Serializable` route objects)
- Deep links declared in `AndroidManifest.xml` and matched in NavHost
- Back stack managed by NavController — never pop manually with fragments

## Testing

### Unit Tests (JUnit 5 + MockK + Turbine)
```kotlin
@ExtendWith(CoroutineTestExtension::class)
class UserListViewModelTest {
    private val getUsersUseCase = mockk<GetUsersUseCase>()
    private lateinit var viewModel: UserListViewModel

    @BeforeEach fun setUp() { viewModel = UserListViewModel(getUsersUseCase) }

    @Test fun `emits success state when use case succeeds`() = runTest {
        coEvery { getUsersUseCase() } returns Result.success(listOf(User.mock))
        viewModel.uiState.test {
            viewModel.refresh()
            assertIs<UiState.Success<*>>(awaitItem())
        }
    }
}
```

- `TestCoroutineDispatcher` / `UnconfinedTestDispatcher` for deterministic tests
- `Turbine` library for Flow testing
- MockK for mocking (not Mockito — Kotlin-idiomatic)
- Test rule or extension to replace `Dispatchers.Main`

### UI Tests (Compose Testing)
```kotlin
@get:Rule val composeRule = createComposeRule()

@Test fun `user list shows items`() {
    composeRule.setContent { UserListScreen(viewModel = fakeViewModel) }
    composeRule.onNodeWithTag("user_list").assertIsDisplayed()
    composeRule.onAllNodesWithTag("user_item").assertCountEquals(3)
}
```

- `semanticsTestTag` on composables for stable test selectors
- Hilt test rules for full-stack integration tests

## Build & Distribution

- Gradle version catalog (`libs.versions.toml`) for dependency management
- Product flavors for environment separation (dev, staging, prod)
- ProGuard / R8 rules committed and tested before release
- `keystore.properties` excluded from version control; loaded from environment in CI
- Fastlane or GitHub Actions + Gradle for Play Store deployment
- App Bundle (`.aab`) for Play Store — not APK
- `minSdk`: target the lowest supported Android version; never raise without justification

## Security
- Encrypted SharedPreferences / EncryptedFile for sensitive local data
- Android Keystore for cryptographic key storage — never store keys in code or properties
- Certificate pinning via `network_security_config.xml` or OkHttp pinner
- ProGuard to obfuscate sensitive logic in release builds
- No logging of PII or auth tokens — strip logs in release via ProGuard
