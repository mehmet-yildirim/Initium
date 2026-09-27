Review an existing UI for visual quality, generic "AI template" tells, and platform guideline
compliance. Read-only: report findings, do not change code (use `/polish` to fix).

Scope from `$ARGUMENTS`: a route, page, screen, component folder, URL, or `diff` (changed UI
files only). Default: `diff`.

---

## Step 1: Gather evidence

- Load the platform skills: web → `frontend-design`, `impeccable` (its
  `reference/critique.md` and `reference/craft-floor.md`), `design-tokens`; iOS →
  `design-apple-hig`; Android → `design-material3`; cross-platform → both platform skills.
- Read `DESIGN.md` / `PRODUCT.md` if present — deviations from them are findings.
- Take screenshots (desktop + mobile for web; smallest and largest device for native; light and
  dark themes). Findings must reference what is visible, not only what the code suggests.
- Optional, only if already installed in the project: `npx impeccable detect --json <path>` for
  deterministic anti-pattern checks. Do not install tools as part of a review.

## Step 2: Generic-template tells

Each item is a finding unless the brief or `DESIGN.md` explicitly chose it.

| Area | Tell |
|---|---|
| Layout | Centered hero + row of three identical icon/heading/text cards; everything centered; cards nested in cards; every section wrapped in a card |
| Hero | Big number + small label + stat row + gradient accent; version/"beta" badges and scroll cues as decoration |
| Labels | Tracked-out ALL-CAPS eyebrow above every heading; 01/02/03 numbering on non-sequential content; `A · B · C` meta strings everywhere |
| Type | Default family chosen by habit (Inter/Roboto/system everywhere) with no reason; flat hierarchy; one highlighted word in the headline; body lines over ~80 characters |
| Color | Purple-to-blue or mesh gradients; gradient text; neon accent on near-black; gray text on colored backgrounds; pure `#000`/`#fff`; more than one accent |
| Surface | Same radius and same soft shadow on everything; glassmorphism as decoration; thick colored left border on cards/alerts; zero-blur offset shadows outside a brutalist world |
| Icons | Emoji or Unicode glyphs as icons; mixed icon sets or stroke weights |
| Motion | Fade-and-slide-up on every section; hover lift on every card; bounce/elastic easing; animating layout properties |
| Copy | Vague CTAs ("Get started", "Learn more", "Submit"); buzzwords ("seamless", "supercharge", "unlock"); invented stats or testimonials; apologetic or vague errors |
| Content | Lorem ipsum; fake product UI drawn with divs; placeholder avatars and logos |

## Step 3: Craft and platform checks

- **Hierarchy:** one clear primary action per view; the eye lands in the intended order.
- **Spacing and alignment:** values from a scale; tight within groups, generous between;
  consistent grid; optical alignment of icons and text.
- **States:** hover, focus-visible, active, disabled, loading, empty, error, long content.
- **Accessibility:** contrast, targets, keyboard/screen reader, reduced motion (run `/a11y` for
  a full WCAG audit).
- **Platform:** iOS — HIG checklist in `design-apple-hig`; Android — checklist in
  `design-material3`; web — responsive at 375/768/1024/1440 px, `:focus-visible`, no layout
  shift.
- **Consistency:** matches `DESIGN.md` tokens; no raw hex/px literals in components.

## Step 4: Report

- Scores 1–5 for: hierarchy, typography, color, layout & spacing, states, accessibility,
  platform fit, and distinctiveness (5 = clearly designed for this product, 1 = interchangeable
  template).
- Findings ordered by impact: severity (high / medium / low), location (file:line or screenshot
  region), what is wrong, and the concrete fix.
- The three changes that would improve the surface most.
- Next step: `/polish <scope>` to apply the fixes.

---

Review scope: $ARGUMENTS
