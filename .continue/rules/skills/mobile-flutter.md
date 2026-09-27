---
name: mobile-flutter
description: Flutter / Dart development standards — cross-platform iOS & Android, Riverpod, GoRouter, testing. Use when writing or reviewing Flutter / Dart code.
globs:
  - "**/*.dart"
  - "**/pubspec.yaml"
  - "**/pubspec.lock"
  - "**/analysis_options.yaml"
  - "**/flutter/**"
alwaysApply: false
---
<!-- Generated from .claude/skills by .initium/scripts/sync-skills.mjs — edit the skill, not this file. -->

# Flutter / Dart Development Standards

## Dart Language

### Modern Dart (3.x)
- Sound null safety: `?` for nullable, `!` only when non-null is guaranteed by invariant
- Records: `(String name, int age)` for lightweight structured values
- Patterns and pattern matching in `switch` expressions
- Sealed classes for exhaustive state modeling
- `extension` methods for adding behavior to existing types
- `typedef` for complex function signatures
- `late` only when initialization is deferred by design — never to suppress null errors

```dart
// Sealed state modeling
sealed class UserState {}
final class UserLoading extends UserState {}
final class UserLoaded extends UserState {
  const UserLoaded(this.user);
  final User user;
}
final class UserError extends UserState {
  const UserError(this.message);
  final String message;
}
```

### Naming Conventions
- Classes / Enums / Typedefs / Extensions: `UpperCamelCase`
- Variables / functions / parameters: `lowerCamelCase`
- Constants: `lowerCamelCase` (Dart convention — not SCREAMING_SNAKE)
- Files and directories: `snake_case`
- Packages and libraries: `snake_case`
- Private members: `_lowerCamelCase`
- Widget names match file names: `UserCard` widget in `user_card.dart`

### Code Quality
- `flutter analyze` with `very_good_analysis` or `flutter_lints` — zero warnings in CI
- `dart format` on every save
- `required` on all non-nullable named parameters
- `const` constructors on all stateless widgets that can be const
- `@visibleForTesting` on members exposed only for tests

## Widget Architecture

### Widget Types
```dart
// Stateless — pure, no mutable state
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.user});
  final User user;

  @override
  Widget build(BuildContext context) => CircleAvatar(
    backgroundImage: NetworkImage(user.avatarUrl),
    radius: 24,
  );
}
```

- `StatelessWidget`: pure, side-effect-free UI — prefer for all leaf components
- `StatefulWidget`: local ephemeral state only (animation, text field focus)
- Hooks (`flutter_hooks`): alternative to `StatefulWidget` for local state
- Avoid deep widget trees in `build()` — extract named widget methods or separate widgets

### Widget Design Principles
- `const` wherever possible — reduces rebuilds
- Keep `build()` methods free of business logic
- Extract reusable widgets to their own files
- `Key` parameter on all widgets that appear in lists or conditional positions
- `Padding` / `SizedBox` over `Container` when only spacing is needed

## State Management (Riverpod — preferred)

```dart
// Provider definition (outside widget)
@riverpod
class UserNotifier extends _$UserNotifier {
  @override
  FutureOr<User?> build() => null;

  Future<void> loadUser(String id) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(userRepositoryProvider).getUser(id));
  }
}

// Consumption in widget
class UserScreen extends ConsumerWidget {
  const UserScreen({super.key, required this.userId});
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userNotifierProvider);
    return userAsync.when(
      loading: () => const CircularProgressIndicator(),
      error: (e, _) => ErrorWidget(e.toString()),
      data: (user) => user == null ? const EmptyView() : UserContent(user: user),
    );
  }
}
```

- Code-generate providers with `@riverpod` annotation + `riverpod_generator`
- `ref.watch` for reactive reads; `ref.read` inside callbacks/actions
- `AsyncNotifierProvider` for async operations with loading/error state
- `StateProvider` for simple, single-value state
- `FutureProvider` for one-shot reads without user actions
- Family modifiers for parameterized providers: `userProvider(userId)`

### State Management Alternatives
- **Bloc/Cubit**: when explicit event-driven state machine is needed
- **GetX**: avoid — no separation of concerns, global state
- **Provider**: legacy; migrate to Riverpod when possible

## Navigation (GoRouter)

```dart
final router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
    GoRoute(
      path: '/users/:id',
      builder: (context, state) => UserScreen(userId: state.pathParameters['id']!),
    ),
  ],
  redirect: (context, state) {
    final isLoggedIn = ref.read(authProvider).isLoggedIn;
    return isLoggedIn ? null : '/login';
  },
);
```

- Type-safe routes with `go_router_builder` code generation
- Nested routes via `ShellRoute` for bottom navigation persistence
- `context.go()` for replace; `context.push()` for stack; `context.pop()` for back
- Deep link configuration in `AndroidManifest.xml` and `Info.plist`

## Project Structure

```
lib/
├── main.dart                    # Entry point
├── app.dart                     # MaterialApp / router setup
├── core/                        # Shared utilities
│   ├── network/                 # HTTP client, interceptors
│   ├── storage/                 # Local persistence
│   ├── theme/                   # Colors, typography, theme
│   └── utils/                   # Date formatters, validators, etc.
├── features/                    # Feature modules
│   └── orders/
│       ├── data/                # Repository implementations, DTOs
│       ├── domain/              # Entities, repository interfaces
│       ├── presentation/        # Screens, widgets, providers
│       └── orders.dart          # Feature barrel export
└── l10n/                        # Localisation ARB files
```

## Networking (Dio + Retrofit)

```dart
@RestApi(baseUrl: 'https://api.example.com')
abstract class UserApi {
  factory UserApi(Dio dio) = _UserApi;

  @GET('/users/{id}')
  Future<UserDto> getUser(@Path('id') String id);
}
```

- Dio for HTTP client with interceptors (auth, logging, retry)
- `retrofit` + `json_serializable` for type-safe API clients
- Repository pattern wraps API calls and maps DTOs to domain models
- `Freezed` for immutable data classes with `copyWith`, `==`, and `hashCode`

## Local Storage
- `shared_preferences` for simple key-value (settings, flags)
- `flutter_secure_storage` for sensitive data (tokens, credentials)
- `drift` (SQLite ORM) for structured local data — not direct `sqflite`
- `hive` for fast, type-safe object storage

## Testing

```dart
// Unit test
void main() {
  group('UserNotifier', () {
    test('loads user successfully', () async {
      final container = ProviderContainer(
        overrides: [userRepositoryProvider.overrideWithValue(FakeUserRepository())],
      );
      await container.read(userNotifierProvider.notifier).loadUser('1');
      expect(container.read(userNotifierProvider).value, isNotNull);
    });
  });
}

// Widget test
testWidgets('UserCard displays user name', (tester) async {
  await tester.pumpWidget(
    ProviderScope(child: MaterialApp(home: UserCard(user: User.mock))),
  );
  expect(find.text(User.mock.name), findsOneWidget);
});
```

- `flutter_test` for widget tests — no external testing library needed
- `mocktail` for mocking (null-safe, no code generation needed)
- `integration_test` package for full app E2E tests on real devices / simulators
- Golden tests with `golden_toolkit` for pixel-perfect UI regression

## Platform Channels & Plugins

- Prefer established pub.dev plugins over custom platform channels
- Custom platform channel: Dart `MethodChannel` ↔ Swift/Kotlin native code
- Document the channel name, method names, and argument types in code
- Plugin testing: `MockMethodChannel` in Dart unit tests

## Flavors & Environments

```yaml
# pubspec.yaml — flavor via dart-define
flutter:
  flavors:
    dev:
      app:
        name: "MyApp Dev"
        applicationId: com.company.myapp.dev
    prod:
      app:
        name: "MyApp"
        applicationId: com.company.myapp
```

- Use `--dart-define-from-file=config.dev.json` for environment configuration
- Separate `GoogleService-Info.plist` and `google-services.json` per flavor
- Never hardcode API URLs or keys — load from dart-defines

## Build & Distribution

- `flutter build appbundle` for Play Store; `flutter build ipa` for App Store
- Fastlane for automated signing and submission
- GitHub Actions / Bitrise / Codemagic for CI/CD
- `very_good_cli` for project generation and CI templates
- Run `flutter pub outdated` in CI; patch minor/patch versions automatically
