# Flutter platform services

Read when wiring crash reporting, push notifications, or background work. Every vendor plugin
sits behind a port in `lib/platform/`; features depend on the port only.

## Crash reporting port and bootstrap

```dart
// lib/platform/crash_reporter.dart
abstract interface class CrashReporter {
  Future<void> recordError(Object error, StackTrace stack, {bool fatal = false});
  Future<void> setUserId(String? id);
}

// lib/platform/crashlytics_reporter.dart — the only file importing the vendor SDK
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

final class CrashlyticsReporter implements CrashReporter {
  CrashlyticsReporter(this._crashlytics);
  final FirebaseCrashlytics _crashlytics;

  @override
  Future<void> recordError(Object error, StackTrace stack, {bool fatal = false}) =>
      _crashlytics.recordError(error, stack, fatal: fatal);

  @override
  Future<void> setUserId(String? id) => _crashlytics.setUserIdentifier(id ?? '');
}
```

```dart
// lib/main.dart
import 'dart:async';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final reporter = await createCrashReporter();

  FlutterError.onError = (details) {
    unawaited(reporter.recordError(details.exception, details.stack ?? StackTrace.current, fatal: true));
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(reporter.recordError(error, stack, fatal: true));
    return true;
  };

  runApp(ProviderScope(
    overrides: [crashReporterProvider.overrideWithValue(reporter)],
    child: const App(),
  ));
}
```

- `createCrashReporter()` lives in the composition root: it initializes Firebase (or Sentry) for
  the current flavor and returns the adapter; tests get a recording fake.
- `crashReporterProvider` is declared with `@Riverpod(keepAlive: true)` and throws
  `UnimplementedError` unless overridden, so a missing wiring fails loudly.
- Report only opaque user IDs; scrub PII from messages and breadcrumbs.
- Build releases with `--obfuscate --split-debug-info` and upload the symbols (Crashlytics or
  `sentry_dart_plugin`) in the same CI job.

## Push notifications (`firebase_messaging`)

```dart
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: currentFirebaseOptions());
  // Keep this handler short: persist the message ID and let the app sync on next launch.
}

final class FirebasePushService implements PushService {
  FirebasePushService(this._messaging, this._registrar);
  final FirebaseMessaging _messaging;
  final PushTokenRegistrar _registrar;

  @override
  Future<bool> enable() async {
    final settings = await _messaging.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied) return false;
    final token = await _messaging.getToken();
    if (token != null) await _registrar.register(token);
    _messaging.onTokenRefresh.listen(_registrar.register);
    return true;
  }
}
```

- Register `FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler)` in
  `main` before `runApp`; the handler must be a top-level function.
- `requestPermission()` covers the iOS prompt and Android 13+ `POST_NOTIFICATIONS`. Ask in
  context, not on first launch.
- iOS needs the Push Notifications capability and an APNs key uploaded to Firebase; show
  foreground notifications with `flutter_local_notifications`.
- Treat payloads as untrusted: validate IDs, route through go_router, fetch details over an
  authenticated API, never put PII or secrets in the payload.

## Background work (`workmanager`)

```dart
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    final sync = await createSyncService();
    return sync.run();
  });
}

Future<void> scheduleSync() async {
  await Workmanager().initialize(callbackDispatcher);
  await Workmanager().registerPeriodicTask(
    'com.example.app.sync',
    'sync',
    frequency: const Duration(minutes: 15),
  );
}
```

- Android runs on WorkManager (minimum 15-minute period); iOS uses BGTaskScheduler, so list the
  unique name in `BGTaskSchedulerPermittedIdentifiers`, enable the Background Modes capability,
  and — after the UIScene migration — call `WorkmanagerPlugin.registerLaunchHandlers()` in
  `AppDelegate.application(_:didFinishLaunchingWithOptions:)`.
- The callback runs in a separate isolate: rebuild dependencies there (`createSyncService()`),
  return `false` on retryable failure, and keep work idempotent.
- The OS decides when tasks run; never promise exact timing to users.
