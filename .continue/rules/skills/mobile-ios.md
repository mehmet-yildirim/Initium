---
name: mobile-ios
description: iOS development standards — Swift 5.9+, SwiftUI, MVVM, async/await, XCTest, App Store guidelines. Use when writing or reviewing native iOS / Swift code.
globs:
  - "**/*.swift"
  - "**/*.xib"
  - "**/*.storyboard"
  - "**/Info.plist"
  - "**/*.xcodeproj/**"
  - "**/*.xcworkspace/**"
  - "**/Package.swift"
  - "**/*.xcconfig"
alwaysApply: false
---
<!-- Generated from .claude/skills by .initium/scripts/sync-skills.mjs — edit the skill, not this file. -->

# iOS Development Standards

Visual and interaction design (Liquid Glass, navigation, Dynamic Type, SF Symbols): `design-apple-hig`.

## Swift Language

### Modern Swift (5.9+)
- Strict concurrency: `Sendable`, `@MainActor`, `actor` for shared mutable state
- `async/await` for all asynchronous work — no callbacks or completion handlers in new code
- Structured concurrency: `async let`, `TaskGroup` for parallel work
- `withTaskCancellationHandler` for graceful cancellation
- Actors isolate mutable state; `MainActor` for all UI updates
- Use `some Protocol` (opaque types) and `any Protocol` (existentials) correctly — prefer `some`

```swift
// Preferred: async/await with actor isolation
@MainActor
final class UserViewModel: ObservableObject {
    @Published private(set) var user: User?
    @Published private(set) var isLoading = false
    @Published private(set) var error: UserError?

    private let repository: UserRepository

    init(repository: UserRepository) {
        self.repository = repository
    }

    func loadUser(id: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            user = try await repository.fetchUser(id: id)
        } catch {
            self.error = error as? UserError ?? .unknown(error)
        }
    }
}
```

### Naming Conventions
- Types / Protocols: `PascalCase`
- Properties / functions / local variables: `camelCase`
- Constants: `camelCase` (Swift convention — not SCREAMING_SNAKE)
- Boolean properties: `is`, `has`, `can`, `should` prefix
- Functions with side effects: verb (`fetchUser`, `saveOrder`, `deleteItem`)
- Protocols: noun (what it is) or `-able`/`-ing` suffix (`Loadable`, `UserProviding`)
- Avoid type name in property name: `user.name` not `user.userName`

### Type Safety
- `enum` with associated values for discriminated results and states
- Never use `!` force-unwrap outside of `IBOutlet` (and test assertions)
- `guard let` for early exit over `if let` with deep nesting
- Prefer `Result<Success, Failure>` for synchronous failable operations
- `throws` + `async throws` for recoverable errors
- Use `@frozen enum` for stable public enums; avoid fragile enum switches

```swift
enum LoadState<T: Sendable>: Sendable {
    case idle
    case loading
    case loaded(T)
    case failed(Error)
}
```

## SwiftUI

### View Design
- Views are value types — keep them pure and small (< 100 lines)
- Extract sub-views aggressively: `UserAvatarView`, `OrderRowView`
- Use `ViewBuilder` closures for composable layouts
- `PreviewProvider` / `#Preview` for every view — use realistic sample data
- Avoid logic in view bodies — delegate to ViewModel or computed properties

### State Management
| Property Wrapper | Use Case |
|-----------------|---------|
| `@State` | Simple local view state (toggle, text field value) |
| `@StateObject` | ViewModel owned by this view (created here) |
| `@ObservedObject` | ViewModel passed in from parent |
| `@EnvironmentObject` | Shared dependency injected via `.environmentObject()` |
| `@Environment` | System values (colorScheme, locale, dismiss) |
| `@Binding` | Two-way binding passed from parent |

- iOS 17+: prefer `@Observable` macro over `ObservableObject` + `@Published`
- Hoist state up to the lowest common ancestor — not higher

### Navigation (iOS 16+)
- Use `NavigationStack` + `navigationDestination(for:)` — not `NavigationView`
- Programmatic navigation via `NavigationPath` or `@State var path`
- `NavigationSplitView` for iPad / Mac layouts
- Deep link handling via `.onOpenURL` + path manipulation

```swift
struct AppView: View {
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            HomeView()
                .navigationDestination(for: User.self) { user in
                    UserDetailView(user: user)
                }
                .navigationDestination(for: Order.self) { order in
                    OrderDetailView(order: order)
                }
        }
    }
}
```

### Performance
- `LazyVStack` / `LazyHStack` / `LazyVGrid` for long lists (not `VStack`)
- `List` for interactive, reorderable, swipeable lists
- `.task` modifier for async work tied to view lifecycle (auto-cancels on disappear)
- `@MainActor` ensures UI updates on main thread
- Avoid `AnyView` — use generics or `@ViewBuilder` instead
- Profile with Instruments (SwiftUI profiler) before optimizing

## Architecture — MVVM + Clean

```
View (SwiftUI)
    ↓ observes
ViewModel (@MainActor, @Observable)
    ↓ calls
Use Case / Service (pure business logic, no UI)
    ↓ calls
Repository (protocol) ← NetworkRepository / LocalRepository
    ↓
Network (URLSession) / Persistence (SwiftData / Core Data)
```

- ViewModels are `@MainActor` — all published state updates are safe
- Use cases / services: plain Swift classes, no UI dependencies, fully testable
- Repository protocol enables mocking in tests
- Dependency injection via `init` — no singletons for business logic

## Networking

```swift
// Preferred: URLSession with async/await
struct NetworkClient {
    private let session: URLSession
    private let decoder = JSONDecoder()

    func fetch<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw NetworkError.httpError((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return try decoder.decode(T.self, from: data)
    }
}
```

- Model API responses as `Codable` structs
- `CodingKeys` for snake_case → camelCase mapping
- Cancel in-flight requests when view disappears (`.task` handles this automatically)
- Certificate pinning for sensitive endpoints

## Persistence

### SwiftData (iOS 17+, preferred for new projects)
```swift
@Model
final class Order {
    var id: UUID
    var total: Decimal
    var createdAt: Date
    @Relationship(deleteRule: .cascade) var items: [OrderItem]

    init(id: UUID = .init(), total: Decimal, createdAt: Date = .now) {
        self.id = id; self.total = total; self.createdAt = createdAt
    }
}
```

### Core Data (for existing projects / complex migrations)
- `NSPersistentContainer` wrapped in a repository
- Background context for write operations: `performBackgroundTask`
- Main context for reads bound to UI
- `NSFetchedResultsController` for live list updates

## Testing (XCTest + Swift Testing)

### Unit Tests
```swift
// Swift Testing (Xcode 16+) — preferred for new tests
@Suite("UserViewModel Tests")
struct UserViewModelTests {
    @Test("shows loaded user after successful fetch")
    func loadsUserSuccessfully() async throws {
        let mockRepo = MockUserRepository(result: .success(.mock))
        let vm = await UserViewModel(repository: mockRepo)
        await vm.loadUser(id: "1")
        #expect(vm.user == .mock)
        #expect(!vm.isLoading)
    }
}
```

- Mock protocols — not concrete types
- `@MainActor` on async view model tests
- Test every state: idle, loading, loaded, error
- Use `withCheckedThrowingContinuation` to bridge callback APIs in tests

### UI Tests (XCUITest)
- Test critical user journeys only (not every screen)
- Use `accessibilityIdentifier` for stable element selection — never UI strings
- `XCTestExpectation` for async assertions

## Accessibility
- Every interactive element needs `accessibilityLabel` if its meaning isn't obvious
- `accessibilityHint` for non-obvious actions
- `accessibilityValue` for sliders, progress indicators
- Support Dynamic Type: use `.font(.body)` system fonts, avoid fixed sizes
- Test with VoiceOver before submitting

## App Store & Distribution
- Increment `CFBundleShortVersionString` (marketing) and `CFBundleVersion` (build) for every submission
- Privacy manifest (`PrivacyInfo.xcprivacy`) required for SDK APIs
- Use `xcconfig` files for environment-specific settings — not hardcoded in Info.plist
- Fastlane for automated builds, signing, and TestFlight uploads
- Never commit `.p12` files or provisioning profiles — use Fastlane Match

## Swift Package Manager
- Prefer SPM over CocoaPods for new projects
- Pin package versions exactly in `Package.resolved`
- Commit `Package.resolved` to version control
- Separate targets for each layer (feature modules) to enforce boundaries

## Code Organization
```
MyApp/
├── App/                    # Entry point, app delegate, scenes
├── Features/               # Feature modules (each is a Swift Package target)
│   └── Orders/
│       ├── Views/
│       ├── ViewModels/
│       ├── Models/
│       └── OrdersFeature.swift   # Public API surface
├── Core/                   # Shared business logic
│   ├── Network/
│   ├── Persistence/
│   └── Analytics/
└── Resources/              # Assets, localization strings
```
