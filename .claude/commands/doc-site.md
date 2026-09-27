Scaffold, configure, or regenerate the project's documentation website. Produces a complete,
deployable documentation site targeting developers, API consumers, and (optionally) stakeholders.

Read `AGENTS.md`, `docs/context/tech-stack.md`, existing `docs/` content, and any existing
documentation site config before generating.

---

## Step 1: Assess Current State and Choose a Site Generator

### If no documentation site exists yet — choose a generator:

| Generator | Choose when | Stack fit |
|-----------|------------|-----------|
| **Docusaurus 3** | Product docs, versioned API docs, need React components | Any |
| **MkDocs Material** | Python-heavy team, fast setup, enterprise feel | Python primary |
| **VitePress** | Vue-heavy team, fastest build | Vue/Vite primary |
| **Mintlify** | API-first product, want zero-config hosting | Any |

**Default recommendation:** Docusaurus 3 — most complete feature set for polyglot projects.

### If a site already exists — detect and update:
- Look for `docusaurus.config.js` / `docusaurus.config.ts` → Docusaurus
- Look for `mkdocs.yml` → MkDocs
- Look for `.vitepress/config.ts` → VitePress
- Look for `mint.json` → Mintlify

---

## Step 2: Scaffold the Site (if new)

### Docusaurus 3 Setup
```bash
# Create site in docs-site/ subdirectory
npx create-docusaurus@latest docs-site classic --typescript

# Install useful plugins
cd docs-site && npm install \
  @docusaurus/plugin-content-docs \
  @docusaurus/plugin-sitemap \
  @docusaurus/theme-search-algolia \
  docusaurus-plugin-sass \
  redocusaurus \
  prism-react-renderer
```

Create `docs-site/docusaurus.config.ts`:
```typescript
import type { Config } from '@docusaurus/types';
import type * as Preset from '@docusaurus/preset-classic';

const config: Config = {
  title: 'TODO: Project Name',
  tagline: 'TODO: Project tagline',
  url: 'https://TODO:docs.yourproject.com',
  baseUrl: '/',
  onBrokenLinks: 'throw',
  onBrokenMarkdownLinks: 'warn',
  i18n: { defaultLocale: 'en', locales: ['en'] },

  presets: [
    ['classic', {
      docs: {
        sidebarPath: './sidebars.ts',
        editUrl: 'https://github.com/TODO:owner/TODO:repo/edit/main/docs-site/',
        showLastUpdateTime: true,
        showLastUpdateAuthor: true,
      },
      theme: { customCss: './src/css/custom.css' },
    } satisfies Preset.Options],
  ],

  plugins: [
    // OpenAPI / ReDoc integration
    ['redocusaurus', {
      specs: [{ id: 'api', spec: 'static/openapi-bundled.json', route: '/api/reference' }],
      theme: { primaryColor: '#1890ff' },
    }],
  ],

  themeConfig: {
    navbar: {
      title: 'TODO: Project Name',
      items: [
        { to: '/docs/intro', label: 'Guides', position: 'left' },
        { to: '/api/reference', label: 'API Reference', position: 'left' },
        { to: '/docs/architecture/overview', label: 'Architecture', position: 'left' },
        { href: 'https://github.com/TODO:owner/TODO:repo', label: 'GitHub', position: 'right' },
      ],
    },
    footer: {
      links: [
        { title: 'Docs', items: [{ label: 'Getting Started', to: '/docs/intro' }] },
        { title: 'API', items: [{ label: 'Reference', to: '/api/reference' }] },
      ],
    },
    prism: { theme: require('prism-react-renderer').themes.github },
  } satisfies Preset.ThemeConfig,
};
export default config;
```

### MkDocs Material Setup
```bash
pip install mkdocs-material mkdocs-mermaid2-plugin mkdocs-include-markdown-plugin
```

Create `mkdocs.yml`:
```yaml
site_name: TODO: Project Name
site_url: https://TODO:docs.yourproject.com
repo_url: https://github.com/TODO:owner/TODO:repo
repo_name: TODO:owner/TODO:repo
edit_uri: edit/main/docs/

theme:
  name: material
  palette: [{ scheme: default, primary: blue }, { scheme: slate, primary: blue }]
  features:
    - navigation.tabs
    - navigation.sections
    - navigation.top
    - search.suggest
    - content.code.copy

plugins:
  - search
  - mermaid2
  - include-markdown

markdown_extensions:
  - pymdownx.superfences:
      custom_fences:
        - name: mermaid
          class: mermaid
          format: !!python/name:pymdownx.superfences.fence_code_format
  - pymdownx.tabbed: { alternate_style: true }
  - admonition
  - pymdownx.details
  - attr_list

nav:
  - Home: index.md
  - Getting Started: onboarding.md
  - Architecture: architecture/overview.md
  - API Reference: api/reference.md
  - Guides: guides/
  - Changelog: changelog.md
```

---

## Step 3: Structure Content

Generate the documentation structure by pulling from existing project files:

```
docs-site/docs/          (Docusaurus)  or  docs/  (MkDocs)
├── intro.md             ← generate from docs/context/project-brief.md
├── onboarding.md        ← copy from docs/guides/onboarding.md
├── architecture/
│   ├── overview.md      ← copy from docs/architecture/overview.md
│   ├── diagrams.md      ← generate Mermaid diagrams
│   └── decisions/       ← copy ADRs
├── guides/              ← per-language developer guides
│   ├── getting-started.md
│   ├── java.md          (if Java in stack)
│   ├── python.md        (if Python in stack)
│   ├── typescript.md    (if TypeScript in stack)
│   ├── go.md            (if Go in stack)
│   ├── react.md         (if React in stack)
│   ├── mobile-ios.md    (if iOS in stack)
│   └── mobile-android.md
├── api/
│   ├── reference.mdx    ← embedded ReDoc (OpenAPI)
│   ├── authentication.md
│   └── error-codes.md
├── security/
│   └── overview.md      ← generate from security guidelines
└── changelog.md         ← copy/link CHANGELOG.md
```

For each guide file, generate content covering:
1. Setup and prerequisites for the language/framework
2. Key project conventions (from AGENTS.md and skill rules)
3. Common patterns used in this project
4. Testing approach
5. Deployment notes

---

## Step 4: Embed the OpenAPI Spec

### In Docusaurus (via redocusaurus)
Create `docs-site/docs/api/reference.mdx`:
```mdx
---
title: API Reference
description: Interactive REST API documentation
---

import ApiReference from '@theme/ApiReference';

<ApiReference id="api" />
```

### In MkDocs (via embedded HTML)
Create `docs/api/reference.md`:
```markdown
# API Reference

<redoc spec-url='../openapi-bundled.json'></redoc>
<script src="https://cdn.jsdelivr.net/npm/redoc/bundles/redoc.standalone.js"></script>
```

### Standalone ReDoc page
```bash
npx @redocly/cli build-docs openapi.json -o docs-site/static/api-reference.html
```

---

## Step 5: Embed Architecture Diagrams

Ensure all Mermaid diagrams in `docs/architecture/` render correctly.

For Docusaurus, add mermaid support:
```bash
npm install @docusaurus/theme-mermaid
```

```typescript
// docusaurus.config.ts
markdown: { mermaid: true },
themes: ['@docusaurus/theme-mermaid'],
```

For PlantUML diagrams, convert to SVG and embed:
```bash
# Convert all .puml files to SVG
for f in docs/architecture/*.puml; do
  docker run --rm -v "$(pwd):/data" plantuml/plantuml -Tsvg "/data/$f"
done
# Reference in markdown: ![Diagram](./diagram.svg)
```

---

## Step 6: Generate llms.txt

Create `docs-site/static/llms.txt` (AI-readable sitemap for LLMs):

```
# <Project Name>

> <One-sentence project description from project-brief.md>

## Documentation
- [Getting Started](/docs/guides/onboarding): Developer onboarding guide
- [Architecture](/docs/architecture/overview): System design and patterns
- [API Reference](/api/reference): Full REST API documentation
- [Domain Glossary](/docs/context/domain-glossary): Business terminology
- [Changelog](/docs/changelog): Release history

## API
- [OpenAPI Spec](/openapi-bundled.json): Machine-readable API specification

## Source
- [GitHub Repository](https://github.com/<owner>/<repo>)
- [Issue Tracker](https://github.com/<owner>/<repo>/issues)
```

---

## Step 7: Add Deployment Configuration

### GitHub Pages
```yaml
# .github/workflows/deploy-docs.yml
name: Deploy Documentation

on:
  push:
    branches: [main]
    paths: ['docs/**', 'docs-site/**', 'openapi.json', 'CHANGELOG.md']

jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      pages: write
      id-token: write
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - uses: actions/setup-node@820762786026740c76f36085b0efc47a31fe5020 # v7.0.0
        with:
          node-version: 24
      - run: cp openapi-bundled.json docs-site/static/
      - run: cd docs-site && npm ci && npm run build
      - uses: actions/upload-pages-artifact@fc324d3547104276b827a68afc52ff2a11cc49c9 # v5.0.0
        with:
          path: docs-site/build
      - uses: actions/deploy-pages@368f82528645a54fb793d4d04e342629a3f51346 # v5.0.1
        id: deployment
```

### Vercel (one-command deploy)
```bash
cd docs-site && npx vercel deploy --prod
```

---

## Step 8: Output Summary

```
Documentation Site Generated
═══════════════════════════════════════════════════════

Generator : Docusaurus 3  (docs-site/)
Config    : docs-site/docusaurus.config.ts

Pages generated:
  Getting Started    : docs/intro.md
  Architecture       : docs/architecture/overview.md  (+3 diagram pages)
  API Reference      : docs/api/reference.mdx  (ReDoc from openapi-bundled.json)
  Developer Guides   : docs/guides/  (N pages — one per detected language/framework)
  Changelog          : docs/changelog.md

Build & verify:
  cd docs-site && npm run start    # Local preview at http://localhost:3000
  cd docs-site && npm run build    # Production build to docs-site/build/

Deploy:
  GitHub Pages : .github/workflows/deploy-docs.yml  (auto on main push)
  Vercel       : cd docs-site && npx vercel deploy --prod
  Netlify      : cd docs-site && npx netlify deploy --prod --dir=build

Next steps:
  1. Fill in TODO: values in docusaurus.config.ts
  2. Review generated guide pages — AI content validated against actual code
  3. Regenerate API reference: /doc-api
  4. Commit: git add docs-site/ && git commit -m "docs: scaffold documentation site"
```

---

Target (optional — "docusaurus" | "mkdocs" | "vitepress" | "rebuild"): $ARGUMENTS
