Final quality pass on a UI before shipping: fix spacing, typography, states, consistency,
accessibility, and generic-template tells without changing the design direction.

Scope from `$ARGUMENTS`: a route, page, screen, component folder, or `diff` (changed UI files
only). Default: `diff`. Add `--report <file>` to fix the findings of an earlier `/design-review`.

---

## Step 0: Branch and context

- Branch: reuse the current feature branch, otherwise `fix/polish-<scope>`.
- Load the platform skills as in `/design` Step 0. For web, also read `impeccable`'s
  `reference/polish.md` and `reference/craft-floor.md`.
- Read `DESIGN.md`. Polish converges on the existing system; it does not invent a new look.
  If the direction itself is wrong, stop and recommend `/design` instead.

## Step 1: Find

Take screenshots (desktop + mobile / smallest + largest device, light + dark), then list issues
using `/design-review` Steps 2–3. If a review report was passed, start from it.

## Step 2: Fix (in this order)

1. **Broken:** overflow, clipping, overlapping, layout shift, unreadable contrast, missing
   focus indicator, targets below 24 px (web) / 44 pt (iOS) / 48 dp (Android).
2. **States:** add missing hover, focus-visible, active, disabled, loading (skeletons that
   match the final layout), empty (explains and invites action), and error (names the problem
   and the recovery).
3. **Consistency:** replace literals with `DESIGN.md` tokens; one radius family; one icon set
   and stroke weight; spacing from the scale.
4. **Typography:** hierarchy through size/weight steps from the scale; line length ≤ ~75
   characters; balanced headings (`text-wrap: balance` on the web); `tabular-nums` for
   compared numbers; real quotes and ellipsis characters.
5. **Template tells:** remove decorative eyebrows, gradient text, emoji icons, uniform section
   entrance animations, and filler copy; tighten CTAs to name their action.
6. **Details:** optical alignment, consistent focus rings, themed selection and scrollbars on the
   web, safe-area and inset handling on native, reduced-motion fallbacks.

Keep each change minimal and inside scope. Do not rename routes, navigation labels, or form
fields, and do not rewrite factual copy without asking.

## Step 3: Verify (bounded)

- One screenshot round after the fixes; fix what it shows; stop after at most one more round.
- Run the project's lint, type check, and UI/visual tests; update snapshots only for intended
  changes.

## Step 4: Report

Before/after screenshots, the fixes grouped by the categories above, anything left unfixed with
the reason, and tokens added to `DESIGN.md`.

---

Polish scope: $ARGUMENTS
