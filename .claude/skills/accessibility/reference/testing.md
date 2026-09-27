# Accessibility testing

Automated tools find a subset of WCAG failures (missing names, contrast, invalid ARIA). They
cannot judge alt-text quality, focus order logic, meaningful announcements, or cognitive load.
Both layers are required.

## Lint: eslint-plugin-jsx-a11y (flat config)

```javascript
// eslint.config.js
import jsxA11y from 'eslint-plugin-jsx-a11y';

export default [
  jsxA11y.flatConfigs.strict,
  {
    settings: {
      'jsx-a11y': {
        components: { Button: 'button', Link: 'a', TextField: 'input' },
      },
    },
  },
];
```

- Map design-system components to native elements so rules apply to them.
- Vue: `eslint-plugin-vuejs-accessibility`; Angular: `@angular-eslint` template accessibility rules.

## Component tests

- Query by role and name (`getByRole('button', { name: 'Save' })`); a test that cannot find an
  element by role usually exposes a real accessibility bug.
- Run axe on rendered components (`vitest-axe`/`jest-axe`, or `@axe-core/playwright` in Vitest
  browser mode/Playwright component tests).

## E2E with axe

See `testing-e2e` → `reference/playwright.md`. Tags for WCAG 2.2 AA:
`wcag2a`, `wcag2aa`, `wcag21a`, `wcag21aa`, `wcag22aa` (no `wcag22a` tag exists).

```typescript
const results = await new AxeBuilder({ page })
  .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa'])
  .exclude('#third-party-chat') // TODO(#456): vendor fix pending
  .analyze();
expect(results.violations).toEqual([]);
```

## Lighthouse 13

- Use for page-level trends and CI budgets (`@lhci/cli` with an accessibility score assertion);
  its accessibility category runs a subset of axe rules. A score of 100 does not mean conformant.

## Manual test pass (per feature)

1. **Keyboard only:** Tab/Shift+Tab through everything; operate controls with Enter/Space/arrows;
   Escape closes overlays; focus is always visible and never trapped or obscured.
2. **Zoom and reflow:** 200% browser zoom; 320 CSS px viewport; OS text size at maximum.
3. **Preferences:** reduced motion, dark mode, forced colors / high contrast.
4. **Screen reader:** navigate by headings, landmarks and form controls; verify names, roles,
   states and announcements for dynamic updates.

| Platform | Screen reader | Browser/app | Start |
|---|---|---|---|
| Windows | NVDA (free) | Firefox or Chrome | Ctrl+Alt+N |
| macOS | VoiceOver | Safari | Cmd+F5 |
| iOS | VoiceOver | Safari / app | Settings → Accessibility → VoiceOver |
| Android | TalkBack | Chrome / app | Settings → Accessibility → TalkBack |

Rotate combinations across releases; always test NVDA + a Chromium browser and VoiceOver + Safari
for web, and both mobile screen readers for native apps.

## Reporting

- File each issue with: WCAG success criterion, affected component, steps, assistive technology
  and version, expected vs. actual, severity (blocker if a task cannot be completed).
- Keep an accessibility conformance report (VPAT/ACR, EN 301 549 edition) for sold products.
