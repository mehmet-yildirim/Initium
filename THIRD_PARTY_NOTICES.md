# Third-Party Notices

Initium vendors the following third-party works. Each is used under its original license; the
full license text ships next to the vendored files. Refresh them with
`bash .initium/scripts/vendor-design-skills.sh` (pins are set in that script).

## frontend-design (Anthropic)

- **Files:** `.claude/skills/frontend-design/`
- **Source:** <https://github.com/anthropics/skills/tree/main/skills/frontend-design>
- **Pinned commit:** `33375500bcea98d610eb30ce10ac4e59b89c390d`
- **License:** Apache License 2.0 — `.claude/skills/frontend-design/LICENSE.txt`
- **Changes:** none.

## Impeccable (Paul Bakaus)

- **Files:** `.claude/skills/impeccable/` (`SKILL.md`, `reference/`), `.claude/agents/impeccable-*.md`
- **Source:** <https://github.com/pbakaus/impeccable> (`plugin/skills/impeccable`, `plugin/agents`)
- **Pinned commit:** `9d715cc4f5564a990ca8345abfdd5df6dc9b41c8` (skill version 4.4.0)
- **License:** Apache License 2.0 — `.claude/skills/impeccable/LICENSE`; upstream notices in
  `.claude/skills/impeccable/NOTICE.md`
- **Changes:** files are unmodified. The `scripts/` directory (launcher, downloaded engine
  binary, font index, live-browser scripts) and the plugin hooks are not included; the skill
  uses its documented fallback when the launcher is unavailable. Install the full tool with
  `npx impeccable install` to enable the detector, design hook, and live mode.

## Referenced, not vendored

- **Apple Human Interface Guidelines** — © Apple Inc., not licensed for redistribution.
  `.claude/skills/design-apple-hig/` is an original summary that links to
  <https://developer.apple.com/design/human-interface-guidelines/>.
- **Material Design 3** — © Google LLC, CC BY 4.0. `.claude/skills/design-material3/` adapts
  and condenses guidance from <https://m3.material.io>. "Material Design" is a trademark of
  Google LLC.
- **DESIGN.md format** — Google Labs, <https://github.com/google-labs-code/design.md>
  (Apache-2.0); `.claude/skills/design-tokens/` follows its section structure.
