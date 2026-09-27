# Compose Multiplatform

## Module setup (CMP 1.12)

The Compose Gradle plugin's dependency aliases (`compose.ui`, `compose.material3`, …) are
deprecated since 1.10 — declare direct coordinates in the version catalog.

```toml
[libraries]
compose-runtime = { module = "org.jetbrains.compose.runtime:runtime", version.ref = "compose-multiplatform" }
compose-foundation = { module = "org.jetbrains.compose.foundation:foundation", version.ref = "compose-multiplatform" }
compose-ui = { module = "org.jetbrains.compose.ui:ui", version.ref = "compose-multiplatform" }
compose-components-resources = { module = "org.jetbrains.compose.components:components-resources", version.ref = "compose-multiplatform" }
compose-ui-tooling-preview = { module = "org.jetbrains.compose.ui:ui-tooling-preview", version.ref = "compose-multiplatform" }
# Material3 is versioned separately: 1.9.0 is stable (Jetpack Material3 1.4, no Expressive);
# the 1.12.0-alpha line matches CMP 1.12 and carries Expressive APIs.
compose-material3 = { module = "org.jetbrains.compose.material3:material3", version.ref = "compose-material3" }
jetbrains-lifecycle-viewmodel-navigation3 = { module = "org.jetbrains.androidx.lifecycle:lifecycle-viewmodel-navigation3", version.ref = "jetbrains-lifecycle" }
```

```kotlin
// composeApp/build.gradle.kts
plugins {
    alias(libs.plugins.kotlin.multiplatform)
    alias(libs.plugins.android.kotlin.multiplatform.library)
    alias(libs.plugins.compose.multiplatform)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

kotlin {
    android {
        namespace = "com.example.composeapp"
        compileSdk = 37
        minSdk = 26
        androidResources { enable = true }   // required for composeResources on Android
    }
    iosArm64()
    iosSimulatorArm64()
    jvm("desktop")

    sourceSets {
        commonMain.dependencies {
            implementation(libs.compose.runtime)
            implementation(libs.compose.foundation)
            implementation(libs.compose.ui)
            implementation(libs.compose.material3)
            implementation(libs.compose.components.resources)
            implementation(libs.jetbrains.lifecycle.viewmodel.compose)
            implementation(libs.jetbrains.navigation3.ui)
            implementation(libs.jetbrains.lifecycle.viewmodel.navigation3)
        }
        val desktopMain by getting {
            dependencies { implementation(libs.kotlinx.coroutines.swing) }  // Dispatchers.Main on desktop
        }
    }
}
```

## Navigation 3

Non-JVM targets have no reflection, so every `NavKey` must be registered for polymorphic
serialization. A missing registration crashes on iOS at state save time.

```kotlin
@Serializable data object OrderList : NavKey
@Serializable data class OrderDetail(val orderId: String) : NavKey

private val navConfig = SavedStateConfiguration {
    serializersModule = SerializersModule {
        polymorphic(NavKey::class) {
            subclass(OrderList::class, OrderList.serializer())
            subclass(OrderDetail::class, OrderDetail.serializer())
        }
    }
}

@Composable
fun AppNavigation() {
    val backStack = rememberNavBackStack(navConfig, OrderList)

    NavDisplay(
        backStack = backStack,
        onBack = { backStack.removeLastOrNull() },
        entryDecorators = listOf(
            rememberSaveableStateHolderNavEntryDecorator(),
            rememberViewModelStoreNavEntryDecorator(),
        ),
        entryProvider = entryProvider {
            entry<OrderList> {
                OrderListScreen(onOrderClick = { id -> backStack.add(OrderDetail(id)) })
            }
            entry<OrderDetail> { key ->
                OrderDetailScreen(orderId = key.orderId)
            }
        },
    )
}
```

- Keep route keys small (IDs, not objects); load data in the entry's ViewModel.
- Validate deep-link arguments before pushing keys onto the back stack.
- Adaptive list-detail: `org.jetbrains.compose.material3.adaptive:adaptive-navigation3`
  (`ListDetailSceneStrategy`, experimental API).

## Resources

- Put strings, images, and fonts in `src/commonMain/composeResources/`; access through the
  generated `Res` class (`stringResource(Res.string.order_title)`). No `R.*` in common code.
- Qualifiers (`values-de/`, `drawable-dark/`) work as on Android; test RTL and font scaling.

## Platform views and back handling

- Wrap native widgets behind an interface or `expect`/`actual` composable using `AndroidView`
  (androidMain) and `UIKitView`/`UIKitViewController` (iosMain).
- `NavDisplay` handles Android predictive back and iOS back-swipe; do not intercept system back
  unless a screen has unsaved input.

## iOS entry point

```kotlin
// iosMain
fun MainViewController(): UIViewController = ComposeUIViewController { App() }
```

Host it from SwiftUI via `UIViewControllerRepresentable`; start the DI graph before creating it.
