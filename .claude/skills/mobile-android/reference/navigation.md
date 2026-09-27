# Navigation 3 and type-safe Navigation 2

Navigation 3 (`androidx.navigation3:navigation3-runtime` / `navigation3-ui`, 1.2.x stable) treats
the back stack as a list you own. Navigation 2.10 remains supported for existing apps.

## Dependencies

```toml
[versions]
navigation3 = "1.2.0"
lifecycle = "2.11.0"
material3Adaptive = "1.3.0"

[libraries]
androidx-navigation3-runtime = { module = "androidx.navigation3:navigation3-runtime", version.ref = "navigation3" }
androidx-navigation3-ui = { module = "androidx.navigation3:navigation3-ui", version.ref = "navigation3" }
androidx-lifecycle-viewmodel-navigation3 = { module = "androidx.lifecycle:lifecycle-viewmodel-navigation3", version.ref = "lifecycle" }
androidx-compose-material3-adaptive-navigation3 = { module = "androidx.compose.material3.adaptive:adaptive-navigation3", version.ref = "material3Adaptive" }
```

Keys must be `@Serializable` (apply `org.jetbrains.kotlin.plugin.serialization`) so the back stack
survives process death.

## Keys and NavDisplay

```kotlin
@Serializable data object Home : NavKey
@Serializable data class UserDetail(val userId: String) : NavKey

@Composable
fun AppNavDisplay(modifier: Modifier = Modifier) {
    val backStack = rememberNavBackStack(Home)
    NavDisplay(
        backStack = backStack,
        modifier = modifier,
        onBack = { backStack.removeLastOrNull() },
        entryDecorators = listOf(
            rememberSaveableStateHolderNavEntryDecorator(),
            rememberViewModelStoreNavEntryDecorator(),
        ),
        entryProvider = entryProvider {
            entry<Home> {
                UserListScreen(onUserClick = { id -> backStack.add(UserDetail(id)) })
            }
            entry<UserDetail> { key ->
                UserDetailScreen(userId = key.userId)
            }
        },
    )
}
```

- `rememberViewModelStoreNavEntryDecorator()` scopes ViewModels to the entry; pass the key into
  the ViewModel (assisted injection or `SavedStateHandle`) instead of reading global state.
- Feature modules contribute entries as `EntryProviderScope<NavKey>.featureEntries()` extension
  functions; the app module calls them inside `entryProvider { }` (or collects them via a Hilt
  `@IntoSet` multibinding).
- Navigation actions are lambdas passed down from the `NavDisplay` owner. Screens never hold the
  back stack.
- Deep links: Navigation 3 1.2 adds `DeepLinkMatcher`/`UriDeepLinkMatcher` in
  `androidx.navigation3.runtime.deeplink`. Parse and validate the URI, map it to a key, and build a
  synthetic back stack (`withBackStack`) so Up/Back behave.

## Adaptive list-detail

`adaptive-navigation3` provides `ListDetailSceneStrategy` (still
`@ExperimentalMaterial3AdaptiveApi`):

```kotlin
@OptIn(ExperimentalMaterial3AdaptiveApi::class)
@Composable
fun InboxNavDisplay() {
    val backStack = rememberNavBackStack(ConversationList)
    val listDetail = rememberListDetailSceneStrategy<NavKey>()
    NavDisplay(
        backStack = backStack,
        onBack = { backStack.removeLastOrNull() },
        sceneStrategies = listOf(listDetail),
        entryProvider = entryProvider {
            entry<ConversationList>(
                metadata = ListDetailSceneStrategy.listPane(
                    detailPlaceholder = { SelectConversationPlaceholder() },
                ),
            ) {
                ConversationListScreen(onOpen = { id -> backStack.add(ConversationDetail(id)) })
            }
            entry<ConversationDetail>(metadata = ListDetailSceneStrategy.detailPane()) { key ->
                ConversationDetailScreen(conversationId = key.id)
            }
        },
    )
}
```

## Navigation 2 fallback (existing apps)

```kotlin
@Serializable data object HomeRoute
@Serializable data class UserDetailRoute(val userId: String)

@Composable
fun AppNavHost(navController: NavHostController = rememberNavController()) {
    NavHost(navController, startDestination = HomeRoute) {
        composable<HomeRoute> {
            UserListScreen(onUserClick = { id -> navController.navigate(UserDetailRoute(id)) })
        }
        composable<UserDetailRoute> { entry ->
            val route: UserDetailRoute = entry.toRoute()
            UserDetailScreen(userId = route.userId)
        }
    }
}
```

- In ViewModels read arguments with `savedStateHandle.toRoute<UserDetailRoute>()`.
- Migrate screen by screen: keep screens free of `NavController` so the switch to `NavDisplay`
  only touches the navigation host.
