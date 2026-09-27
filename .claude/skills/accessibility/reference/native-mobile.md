# Native and cross-platform mobile accessibility APIs

Common checklist: every control has a label, headings are marked, related elements are grouped
into one focus stop, state is exposed, targets meet 44 pt (iOS) / 48 dp (Android), text scales,
and animations respect the reduce-motion setting.

## SwiftUI

```swift
struct OrderRow: View {
    let order: Order
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 20

    var body: some View {
        HStack {
            Image(systemName: "shippingbox")
                .resizable()
                .frame(width: iconSize, height: iconSize)
                .accessibilityHidden(true)
            VStack(alignment: .leading) {
                Text(order.title).font(.headline)
                Text(order.status).font(.subheadline)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens order details")
        .animation(reduceMotion ? nil : .default, value: order.status)
    }
}

Button(action: close) { Image(systemName: "xmark") }
    .accessibilityLabel("Close")
    .frame(minWidth: 44, minHeight: 44)

Text("Orders").font(.title).accessibilityAddTraits(.isHeader)
```

- Use text styles (`.body`, `.headline`) so Dynamic Type works; test at the largest
  accessibility sizes and switch stacks to vertical with `dynamicTypeSize.isAccessibilitySize`.
- Custom actions: `.accessibilityAction(named: "Archive") { archive() }` instead of swipe-only.
- UIKit: `isAccessibilityElement`, `accessibilityLabel`, `accessibilityTraits`,
  `adjustsFontForContentSizeCategory = true`, `UIAccessibility.post(notification:argument:)`.
- UI tests: `try XCUIApplication().performAccessibilityAudit()` (Xcode 15+).

## Jetpack Compose

```kotlin
@Composable
fun OrderRow(order: Order, onOpen: () -> Unit) {
    Row(
        modifier = Modifier
            // clickable merges descendants into one focus stop
            .clickable(onClickLabel = "Open order details", onClick = onOpen)
            .padding(16.dp),
    ) {
        Icon(Icons.Default.ShoppingCart, contentDescription = null)
        Column {
            Text(order.title, style = MaterialTheme.typography.titleMedium)
            Text(order.status)
        }
    }
}

IconButton(onClick = onClose) {
    Icon(Icons.Default.Close, contentDescription = stringResource(R.string.close))
}

Text(
    text = stringResource(R.string.orders_title),
    modifier = Modifier.semantics { heading() },
)
```

- Material 3 components enforce 48 dp via `minimumInteractiveComponentSize()`; apply it to custom
  clickable elements.
- Toggles: `Modifier.toggleable(value, role = Role.Switch, onValueChange = ...)` exposes state.
- Custom actions: `Modifier.semantics { customActions = listOf(CustomAccessibilityAction("Archive") { archive(); true }) }`.
- Size text in `sp`; read animation scale / reduce-motion settings before long animations.
- Tests: `composeTestRule.onNodeWithContentDescription("Close").assertHasClickAction()`; Espresso
  `AccessibilityChecks.enable()` for View-based screens; Accessibility Scanner for manual audits.

## Flutter

```dart
Semantics(
  button: true,
  label: 'Close',
  child: IconButton(icon: const Icon(Icons.close), onPressed: onClose, tooltip: 'Close'),
);

MergeSemantics(
  child: ListTile(title: Text(order.title), subtitle: Text(order.status), onTap: onOpen),
);

Semantics(header: true, child: Text('Orders', style: Theme.of(context).textTheme.headlineSmall));

final reduceMotion = MediaQuery.disableAnimationsOf(context);
```

```dart
testWidgets('meets accessibility guidelines', (tester) async {
  final handle = tester.ensureSemantics();
  await tester.pumpWidget(const MyApp());
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
  handle.dispose();
});
```

- Hide decorative widgets with `ExcludeSemantics`; respect `MediaQuery.textScalerOf(context)`.

## React Native

```tsx
<Pressable
  onPress={onClose}
  accessibilityRole="button"
  accessibilityLabel="Close"
  hitSlop={12}
  style={{ minWidth: 48, minHeight: 48 }}
>
  <CloseIcon />
</Pressable>

<Text accessibilityRole="header">Orders</Text>

<Switch
  value={enabled}
  onValueChange={setEnabled}
  accessibilityLabel="Email notifications"
/>
```

```typescript
const reduceMotion = await AccessibilityInfo.isReduceMotionEnabled();
AccessibilityInfo.announceForAccessibility('Changes saved');
```

- Group children with `accessible` on the container; expose state with
  `accessibilityState={{ selected, disabled, expanded }}`.
- Test on real devices with VoiceOver and TalkBack; simulators miss gesture issues.
