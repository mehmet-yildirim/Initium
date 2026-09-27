# Swift / iOS security examples

Platform rules: `mobile-ios`. Follow the OWASP MASVS for mobile-specific requirements.

## Secrets and storage

- No API secrets in the app binary, `Info.plist`, xcconfig, or asset catalogs — anything shipped
  can be extracted. Call your backend, or exchange the user session for short-lived scoped tokens.
- Tokens and credentials go in the Keychain, never `UserDefaults` or plain files.

```swift
import Foundation
import Security

enum SecurityFrameworkError: Error {
    case unexpectedStatus(OSStatus)
}

func storeToken(_ token: Data, account: String) throws {
    let lookup: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrAccount as String: account,
    ]
    SecItemDelete(lookup as CFDictionary)

    var item = lookup
    item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    item[kSecValueData as String] = token
    let status = SecItemAdd(item as CFDictionary, nil)
    guard status == errSecSuccess else { throw SecurityFrameworkError.unexpectedStatus(status) }
}
```

- Use Data Protection (`.completeFileProtection`) for sensitive files.

## Randomness

```swift
func randomBytes(count: Int) throws -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: count)
    let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
    guard status == errSecSuccess else { throw SecurityFrameworkError.unexpectedStatus(status) }
    return bytes
}
// CryptoKit keys: SymmetricKey(size: .bits256)
```

## Logging

```swift
import os

let logger = Logger(subsystem: "com.example.app", category: "auth")
logger.debug("Refreshed session for \(userID, privacy: .private)")
// Never print()/NSLog() tokens, passwords, or PII
```

## Transport

- Keep App Transport Security on; no `NSAllowsArbitraryLoads`. Exceptions per domain with a
  written justification.
- Never accept invalid certificates in a `URLSessionDelegate`
  (`completionHandler(.useCredential, URLCredential(trust:))` without evaluating the trust is a
  bypass). Pin with `NSPinnedDomains` in `Info.plist` when pinning is required.

## Tooling

- Semgrep `p/swift`, CodeQL `swift`; MobSF for binary review; OSV-Scanner on `Package.resolved`.
