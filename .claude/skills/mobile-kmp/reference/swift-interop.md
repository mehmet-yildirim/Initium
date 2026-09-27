# Swift interop

Pick exactly one strategy per framework: Objective-C export + SKIE (production default), plain
Objective-C export with hand-written wrappers, or Swift Export (Alpha in Kotlin 2.4).

## SKIE (Objective-C export + Swift-friendly layer)

```kotlin
// shared/build.gradle.kts
plugins {
    alias(libs.plugins.kotlin.multiplatform)
    alias(libs.plugins.skie)   // co.touchlab.skie 0.10.15 supports Kotlin 2.4.20
}
```

```swift
// iosApp — StateFlow is an AsyncSequence, sealed types become exhaustive enums
@MainActor
final class OrderListModel: ObservableObject {
    @Published private(set) var state: OrderListUiState
    private let viewModel: OrderListViewModel

    init(viewModel: OrderListViewModel) {
        self.viewModel = viewModel
        self.state = viewModel.state.value
    }

    func observe() async {
        for await next in viewModel.state {
            state = next
        }
    }
}

// SwiftUI: .task { await model.observe() } — cancelled automatically when the view disappears.
```

- `suspend` functions become Swift `async` with two-way cancellation.
- Keep SKIE's version pinned to the Kotlin version it lists as supported; upgrade both together.

## Without SKIE or Swift Export

`for await` over a Kotlin `Flow` is not available; expose a callback wrapper that the Swift side
cancels explicitly.

```kotlin
// commonMain (or iosMain if only iOS consumes it)
class FlowSubscription internal constructor(private val job: Job) {
    fun cancel() = job.cancel()
}

fun <T> StateFlow<T>.watch(scope: CoroutineScope, onEach: (T) -> Unit): FlowSubscription =
    FlowSubscription(onEach(onEach).launchIn(scope))

// In the shared ViewModel — viewModelScope is not visible from Swift
fun watchState(onEach: (OrderListUiState) -> Unit): FlowSubscription =
    state.watch(viewModelScope, onEach)
```

```swift
private var subscription: FlowSubscription?

func start() {
    subscription = viewModel.watchState { [weak self] next in
        self?.state = next
    }
}

deinit { subscription?.cancel() }
```

## Swift Export (Alpha)

```kotlin
// shared/build.gradle.kts — no binaries.framework {} and no SKIE when using Swift Export
kotlin {
    iosArm64()
    iosSimulatorArm64()

    swiftExport {
        moduleName = "Shared"
        flattenPackage = "com.example.shared"
    }
}
```

- Xcode integration: a Run Script build phase calling
  `./gradlew :shared:embedSwiftExportForXcode`; direct integration only (no CocoaPods/SPM export).
- Generics are erased at the boundary; keep exported APIs concrete.
- Use it for spikes and new, small surfaces; keep shipping apps on Obj-C export + SKIE until the
  feature leaves Alpha.

## Exceptions at the boundary

- Model expected failures as values (`Outcome`, sealed results) — Swift sees them as enums.
- An uncaught Kotlin exception crossing into Swift terminates the app. If a function must throw,
  annotate it: `@Throws(OrderException::class, CancellationException::class)` so Swift sees
  `throws` and receives an `NSError`.
- Never export types that expose vendor SDK classes; map to shared domain types first.
