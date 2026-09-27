# Flutter flavors and environments

Read when adding an environment (dev/staging/production), a per-flavor Firebase project, or
per-flavor app IDs and names. Official guides: "Set up Flutter flavors for Android" and
"Set up Flutter flavors for iOS and macOS" on docs.flutter.dev.

A flavor is native build configuration: Gradle `productFlavors` on Android and Xcode schemes +
build configurations on iOS, selected with `--flavor`. There is no `flavors:` section in
`pubspec.yaml`.

## Android — `android/app/build.gradle.kts`

```kotlin
android {
    // ...
    flavorDimensions += "environment"
    productFlavors {
        create("staging") {
            dimension = "environment"
            applicationIdSuffix = ".staging"
            resValue(type = "string", name = "app_name", value = "Example Staging")
        }
        create("production") {
            dimension = "environment"
            resValue(type = "string", name = "app_name", value = "Example")
        }
    }
}
```

- Reference the name in `AndroidManifest.xml` with `android:label="@string/app_name"`.
- Per-flavor resources and `google-services.json` go in `android/app/src/<flavor>/`.

## iOS — Xcode schemes

1. Duplicate the `Debug`, `Release`, and `Profile` build configurations per flavor
   (`Debug-staging`, `Release-staging`, `Profile-staging`, …).
2. Create one shared scheme per flavor (`staging`, `production`) whose actions use the matching
   configurations; the scheme name must equal the `--flavor` value.
3. Set `PRODUCT_BUNDLE_IDENTIFIER`, display name, and app icon per configuration (xcconfig files
   per flavor keep this reviewable).
4. Copy the matching `GoogleService-Info.plist` in a build phase keyed on the configuration.
5. Commit the shared schemes (`xcshareddata/xcschemes`).

## Running and building

```bash
flutter run --flavor staging --dart-define-from-file=config/staging.json
flutter build appbundle --flavor production --dart-define-from-file=config/production.json
flutter build ipa --flavor production --dart-define-from-file=config/production.json
```

## Reading the flavor in Dart

```dart
import 'package:flutter/services.dart';

enum Environment { staging, production }

Environment resolveEnvironment() => switch (appFlavor) {
      'production' => Environment.production,
      'staging' => Environment.staging,
      _ => throw StateError('Unknown or missing flavor: $appFlavor'),
    };
```

- `appFlavor` is `null` when no `--flavor` was passed; fail fast rather than defaulting to
  production.
- Environment values (API base URL, feature flags) come from `--dart-define-from-file` JSON read
  with `String.fromEnvironment`. They end up in the binary — public values only; secrets stay on
  the server.
- For Firebase, run `flutterfire configure` once per flavor and select the generated options by
  `Environment` in the composition root.
- CI builds every flavor it ships and runs `integration_test` against the staging flavor.
