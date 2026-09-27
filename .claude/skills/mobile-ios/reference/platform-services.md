# iOS platform services

Recipes for the services summarized in `SKILL.md`. Each one lives in a `Platform/` adapter
behind a domain protocol so features and tests never touch the system or vendor API directly.

## Keychain (`SecureStore` port)

```swift
import Foundation
import Security

enum SecureStoreError: Error, Equatable {
    case unexpectedStatus(OSStatus)
    case invalidData
}

protocol SecureStore: Sendable {
    func save(_ data: Data, for key: String) throws(SecureStoreError)
    func read(_ key: String) throws(SecureStoreError) -> Data?
    func delete(_ key: String) throws(SecureStoreError)
}

struct KeychainStore: SecureStore {
    let service: String

    func save(_ data: Data, for key: String) throws(SecureStoreError) {
        let query = baseQuery(key)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let item = query.merging(attributes) { _, new in new }
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw SecureStoreError.unexpectedStatus(addStatus) }
            return
        }
        guard status == errSecSuccess else { throw SecureStoreError.unexpectedStatus(status) }
    }

    func read(_ key: String) throws(SecureStoreError) -> Data? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw SecureStoreError.unexpectedStatus(status) }
        guard let data = item as? Data else { throw SecureStoreError.invalidData }
        return data
    }

    func delete(_ key: String) throws(SecureStoreError) {
        let status = SecItemDelete(baseQuery(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureStoreError.unexpectedStatus(status)
        }
    }

    private func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }
}
```

- `…ThisDeviceOnly` keeps items out of backups and device migration; use
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` only for items background tasks must read.
- Share items with extensions through a Keychain access group, not the app group container.
- Gate high-value reads with `SecAccessControl` (`.biometryCurrentSet`) and LocalAuthentication.

## APNs

```swift
import OSLog
import UIKit
import UserNotifications

protocol PushTokenRegistrar: Sendable {
    func register(token: String) async
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    var registrar: (any PushTokenRegistrar)?
    private let logger = Logger(subsystem: "com.example.app", category: "push")

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { await registrar?.register(token: token) }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        logger.error("APNs registration failed: \(error.localizedDescription, privacy: .public)")
    }
}

@MainActor
func enablePushNotifications() async throws {
    let granted = try await UNUserNotificationCenter.current()
        .requestAuthorization(options: [.alert, .badge, .sound])
    guard granted else { return }
    UIApplication.shared.registerForRemoteNotifications()
}
```

- Attach the delegate in SwiftUI with `@UIApplicationDelegateAdaptor(AppDelegate.self)` and
  inject `registrar` from the composition root.
- Ask for permission after the user understands the value (e.g. after enabling order updates),
  not at first launch. Consider provisional authorization for low-stakes notifications.
- Implement `UNUserNotificationCenterDelegate` to route taps into the typed deep-link router.
- Payloads are untrusted input: validate IDs, never embed secrets or PII, and fetch details over
  an authenticated API.
- The backend sends pushes with token-based (`.p8`) auth; the key never ships in the app.

## Background tasks

```xml
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array><string>com.example.app.refresh</string></array>
<key>UIBackgroundModes</key>
<array><string>fetch</string></array>
```

`SyncService` is a domain port; the composition root supplies the live adapter.

```swift
import BackgroundTasks
import OSLog
import SwiftUI

protocol SyncService: Sendable {
    func run() async
}

@main
struct ExampleApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let sync: any SyncService = AppComposition.makeSyncService()

    var body: some Scene {
        WindowGroup { RootView() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { scheduleRefresh() }
            }
            .backgroundTask(.appRefresh("com.example.app.refresh")) { [sync] in
                await sync.run()
                scheduleRefresh()
            }
    }
}

nonisolated func scheduleRefresh() {
    let request = BGAppRefreshTaskRequest(identifier: "com.example.app.refresh")
    request.earliestBeginDate = .now.addingTimeInterval(15 * 60)
    do {
        try BGTaskScheduler.shared.submit(request)
    } catch {
        Logger(subsystem: "com.example.app", category: "background")
            .error("Refresh scheduling failed: \(error.localizedDescription, privacy: .public)")
    }
}
```

- The system decides when tasks run; never rely on exact timing. Work must be idempotent and
  resumable.
- Use `BGProcessingTaskRequest` (`processing` mode) for long maintenance work that can wait for
  charging; on iOS 26+ use `BGContinuedProcessingTaskRequest` for user-started work that should
  continue after the app is backgrounded.
- Test with the debugger command
  `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.example.app.refresh"]`.

## Universal Links

- Entitlement: `com.apple.developer.associated-domains` = `applinks:example.com`.
- Host `https://example.com/.well-known/apple-app-site-association` (JSON, no redirects, no file
  extension) listing the app ID and path components.
- Handle links with `.onOpenURL` (SwiftUI) and parse into a typed route; reject unknown paths and
  re-authorize any action a link triggers.
- Prefer Universal Links to custom schemes for auth callbacks and marketing links.

## App Intents

- Declare `AppIntent` types with `static let title: LocalizedStringResource` and `@Parameter`
  properties; `perform()` calls the same use case as the UI.
- Model user content as `AppEntity` with an `EntityQuery` so Siri and Shortcuts can resolve it.
- Publish common intents with an `AppShortcutsProvider`; every phrase must include
  `\(.applicationName)`.
- Intents must live in the app target (or an App Intents package it links) because metadata is
  extracted at build time.

## App Tracking Transparency

- Only needed if you track users across apps or websites owned by others (including via
  vendor SDKs).
- Add `NSUserTrackingUsageDescription`; call `await ATTrackingManager.requestTrackingAuthorization()`
  once the scene is active, before any tracking SDK starts.
- Treat `.denied`, `.restricted`, and `.notDetermined` identically: no IDFA, no fingerprinting,
  no degraded features.

## Vendor SDK adapter

```swift
// Domain
protocol CrashReporter: Sendable {
    func record(_ error: any Error, context: [String: String])
    func setUserID(_ id: String?)
}

// Platform/CrashReportingFirebase — the only target that imports the vendor SDK
import FirebaseCrashlytics

struct CrashlyticsReporter: CrashReporter {
    func record(_ error: any Error, context: [String: String]) {
        let crashlytics = Crashlytics.crashlytics()
        for (key, value) in context { crashlytics.setCustomValue(value, forKey: key) }
        crashlytics.record(error: error)
    }

    func setUserID(_ id: String?) {
        Crashlytics.crashlytics().setUserID(id ?? "")
    }
}
```

- Pass opaque user IDs only; never emails or names.
- Tests and previews use a no-op or recording fake of the protocol.
