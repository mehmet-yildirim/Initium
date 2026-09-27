---
name: design-tokens
description: Design system and design token standards — primitive/semantic/component token layers, DESIGN.md (Google DESIGN.md spec) as the agent-readable source of truth, mapping tokens to CSS custom properties, Tailwind, SwiftUI, and Compose, and keeping components consistent. Use when creating or changing colors, typography, spacing, radius, elevation, or motion values, building shared UI components, or writing or updating DESIGN.md.
globs:
  - "**/tokens/**"
  - "**/*.tokens.json"
  - "**/DESIGN.md"
alwaysApply: false
---
<!-- Generated from .claude/skills by .initium/scripts/sync-skills.mjs — edit the skill, not this file. -->

# Design Tokens and Design System

A design system is the set of decisions that keeps every screen looking like the same product.
Tokens are those decisions in machine-readable form. Agents drift toward generic defaults when
the decisions are not written down — so write them down once, in `DESIGN.md`, and reference
tokens everywhere else.

## Source of Truth: `DESIGN.md`

- Lives at the project root. Format: [DESIGN.md spec](https://github.com/google-labs-code/design.md)
  (Google Labs, Apache-2.0) — YAML frontmatter with tokens, then prose sections in this order:
  Overview, Colors, Typography, Layout, Elevation & Depth, Shapes, Components, Do's and Don'ts.
- **Tokens are normative; prose explains how to apply them.** Omit sections that do not apply
  instead of inventing rules.
- `PRODUCT.md` (optional, root) holds the non-visual context: audience, jobs to be done, voice,
  brand personality, and anti-references ("must not look like …").
- The `impeccable` skill reads and writes the same files; `/design-system` creates or refreshes
  them. Never silently overwrite an existing `DESIGN.md` — show the diff and ask.

```yaml
---
name: Acme Console
description: Operations console for warehouse leads
colors:
  ink: "#1d2126"
  paper: "#f6f5f1"
  accent: "#2f5d50"
  danger: "#a8321f"
typography:
  display: { fontFamily: "Söhne, system-ui, sans-serif", fontSize: "2rem", fontWeight: 600, lineHeight: 1.15 }
  body:    { fontFamily: "Söhne, system-ui, sans-serif", fontSize: "1rem", fontWeight: 400, lineHeight: 1.5 }
rounded: { sm: "4px", md: "6px" }
spacing: { xs: "4px", sm: "8px", md: "16px", lg: "24px", xl: "40px" }
components:
  button-primary: { backgroundColor: "{colors.accent}", textColor: "{colors.paper}", rounded: "{rounded.sm}", padding: "10px 16px" }
---
```

## Token Layers

| Layer | Example | Rule |
|---|---|---|
| Primitive | `green-700: #2f5d50`, `space-4: 16px` | Raw palette and scales. Never used directly in components. |
| Semantic | `color-accent`, `color-text-muted`, `space-inset-md` | Named by purpose. Components use these. Themes (dark, high contrast, brand) swap semantic → primitive mappings. |
| Component | `button-primary-bg` | Only when a component needs to diverge from the semantic default. Keep few. |

- Components reference semantic tokens only; a hex value or pixel literal in a component is a
  defect (exceptions: `0`, `1px` hairlines, `100%`).
- Name tokens by role, not appearance: `color-danger`, not `color-red`.
- For tool interchange use the W3C [Design Tokens Format](https://www.designtokens.org/)
  (`*.tokens.json`, `$value` / `$type`) and generate platform outputs (e.g. Style Dictionary)
  instead of maintaining parallel hand-written files.

## Scales (decide once, then only use the scale)

- **Spacing:** a 4 px base (4, 8, 12, 16, 24, 32, 48, 64 …). Vary spacing deliberately: tight
  within a group, generous between groups. Uniform spacing everywhere flattens hierarchy.
- **Type:** 5–7 sizes from a ratio (1.125–1.333) with explicit line heights; body 16 px on the
  web, line length 45–80 characters. Web form controls (`input`, `select`, `textarea`) use a
  computed font size of at least 16 px so iOS Safari does not auto-zoom on focus. This is a
  mobile-web rule; native apps follow platform text styles (`sp` / Dynamic Type) instead.
- **Color:** 1 accent, 1 neutral ramp (tinted toward the brand hue, not pure gray), and status
  colors (success, warning, danger, info). Pure `#000` / `#fff` are rarely right — use tinted
  near-black and near-white. Verify contrast for every text/background pair in every theme.
- **Radius:** one family — sharp, soft, or pill — applied consistently; nested radius =
  outer radius − padding.
- **Elevation:** few levels. Prefer tonal surfaces or a hairline border over heavy shadows; when
  shadows are used, layer two soft ones and tint them toward the background.
- **Motion:** 2–3 durations (e.g. 120 / 200 / 320 ms) and 1–2 easing curves or spring presets;
  animate `transform` and `opacity` only; honor reduced-motion settings.

## Platform Mapping

| Platform | Where tokens live |
|---|---|
| CSS | `:root { --color-accent: … }` with `[data-theme="dark"]` / `prefers-color-scheme` overrides |
| Tailwind v4 | `@theme { --color-accent: …; --spacing: 4px; }` in the main CSS file; remove unused default palette |
| Tailwind v3 | `theme.extend` in `tailwind.config.*`; do not mix arbitrary values (`bg-[#123456]`) into components |
| SwiftUI | Asset-catalog color sets (light/dark/high-contrast) + a `Theme` namespace for spacing and fonts via `relativeTo:` text styles — see `design-apple-hig` |
| Compose | `MaterialTheme(colorScheme, typography, shapes)` or a custom `CompositionLocal` theme — see `design-material3` |
| Flutter | `ThemeData` + `ThemeExtension` for custom tokens |

## Component Rules

- Build from the tokens; every component documents its states: default, hover, focus-visible,
  active, disabled, loading, error, empty.
- Extract a shared component on the third repetition, not the first.
- Prefer composition and variants (`variant="primary" | "secondary"`) over boolean-prop sprawl.
- Use an established system package when the brief calls for one (Material, Fluent, Carbon,
  Polaris, Primer, GOV.UK, USWDS, shadcn/ui, Radix) and theme it — do not rebuild it by hand.
- Visual regression (Storybook + Chromatic/Playwright screenshots) guards the system once it
  exists.

## Review Checklist

- [ ] `DESIGN.md` exists and matches the code (no drift)
- [ ] No raw hex / px literals in components; semantic tokens only
- [ ] Every text/background pair passes contrast in light, dark, and high-contrast themes
- [ ] Spacing, type, radius, and motion values all come from their scales
- [ ] Components cover all interactive and data states

_Versions verified September 2026._
