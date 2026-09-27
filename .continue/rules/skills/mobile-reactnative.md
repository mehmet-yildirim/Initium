---
name: mobile-reactnative
description: React Native development standards — TypeScript, Expo, React Navigation, Zustand, EAS Build, cross-platform iOS & Android. Use when writing or reviewing React Native / Expo code.
globs:
  - "**/metro.config.*"
  - "**/app.json"
  - "**/eas.json"
  - "**/babel.config.*"
  - "**/react-native.config.*"
  - "**/ios/**/*.swift"
  - "**/android/**/*.kt"
alwaysApply: false
---
<!-- Generated from .claude/skills by .initium/scripts/sync-skills.mjs — edit the skill, not this file. -->

# React Native Development Standards

## TypeScript — Strict Mode Required

Same TypeScript standards as the web (see `lang-typescript.mdc`) plus mobile-specific:
- `"strict": true` — non-negotiable
- `"noUncheckedIndexedAccess": true`
- Platform-specific types: `Platform.OS === 'ios'` with proper type narrowing
- `StyleSheet.create()` always — never inline style objects in JSX

## Project Setup

### Expo (preferred for new projects)
```bash
npx create-expo-app MyApp --template expo-template-blank-typescript
```
- Managed workflow for most apps; bare workflow when native modules require it
- `expo-modules-core` for type-safe native module creation
- `expo-dev-client` for custom native code during development
- Config plugins for native configuration (no manual Xcode/Android project edits)

### Bare React Native
- Only when Expo's managed workflow is insufficient
- `react-native-builder-bob` for creating native libraries
- Autolinking for native modules (`npx pod-install` for iOS)

## Component Design

```tsx
// Preferred: typed, const-named, StyleSheet
import { StyleSheet, Text, TouchableOpacity } from 'react-native';

interface PrimaryButtonProps {
  title: string;
  onPress: () => void;
  disabled?: boolean;
}

export function PrimaryButton({ title, onPress, disabled = false }: PrimaryButtonProps) {
  return (
    <TouchableOpacity
      style={[styles.button, disabled && styles.disabled]}
      onPress={onPress}
      disabled={disabled}
      accessibilityRole="button"
      accessibilityLabel={title}
    >
      <Text style={styles.label}>{title}</Text>
    </TouchableOpacity>
  );
}

const styles = StyleSheet.create({
  button: { backgroundColor: '#007AFF', borderRadius: 8, padding: 16 },
  disabled: { opacity: 0.5 },
  label: { color: '#fff', fontSize: 16, fontWeight: '600', textAlign: 'center' },
});
```

- Named exports for all components (not default exports)
- `StyleSheet.create()` for all styles — enables native optimization
- Prefer `Pressable` over `TouchableOpacity` for custom press behavior (RN 0.64+)
- `FlatList` / `SectionList` / `FlashList` for all scrollable lists — never `ScrollView` + `map()`
- `KeyboardAvoidingView` with `behavior={Platform.OS === 'ios' ? 'padding' : 'height'}` for forms

## Platform Handling

```tsx
// Platform-specific code
const hitSlop = Platform.select({ ios: 10, android: 8, default: 10 });

// Platform-specific files (RN resolves automatically)
// Button.ios.tsx
// Button.android.tsx
// Button.tsx (fallback)
```

- `Platform.OS` for simple branches; platform-specific file extensions for divergent UX
- `Platform.select()` for style values that differ by platform
- Never write `if (Platform.OS === 'ios')` blocks longer than 3 lines — extract to platform files
- Test on both platforms before every PR — Android and iOS can behave differently

## State Management

### Server State — TanStack Query
```tsx
const { data: user, isLoading, error } = useQuery({
  queryKey: ['user', userId],
  queryFn: () => userApi.getUser(userId),
  staleTime: 5 * 60 * 1000,
});
```

### Client/UI State — Zustand
```tsx
interface AuthStore {
  user: User | null;
  token: string | null;
  signIn: (credentials: Credentials) => Promise<void>;
  signOut: () => void;
}

const useAuthStore = create<AuthStore>()(
  persist(
    (set) => ({
      user: null,
      token: null,
      signIn: async (credentials) => {
        const { user, token } = await authApi.signIn(credentials);
        set({ user, token });
      },
      signOut: () => set({ user: null, token: null }),
    }),
    { name: 'auth-storage', storage: createJSONStorage(() => AsyncStorage) }
  )
);
```

- TanStack Query for all server/API state
- Zustand with `persist` middleware for auth / global app state
- `AsyncStorage` or `expo-secure-store` as Zustand persistence backend
- Avoid Redux — overhead not justified for mobile; if existing project uses it, follow existing patterns

## Navigation (React Navigation v7)

```tsx
// Type-safe navigation
type RootStackParamList = {
  Home: undefined;
  UserDetail: { userId: string };
  Settings: undefined;
};

const Stack = createNativeStackNavigator<RootStackParamList>();

function AppNavigator() {
  return (
    <Stack.Navigator screenOptions={{ headerShown: false }}>
      <Stack.Screen name="Home" component={HomeScreen} />
      <Stack.Screen name="UserDetail" component={UserDetailScreen} />
    </Stack.Navigator>
  );
}

// Typed usage in component
const navigation = useNavigation<NativeStackNavigationProp<RootStackParamList>>();
navigation.navigate('UserDetail', { userId: '123' });
```

- `createNativeStackNavigator` for iOS/Android native transitions
- `createBottomTabNavigator` for tab bars
- Always type `ParamList` — catch navigation bugs at compile time
- Deep links configured in `app.json` (Expo) or `AppDelegate`/`AndroidManifest`
- `Linking.createURL()` for dynamic deep links (Expo)

## Networking

```tsx
// Axios with interceptors
const apiClient = axios.create({ baseURL: Config.API_URL });

apiClient.interceptors.request.use((config) => {
  const token = useAuthStore.getState().token;
  if (token) config.headers.Authorization = `Bearer ${token}`;
  return config;
});
```

- Axios with interceptors for auth headers, error normalization, retry
- All network calls go through TanStack Query or a repository layer
- `react-native-mmkv` for fast token caching (alternative to AsyncStorage)
- Certificate pinning via `react-native-ssl-pinning` for sensitive apps

## Local Storage

| Use Case | Library |
|----------|---------|
| Key-value (fast) | `react-native-mmkv` |
| Sensitive data (tokens) | `expo-secure-store` |
| Large structured data | WatermelonDB / SQLite via `expo-sqlite` |
| Simple serializable state | `AsyncStorage` (only when others don't fit) |

## Styling

```tsx
// Prefer: typed design system constants
const { colors, spacing, typography } = useTheme();

// Conditional styles with array
<View style={[styles.container, isActive && styles.active, { marginTop: spacing.md }]} />
```

- Build a typed design system (`colors`, `spacing`, `typography`, `shadows`)
- Dark mode: `useColorScheme()` or `react-native-appearance`
- `react-native-unistyles` or `dripsy` for responsive, theme-aware styling
- Avoid `StyleSheet.flatten()` in hot paths — allocates new objects

## Performance

- Use `FlashList` (not `FlatList`) for long, virtualized lists (Shopify library)
- `useCallback` on event handlers passed to list items
- `useMemo` for expensive derived data; profile with Flipper before adding
- `react-native-reanimated` for smooth 60fps animations (Worklets API)
- `react-native-gesture-handler` for gesture-driven UX
- `InteractionManager.runAfterInteractions()` for deferred post-navigation work
- Hermes engine enabled — verify in `android/app/build.gradle` and Podfile

## Testing

```tsx
// React Native Testing Library
import { render, screen, fireEvent } from '@testing-library/react-native';

it('calls onPress when button is tapped', () => {
  const onPress = jest.fn();
  render(<PrimaryButton title="Submit" onPress={onPress} />);
  fireEvent.press(screen.getByRole('button', { name: 'Submit' }));
  expect(onPress).toHaveBeenCalledTimes(1);
});
```

- `@testing-library/react-native` for all component tests
- Jest with `jest-expo` preset (Expo) or `react-native` preset (bare)
- `msw` (Mock Service Worker) for network mocking — works in RN via `msw/native`
- Maestro for E2E UI tests (YAML-based, runs on real devices/simulators)
- Detox as alternative E2E for complex gesture and animation testing

## Build & Distribution (EAS)

```json
// eas.json
{
  "build": {
    "development": {
      "developmentClient": true,
      "distribution": "internal",
      "env": { "APP_ENV": "development" }
    },
    "production": {
      "autoIncrement": true,
      "env": { "APP_ENV": "production" }
    }
  },
  "submit": {
    "production": {
      "ios": { "appleId": "...", "ascAppId": "..." },
      "android": { "serviceAccountKeyPath": "./service-account.json", "track": "internal" }
    }
  }
}
```

- EAS Build for cloud builds (no local Xcode / Android Studio required for CI)
- EAS Submit for automated App Store / Play Store submissions
- EAS Update (OTA) for JS-only hotfixes — never use it to bypass App Store review for native changes
- Environment variables via `eas secret:create` — never commit `.env` with secrets
- `app.config.ts` (dynamic config) over `app.json` when environment-aware config is needed

## Security
- `expo-secure-store` / iOS Keychain / Android Keystore for tokens and credentials
- Jailbreak / root detection via `expo-device` or `react-native-jailmonkey`
- Certificate pinning for sensitive API communication
- Obfuscate JS bundle with Hermes bytecode — production builds only
- Remove `console.log` in production (Babel plugin `transform-remove-console`)
- Code push (OTA updates) only for bug fixes — never for new features requiring store review
