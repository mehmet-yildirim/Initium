# Platform services: push, background work, crash reporting

Read when adding push notifications, periodic background work, or crash reporting to an Expo app.
All vendor SDKs stay in `src/platform/`; features depend on the interfaces below.

## Push notifications (`expo-notifications`)

- Test push in a development build, not Expo Go. It works on physical devices, Android emulators
  with Google Play services, and recent iOS simulators; drop the `Device.isDevice` guard below if
  you test on simulators.
- Configure FCM (Android) and APNs (iOS) credentials through EAS; never commit them.
- Ask for permission in context (after the user opts into something that needs it), not at launch.

```ts
// src/platform/push-service.ts
import Constants from 'expo-constants';
import * as Device from 'expo-device';
import * as Notifications from 'expo-notifications';
import { Platform } from 'react-native';

export type PushRegistrationError = 'NOT_A_DEVICE' | 'PERMISSION_DENIED' | 'MISSING_PROJECT_ID';

export type PushRegistration =
  | { ok: true; token: string }
  | { ok: false; error: PushRegistrationError };

export interface PushService {
  register(): Promise<PushRegistration>;
}

Notifications.setNotificationHandler({
  handleNotification: async () => ({
    shouldShowBanner: true,
    shouldShowList: true,
    shouldPlaySound: false,
    shouldSetBadge: false,
  }),
});

export const expoPushService: PushService = {
  async register() {
    if (!Device.isDevice) return { ok: false, error: 'NOT_A_DEVICE' };

    if (Platform.OS === 'android') {
      await Notifications.setNotificationChannelAsync('default', {
        name: 'Default',
        importance: Notifications.AndroidImportance.DEFAULT,
      });
    }

    const current = await Notifications.getPermissionsAsync();
    const permission = current.granted ? current : await Notifications.requestPermissionsAsync();
    if (!permission.granted) return { ok: false, error: 'PERMISSION_DENIED' };

    const projectId = Constants.expoConfig?.extra?.eas?.projectId as string | undefined;
    if (!projectId) return { ok: false, error: 'MISSING_PROJECT_ID' };

    const { data } = await Notifications.getExpoPushTokenAsync({ projectId });
    return { ok: true, token: data };
  },
};
```

- Create the Android channel before requesting the token (Android 13+ shows the permission
  prompt only once a channel exists).
- Send the token to your backend over an authenticated request; treat it as user-linked data.
- Handle taps with `Notifications.addNotificationResponseReceivedListener` (and
  `getLastNotificationResponseAsync` for cold starts) and route with expo-router; validate the
  payload with Zod before navigating.
- Notification payloads are visible to Apple/Google infrastructure: no secrets or sensitive PII.

## Background work (`expo-background-task`)

`expo-background-fetch` is deprecated; use `expo-background-task` (WorkManager on Android,
`BGTaskScheduler` on iOS). The OS decides when tasks run — never rely on exact timing.

```ts
// src/platform/background-sync.ts
import * as BackgroundTask from 'expo-background-task';
import * as TaskManager from 'expo-task-manager';

import { logger } from '@/platform/logger';
import { syncPendingOrders } from '@/features/orders/data/sync';

const SYNC_TASK = 'background-sync';
const SYNC_INTERVAL_MINUTES = 15;

// Must run at module scope, imported from the root layout, so the task exists at cold launch.
TaskManager.defineTask(SYNC_TASK, async () => {
  try {
    await syncPendingOrders();
    return BackgroundTask.BackgroundTaskResult.Success;
  } catch (error) {
    logger.error('background sync failed', { error });
    return BackgroundTask.BackgroundTaskResult.Failed;
  }
});

export async function registerBackgroundSync(): Promise<void> {
  const status = await BackgroundTask.getStatusAsync();
  if (status !== BackgroundTask.BackgroundTaskStatus.Available) {
    logger.warn('background tasks unavailable', { status });
    return;
  }
  await BackgroundTask.registerTaskAsync(SYNC_TASK, { minimumInterval: SYNC_INTERVAL_MINUTES });
}
```

- `minimumInterval` is in minutes; 15 is the minimum.
- iOS needs `UIBackgroundModes: ["processing"]` and
  `BGTaskSchedulerPermittedIdentifiers: ["com.expo.modules.backgroundtask.processing"]` in
  `ios.infoPlist`; background tasks don't run on the iOS simulator.
- Test with `BackgroundTask.triggerTaskWorkerForTestingAsync()` in development builds only.
- Keep work short, idempotent, and resumable; the OS may kill it at any time.

## Crash reporting (`@sentry/react-native`)

```ts
// src/platform/crash-reporter.ts
export interface CrashReporter {
  captureError(error: unknown, context?: Record<string, string>): void;
  setUser(userId: string | null): void;
}
```

```ts
// src/platform/sentry-crash-reporter.ts
import * as Sentry from '@sentry/react-native';
import { isRunningInExpoGo } from 'expo';

import type { CrashReporter } from './crash-reporter';

Sentry.init({
  dsn: process.env.EXPO_PUBLIC_SENTRY_DSN,
  environment: process.env.EXPO_PUBLIC_APP_ENV,
  sendDefaultPii: false,
  tracesSampleRate: 0.2,
  integrations: [
    Sentry.expoRouterIntegration({ enableTimeToInitialDisplay: !isRunningInExpoGo() }),
  ],
  enableNativeFramesTracking: !isRunningInExpoGo(),
});

export const sentryCrashReporter: CrashReporter = {
  captureError(error, context) {
    Sentry.captureException(error, { tags: context });
  },
  setUser(userId) {
    Sentry.setUser(userId ? { id: userId } : null);
  },
};

export const wrapRoot = Sentry.wrap;
```

- Wrap the root layout's default export with `wrapRoot` so render errors are captured.
- Add the `@sentry/react-native/expo` config plugin (organization, project) in `app.config.ts` and
  use `getSentryExpoConfig(__dirname)` in `metro.config.js` so source maps map to your code.
- `SENTRY_AUTH_TOKEN` is a `sensitive` EAS variable (needed for build and update source-map
  uploads); the DSN is public config.
- Scrub PII in `beforeSend`; identify users by opaque ID only.
- Swap vendors by writing another `CrashReporter`; tests use an in-memory fake.
