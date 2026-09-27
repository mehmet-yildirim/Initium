# TypeScript toolchain configuration

Read when creating or changing `tsconfig*.json`, `package.json`, or ESLint configuration.

## TypeScript 7 alongside the 6.0 API

TypeScript 7.0 ships the native `tsc` but no compiler API. Keep the 6.0 API under the `typescript`
name for API consumers (typescript-eslint, ts-morph) and install 7.0 under an alias so `npx tsc`
runs the native compiler:

```json
{
  "devDependencies": {
    "typescript": "npm:@typescript/typescript6@^6.0.2",
    "@typescript/native": "npm:typescript@^7.0.2"
  }
}
```

- `tsc` → TypeScript 7 (native). `tsc6` → TypeScript 6 (from the compatibility package).
- Remove both aliases and depend on `typescript` directly once TypeScript 7.1 (new API) is out and
  typescript-eslint's peer range accepts it.

## tsconfig — Node 24 application

```jsonc
{
  "compilerOptions": {
    "target": "es2024",
    "lib": ["es2024", "esnext.disposable"],
    "module": "nodenext",
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "exactOptionalPropertyTypes": true,
    "noImplicitOverride": true,
    "noFallthroughCasesInSwitch": true,
    "erasableSyntaxOnly": true,
    "verbatimModuleSyntax": true,
    "rewriteRelativeImportExtensions": true,
    "rootDir": "./src",
    "outDir": "./dist",
    "types": ["node"],
    "skipLibCheck": true
  },
  "include": ["src"]
}
```

- If Node runs the sources directly (type stripping, no build), add `"noEmit": true` and drop
  `outDir`.
- Relative imports use `.ts` (`import { placeOrder } from './place-order.ts'`); the compiler
  rewrites them to `.js` on emit.

## tsconfig — publishable library

Extend the application config and add declaration output:

```jsonc
{
  "extends": "./tsconfig.json",
  "compilerOptions": {
    "declaration": true,
    "declarationMap": true,
    "isolatedDeclarations": true
  }
}
```

`isolatedDeclarations` forces explicit return types on exports so declaration files can be generated
without full type checking.

## package.json

Application:

```json
{
  "name": "orders-service",
  "private": true,
  "type": "module",
  "engines": { "node": ">=24" },
  "imports": {
    "#app/*": "./src/*"
  },
  "scripts": {
    "start": "node src/main.ts",
    "typecheck": "tsc --noEmit",
    "lint": "eslint .",
    "test": "vitest run"
  }
}
```

- The `#app/*` mapping points at sources, so use it only when Node runs `.ts` directly. Compiled
  apps should use relative imports (or conditional `imports` targets for `dist/`).

Library — declare every entry point in `exports`, with `types` first:

```json
{
  "name": "@acme/orders-client",
  "version": "1.0.0",
  "type": "module",
  "engines": { "node": ">=24" },
  "files": ["dist"],
  "exports": {
    ".": {
      "types": "./dist/index.d.ts",
      "default": "./dist/index.js"
    },
    "./package.json": "./package.json"
  }
}
```

- Anything not listed in `exports` is private to the package.
- Do not publish `.ts` sources for consumers to strip — Node does not strip types under
  `node_modules`.

## ESLint (flat config)

```js
// eslint.config.js
import eslint from '@eslint/js';
import { defineConfig } from 'eslint/config';
import importX from 'eslint-plugin-import-x';
import tseslint from 'typescript-eslint';

export default defineConfig(
  eslint.configs.recommended,
  tseslint.configs.strictTypeChecked,
  tseslint.configs.stylisticTypeChecked,
  {
    languageOptions: {
      parserOptions: {
        projectService: true,
        tsconfigRootDir: import.meta.dirname,
      },
    },
    plugins: { 'import-x': importX },
    rules: {
      '@typescript-eslint/no-floating-promises': 'error',
      '@typescript-eslint/no-misused-promises': 'error',
      '@typescript-eslint/switch-exhaustiveness-check': 'error',
      'import-x/order': [
        'error',
        {
          groups: ['builtin', 'external', 'internal', ['parent', 'sibling', 'index']],
          'newlines-between': 'always',
        },
      ],
      'no-console': 'error',
    },
  },
);
```

## CI sequence

```bash
npm ci
npm audit --audit-level=high
npx tsc --noEmit
npx eslint .
npx vitest run
```
