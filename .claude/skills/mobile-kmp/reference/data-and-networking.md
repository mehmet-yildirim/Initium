# Data and networking in shared code

## AppConfig instead of BuildConfig

```kotlin
// commonMain
data class AppConfig(
    val apiBaseUrl: String,
    val appVersion: String,
    val isDebug: Boolean,
)
```

Each entry point builds it: `androidApp` from `BuildConfig`, `iosApp` from `Info.plist` values,
desktop from its packaging config. Nothing in `commonMain` reads platform build metadata.

## Ktor client

```kotlin
// commonMain — the engine is injected so commonMain never names OkHttp or Darwin
private const val REQUEST_TIMEOUT_MS = 15_000L
private const val CONNECT_TIMEOUT_MS = 10_000L

fun createHttpClient(engine: HttpClientEngine, config: AppConfig): HttpClient =
    HttpClient(engine) {
        expectSuccess = true
        install(ContentNegotiation) {
            json(Json { ignoreUnknownKeys = true })
        }
        install(HttpTimeout) {
            requestTimeoutMillis = REQUEST_TIMEOUT_MS
            connectTimeoutMillis = CONNECT_TIMEOUT_MS
        }
        defaultRequest { url(config.apiBaseUrl) }
    }
```

```kotlin
// androidMain / jvmMain:  createHttpClient(OkHttp.create(), config)
// iosMain:                createHttpClient(Darwin.create(), config)
```

Adapter that maps transport failures to domain errors (only specific exceptions are caught, so
`CancellationException` propagates):

```kotlin
class KtorOrderApi(private val client: HttpClient) : OrderApi {
    override suspend fun fetchOrder(id: OrderId): Outcome<Order, OrderError> =
        try {
            Outcome.Ok(client.get("orders/${id.value}").body<OrderDto>().toDomain())
        } catch (e: ClientRequestException) {
            if (e.response.status == HttpStatusCode.NotFound) Outcome.Err(OrderError.NotFound)
            else Outcome.Err(OrderError.Rejected(e.response.status.value))
        } catch (e: ServerResponseException) {
            Outcome.Err(OrderError.Unavailable)
        } catch (e: HttpRequestTimeoutException) {
            Outcome.Err(OrderError.Offline)
        } catch (e: IOException) {           // kotlinx.io.IOException
            Outcome.Err(OrderError.Offline)
        } catch (e: ContentConvertException) {
            Outcome.Err(OrderError.InvalidPayload)
        }
}
```

- `toDomain()` validates business rules and returns a domain type; reject invalid payloads there.
- Pinning: OkHttp engine `config { certificatePinner(...) }` in `androidMain`; Darwin engine
  `handleChallenge(CertificatePinner.Builder().add(host, pin).build())` in `iosMain`.
- Auth: the Ktor `Auth` plugin (`bearer { loadTokens { … } refreshTokens { … } }`) reading from the
  `SecureStore` port.

## SQLDelight 2

```sql
-- src/commonMain/sqldelight/com/example/shared/db/Order.sq
CREATE TABLE orderEntity (
    id TEXT NOT NULL PRIMARY KEY,
    total_cents INTEGER NOT NULL,
    created_at INTEGER NOT NULL
);

selectAll:
SELECT * FROM orderEntity ORDER BY created_at DESC;

upsert:
INSERT OR REPLACE INTO orderEntity(id, total_cents, created_at) VALUES (?, ?, ?);
```

```kotlin
// androidMain
AndroidSqliteDriver(AppDatabase.Schema, context, "app.db")
// iosMain
NativeSqliteDriver(AppDatabase.Schema, "app.db")
// jvmMain
JdbcSqliteDriver("jdbc:sqlite:app.db", Properties(), AppDatabase.Schema)

// commonMain — reactive query
fun observeOrders(): Flow<List<Order>> =
    database.orderQueries.selectAll().asFlow().mapToList(dispatchers.io)
        .map { rows -> rows.map { it.toDomain() } }
```

- Schema changes go in numbered `.sqm` files (`1.sqm`, `2.sqm`, …); enable `verifyMigrations` and
  commit the generated `.db` schema snapshots.
- Bound parameters only; never build SQL strings from user input.

## Room 3 (KMP)

```kotlin
// commonMain — imports from androidx.room3.*
@Database(entities = [OrderEntity::class], version = 1)
@ConstructedBy(AppDatabaseConstructor::class)
abstract class AppDatabase : RoomDatabase() {
    abstract fun orderDao(): OrderDao
}

// Room's KSP processor generates the actual objects per target.
@Suppress("KotlinNoActualForExpect")
expect object AppDatabaseConstructor : RoomDatabaseConstructor<AppDatabase> {
    override fun initialize(): AppDatabase
}

@Dao
interface OrderDao {
    @Query("SELECT * FROM OrderEntity ORDER BY createdAt DESC")
    fun observeAll(): Flow<List<OrderEntity>>

    @Upsert
    suspend fun upsert(order: OrderEntity)
}

fun buildDatabase(builder: RoomDatabase.Builder<AppDatabase>, io: CoroutineDispatcher): AppDatabase =
    builder
        .setDriver(BundledSQLiteDriver())
        .setQueryCoroutineContext(io)
        .build()
```

```kotlin
// androidMain
Room.databaseBuilder<AppDatabase>(context = appContext, name = appContext.getDatabasePath("app.db").absolutePath)
// iosMain — path under NSDocumentDirectory / Application Support
Room.databaseBuilder<AppDatabase>(name = "$documentsPath/app.db")
```

- Apply the `androidx.room3` Gradle plugin with `room3 { schemaDirectory("$projectDir/schemas") }`
  and commit the schema JSON; add the compiler per target (`kspAndroid`, `kspIosArm64`, …).
- Room 3 is KSP-only and coroutine-only (DAO functions are `suspend` or return `Flow`); column
  converters use `@ColumnTypeConverter` (renamed from `@TypeConverter`).
- Transactions: `useWriterConnection { }` / `withWriteTransaction { }`; `SupportSQLite*` APIs are gone.
- Room 2.8 (`androidx.room`) remains supported for existing codebases; migrate imports when moving.

## DataStore (KMP)

```kotlin
// commonMain
const val PREFERENCES_FILE_NAME = "app.preferences_pb"

fun createPreferencesStore(producePath: () -> String): DataStore<Preferences> =
    PreferenceDataStoreFactory.createWithPath(produceFile = { producePath().toPath() })

// androidMain
createPreferencesStore { context.filesDir.resolve(PREFERENCES_FILE_NAME).absolutePath }
```

- Create exactly one instance per file (a singleton in DI); two instances on one file corrupt it.
- DataStore is not encrypted — tokens go through `SecureStore`, never plain Preferences.
