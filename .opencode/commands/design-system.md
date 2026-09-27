Create or refresh the project's design system files: `DESIGN.md` (visual tokens and rules) and
`PRODUCT.md` (audience, voice, anti-references), so every agent generates on-brand UI.

Mode from `$ARGUMENTS`:
- *(empty)* or `scan` — extract the design system from existing code and UI (default)
- `seed` — no UI yet: define a starting design direction with the user
- `check` — report drift between `DESIGN.md` and the code, change nothing
- `tokens` — also generate platform token files from `DESIGN.md`

---

## Step 0: Branch and skills

- Branch: `chore/design-system` (reuse the current feature branch if already on one).
- Load `design-tokens`, plus `design-apple-hig` / `design-material3` for native apps and
  `frontend-design` for web. `impeccable`'s `reference/document.md` describes the same file
  format in more depth.

## Step 1: Existing files

- If `DESIGN.md` exists, show a summary and ask whether to **refresh** (update values, keep
  prose), **merge** (add missing sections), or **overwrite**. Never overwrite silently.
- `PRODUCT.md`: if missing, ask for (or infer from `README.md` / `AGENTS.md` and confirm) the
  audience, the primary jobs, brand personality in three words, voice, and two or three
  anti-references ("must not look like …").

## Step 2: Scan (default mode)

Collect the values the code actually uses:

- Web: CSS custom properties, Tailwind `@theme` / config, CSS-in-JS themes, component library
  theme overrides, font loading.
- iOS: asset-catalog color sets, font registrations, spacing/radius constants.
- Android: `MaterialTheme` color scheme, typography, shapes, `res/values`.
- Flutter: `ThemeData` and `ThemeExtension`s.

Group near-duplicates (e.g. five grays that differ by 2%), identify the real scales, and list
the one-off literals as drift to clean up rather than encoding them as tokens. Take a screenshot
of two or three representative screens to describe the look in words.

## Step 2b: Seed (no UI yet)

Propose two or three distinct directions that fit `PRODUCT.md` — each with palette, type
pairing, radius family, density, and one signature element — explicitly avoiding the
generic-template tells listed in `/design-review`. Let the user choose, then write that
direction.

## Step 3: Write `DESIGN.md`

Follow the format in `design-tokens`: YAML frontmatter tokens (colors, typography, rounded,
spacing, components), then Overview, Colors, Typography, Layout, Elevation & Depth, Shapes,
Components, Do's and Don'ts. Only rules the project actually follows; omit empty sections.
For native apps, record platform-specific decisions (e.g. "system tab bar with SF Symbols",
"dynamic color on, brand scheme fallback").

## Step 4: Tokens (`tokens` mode)

Generate or update the platform files from `DESIGN.md` — CSS custom properties or Tailwind
`@theme`, Swift/asset-catalog colors, Compose theme — or a W3C `*.tokens.json` plus the existing
build step (e.g. Style Dictionary) if the project has one. Do not add a new build dependency
without asking.

## Step 5: Report

Files written, the scales found, drift to clean up (file:line), and open questions for the user.
In `check` mode, report only the drift and whether `DESIGN.md` needs a refresh.

---

Design system mode: $ARGUMENTS
