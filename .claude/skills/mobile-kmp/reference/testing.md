# KMP testing templates

## Where tests run

| Source set | Runs on | Allowed tools |
|---|---|---|
| `commonTest` | every target (`allTests`) | kotlin.test, kotlinx-coroutines-test, Turbine, Mokkery, Ktor `MockEngine` |
| `androidHostTest` | JVM on the host | + JUnit, MockK, Robolectric |
| `androidDeviceTest` | device/emulator | + AndroidX Test, Compose UI tests |
| `iosTest` | iOS simulator (macOS) | kotlin.test only; Kotlin/Native APIs |
| `jvmTest` | desktop JVM | + JUnit, MockK |

Prefer hand-written fakes for ports; reach for Mokkery when a fake would be larger than the test.

## ViewModel with StandardTestDispatcher and Turbine

```kotlin
class OrderListViewModelTest {
    private val dispatcher = StandardTestDispatcher()
    private val repository = FakeOrderRepository()

    @BeforeTest fun setUp() = Dispatchers.setMain(dispatcher)
    @AfterTest fun tearDown() = Dispatchers.resetMain()

    @Test
    fun emitsOrdersAfterLoad() = runTest(dispatcher) {
        repository.orders = listOf(sampleOrder)
        val viewModel = OrderListViewModel(repository)

        viewModel.state.test {
            assertEquals(OrderListUiState(isLoading = true), awaitItem())
            assertEquals(OrderListUiState(orders = listOf(sampleOrder)), awaitItem())
        }
    }
}
```

## Mokkery

```kotlin
// build.gradle.kts: plugins { alias(libs.plugins.mokkery) }
class SyncOrdersTest {
    private val api = mock<OrderApi>()

    @Test
    fun mapsOfflineToError() = runTest {
        everySuspend { api.fetchOrder(any()) } returns Outcome.Err(OrderError.Offline)

        val result = SyncOrders(api).invoke(OrderId("42"))

        assertEquals(Outcome.Err(OrderError.Offline), result)
        verifySuspend { api.fetchOrder(OrderId("42")) }
    }
}
```

Mock interfaces (ports), not concrete classes; introduce a port rather than opening a final class.

## Ktor MockEngine

```kotlin
class KtorOrderApiTest {
    private fun apiRespondingWith(status: HttpStatusCode, body: String = ""): KtorOrderApi {
        val engine = MockEngine { _ ->
            respond(
                content = body,
                status = status,
                headers = headersOf(HttpHeaders.ContentType, ContentType.Application.Json.toString()),
            )
        }
        val config = AppConfig(apiBaseUrl = "https://api.test/", appVersion = "test", isDebug = true)
        return KtorOrderApi(createHttpClient(engine, config))
    }

    @Test
    fun notFoundMapsToDomainError() = runTest {
        val result = apiRespondingWith(HttpStatusCode.NotFound).fetchOrder(OrderId("missing"))
        assertEquals(Outcome.Err(OrderError.NotFound), result)
    }
}
```

Use the real `createHttpClient` so tests cover `expectSuccess`, timeouts, and JSON config.

## Databases

```kotlin
// commonTest
expect fun createTestDriver(): SqlDriver

// jvmTest / androidHostTest
actual fun createTestDriver(): SqlDriver =
    JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY).also { AppDatabase.Schema.create(it) }

// iosTest
actual fun createTestDriver(): SqlDriver = inMemoryDriver(AppDatabase.Schema)
```

Room 3: `Room.inMemoryDatabaseBuilder<AppDatabase>().setDriver(BundledSQLiteDriver()).build()`
works in common code; close the database in `@AfterTest`.

- Add a migration test per `.sqm` file (or Room schema version) that migrates a populated
  database and asserts data survives.

## CI commands

```bash
./gradlew :shared:allTests
./gradlew :shared:iosSimulatorArm64Test      # macOS runner
```
