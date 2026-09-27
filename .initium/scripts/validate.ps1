# =============================================================================
# AI Configuration Validator (Windows / PowerShell)
# Checks that all AI tool config files are present and customized.
# Requires PowerShell 5.1+ (built-in on Windows 10/11) or PowerShell 7+.
#
# Usage:
#   .\.initium\scripts\validate.ps1
#
# If blocked by execution policy, run once as Administrator:
#   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
# =============================================================================

$ErrorActionPreference = 'Stop'

$passCount = 0
$warnCount = 0
$failCount = 0

function Write-Pass { param($msg) Write-Host "  PASS $msg" -ForegroundColor Green;  $script:passCount++ }
function Write-Warn { param($msg) Write-Host "  WARN $msg" -ForegroundColor Yellow; $script:warnCount++ }
function Write-Fail { param($msg) Write-Host "  FAIL $msg" -ForegroundColor Red;    $script:failCount++ }

Write-Host ""
Write-Host "========================================"
Write-Host "  AI Configuration Validator"
Write-Host "========================================"

# ---------------------------------------------------------------------------
# File existence checks
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "--- File Presence ---"

function Check-Exists {
    param($file)
    # Normalize separators for cross-platform display
    $display = $file -replace '/', '\'
    if (Test-Path $file) {
        Write-Pass "Found: $display"
        return $true
    } else {
        Write-Fail "Missing: $display"
        return $false
    }
}

# Core AI tool configs
Check-Exists "AGENTS.md"
Check-Exists "CLAUDE.md"
if ((Test-Path "CLAUDE.md") -and -not (Select-String -Path "CLAUDE.md" -Pattern "^@AGENTS\.md" -Quiet)) {
    Write-Warn "CLAUDE.md does not import @AGENTS.md — Claude Code may follow different instructions"
}
Check-Exists "SECURITY.md"
Check-Exists ".cursor/rules/00-project-overview.mdc"
Check-Exists ".cursor/rules/01-coding-standards.mdc"
Check-Exists ".cursor/rules/02-architecture.mdc"
Check-Exists ".cursor/rules/03-testing.mdc"
Check-Exists ".cursor/rules/04-git-workflow.mdc"
Check-Exists ".cursor/rules/05-security.mdc"
Check-Exists ".cursor/mcp.json"
Check-Exists ".continue/config.yaml"
Check-Exists ".continue/rules/01-coding-standards.md"
Check-Exists ".continue/rules/02-architecture.md"
Check-Exists ".continue/rules/03-testing.md"
Check-Exists ".continue/rules/04-security.md"

# Claude Code slash commands
Check-Exists ".claude/commands/init.md"
Check-Exists ".claude/commands/requirements.md"
Check-Exists ".claude/commands/architect.md"
Check-Exists ".claude/commands/implement.md"
Check-Exists ".claude/commands/review.md"
Check-Exists ".claude/commands/qa.md"
Check-Exists ".claude/commands/test.md"
Check-Exists ".claude/commands/debug.md"
Check-Exists ".claude/commands/deploy.md"
Check-Exists ".claude/commands/migrate.md"
Check-Exists ".claude/commands/db.md"
Check-Exists ".claude/commands/sprint.md"
Check-Exists ".claude/commands/docs.md"
Check-Exists ".claude/commands/standup.md"
Check-Exists ".claude/commands/security-audit.md"
Check-Exists ".claude/commands/triage.md"
Check-Exists ".claude/commands/groom.md"
Check-Exists ".claude/commands/loop.md"
Check-Exists ".claude/commands/escalate.md"
Check-Exists ".claude/commands/goal.md"
Check-Exists ".claude/commands/help.md"
Check-Exists ".claude/commands/codegraph.md"
Check-Exists ".claude/commands/refactor.md"
Check-Exists ".claude/commands/upgrade.md"
Check-Exists ".claude/commands/perf.md"
Check-Exists ".claude/commands/a11y.md"
Check-Exists ".claude/commands/eval.md"
Check-Exists ".claude/commands/skill.md"
Check-Exists "opencode.json"
Check-Exists ".opencode/README.md"
if (Test-Path ".initium/scripts/sync-opencode-commands.sh") {
    $syncCheck = bash .initium/scripts/sync-opencode-commands.sh --check 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Pass "OpenCode commands in sync with .claude/commands/"
    } else {
        Write-Fail "OpenCode commands out of sync — run: bash .initium/scripts/sync-opencode-commands.sh"
    }
}

# Autonomous agent config & docs
Check-Exists "agent.config.yaml"
Check-Exists "docs/context/domain-boundaries.md"
Check-Exists ".initium/docs/agent/autonomous-workflow.md"
Check-Exists ".initium/docs/agent/escalation-protocol.md"
Check-Exists ".initium/docs/agent/decision-log-template.md"
Check-Exists ".initium/docs/agent/jira-server-setup.md"
Check-Exists ".initium/docs/agent/security-evaluator.md"
Check-Exists ".agent-templates/webhook-receiver.mjs"
Check-Exists ".initium/docs/agent/schemas/task-state.json"
Check-Exists ".initium/docs/agent/schemas/decision.json"
Check-Exists ".initium/docs/agent/schemas/requirement-analysis.json"
Check-Exists ".initium/docs/agent/schemas/qa-report.json"
Check-Exists ".initium/docs/agent/schemas/security-report.json"
Check-Exists ".claude/hooks/post-write.mjs"
Check-Exists ".claude/hooks/audit-log.mjs"
Check-Exists ".claude/hooks/on-stop.mjs"

# Agent Skills (.claude/skills/<name>/SKILL.md — single source)
$skillFiles = @(Get-ChildItem -Path ".claude/skills" -Filter "SKILL.md" -Recurse -Depth 1 -ErrorAction SilentlyContinue)
if ($skillFiles.Count -gt 0) {
    Write-Pass "Found $($skillFiles.Count) skill(s) in .claude/skills/"
} else {
    Write-Fail "No skills found in .claude/skills/"
}
if (Test-Path ".cursor/rules/skills/*.mdc") {
    Write-Warn "Legacy .cursor/rules/skills/ still present — skills now live in .claude/skills/ (see UPDATES.md v1.1.0)"
}
Check-Exists ".initium/scripts/sync-skills.mjs"
Check-Exists ".initium/scripts/check-update.mjs"
Check-Exists ".github/workflows/initium-sync.yml"
Check-Exists "THIRD_PARTY_NOTICES.md"
Check-Exists ".claude/skills/frontend-design/LICENSE.txt"
Check-Exists ".claude/skills/impeccable/LICENSE"
if (Get-Command node -ErrorAction SilentlyContinue) {
    $null = node .initium/scripts/sync-skills.mjs --check 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Pass "Skills valid; Continue rules in sync"
    } else {
        Write-Fail "Skill frontmatter invalid or Continue rules stale — run: node .initium/scripts/sync-skills.mjs"
    }
} else {
    Write-Warn "node not found — cannot validate skills (requires Node.js 22+)"
}

# Workflow docs
Check-Exists "docs/guides/workflows/01-requirements-analysis.md"
Check-Exists "docs/guides/workflows/02-feature-development.md"
Check-Exists "docs/guides/workflows/03-testing-strategy.md"
Check-Exists "docs/guides/workflows/04-deployment.md"
Check-Exists "docs/guides/workflows/05-security-evaluation.md"
Check-Exists "docs/guides/workflows/06-database-migrations.md"
Check-Exists "docs/guides/workflows/07-deployment-platforms.md"
Check-Exists "skills/README.md"

# Context & architecture docs
Check-Exists "docs/context/project-brief.md"
Check-Exists "docs/context/tech-stack.md"
Check-Exists "docs/context/domain-boundaries.md"
Check-Exists "docs/context/domain-glossary.md"
Check-Exists "docs/architecture/overview.md"

# Scripts
Check-Exists ".initium/scripts/setup.sh"
Check-Exists ".initium/scripts/setup.ps1"
Check-Exists ".initium/scripts/setup.cmd"
Check-Exists ".initium/scripts/init.sh"
Check-Exists ".initium/scripts/init.ps1"
Check-Exists ".initium/scripts/init.cmd"

# ---------------------------------------------------------------------------
# Customization checks (look for TODO placeholders)
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "--- Customization (TODO placeholders remaining) ---"

function Check-Customized {
    param($file)
    if (-not (Test-Path $file)) { return }
    $display = $file -replace '/', '\'
    $todoCount = (Select-String -Path $file -Pattern "^TODO|: TODO|TODO:" -ErrorAction SilentlyContinue | Measure-Object).Count
    if ($todoCount -eq 0) {
        Write-Pass "Customized: $display"
    } else {
        Write-Warn "$display has $todoCount TODO(s) remaining"
    }
}

Check-Customized "AGENTS.md"
Check-Customized "SECURITY.md"
Check-Customized ".cursor/rules/00-project-overview.mdc"
Check-Customized "docs/context/project-brief.md"
Check-Customized "docs/context/tech-stack.md"
Check-Customized "docs/context/domain-boundaries.md"
Check-Customized "docs/architecture/overview.md"
Check-Customized "agent.config.yaml"

# ---------------------------------------------------------------------------
# Environment check
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "--- Environment ---"

if (Test-Path ".env") {
    Write-Pass "Found: .env"
} else {
    Write-Warn "Missing .env — copy from .env.example and fill in values"
}

if (Test-Path ".env.example") {
    Write-Pass "Found: .env.example"
} else {
    Write-Warn "Missing .env.example — create one to document required variables"
}

# ---------------------------------------------------------------------------
# Git check
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "--- Git ---"

if (Test-Path ".git") {
    Write-Pass "Git repository initialized"
} else {
    Write-Fail "No git repository — run: git init"
}

$remoteOutput = git remote get-url origin 2>$null
if ($LASTEXITCODE -eq 0 -and $remoteOutput) {
    Write-Pass "Remote origin: $remoteOutput"
} else {
    Write-Warn "No remote origin set — run: git remote add origin <url>"
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "========================================"
Write-Host "  Results"
Write-Host "========================================"
Write-Host "  PASS: $passCount" -ForegroundColor Green
Write-Host "  WARN: $warnCount" -ForegroundColor Yellow
Write-Host "  FAIL: $failCount" -ForegroundColor Red
Write-Host ""

if ($failCount -gt 0) {
    Write-Host "Action required: fix FAIL items before starting development." -ForegroundColor Red
    exit 1
} elseif ($warnCount -gt 0) {
    Write-Host "Warnings present: review WARN items and customize as needed." -ForegroundColor Yellow
    exit 0
} else {
    Write-Host "All checks passed! You're ready to code." -ForegroundColor Green
    exit 0
}
