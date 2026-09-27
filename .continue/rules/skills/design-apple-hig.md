---
name: design-apple-hig
description: Apple Human Interface Guidelines for iOS, iPadOS, macOS, watchOS, tvOS, and visionOS UI — Liquid Glass, resizable layouts and safe areas, navigation, typography and Dynamic Type, SF Symbols, touch targets, color, motion, and accessibility. Use when designing, building, or reviewing screens for Apple platforms (SwiftUI, UIKit, or cross-platform apps shipping to iOS).
globs:
  - "**/*View.swift"
  - "**/*.xcassets/**"
alwaysApply: false
---
<!-- Generated from .claude/skills by .initium/scripts/sync-skills.mjs — edit the skill, not this file. -->

# Apple Human Interface Guidelines — Working Summary

This is a condensed, paraphrased checklist. Apple's HIG is the authority and is not licensed
for redistribution, so do not paste its text into the repo — link to it instead.

- Canonical source: <https://developer.apple.com/design/human-interface-guidelines/>
- Markdown mirror for agents (unofficial, lookup only): replace `developer.apple.com` with
  `sosumi.ai`, e.g. `https://sosumi.ai/design/human-interface-guidelines/layout`. If the
  `sosumi` MCP server is enabled, use `searchAppleDocumentation` / `fetchAppleDocumentation`.
- When a rule below matters for a decision, open the linked page and confirm it — the HIG is
  revised every year around WWDC.

Pair this skill with `mobile-ios` (code standards) and, for web-style surfaces inside the app,
`frontend-design`.

## Principles

- **Hierarchy:** controls and navigation float above content; content is the focus.
- **Harmony:** match the platform's shapes, motion, and typography so the app feels native.
- **Consistency:** use system components before custom ones; a custom control must behave
  like the system control it resembles (gestures, states, accessibility).
- Design for every device class you ship — iPhone portrait/landscape, iPad split view and
  Stage Manager, Mac windows — not just one screenshot size.

## Liquid Glass (iOS / iPadOS / macOS / watchOS / tvOS 26+)

[Materials](https://developer.apple.com/design/human-interface-guidelines/materials)

- Liquid Glass is the material of the **navigation and control layer** (tab bars, toolbars,
  sidebars, sheets, floating buttons). Never apply it to content — lists, cards, body text.
- System components adopt it automatically when built with the current SDK; prefer them over
  re-creating glass by hand.
- Use it sparingly on custom controls (`glassEffect(_:in:)`, `GlassEffectContainer` in
  SwiftUI; `UIGlassEffect` in UIKit). Stacked glass on glass loses legibility.
- The *regular* variant adapts for legibility and suits most controls; the *clear* variant is
  for controls over rich media and needs a dimming layer when the content behind is bright.
- Remove custom backgrounds and borders from bars so the system material and scroll-edge
  effects can do their job.
- iOS 27 lets users set Liquid Glass on a continuous slider from more transparent to more
  tinted (Settings > Appearance). Design for the whole range: check both ends of the slider.
- Verify with Reduce Transparency and Increase Contrast turned on.

## Layout and Safe Areas

[Layout](https://developer.apple.com/design/human-interface-guidelines/layout)

- Keep interactive content inside the safe area; let backgrounds and media extend edge to edge.
- Respect layout margins and readable content width on iPad and Mac; do not stretch text
  columns across a 13" display.
- Support every size class the app runs in; test portrait, landscape, split view, and the
  largest Dynamic Type size.
- With the iOS 27 SDK, iPhone apps are resizable (iPhone Mirroring, iPhone apps on iPad) and
  `UIRequiresFullScreen` no longer opts out. Lay out by available size and size class, never by
  device model, idiom, or orientation.
- Concentric corners: a nested element's corner radius follows its container's curve.
- Group related items with spacing and alignment before reaching for dividers or boxes.

## Navigation

- [Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars): for
  top-level destinations, not actions. Always visible, always labeled, ideally five or fewer
  tabs; avoid a "More" overflow tab. On iPad a tab bar can adapt into a sidebar.
- [Navigation bars](https://developer.apple.com/design/human-interface-guidelines/navigation-bars)
  and stacks for hierarchy; the back button shows the previous title. Large titles on top-level
  screens, standard titles deeper.
- [Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars) for
  iPad/Mac apps with many sections;
  [toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars) for
  screen-level actions.
- [Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets) for focused,
  dismissible tasks; full-screen covers only for immersive or multi-step flows.
- Never break the system back gesture (edge swipe) or the Home indicator area.

## Typography and Dynamic Type

[Typography](https://developer.apple.com/design/human-interface-guidelines/typography)

- Use the system text styles (`.largeTitle` … `.caption2`) so text scales with Dynamic Type.
  iOS body text defaults to 17 pt; avoid text smaller than 11 pt.
- Layouts must survive at least 200% text enlargement, including the accessibility sizes —
  wrap, stack horizontally-arranged elements vertically, never truncate essential text.
- San Francisco (SF Pro, SF Compact, SF Mono, New York) is the system family. A custom brand
  font must still support Dynamic Type (`relativeTo:` / `UIFontMetrics`).
- Build hierarchy with weight and size from the text styles, not with many custom sizes.

## SF Symbols and Icons

[SF Symbols](https://developer.apple.com/design/human-interface-guidelines/sf-symbols) ·
[App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons)

- Prefer SF Symbols for interface icons; they align with text, scale with Dynamic Type, and
  support weights, rendering modes, and animations.
- Tab bars prefer filled symbol variants; toolbars and lists typically use outlined ones.
- Custom icons match SF Symbols' weight and optical size; export as custom symbols.
- Never use emoji as interface icons.
- App icons use the layered format that supports light, dark, tinted, and clear appearances.

## Touch Targets and Controls

[Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) ·
[Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons)

- Hit targets default to 44×44 pt; never below 28×28 pt. Leave space between adjacent targets.
  Cross-platform target sizes and the WCAG mapping live in the `accessibility` skill.
- One primary action per screen; destructive actions use the destructive role and confirm when
  irreversible.
- Use system controls (Toggle, Picker, Menu, DatePicker) before custom widgets.
- Every gesture has a visible alternative; do not rely on long-press or hidden swipes alone.

## Color and Dark Mode

[Color](https://developer.apple.com/design/human-interface-guidelines/color) ·
[Dark Mode](https://developer.apple.com/design/human-interface-guidelines/dark-mode)

- Use semantic system colors (`label`, `secondaryLabel`, `systemBackground`, `tint`) so the app
  adapts to Dark Mode, Increase Contrast, and vibrancy automatically.
- Define custom colors as asset-catalog color sets with light, dark, and high-contrast variants.
- One accent (tint) color, used consistently for interactive elements.
- Contrast at least 4.5:1 for text up to 17 pt, 3:1 for larger or bold text.
- Never communicate state by color alone.

## Motion and Feedback

[Motion](https://developer.apple.com/design/human-interface-guidelines/motion) ·
[Playing haptics](https://developer.apple.com/design/human-interface-guidelines/playing-haptics)

- Motion explains a change (where something came from, where it went); it is never decoration.
- Prefer system transitions and spring animations; keep interactions interruptible.
- With Reduce Motion on, replace slides and zooms with fades and shorten springs.
- Haptics confirm meaningful events; do not fire them on every tap.

## Accessibility (non-negotiable)

- Every control has a VoiceOver label, trait, and value; group related elements.
- Support Dynamic Type, Bold Text, Reduce Motion, Reduce Transparency, Increase Contrast,
  Full Keyboard Access, and Switch Control.
- No UI that dismisses itself on a timer without a way to extend it.
- Run the Accessibility Inspector and `performAccessibilityAudit()` in UI tests.

## Review Checklist

- [ ] System components and Liquid Glass used in the control layer only
- [ ] Safe areas respected; tested on the smallest and largest supported devices and iPad
- [ ] Tab bar ≤ 5 labeled destinations; no actions in the tab bar
- [ ] Text uses system text styles; usable at the largest accessibility size
- [ ] SF Symbols (or matching custom symbols); no emoji icons
- [ ] Targets ≥ 44×44 pt
- [ ] Semantic colors; light, dark, and increased-contrast checked
- [ ] Reduce Motion and Reduce Transparency respected
- [ ] VoiceOver walkthrough of the main flow completed
- [ ] Liquid Glass legible at both ends of the iOS 27 transparency slider
- [ ] Layout survives arbitrary window sizes (resizable iPhone app, iPad, Mac)

_Versions verified September 2026._
