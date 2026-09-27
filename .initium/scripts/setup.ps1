# =============================================================================
# Initium — Project Setup Script (Windows / PowerShell)
# =============================================================================
# Run this once after cloning Initium to initialize your project.
# Requires PowerShell 5.1+ (built-in on Windows 10/11) or PowerShell 7+.
#
# Usage:
#   .\.initium\scripts\setup.ps1
#
# If blocked by execution policy, run once as Administrator:
#   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
# =============================================================================

$ErrorActionPreference = 'Stop'

function Write-Info    { param($msg) Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Ok      { param($msg) Write-Host "[OK]   $msg" -ForegroundColor Green }
function Write-Warn    { param($msg) Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Err     { param($msg) Write-Host "[ERROR] $msg" -ForegroundColor Red; exit 1 }

Write-Host ""
Write-Host "========================================"
Write-Host "  AI-Native Project Setup"
Write-Host "========================================"
Write-Host ""

# ---------------------------------------------------------------------------
# 1. Initialize git repository (if not already a repo)
# ---------------------------------------------------------------------------
if (-not (Test-Path ".git")) {
    Write-Info "Initializing git repository..."
    git init
    Write-Ok "Git repository initialized."
} else {
    Write-Info "Git repository already exists, skipping init."
}

# ---------------------------------------------------------------------------
# 2. Remove Initium remote origin (if inherited from clone)
# ---------------------------------------------------------------------------
$remoteOutput = git remote get-url origin 2>$null
if ($LASTEXITCODE -eq 0 -and $remoteOutput -match "Initium") {
    Write-Warn "Removing Initium remote origin: $remoteOutput"
    git remote remove origin
    Write-Ok "Removed Initium remote. Add your own with: git remote add origin <url>"
}

# ---------------------------------------------------------------------------
# 2a. Enable the guardrail pre-commit hook (.githooks/pre-commit)
# ---------------------------------------------------------------------------
$hooksPath = git config --get core.hooksPath 2>$null
if (-not $hooksPath) {
    git config core.hooksPath .githooks
    Write-Ok "Guardrail pre-commit hook enabled (core.hooksPath=.githooks)."
} elseif ($hooksPath -eq ".githooks") {
    Write-Info "Guardrail pre-commit hook already enabled."
} else {
    Write-Warn "core.hooksPath is '$hooksPath' (e.g. husky). Call 'sh .githooks/pre-commit' from your pre-commit hook to keep guardrails."
}

# ---------------------------------------------------------------------------
# 3. Create .env from .env.example if it doesn't exist
# ---------------------------------------------------------------------------
if ((Test-Path ".env.example") -and (-not (Test-Path ".env"))) {
    Write-Info "Creating .env from .env.example..."
    Copy-Item ".env.example" ".env"
    Write-Ok "Created .env — fill in your values before starting development."
} elseif (-not (Test-Path ".env.example")) {
    Write-Warn "No .env.example found. Create one with your required environment variables."
} else {
    Write-Info ".env already exists, skipping."
}

# ---------------------------------------------------------------------------
# 4. Validate required AI tool configurations
# ---------------------------------------------------------------------------
Write-Info "Checking AI tool configuration files..."

$missingConfig = $false

function Check-File {
    param($file, $label)
    if (Test-Path $file) {
        Write-Ok "${label}: $file"
    } else {
        Write-Warn "${label} not found: $file"
        $script:missingConfig = $true
    }
}

Check-File "AGENTS.md"                               "Agent instructions (all tools)"
Check-File "CLAUDE.md"                               "Claude Code import of AGENTS.md"
Check-File ".cursor\rules\00-project-overview.mdc"   "Cursor project overview"
Check-File ".continue\config.yaml"                   "Continue config"

if ($missingConfig) {
    Write-Warn "Some AI config files are missing. Run: .\.initium\scripts\validate.ps1"
}

# ---------------------------------------------------------------------------
# 5. Remind about customization
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "========================================"
Write-Host "  Next Steps"
Write-Host "========================================"
Write-Host ""
Write-Host "  STEP 1 - Run the initialization wizard:"
Write-Host "  .\.initium\scripts\init.ps1"
Write-Host "  (configures project name, stack, tracker, and domain keywords)"
Write-Host ""
Write-Host "  STEP 2 - AI-powered content generation:"
Write-Host "  Open Claude Code and run:  /init <describe your project>"
Write-Host "  Or in Cursor:              @.cursor/prompts/init.md"
Write-Host ""
Write-Host "  This populates:"
Write-Host "    * AGENTS.md, docs\context\, docs\architecture\overview.md"
Write-Host "    * agent.config.yaml domain keywords"
Write-Host "    * .github\workflows\ci.yml  (use: /init ci: <your stack>)"
Write-Host ""
Write-Host "  STEP 3 - Finish setup:"
Write-Host "  * Edit .continue\config.yaml (add API keys)"
Write-Host "  * Add git remote:  git remote add origin <url>"
Write-Host "  * Install dependencies: [from AGENTS.md after /init]"
Write-Host "  * Validate: .\.initium\scripts\validate.ps1"
Write-Host "  * Read the AI workflow: docs\ai-workflow.md"
Write-Host ""
Write-Host "  AI commands available in Claude Code (type / to invoke):"
Write-Host "  /init       - populate all TODO files from your project description"
Write-Host "  /architect  - design a feature before implementing"
Write-Host "  /review     - review code for issues"
Write-Host "  /test       - generate tests"
Write-Host "  /debug      - systematic debugging"
Write-Host ""

Write-Ok "Setup complete!"
