---
name: mobile-ios
description: Native iOS/iPadOS standards for Swift 6.2+ on Xcode 26+ (Xcode 27 / Swift 6.4 / iOS 27 SDK current) — SwiftUI with Observation (@Observable), Approachable Concurrency, SwiftData, Swift Testing, privacy manifests, Keychain, APNs, BGTaskScheduler, Universal Links, String Catalogs, MetricKit, and vendor SDKs behind adapters. Use when writing, reviewing, or configuring Swift code, Swift packages, Xcode projects, Info.plist, or PrivacyInfo.xcprivacy; use `design-apple-hig` for visual and interaction design.
paths:
  - "**/*.swift"
  - "**/Package.swift"
  - "**/*.xcodeproj/**"
  - "**/Info.plist"
  - "**/PrivacyInfo.xcprivacy"
---

# iOS Development Standards

Code, architecture, and store rules for native Apple-platform apps. Visual design (Liquid Glass,
navigation, Dynamic Type, SF Symbols): `design-apple-hig`. Accessibility audits: `accessibility`.

## Baseline

- Xcode 27 (Swift 6.4, iOS 27 SDK) is current; it needs macOS Tahoe 26.6+ on Apple silicon.
- App Store Connect has required Xcode 26+ and the iOS 26 SDK since 2026-04-28. Pin the Xcode
  version in CI and bump it deliberately.
- Swift 6 language mode for all targets; minimum toolchain Swift 6.2.
- Deployment target iOS 17+ for the patterns below (Observation, SwiftData, `#Preview`); gate
  newer APIs with `#available`.
- Building with the iOS 27 SDK:
  - Adopt the UIScene life cycle — apps without it fail to launch.
  - iPhone apps become resizable (iPhone Mirroring, iPad). Lay out from size classes and
    container size, never from `UIScreen.main`, `userInterfaceIdiom`, or interface orientation.
  - `@State` is now a macro (back-deploys to iOS 17). Never give a `@State` property a
    declaration-site value *and* assign it in `init`.
  - `PreviewProvider` and its preview modifiers are deprecated — use `#Preview` only.
  - `canOpenURL(_:)` is deprecated — call `open(_:)` and handle failure.

## Toolchain

- Format with `swift format` (ships with the toolchain); lint with SwiftLint; both run in CI.
- `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` on release CI builds; strict concurrency is implied by
  Swift 6 mode.
- Swift Package Manager only for new dependencies. CocoaPods trunk goes read-only on
  2026-12-02 and vendors (e.g. Firebase) have stopped publishing pods — plan migrations now.
- Commit `Package.resolved`; pin exact versions for binary SDKs; enable Dependabot or Renovate
  for Swift packages.
- Build and sign with Xcode Cloud or Fastlane (`match` for certificates). Never commit `.p12`,
  `.mobileprovision`, or `.p8` files.

## Concurrency (Approachable Concurrency)

- App and UI targets: *Default Actor Isolation* = `MainActor` and *Approachable Concurrency* =
  `YES` (the Xcode 26+ defaults for new projects). This turns on `nonisolated(nonsending)` by
  default, so nonisolated async functions run on the caller's actor.
- Domain, networking, and persistence packages keep `nonisolated` default isolation. In
  `Package.swift`, opt UI packages in with `swiftSettings: [.defaultIsolation(MainActor.self)]`.
- Mark CPU-heavy functions `@concurrent` to run them off the caller's actor; use `actor` for
  shared mutable state; pass `Sendable` value types across isolation boundaries.
- Use `.task` / `.task(id:)` for view-scoped async work (cancelled on disappear); check
  `Task.isCancelled` in long loops.
- No `DispatchQueue` or completion handlers in new code. Bridge legacy callback APIs once, inside
  an adapter, with `withCheckedThrowingContinuation`.

## Structure

Feature packages with hexagonal layering: domain (entities, errors, ports) → application (view
models, use cases) → adapters (URLSession, SwiftData, Keychain, vendor SDKs).

```
App/                        # @main, scenes, composition root (wires adapters to ports)
Packages/
├── Features/Orders/        # views + @Observable view models; imports Domain only
├── Domain/                 # entities, typed errors, repository/service protocols (no UIKit/SwiftUI)
├── Data/                   # URLSession + SwiftData adapters implementing Domain ports
└── Platform/               # Keychain, push, analytics, crash-reporting adapters
```

- Vendor SDKs (Firebase, analytics, payments, crash reporting, feature flags) are imported only
  in `Platform/` adapters behind a protocol. Features never `import FirebaseX`.
- Inject dependencies through initializers or `@Environment(Type.self)`; no singletons for
  business logic.
- One public entry point per feature package; everything else `internal`.

```swift
// Domain
struct User: Sendable, Equatable, Identifiable {
    let id: String
    var name: String
}

enum UserError: Error, Sendable, Equatable {
    case notFound, offline, unexpected
}

protocol UserRepository: Sendable {
    func user(id: String) async throws(UserError) -> User
}

// Feature
@MainActor
@Observable
final class UserViewModel {
    enum State: Equatable { case idle, loading, loaded(User), failed(UserError) }

    private(set) var state: State = .idle
    private let repository: any UserRepository

    init(repository: any UserRepository) {
        self.repository = repository
    }

    func load(id: String) async {
        state = .loading
        do {
            state = .loaded(try await repository.user(id: id))
        } catch {
            state = .failed(error)
        }
    }
}

struct UserScreen: View {
    let userID: String
    @State private var model: UserViewModel

    init(userID: String, repository: any UserRepository) {
        self.userID = userID
        self.model = UserViewModel(repository: repository)
    }

    var body: some View {
        content.task(id: userID) { await model.load(id: userID) }
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .idle, .loading: ProgressView()
        case .loaded(let user): Text(user.name).font(.title)
        case .failed: ContentUnavailableView("Couldn't load profile", systemImage: "wifi.exclamationmark")
        }
    }
}

struct PreviewUserRepository: UserRepository {
    func user(id: String) async throws(UserError) -> User { User(id: id, name: "Ada Lovelace") }
}

#Preview {
    UserScreen(userID: "42", repository: PreviewUserRepository())
}
```

## SwiftUI

- Observation first: `@State` owns a value or an `@Observable` model, `@Bindable` creates
  bindings into an observable passed in, `@Environment(Type.self)` reads an injected observable,
  `@Binding` for two-way value bindings.
- `ObservableObject`, `@Published`, `@StateObject`, `@ObservedObject`, `@EnvironmentObject` are
  legacy — only in code not yet migrated; never mix both models in one type.
- Views stay small and free of business logic; every screen has a `#Preview` with fake ports.
- `NavigationStack` with a typed path and `navigationDestination(for:)`; `NavigationSplitView`
  for iPad and Mac. Parse deep links into a typed route enum before touching the path.
- `List` / `LazyVStack` for long collections; avoid `AnyView`; profile with the SwiftUI
  instrument before optimizing.

## Errors

- Domain errors are enums; use typed throws (`throws(UserError)`) at module boundaries.
- Adapters map `URLError`, `DecodingError`, and `SwiftData` errors to domain errors, logging the
  original once. Views render state; they never inspect transport errors.
- Never swallow: no bare `try?` on fallible I/O without logging; no `try!` or force-unwrap
  outside tests. `fatalError` only for programmer errors (impossible states).

## Networking and persistence

- `URLSession` async APIs inside a `Data/` adapter; decode `Codable` DTOs and map them to domain
  types; validate status codes and payloads at the edge; set timeouts per request.
- SwiftData behind a repository port; do background writes in a `@ModelActor`; keep Core Data
  only for existing stores.
- Store nothing sensitive in `UserDefaults`, SwiftData, or files without data protection.

## Security

- Secrets and tokens in the Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`) behind a
  `SecureStore` port. No API secrets in the binary, Info.plist, or committed `.xcconfig`.
- Keep App Transport Security on; never set `NSAllowsArbitraryLoads`. Pin certificates
  declaratively with `NSPinnedDomains` in Info.plist (include a backup key).
- OAuth via `ASWebAuthenticationSession` with PKCE; callbacks through Universal Links, not custom
  URL schemes. Validate every incoming URL and push payload before acting on it.
- Files with sensitive data use `.completeFileProtection`.
- Request permissions just in time with specific `NS…UsageDescription` strings; ask for App
  Tracking Transparency before any cross-app tracking and never gate features on consent.

## Observability

- Log with `os.Logger(subsystem:category:)`; mark dynamic values `privacy: .private` unless
  they are safe. No `print` / `NSLog` in shipped code.
- MetricKit: on iOS 27 use the Swift `MetricManager` (`metricReports`, `diagnosticReports`
  async streams, retained for the app's lifetime); `MXMetricManager` is no longer recommended
  for new adoption. Forward reports through a `MetricsSink` port.
- Crash reporting (Crashlytics, Sentry) and analytics behind protocols in `Platform/`; scrub PII
  before sending. Use the OpenTelemetry Swift SDK when the backend is OTel-based.
- `OSSignposter` intervals around critical paths; verify in Instruments.

## Accessibility and localization

- Follow the `accessibility` skill. Hit targets ≥ 44×44 pt, VoiceOver labels on icon-only
  controls, Dynamic Type via text styles, and `performAccessibilityAudit()` in UI tests.
- String Catalogs (`.xcstrings`) for all user-facing text; `String(localized:)` /
  `LocalizedStringResource` in code; plurals and device variants in the catalog, not in code.
- RTL: use leading/trailing, never left/right; preview with
  `.environment(\.layoutDirection, .rightToLeft)` and a pseudolanguage; format numbers, dates,
  and currency with `FormatStyle`.

## Platform services

Keychain, APNs, background tasks, Universal Links, App Intents, ATT, and vendor-SDK adapters.
Read `reference/platform-services.md` when implementing any of them.

- APNs: request authorization in context, register, send the token to your backend; the backend
  sends pushes with token-based (`.p8`) auth. Handle taps through the scene's router.
- Background work: `BGTaskScheduler` with identifiers listed in
  `BGTaskSchedulerPermittedIdentifiers`; SwiftUI `.backgroundTask(.appRefresh(_:))`; work must be
  idempotent and finish within budget.
- Universal Links: Associated Domains entitlement (`applinks:`) plus an
  `apple-app-site-association` file served over HTTPS without redirects.
- App Intents: expose key actions to Siri, Shortcuts, Spotlight, and widgets; intents call the
  same use cases as the UI.

## Store compliance

- Privacy manifest (`PrivacyInfo.xcprivacy`) in the app and every SDK: required-reason API
  declarations, collected data types, tracking domains. Third-party SDKs on Apple's list must
  ship a manifest and a signature. Read `reference/privacy-manifest.md` before editing it or
  adding an SDK.
- Privacy nutrition labels in App Store Connect must match the merged privacy report (Xcode
  Organizer → Generate Privacy Report).
- Apps that create accounts must offer in-app account deletion.
- Set `ITSAppUsesNonExemptEncryption` in Info.plist; bump `CFBundleVersion` for every upload.
- Environment config via `.xcconfig` per scheme (no secrets); release builds strip debug menus.

## Testing

- Swift Testing is the default for unit and integration tests (`@Test`, `#expect`, `#require`,
  parameterized `arguments:`). Put `@MainActor` on suites that exercise main-actor view models.
- XCTest only for XCUITest UI flows and `measure` performance tests. Select elements with
  `accessibilityIdentifier`, never localized strings.
- Fakes implement domain protocols; never mock concrete adapters. Test every view-model state.

```swift
import Testing
@testable import Profile

@MainActor
@Suite("UserViewModel")
struct UserViewModelTests {
    @Test func loadsUser() async {
        let user = User(id: "1", name: "Ada")
        let model = UserViewModel(repository: StubUserRepository(result: .success(user)))
        await model.load(id: "1")
        #expect(model.state == .loaded(user))
    }

    @Test(arguments: [UserError.notFound, .offline])
    func surfacesFailure(_ error: UserError) async {
        let model = UserViewModel(repository: StubUserRepository(result: .failure(error)))
        await model.load(id: "1")
        #expect(model.state == .failed(error))
    }
}

struct StubUserRepository: UserRepository {
    let result: Result<User, UserError>
    func user(id: String) async throws(UserError) -> User { try result.get() }
}
```

_Versions verified September 2026._
