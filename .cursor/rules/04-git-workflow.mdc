---
description: Git workflow, branch naming, commit conventions, and PR guidelines. Apply for git operations and PR creation.
globs:
alwaysApply: false
---

# Git Workflow

## Branch Before Any Code Change

**Before writing or modifying any code — regardless of whether a slash command was used — always create and switch to a feature branch first.**

This rule applies to all change requests:
- Slash commands (`/implement`, `/debug`, `/fix`, etc.)
- Direct instructions in chat ("fix this bug", "change this function", "update this file")
- Inline edit requests

```bash
git branch --show-current   # verify you are NOT on main or develop
git checkout -b fix/<slug>   # for bug fixes
git checkout -b feat/<slug>  # for features or new code
git checkout -b chore/<slug> # for config or tooling changes
```

If already on a feature branch (not `main` or `develop`), proceed. Never commit implementation work directly to `main` or `develop`.

---

## Branching Strategy

### Branch types
| Prefix | Purpose | Example |
|--------|---------|---------|
| `feat/` | New feature | `feat/PROJ-42-user-authentication` |
| `fix/` | Bug fix | `fix/PROJ-87-null-pointer-on-checkout` |
| `chore/` | Tooling, deps, config | `chore/upgrade-to-node-22` |
| `docs/` | Documentation only | `docs/api-auth-guide` |
| `test/` | Tests only | `test/increase-coverage-payments` |
| `refactor/` | Code restructure (no behavior change) | `refactor/extract-payment-service` |
| `hotfix/` | Urgent production fix | `hotfix/critical-auth-bypass` |

### Branch rules
- Branch from `main` (or `develop` if using Gitflow)
- Ticket ID in branch name when applicable: `feat/PROJ-42-...`
- Keep branches short-lived: merge within days, not weeks
- One concern per branch — don't mix features with refactoring

## Commit Conventions

Use **Conventional Commits** format:
```
<type>(<scope>): <description>

[optional body]

[optional footer(s)]
```

### Types
| Type | When to use |
|------|------------|
| `feat` | New feature |
| `fix` | Bug fix |
| `chore` | Maintenance, deps, tooling |
| `docs` | Documentation |
| `test` | Adding or fixing tests |
| `refactor` | Code change with no behavior change |
| `perf` | Performance improvement |
| `ci` | CI/CD changes |
| `revert` | Reverting a previous commit |

### Examples
```
feat(auth): add OAuth2 login with Google
fix(cart): prevent negative quantity on item removal
chore(deps): upgrade Drizzle ORM to v0.30
test(users): add integration tests for user creation endpoint
docs(api): document rate limiting headers
```

### Rules
- Description: present tense, lowercase, no period at the end, ≤ 72 characters
- Body: wrap at 72 chars; explain *why*, not *what*
- Reference issues: `Closes #42` or `Fixes PROJ-87` in footer
- One logical change per commit

## Pull Request Guidelines

### Before opening a PR
- [ ] All tests pass locally
- [ ] Linter and formatter pass
- [ ] Type checking passes
- [ ] Self-review completed (read every line of your diff)
- [ ] AGENTS.md / project docs updated if needed
- [ ] No debug code, console.logs, or commented-out code

### PR size
- Aim for < 400 lines changed per PR
- Large features: break into a series of stacked PRs
- If a PR is large, add a PR description that guides reviewers through the changes

### PR description
Use the template in `.github/PULL_REQUEST_TEMPLATE.md`.

### Review process
- At least one reviewer approval required before merge
- Author resolves all comments before merging (or explicitly marks as "won't fix" with reason)
- CI must be green before merge

### Merge strategy
- **Squash merge** to `main` to keep history clean
- Squash commit message = PR title (must be conventional commit format)

## Protected Branch Rules

- `main` / `master`: No direct pushes. PR required. CI must pass.
- `develop` (if used): Same as main.
- **Never** `--force-push` to protected branches

## Tagging & Releases

- Semantic versioning: `v<major>.<minor>.<patch>`
- Tag releases from `main` after merge
- Changelog maintained in `CHANGELOG.md` (or auto-generated from commits)

## Common Operations

```bash
# Start a new feature
git checkout main && git pull
git checkout -b feat/PROJ-42-my-feature

# Keep branch up to date
git fetch origin
git rebase origin/main

# Commit staged changes
git commit -m "feat(scope): description"

# Push branch and open PR
git push -u origin HEAD
gh pr create --fill
```
