---
name: mobile-flutter
description: Flutter 3.47 / Dart 3.13 standards for iOS and Android apps — Riverpod 3 with riverpod_generator, go_router inside a provider, material_ui/cupertino_ui packages, flavors via Gradle productFlavors and Xcode schemes, gen-l10n and RTL, accessibility, push, background work and crash reporting behind adapters, UIScene and iOS privacy manifests, and flutter_test/alchemist/integration_test. Use when writing, reviewing, or configuring Dart code, pubspec.yaml, flavors, platform channels, or Flutter builds.
globs:
  - "**/*.dart"
  - "**/pubspec.yaml"
alwaysApply: false
---
<!-- Generated from .claude/skills by .initium/scripts/sync-skills.mjs — edit the skill, not this file. -->

# Flutter / Dart Development Standards

Platform look and feel: `design-material3` (Android) and `design-apple-hig` (iOS); shared tokens:
`design-tokens`; accessibility audits: `accessibility`. Native iOS code in `ios/`: `mobile-ios`.

## Baseline

- Flutter 3.47.5 stable with Dart 3.13.4. Upgrade with `flutter upgrade`; pin the version in CI
  (FVM or `flutter-version-file`).
- Flutter 3.47 ships Material and Cupertino as standalone packages (`material_ui`,
  `cupertino_ui` 1.0); the in-framework libraries are slated for deprecation in the next stable.
  New code imports the packages; migrate existing imports with the official guide.
- Android matrix verified for 3.47: Java 17, AGP 9.1, Kotlin Gradle Plugin 2.4.0, Gradle 9.3.1;
  use `flutter.compileSdkVersion` / `flutter.targetSdkVersion` (API 36) and
  `flutter.minSdkVersion` (API 24) in Gradle files.
- iOS: minimum iOS 15. UIScene is the default since Flutter 3.41 and mandatory with Xcode 27;
  a customized `AppDelegate` must be migrated by hand (plugin registration moves to
  `didInitializeImplicitFlutterEngine`).
- State and routing: `flutter_riverpod` 3.4, `riverpod_generator` / `riverpod_annotation` 4.0,
  `go_router` 18 (feature-complete, maintenance only).
- Impeller is the renderer on iOS and the default on Android; Widget Previews are stable in 3.47.

## Toolchain

- `dart format` and `flutter analyze` with `very_good_analysis` or `flutter_lints`, zero warnings
  in CI; enable `avoid_print` and `unawaited_futures`.
- Code generation: `dart run build_runner build --delete-conflicting-outputs`; commit generated
  files or regenerate in CI — pick one and be consistent.
- Commit `pubspec.lock` for apps; Dependabot/Renovate (pub ecosystem) plus OSV-Scanner on the
  lockfile; `flutter pub outdated` in CI.
- Release builds: `flutter build appbundle|ipa --obfuscate --split-debug-info=build/symbols`
  and upload symbols to the crash reporter.

## Structure

Feature folders with hexagonal layering; vendor SDKs only behind adapters.

```
lib/
├── main.dart                 # bootstrap: error hooks, composition root, ProviderScope
├── app/                      # App widget, router provider, theme
├── features/orders/
│   ├── domain/               # entities, sealed failures, repository interfaces (pure Dart)
│   ├── data/                 # DTOs, Dio/drift adapters implementing domain interfaces
│   └── presentation/         # screens, widgets, notifiers
├── platform/                 # push, crash reporting, analytics, secure storage adapters
└── l10n/                     # ARB files + generated AppLocalizations
```

- Ports are `abstract interface class`; adapters are `final class`. Only `platform/` and `data/`
  import `firebase_*`, `sentry_flutter`, `dio`, or plugin packages.
- Domain code never imports `package:flutter`.
- Widgets: `const` constructors, small `build` methods, extracted widgets over helper methods,
  `Key`s on list items, `SizedBox`/`Padding` over `Container` for spacing.

## State management (Riverpod 3)

```dart
@riverpod
UserRepository userRepository(Ref ref) => HttpUserRepository(ref.watch(dioProvider));

@riverpod
class UserProfile extends _$UserProfile {
  @override
  Future<User> build(String userId) => ref.watch(userRepositoryProvider).getUser(userId);

  Future<void> rename(String name) async {
    final repository = ref.read(userRepositoryProvider);
    state = await AsyncValue.guard(() => repository.rename(userId, name));
  }
}

@riverpod
class SelectedTab extends _$SelectedTab {
  @override
  int build() => 0;

  void select(int index) => state = index;
}

class UserScreen extends ConsumerWidget {
  const UserScreen({super.key, required this.userId});
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return switch (ref.watch(userProfileProvider(userId))) {
      AsyncData(:final value) => UserDetails(user: value),
      AsyncError(error: UserNotFound()) => Center(child: Text(l10n.userNotFound)),
      AsyncError() => Center(child: Text(l10n.genericError)),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}
```

- Generate providers with `@riverpod`; the generator strips a trailing `Notifier` from class
  names (`UserNotifier` → `userProvider`). Keep the default; don't mix naming schemes.
- `Notifier` / `AsyncNotifier` for mutable state; functional providers for derived or read-only
  values; family parameters are `build` arguments.
- `StateProvider`, `StateNotifierProvider`, and `ChangeNotifierProvider` are legacy
  (`legacy.dart` imports) — never in new code.
- `ref.watch` in `build`; `ref.read` in callbacks; check `ref.mounted` after `await` before
  touching `state` in long operations.
- Riverpod 3 retries failing providers automatically; pass a `retry` function (provider or
  `ProviderScope`) that returns `null` for non-transient failures such as `UserNotFound`.
- Alternatives: Bloc/Cubit when the team already uses it; never GetX.

## Navigation (go_router)

Build the router inside a provider so redirects can read app state, and refresh it with a
`Listenable` instead of rebuilding the router.

```dart
@Riverpod(keepAlive: true)
GoRouter router(Ref ref) {
  final isSignedIn = ValueNotifier<bool>(false);
  ref
    ..listen(authProvider, (_, next) => isSignedIn.value = next is SignedIn, fireImmediately: true)
    ..onDispose(isSignedIn.dispose);

  final router = GoRouter(
    refreshListenable: isSignedIn,
    redirect: (context, state) {
      final isOnLogin = state.matchedLocation == '/login';
      if (!isSignedIn.value) return isOnLogin ? null : '/login';
      return isOnLogin ? '/' : null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(
        path: '/users/:id',
        builder: (_, state) => UserScreen(userId: state.pathParameters['id']!),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
}
```

- `MaterialApp.router(routerConfig: ref.watch(routerProvider))` in the root `ConsumerWidget`.
- Type-safe routes with `go_router_builder`; `StatefulShellRoute` for tab stacks.
- Deep links: App Links (`assetlinks.json`) and Universal Links (`apple-app-site-association`);
  validate path parameters before use.

## Errors

- Domain failures are `sealed class` hierarchies (`UserNotFound`, `NetworkUnavailable`);
  repositories catch `DioException`/`PlatformException` and throw or return domain failures.
- UI pattern-matches `AsyncValue` / failures; never shows `error.toString()` to users.
- Bootstrap wires `FlutterError.onError` and `PlatformDispatcher.instance.onError` to the
  `CrashReporter` port. Never swallow errors in `catch (_) {}`.

## Security

- Tokens in `flutter_secure_storage` (Keychain / Keystore) behind a `SecureStore` port;
  `shared_preferences` only for non-sensitive settings.
- `--dart-define` values are compiled into the binary: public config only, never secrets.
- TLS: never override `badCertificateCallback`; if pinning is required, configure it natively
  (`NSPinnedDomains` on iOS, network security config on Android) or via a maintained plugin.
- Local data: `drift` for relational storage, `hive_ce` for simple boxes (original `hive` is
  unmaintained); encrypt sensitive stores with a key held in secure storage.
- iOS privacy manifests: the Runner target has its own `PrivacyInfo.xcprivacy`; only use plugin
  versions that ship one (see `mobile-ios` → privacy manifests).

## Observability

- `package:logging` with one root handler: console in debug, crash-reporter breadcrumbs in
  release. No `print` / `debugPrint` in shipped code.
- Crash reporting (`firebase_crashlytics` or `sentry_flutter`), analytics, and push behind ports
  in `platform/`; upload obfuscation symbols per build.
- Profile in DevTools (profile mode, real device) before optimizing.

## Accessibility and localization

- Follow the `accessibility` skill. Touch targets ≥ 48×48 dp (Android) / 44×44 pt (iOS);
  `tooltip` on `IconButton`; `Semantics` for custom controls; never color-only state.
- Respect text scaling via `MediaQuery.textScalerOf`; never lock the scaler; test at 200%.
- `flutter_localizations` + `intl`, `generate: true` in pubspec, ARB files in `lib/l10n`; import
  generated `AppLocalizations` from source (the `flutter_gen` synthetic package is gone).
- RTL: `EdgeInsetsDirectional`, `AlignmentDirectional`, `start`/`end`; mirror directional icons.

## Platform services

Push (`firebase_messaging`), background work (`workmanager` → WorkManager / BGTaskScheduler),
crash-reporter adapters, and bootstrap wiring: read `reference/platform-services.md`.
Flavors and per-environment config: read `reference/flavors.md` — flavors are Gradle
`productFlavors` plus Xcode schemes, selected with `--flavor`, never a pubspec section.

## Platform channels

- Prefer maintained pub.dev plugins; custom channels use `pigeon` for type-safe messages.
- Document channel names and payloads; validate everything crossing the channel.

## Testing

- Unit: `ProviderContainer.test(overrides: [...])` with fakes of domain interfaces;
  `mocktail` for interaction checks.
- Widget: `flutter_test`; include the `androidTapTargetGuideline`, `iOSTapTargetGuideline`,
  `labeledTapTargetGuideline`, and `textContrastGuideline` matchers on key screens.
- Goldens: `matchesGoldenFile` or `alchemist` (`golden_toolkit` is discontinued); run golden
  comparisons on one CI OS.
- Platform channels: mock at the binary messenger.

```dart
testWidgets('shows battery level', (tester) async {
  const channel = MethodChannel('com.example/battery');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    channel,
    (call) async => call.method == 'getLevel' ? 87 : null,
  );
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

  await tester.pumpWidget(const MaterialApp(home: BatteryBadge()));
  await tester.pumpAndSettle();
  expect(find.text('87%'), findsOneWidget);
});
```

- Outside `testWidgets`, use `TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger`
  after `TestWidgetsFlutterBinding.ensureInitialized()`.
- E2E: `integration_test` on real devices/emulators for critical journeys, per flavor.

_Versions verified September 2026._
