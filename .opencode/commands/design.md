Design and build a UI surface that looks deliberate, professional, and native to its platform —
not like a generic AI template.

Target from `$ARGUMENTS`: a page, screen, component, or flow, plus any brief (audience, purpose,
references, constraints). Examples: `pricing page for a B2B invoicing tool`,
`onboarding screens for the iOS app`, `redesign src/app/settings`.

---

## Step 0: Branch and platform

- Branch: `feat/design-<slug>` (reuse the current feature branch if already on one).
- Detect the platform from the target and the repo, then load the matching skills — do not
  load the others:

| Platform | Skills |
|---|---|
| Web (React, Vue, Angular, Next.js, plain HTML/CSS) | `frontend-design`, `impeccable`, `design-tokens`, plus the framework skill (`fe-*`) |
| iOS / iPadOS / macOS | `design-apple-hig`, `mobile-ios`, `design-tokens` |
| Android | `design-material3`, `mobile-android`, `design-tokens` |
| Flutter / React Native / KMP | both `design-apple-hig` and `design-material3` (respect each platform's conventions per build target) + the framework skill |

## Step 1: Context before pixels

1. Read `DESIGN.md` and `PRODUCT.md` if they exist. An existing design system is the brief:
   extend it, do not replace it, unless the user asked for a redesign.
2. If there is no `DESIGN.md` and the project has UI code, inspect the incumbent tokens,
   components, and a screenshot of the current UI before deciding anything.
3. If the brief does not name the audience, the primary job of the surface, and the tone, state
   your assumptions in one short paragraph and confirm them with the user before building.
4. Use real content from the product (or realistic content the user approves). No lorem ipsum,
   no invented metrics, testimonials, or customer logos.

## Step 2: Direction (write it down before coding)

Produce a short plan and show it to the user:

- **Mode:** persuade (marketing), operate (app/dashboard), read (docs), or experience (showcase).
- **Tokens:** 4–6 named colors with hex values and roles, typefaces with roles, spacing and
  radius scale — taken from `DESIGN.md` when it exists.
- **Layout:** an ASCII wireframe of the main breakpoint(s) and the alignment/grid choice.
- **One signature element:** the single memorable decision for this surface; everything else
  stays quiet.
- **Platform conventions** (native targets): navigation pattern, system components, touch
  targets, Dynamic Type / font scale behavior.

Review the plan against the generic-template tells in `/design-review` Step 2. Revise anything
that matches one and say what you changed and why.

## Step 3: Build

- Implement with the project's stack and components; tokens from `DESIGN.md`, no literals.
- Cover every state: default, hover, focus-visible, active, disabled, loading, empty, error, and
  long / missing content.
- Responsive (web: 375, 768, 1024, 1440 px) or adaptive (native: smallest and largest device,
  landscape, iPad / tablet if supported).
- Accessibility floor: semantic structure, keyboard and screen-reader access, contrast
  (4.5:1 text, 3:1 UI), targets (24 px web / 44 pt iOS / 48 dp Android), reduced motion.

## Step 4: Look at it (bounded)

- Render it and take screenshots: web via the browser MCP or Playwright at desktop and mobile
  widths; iOS via `xcrun simctl io booted screenshot`; Android via
  `adb exec-out screencap -p > screen.png`.
- Critique the screenshots against the plan and `/design-review` Step 2, fix everything found in
  one batch, and confirm with at most one more round. Do not loop on polish.

## Step 5: Record and report

- New or changed tokens go into `DESIGN.md` (run `/design-system` if it does not exist yet).
- Report: the direction chosen and why, screenshots, files changed, states covered, and any
  assumption the user should confirm.

---

Design target: $ARGUMENTS
