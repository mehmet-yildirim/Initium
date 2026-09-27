# EAS Build, environment variables, Update, and Submit

Read when editing `eas.json`, adding environment variables, shipping over-the-air updates, or
submitting to the stores.

## Build profiles

```json
{
  "cli": { "appVersionSource": "remote" },
  "build": {
    "development": {
      "developmentClient": true,
      "distribution": "internal",
      "environment": "development",
      "channel": "development"
    },
    "preview": {
      "distribution": "internal",
      "environment": "preview",
      "channel": "preview"
    },
    "production": {
      "autoIncrement": true,
      "environment": "production",
      "channel": "production"
    }
  },
  "submit": {
    "production": {
      "ios": { "ascAppId": "1234567890" },
      "android": { "track": "internal" }
    }
  }
}
```

- `appVersionSource: "remote"` lets EAS own build numbers; `autoIncrement` bumps them.
- Each profile maps to one EAS environment and one update channel.
- Signing credentials are EAS-managed; never commit keystores, `.p8`/`.p12`, or Play service
  account JSON. The only CI secret needed is `EXPO_TOKEN`.

## Environment variables (`eas env`)

```bash
eas env:set --name EXPO_PUBLIC_API_URL --value https://api.example.com \
  --environment production --visibility plaintext
eas env:set --name SENTRY_AUTH_TOKEN --value "$SENTRY_AUTH_TOKEN" \
  --environment production --visibility sensitive
eas env:pull --environment development
```

| Visibility | Readable where | Use for |
|---|---|---|
| `plaintext` | website, CLI, logs | public config (`EXPO_PUBLIC_*`) |
| `sensitive` | CLI and `env:pull`; masked in logs | tokens needed by builds *and* updates or locally (Sentry upload) |
| `secret` | EAS servers only | build-only credentials (private registry tokens, files) |

- `EXPO_PUBLIC_*` values are inlined into the JS bundle — never secrets, regardless of visibility.
- `secret` values are unavailable to `eas update`, local builds, and local config resolution.
- `.env*` files are gitignored; `eas env:pull` generates them locally. The legacy
  `eas secret:*` commands are replaced by `eas env:*`.
- Validate the resolved config with a Zod schema in `app.config.ts` and at app start.

## EAS Update and runtime versions

- A build only accepts updates with the same `runtimeVersion`. Choose one policy per app:
  - `{ "policy": "appVersion" }` (the `eas update:configure` default): bump `version` for every
    native change.
  - `{ "policy": "fingerprint" }`: derived from a hash of the native project so native changes
    can't be forgotten; SDK 58 defaults fingerprinting to the `balanced` preset.
- Publish per environment: `eas update --channel production --environment production`
  (`--environment` is required on SDK 55+).
- Updates may only change JS and assets. Never use them to add features that need review or to
  change the app's purpose; native changes need a store build.
- Roll out gradually (`--rollout-percentage`, then `eas update:edit`), watch crash rates per
  update ID, and keep `eas update:republish` of the previous group ready as the rollback path.
- Upload source maps for every update to the crash reporter.

## Submit

- `eas build --profile production --auto-submit` or `eas submit --profile production`.
- Store the Play service account key and App Store Connect API key as EAS credentials, not in the
  repo.
- iOS builds need the current App Store SDK (Xcode 26+ since 2026-04-28); use an EAS build image
  that satisfies it.
