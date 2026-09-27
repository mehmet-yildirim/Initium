# Platform feature recipes

## Push (FCM) behind a port

```kotlin
// core/domain
interface PushTokenRegistrar {
    suspend fun register(token: String): Outcome<Unit, PushError>
}

// core/data — the only place that imports Firebase
@AndroidEntryPoint
class AppMessagingService : FirebaseMessagingService() {
    @Inject lateinit var registrar: PushTokenRegistrar
    @Inject lateinit var notifier: AppNotifier
    @Inject @ApplicationScope lateinit var appScope: CoroutineScope

    override fun onNewToken(token: String) {
        // Service callbacks are not suspend; the application scope outlives the service.
        appScope.launch { registrar.register(token) }
    }

    override fun onMessageReceived(message: RemoteMessage) {
        notifier.show(message.toAppNotification())
    }
}
```

- Declare the service with `android:exported="false"` and the `com.google.firebase.MESSAGING_EVENT`
  intent filter.
- Ask for `POST_NOTIFICATIONS` (API 33+) with `rememberLauncherForActivityResult(RequestPermission())`
  after explaining the value, not at first launch. Handle "denied" without nagging.
- Create notification channels at startup; payloads carry IDs, not PII — fetch details over an
  authenticated API.

## WorkManager

```kotlin
private const val MAX_SYNC_ATTEMPTS = 5

@HiltWorker
class SyncWorker @AssistedInject constructor(
    @Assisted context: Context,
    @Assisted params: WorkerParameters,
    private val sync: SyncOrdersUseCase,
) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result = when (sync()) {
        is Outcome.Ok -> Result.success()
        is Outcome.Err -> if (runAttemptCount < MAX_SYNC_ATTEMPTS) Result.retry() else Result.failure()
    }
}

fun enqueueSync(workManager: WorkManager) {
    val request = PeriodicWorkRequestBuilder<SyncWorker>(6, TimeUnit.HOURS)
        .setConstraints(Constraints(requiredNetworkType = NetworkType.CONNECTED))
        .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
        .build()
    workManager.enqueueUniquePeriodicWork("order-sync", ExistingPeriodicWorkPolicy.KEEP, request)
}
```

- Use `HiltWorkerFactory` via `Configuration.Provider` on the `Application` and remove the default
  WorkManager initializer from the manifest.
- Unique work names prevent duplicate schedules; long-running work calls `setForeground()` with a
  declared `foregroundServiceType`.

## App Links

```xml
<activity android:name=".MainActivity" android:exported="true">
    <intent-filter android:autoVerify="true">
        <action android:name="android.intent.action.VIEW" />
        <category android:name="android.intent.category.DEFAULT" />
        <category android:name="android.intent.category.BROWSABLE" />
        <data android:scheme="https" android:host="app.example.com" android:pathPrefix="/orders/" />
    </intent-filter>
</activity>
```

- Host `https://app.example.com/.well-known/assetlinks.json` with the Play App Signing certificate
  SHA-256 (and the upload key for internal testing).
- Validate every path segment and query parameter; unknown links open a safe default screen.

## Per-app language and RTL

- `androidResources { generateLocaleConfig = true }` plus `res/resources.properties` containing
  `unqualifiedResLocale=en`. Do not combine with language `resourceConfigurations`; use
  `localeFilters` if you must strip library translations.
- In-app picker: `AppCompatDelegate.setApplicationLocales(LocaleListCompat.forLanguageTags("ar"))`.
- Use `start`/`end`, `Arrangement.Start`, auto-mirrored icons; format numbers, dates, and plurals
  with locale-aware APIs (`pluralStringResource`, `DateTimeFormatter.ofLocalizedDate`).

## Baseline Profiles

- Add a `:baselineprofile` test module (Android Studio template) and apply `androidx.baselineprofile`
  to `:app` and the producer module.
- Generate with a Macrobenchmark journey covering startup and top flows; commit the generated
  `baseline-prof.txt`; regenerate when critical flows change.
- Measure with `StartupTimingMetric` and `FrameTimingMetric` in CI on a physical device or
  emulator-based benchmark runner.

## Crash reporting adapter

```kotlin
interface CrashReporter {
    fun record(throwable: Throwable, context: Map<String, String> = emptyMap())
}

class CrashlyticsReporter @Inject constructor() : CrashReporter {
    private val crashlytics = FirebaseCrashlytics.getInstance()

    override fun record(throwable: Throwable, context: Map<String, String>) {
        context.forEach { (key, value) -> crashlytics.setCustomKey(key, value) }
        crashlytics.recordException(throwable)
    }
}
```

Never pass tokens, emails, or free-text user input as custom keys.
