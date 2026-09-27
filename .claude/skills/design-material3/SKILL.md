---
name: design-material3
description: Material Design 3 and M3 Expressive guidelines for Android (and Material-based web or Flutter) UI — color roles and dynamic color, type scale, shape, spring motion, touch targets, adaptive layouts and breakpoints, navigation components, edge-to-edge, predictive back, and accessibility. Use when designing, building, or reviewing Android screens or any UI that follows Material Design.
paths:
  - "**/*.kt"
  - "**/res/values/**"
  - "**/res/layout/**"
  - "**/AndroidManifest.xml"
  - "**/android/**"
---

# Material Design 3 — Working Summary

Condensed from Material Design 3 guidelines by Google (<https://m3.material.io>), licensed under
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/); adapted and shortened for agents.
Android platform behavior from <https://developer.android.com> (CC BY 4.0). "Material Design"
is a trademark of Google LLC.

- Canonical source: <https://m3.material.io> — confirm specifics there before shipping; M3
  Expressive (May 2025) changed motion, shape, and typography tokens.
- Compose APIs: <https://developer.android.com/develop/ui/compose/designsystems/material3>

Pair this skill with `mobile-android` (code standards), `mobile-flutter`, or `frontend-design`
for Material-based web.

## Principles

- Use the Material components and theme tokens; customize through the theme
  (`MaterialTheme` / `MaterialExpressiveTheme`), never by hard-coding values in screens.
- Expressive does not mean decorated: emphasis (bigger type, bolder shape, livelier motion) is
  reserved for the one or two moments that matter on a screen.
- Adaptive by default: every screen works from a compact phone to a desktop window.

## Color

[Color roles](https://m3.material.io/styles/color/roles) ·
[Dynamic color](https://m3.material.io/styles/color/dynamic/choosing-a-source)

- Use color **roles** (`primary`, `onPrimary`, `primaryContainer`, `surface`,
  `surfaceContainer*`, `outline`, `error` …), not raw hex values, in UI code.
- Each `onX` role is the content color for `X`; pairing roles guarantees contrast in light and
  dark schemes.
- Support dynamic color (wallpaper-based, Android 12+) with a brand scheme as the fallback;
  decide deliberately if brand color must override it.
- Surfaces are distinguished by tonal `surfaceContainer` levels, not by shadows.
- Text contrast at least 4.5:1 (3:1 for large text); never convey state by color alone.

## Typography

[Type scale tokens](https://m3.material.io/styles/typography/type-scale-tokens)

- Five roles × three sizes: display, headline, title, body, label (Large/Medium/Small), plus
  emphasized variants in M3 Expressive.
- Use `MaterialTheme.typography.*` styles; font sizes in `sp` so they follow the user's font
  scale.
- Brand and plain typeface tokens are separate: a display/brand face for headlines, a highly
  legible face for body and labels. Roboto / Roboto Flex is the default, not a requirement.
- Test at 200% font scale; nothing essential truncates.

## Shape

[Shape](https://m3.material.io/styles/shape/overview)

- Use the shape scale (extra-small → extra-large, full) from the theme; one scale per app.
- Expressive adds a library of abstract shapes and shape morphing for moments of emphasis
  (loading, selection) — use them sparingly.
- Nested containers keep corners concentric: inner radius = outer radius − padding.

## Motion

[Motion](https://m3.material.io/styles/motion/overview/how-it-works)

- M3 Expressive motion is spring-based: spatial springs (position, size) and effects springs
  (color, opacity), each at fast, default, or slow speed. Use the motion scheme tokens instead
  of hand-tuned durations and easing curves.
- Standard scheme for utilitarian apps; expressive scheme where brand personality matters.
- Motion shows relationships (container transform, shared axis, fade through); it is never
  decoration. Respect the system "Remove animations" setting.

## Touch Targets and Components

[Accessibility — structure](https://m3.material.io/foundations/designing/structure) ·
[Components](https://m3.material.io/components)

- Touch targets at least 48×48 dp (a 24 dp icon sits in a 48 dp target); 8 dp between targets.
- One primary action per screen: a FAB or a filled button, not both competing.
- Button hierarchy: filled → tonal → outlined → text. Match the action's importance.
- Use snackbars for brief feedback, dialogs only for decisions that block progress.
- Top app bars scroll behavior (`enterAlways`, `exitUntilCollapsed`) matches content type.

## Adaptive Layout

[Breakpoints](https://m3.material.io/foundations/layout/breakpoints/overview) ·
[Window size classes](https://developer.android.com/develop/adaptive-apps/guides/use-window-size-classes)

| Width breakpoint | Range | Navigation | Panes |
|---|---|---|---|
| Compact | < 600 dp | Navigation bar | 1 |
| Medium | 600–839 dp | Navigation rail | 1 (2 optional) |
| Expanded | 840–1199 dp | Navigation rail / drawer | 2 |
| Large | 1200–1599 dp | Navigation rail / drawer | 2 |
| Extra-large | ≥ 1600 dp | Navigation rail / drawer | 1–3 |

- Height classes: compact < 480 dp, medium 480–899 dp, expanded ≥ 900 dp.
- Use `NavigationSuiteScaffold`, `ListDetailPaneScaffold`, and `SupportingPaneScaffold` with
  `currentWindowAdaptiveInfo()` instead of hand-rolled breakpoint logic.
- Adapt by showing/hiding, levitating (sheets become side panels), or reflowing content — never
  by stretching a phone layout.
- Support foldables (hinge-aware), keyboard/mouse input, and multi-window.

## Android Platform Behavior

- **Edge-to-edge** is enforced for apps targeting API 35+, and the opt-out is gone when
  targeting API 36. Call `enableEdgeToEdge()` and handle `WindowInsets` (system bars, IME,
  display cutout) on every screen.
- **Predictive back** animations are on by default when targeting API 36; use
  `BackHandler` / `PredictiveBackHandler` / `OnBackPressedCallback`, never `onBackPressed()`.
- Themed app icons (monochrome layer) and splash screen API for launch.

## Accessibility (non-negotiable)

- Every interactive element has a `contentDescription` or text label; merge semantics for
  compound items; headings marked with `semantics { heading() }`.
- Focus order is logical with a keyboard and D-pad; TalkBack walkthrough of the main flow.
- Test with font scale 200%, display size largest, dark theme, and high-contrast text.
- Run Accessibility Scanner and Compose UI tests with accessibility checks enabled.

## Review Checklist

- [ ] Colors from roles; dynamic color supported or its absence decided
- [ ] Typography from the type scale in `sp`; works at 200% font scale
- [ ] One shape scale; concentric corners
- [ ] Motion scheme tokens; animations respect system settings
- [ ] Targets ≥ 48×48 dp
- [ ] Layout adapts across compact → expanded (and large if tablets/desktop are supported)
- [ ] Edge-to-edge insets handled; predictive back works
- [ ] TalkBack walkthrough completed
