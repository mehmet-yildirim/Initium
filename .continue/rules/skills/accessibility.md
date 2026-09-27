---
name: accessibility
description: Accessibility for web and native mobile UI — WCAG 2.2 AA, European Accessibility Act and EN 301 549, semantic HTML and ARIA rules, keyboard and focus, contrast, motion, forms and errors, touch targets (24px / 44pt / 48dp), screen readers (VoiceOver, TalkBack, NVDA), SwiftUI/Compose/Flutter/React Native APIs, and automated (axe, Lighthouse, jsx-a11y) versus manual testing. Use when building or reviewing any user interface, component, form, or design system.
alwaysApply: false
---
<!-- Generated from .claude/skills by .initium/scripts/sync-skills.mjs — edit the skill, not this file. -->

# Accessibility

Applies to every UI surface: web, hybrid, and native mobile. E2E wiring for axe checks:
`testing-e2e`. Visual design direction: `frontend-design` / `impeccable`. Platform idioms:
the `mobile-*` and frontend skills.

## Baseline

- Target WCAG 2.2 Level AA for all new work. 4.1.1 Parsing is obsolete in 2.2.
- WCAG 3 is a W3C Working Draft (latest September 2026), years from a Recommendation; WCAG 2 will
  not be deprecated. Do not design to WCAG 3 scoring.
- European Accessibility Act: applies to covered products and services (e-commerce, banking,
  e-books, transport, telecoms, and more) placed on the EU market since 28 June 2025.
  - Presumption of conformity: EN 301 549 v3.2.1 (≈ WCAG 2.1 AA) is still the cited standard.
  - EN 301 549 v4.1.1 (September 2026) adopts WCAG 2.2 AA; not yet cited in the Official Journal.
    Building to WCAG 2.2 AA covers both.
  - Services must publish how they meet the requirements (EAA Annex V), typically as an
    accessibility statement; microenterprises providing services are exempt.
- Accessibility is a requirement in the definition of done, not a later audit.

## Toolchain

| Concern | Tool |
|---|---|
| Lint (JSX) | `eslint-plugin-jsx-a11y` 6.10 (`jsxA11y.flatConfigs.recommended` or `.strict`) |
| Automated rules | axe-core 4.13 (`@axe-core/playwright`, browser extension), Lighthouse 13 |
| Component tests | Testing Library / Vitest browser mode queries by role and label |
| Contrast | Browser DevTools contrast picker, design-tool contrast plugins |
| Screen readers | VoiceOver (macOS, iOS), TalkBack (Android), NVDA (Windows), JAWS where contracted |
| Native audits | Xcode Accessibility Inspector, `XCUIApplication().performAccessibilityAudit()`, Android Accessibility Scanner, Espresso `AccessibilityChecks`, Flutter `meetsGuideline` |

## Semantic structure

- Use native elements first: `<button>`, `<a href>`, `<input>`, `<select>`, `<dialog>`,
  `<details>`, `<table>`. A `<div onClick>` is a defect.
- One `<h1>` per page, no skipped heading levels; landmarks: `<header>`, `<nav>`, `<main>`,
  `<footer>`; label repeated landmarks (`<nav aria-label="Breadcrumb">`).
- Set `<html lang>`, a unique descriptive `<title>` per view, and update both on SPA navigation.
- Images: meaningful `alt`; decorative images `alt=""`; complex charts get a text alternative.
- Provide captions for video and transcripts for audio.

## ARIA rules

1. Don't use ARIA if a native element or attribute does the job.
2. Don't change native semantics (`<h2 role="tab">` is wrong; wrap instead).
3. Every interactive ARIA control must be keyboard operable.
4. Never put `role="presentation"` or `aria-hidden="true"` on focusable elements.
5. Every interactive element needs an accessible name.

- Follow the ARIA Authoring Practices Guide patterns for composite widgets (tabs, combobox,
  menu, tree, grid) — keyboard model included — or use a vetted headless library.
- Announce async updates with a live region present in the DOM before the update
  (`role="status"` polite, `role="alert"` for errors only).

## Keyboard and focus

- Everything operable with a pointer is operable with a keyboard, in a logical order; no
  positive `tabindex`.
- Visible focus indicator on every focusable element (`:focus-visible`), ≥3:1 against adjacent
  colors; never `outline: none` without a replacement.
- 2.4.11 Focus Not Obscured: sticky headers, cookie banners and chat widgets must not hide the
  focused element (`scroll-padding-top`).
- Modals: use `<dialog>` with `showModal()` (focus moves in, background inert, Escape closes);
  return focus to the trigger on close.
- Provide a "Skip to main content" link; move focus to the new view's heading on SPA navigation.
- 2.5.7 Dragging: every drag interaction has a single-pointer alternative (buttons, menus).

## Color, contrast and motion

- Text contrast ≥4.5:1; large text (≥24px, or ≥18.66px bold) ≥3:1; UI components, focus
  indicators and meaningful graphics ≥3:1.
- Never use color alone to convey meaning (add text, icons, or patterns).
- Support 200% zoom and reflow at 320 CSS px wide without horizontal scrolling; respect user
  text-spacing overrides; size text in `rem`.
- Honor `prefers-reduced-motion`: disable parallax, auto-playing and large transitions; nothing
  flashes more than three times per second; auto-moving content > 5 s has pause/stop.
- Support dark mode and forced colors (`forced-colors: active`) without losing boundaries.

## Forms and errors

- Every input has a visible, programmatically associated `<label>`; placeholders are not labels.
- Group related controls with `<fieldset>`/`<legend>`; mark required fields in text and with
  `required`; set `autocomplete` tokens for personal data.
- On error: describe the problem and fix in text, link it with `aria-describedby`, set
  `aria-invalid="true"`, move focus to an error summary or the first invalid field.
- 3.3.7 Redundant Entry: don't ask for the same information twice in a flow.
- 3.3.8 Accessible Authentication: allow paste and password managers; no cognitive puzzles
  without an alternative (passkeys, email links, object-recognition CAPTCHAs are acceptable).
- 3.2.6 Consistent Help: help links/contact appear in the same relative place on every page.
- Session timeouts warn the user and allow extension.

## Touch targets and mobile

- Web: ≥24×24 CSS px per target or equivalent spacing (2.5.8, AA); aim for 44×44.
- iOS: ≥44×44 pt. Android: ≥48×48 dp. Expand hit areas rather than shrinking spacing.
- Support Dynamic Type / font scaling to at least 200% without truncation; support both
  orientations unless essential.
- Native semantics: label every control, mark headings, group related elements, expose state
  (selected, expanded, disabled), and respect reduce-motion settings.

## Structure

- Build accessibility into shared design-system components (button, input, dialog, menu) so
  product code inherits correct semantics; wrap third-party widgets behind your own component and
  fix their gaps there.
- Store accessible names in the same i18n catalog as visible strings.
- Design tokens encode contrast-safe color pairs; lint forbids raw colors in components.

## Security and privacy

- Never expose sensitive data only visually hidden (`sr-only` content is still in the DOM).
- CAPTCHA and bot defenses need an accessible path; do not block assistive technology user agents.
- Don't detect or log whether a user runs assistive technology.

## Observability

- Track axe violation counts per route in CI over time; alert on regressions.
- Log client errors from focus traps and live regions through the frontend logger, not
  `console.log`.
- Record accessibility feedback channel reports as issues with a WCAG criterion label.

## Testing

- Automated checks catch roughly a third to half of issues: lint in the editor, axe in
  component and E2E tests (tags `wcag2a`, `wcag2aa`, `wcag21a`, `wcag21aa`, `wcag22aa`),
  Lighthouse in CI for page-level trends.
- Manual, every feature: keyboard-only pass, 200% zoom and 320px reflow, reduced motion, and one
  screen reader per platform (NVDA + Firefox/Chrome, VoiceOver + Safari, TalkBack + Chrome,
  VoiceOver on iOS).
- Before major releases: audit against WCAG 2.2 AA and include users with disabilities where
  possible.

## References

- `reference/web-patterns.md` — Read when implementing dialogs, forms, error summaries, live
  regions, skip links, focus management, or reduced-motion CSS.
- `reference/native-mobile.md` — Read when building SwiftUI, UIKit, Jetpack Compose, Flutter, or
  React Native UI.
- `reference/testing.md` — Read when configuring eslint-plugin-jsx-a11y, axe, Lighthouse CI, or
  planning screen-reader test passes.

_Versions verified September 2026._
