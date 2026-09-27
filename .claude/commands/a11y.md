Audit and fix accessibility against WCAG 2.2 level AA for web or mobile UI.

Scope from `$ARGUMENTS`: a component, page, route, screen, or `diff` (changed UI files only).
Default: `diff`.

---

## Step 1: Automated checks

Run the tools that match the stack and collect every violation:

- Web: axe-core (`@axe-core/playwright`, `jest-axe`, `vitest-axe`), Lighthouse accessibility,
  `eslint-plugin-jsx-a11y` / `eslint-plugin-vuejs-accessibility` / `@angular-eslint` template
  accessibility rules.
- iOS: Xcode Accessibility Inspector, `performAccessibilityAudit()` in XCUITest.
- Android: Accessibility Scanner, Compose semantics tests, Espresso `AccessibilityChecks`.
- Flutter / React Native: `flutter test` with semantics guidelines, RN accessibility props lint.

Automated tools catch only part of the problems; always continue with the manual review.

## Step 2: Manual review checklist

| Area | Check |
|------|-------|
| Semantics | Native elements first (`button`, `a`, `label`, headings in order); ARIA only when no native element exists, and never contradicting native semantics |
| Names | Every interactive element and image has an accessible name; decorative images are hidden from assistive tech |
| Keyboard | Everything operable by keyboard; logical focus order; visible focus indicator not obscured by sticky headers; no keyboard traps |
| Forms | Labels bound to inputs; errors announced and described in text, not color alone; required fields indicated |
| Contrast | Text ≥ 4.5:1 (large text ≥ 3:1); UI components and focus indicators ≥ 3:1 |
| Targets | Pointer targets at least 24×24 CSS px (mobile platform guidance: 44 pt iOS / 48 dp Android) |
| Motion | Respect reduced-motion preferences; nothing flashes more than 3 times per second |
| Dynamic content | Live regions for async updates; dialogs trap and restore focus; route changes move focus |
| Zoom and reflow | Usable at 200% text size and 320 px width without horizontal scrolling |
| Mobile | Screen reader labels, traits/roles, and grouping verified with VoiceOver and TalkBack; supports dynamic type / font scaling |
| Authentication | No cognitive tests without an alternative; allow paste and password managers |

## Step 3: Fix

- Branch: `fix/a11y-<scope>`.
- Fix violations in priority order: blockers for keyboard / screen-reader users first, then
  contrast and naming, then enhancements.
- Prefer fixing shared components once over patching each usage.
- Add regression tests: axe assertions in component or E2E tests, platform accessibility audits
  in UI tests.

## Step 4: Report

For each issue: WCAG success criterion, severity (blocker / serious / moderate / minor),
location, fix applied or recommended, and whether a regression test was added. State clearly
which checks were automated and which were verified manually.

---

Accessibility scope: $ARGUMENTS
