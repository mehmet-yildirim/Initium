# Web accessibility patterns

## Skip link and SPA route focus

```html
<a class="skip-link" href="#main">Skip to main content</a>
<main id="main" tabindex="-1">…</main>
```

```css
.skip-link { position: absolute; transform: translateY(-120%); }
.skip-link:focus-visible { transform: none; }
```

```typescript
// After client-side navigation completes
export function focusPageHeading(pageTitle: string): void {
  document.title = pageTitle;
  const heading = document.querySelector<HTMLElement>('main h1');
  if (!heading) return;
  heading.tabIndex = -1;
  heading.focus();
}
```

## Modal dialog

```html
<button type="button" id="delete-trigger">Delete project</button>

<dialog id="confirm-delete" aria-labelledby="confirm-title" aria-describedby="confirm-desc">
  <h2 id="confirm-title">Delete project?</h2>
  <p id="confirm-desc">This permanently deletes the project and its files.</p>
  <form method="dialog">
    <button value="cancel" autofocus>Cancel</button>
    <button value="confirm">Delete</button>
  </form>
</dialog>
```

```typescript
const trigger = document.getElementById('delete-trigger') as HTMLButtonElement;
const dialog = document.getElementById('confirm-delete') as HTMLDialogElement;

trigger.addEventListener('click', () => dialog.showModal());
dialog.addEventListener('close', async () => {
  trigger.focus();
  if (dialog.returnValue !== 'confirm') return;
  try {
    await deleteProject();
  } catch (error) {
    logger.error({ err: error }, 'project deletion failed');
    announceError('The project could not be deleted. Try again.');
  }
});
```

- `showModal()` makes the rest of the page inert and closes on Escape; `show()` does not.
- Put initial focus on the least destructive action.

## Form with error summary

```html
<form novalidate aria-describedby="form-errors">
  <div id="form-errors" role="alert" tabindex="-1" hidden>
    <h2>There are 2 problems</h2>
    <ul>
      <li><a href="#email">Enter an email address in the format name@example.com</a></li>
      <li><a href="#password">Password must be at least 12 characters</a></li>
    </ul>
  </div>

  <label for="email">Email</label>
  <input id="email" name="email" type="email" autocomplete="email" required
         aria-invalid="true" aria-describedby="email-error">
  <p id="email-error">Enter an email address in the format name@example.com</p>

  <fieldset>
    <legend>Contact preference</legend>
    <input type="radio" id="pref-email" name="pref" value="email">
    <label for="pref-email">Email</label>
    <input type="radio" id="pref-sms" name="pref" value="sms">
    <label for="pref-sms">Text message</label>
  </fieldset>

  <button type="submit">Create account</button>
</form>
```

- On submit failure: render the summary, unhide it, and move focus to it. Clear `aria-invalid`
  once a field is fixed.
- Validate on submit or on blur, not on every keystroke.
- Server-side validation errors use the same mechanism.

## Live regions

```html
<div id="save-status" role="status"></div>
```

```typescript
function announceSaved(): void {
  const region = document.getElementById('save-status');
  if (region) region.textContent = 'Changes saved';
}
```

- The region must exist before content changes; don't toggle `display` on it.
- Use `role="alert"` only for errors that need immediate attention.

## Icon-only buttons and links

```html
<button type="button" aria-label="Close">
  <svg aria-hidden="true" focusable="false">…</svg>
</button>
<a href="/reports/q3.pdf">Q3 report <span class="visually-hidden">(PDF, 2 MB)</span></a>
```

```css
.visually-hidden {
  position: absolute; width: 1px; height: 1px; margin: -1px; padding: 0;
  overflow: hidden; clip-path: inset(50%); white-space: nowrap; border: 0;
}
```

## Focus, targets, motion, forced colors

```css
:focus-visible { outline: 3px solid var(--color-focus); outline-offset: 2px; }

html { scroll-padding-top: var(--sticky-header-height); }

.icon-button { min-inline-size: 44px; min-block-size: 44px; }

@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: 0.01ms !important;
    animation-iteration-count: 1 !important;
    transition-duration: 0.01ms !important;
    scroll-behavior: auto !important;
  }
}

@media (forced-colors: active) {
  .card { border: 1px solid CanvasText; }
}
```

## Data tables

```html
<table>
  <caption>Orders placed in September 2026</caption>
  <thead>
    <tr><th scope="col">Order</th><th scope="col">Date</th><th scope="col">Total</th></tr>
  </thead>
  <tbody>
    <tr><th scope="row">#1042</th><td>2026-09-14</td><td>€42.00</td></tr>
  </tbody>
</table>
```

Use tables for tabular data only; never for layout. Sortable headers use a `<button>` inside the
`<th>` and `aria-sort` on the sorted column.
