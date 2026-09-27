# Privacy manifests and App Store privacy

Read before editing `PrivacyInfo.xcprivacy`, adding a third-party SDK, or updating App Store
privacy answers. Apple's reference: "Privacy manifest files" and "Describing use of required
reason API" in the Apple Developer documentation — confirm reason codes there.

## What goes in the manifest

| Key | Purpose |
|---|---|
| `NSPrivacyTracking` | `true` only if the app or SDK tracks users as defined by ATT |
| `NSPrivacyTrackingDomains` | Domains that receive tracking data; iOS blocks them until the user allows tracking |
| `NSPrivacyCollectedDataTypes` | Each data type collected, whether it is linked to the user, used for tracking, and its purposes |
| `NSPrivacyAccessedAPITypes` | Every required-reason API category used, with an approved reason code |

Required-reason API categories: `NSPrivacyAccessedAPICategoryUserDefaults`,
`…FileTimestamp`, `…SystemBootTime`, `…DiskSpace`, `…ActiveKeyboards`. Declaring the wrong
reason, or none, gets the upload rejected.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSPrivacyTracking</key>
    <false/>
    <key>NSPrivacyTrackingDomains</key>
    <array/>
    <key>NSPrivacyCollectedDataTypes</key>
    <array>
        <dict>
            <key>NSPrivacyCollectedDataType</key>
            <string>NSPrivacyCollectedDataTypeEmailAddress</string>
            <key>NSPrivacyCollectedDataTypeLinked</key>
            <true/>
            <key>NSPrivacyCollectedDataTypeTracking</key>
            <false/>
            <key>NSPrivacyCollectedDataTypePurposes</key>
            <array>
                <string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
            </array>
        </dict>
    </array>
    <key>NSPrivacyAccessedAPITypes</key>
    <array>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <string>CA92.1</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
```

## Rules

- One manifest per app target and per framework/SDK bundle; each SDK declares its own usage.
  The app's manifest covers only the app's own code.
- Grep for required-reason APIs (`UserDefaults`, `creationDate`/`modificationDate`,
  `systemUptime`/`mach_absolute_time`, `volumeAvailableCapacity…`, `activeInputModes`) when
  reviewing changes and update declarations in the same PR.
- Third-party SDKs on Apple's "commonly used SDKs" list must include their own privacy manifest
  and, when shipped as binaries, a valid code signature. Reject SDK versions that lack them.
- Collected-data declarations must match reality, including data collected by SDKs and by your
  backend from the app.
- After archiving, generate the privacy report (Xcode Organizer → archive → Generate Privacy
  Report). Use it to answer the App Store Connect privacy nutrition label questions and review it
  whenever an SDK is added or updated.

## Related App Store requirements

- Purpose strings (`NS…UsageDescription`) for every protected resource, written for users.
- App Tracking Transparency prompt before any tracking; `NSPrivacyTrackingDomains` must list
  every tracking endpoint.
- In-app account deletion for apps that support account creation.
- Export compliance: set `ITSAppUsesNonExemptEncryption`.
