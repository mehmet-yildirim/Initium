# Android test templates

## Which framework runs where

| Test type | Source set | Framework | Notes |
|---|---|---|---|
| ViewModel, use case, mapper | `src/test` | JUnit 4 (default) or JUnit 5 via `de.mannodermaus.android-junit5` | Pick one per module |
| Compose UI (JVM) | `src/test` | JUnit 4 + Robolectric | `createComposeRule()` is a JUnit 4 rule |
| Compose UI / Hilt integration | `src/androidTest` | JUnit 4 + AndroidJUnitRunner | `HiltTestRunner` for Hilt |
| Startup / jank | `:benchmark` | Macrobenchmark (JUnit 4) | Release-like build |

Compose test rules have no JUnit 5 equivalent; keep Compose tests on JUnit 4 even if the module's
plain unit tests use JUnit 5.

## Main dispatcher rule

```kotlin
class MainDispatcherRule(
    val testDispatcher: TestDispatcher = StandardTestDispatcher(),
) : TestWatcher() {
    override fun starting(description: Description) = Dispatchers.setMain(testDispatcher)
    override fun finished(description: Description) = Dispatchers.resetMain()
}
```

`runTest` reuses the scheduler of a `TestDispatcher` installed as `Dispatchers.Main`, so
`advanceUntilIdle()` drives both.

## ViewModel test (JUnit 4, fakes, Turbine)

```kotlin
class UserListViewModelTest {
    @get:Rule val mainDispatcherRule = MainDispatcherRule()

    private val repository = FakeUserRepository()

    @Test
    fun refresh_success_showsUsers() = runTest {
        repository.result = Outcome.Ok(listOf(TEST_USER))
        val viewModel = UserListViewModel(GetUsersUseCase(repository))

        advanceUntilIdle()

        assertEquals(UserListUiState(users = listOf(TEST_USER)), viewModel.uiState.value)
    }

    @Test
    fun refresh_offline_setsErrorUntilShown() = runTest {
        repository.result = Outcome.Err(UserError.Offline)
        val viewModel = UserListViewModel(GetUsersUseCase(repository))

        viewModel.uiState.test {
            assertEquals(UserListUiState(isLoading = true), awaitItem())
            assertEquals(UserError.Offline, awaitItem().error)
            viewModel.errorShown()
            assertNull(awaitItem().error)
        }
    }
}
```

- `StandardTestDispatcher` queues coroutines until the scheduler advances — assertions see every
  intermediate state. Use `UnconfinedTestDispatcher` only for collectors that must start eagerly.
- `TestCoroutineDispatcher` / `TestCoroutineScope` are removed; do not use them.
- Prefer fakes implementing ports over mocks; use MockK only for types you cannot fake.

## Compose UI test

```kotlin
class UserListContentTest {
    @get:Rule val composeRule = createComposeRule()

    @Test
    fun showsOneRowPerUser() {
        composeRule.setContent {
            AppTheme {
                UserListContent(
                    state = UserListUiState(users = listOf(TEST_USER, OTHER_USER)),
                    snackbarHostState = remember { SnackbarHostState() },
                    onUserClick = {},
                    onRefresh = {},
                )
            }
        }

        composeRule.onAllNodesWithTag(USER_ROW_TAG).assertCountEquals(2)
        composeRule.onNodeWithText(TEST_USER.name).assertHasClickAction()
    }
}

// production composable
LazyColumn {
    items(state.users, key = { it.id }) { user ->
        UserRow(user, onClick = { onUserClick(user.id) }, modifier = Modifier.testTag(USER_ROW_TAG))
    }
}
```

- Test stateless `*Content` composables with fixed state; test `*Screen` + ViewModel wiring in
  a few Hilt instrumentation tests.
- Prefer semantic matchers (text, content description, role); use `Modifier.testTag` for rows and
  containers without stable text.
- Enable accessibility checks in instrumented Compose tests where supported.

## Hilt instrumentation

```kotlin
@HiltAndroidTest
class CheckoutFlowTest {
    @get:Rule(order = 0) val hiltRule = HiltAndroidRule(this)
    @get:Rule(order = 1) val composeRule = createAndroidComposeRule<MainActivity>()

    @Before fun setUp() = hiltRule.inject()
}
```

Replace network and payment adapters with `@TestInstallIn` modules; never hit production services.
