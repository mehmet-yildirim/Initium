# =============================================================================
# Initium — Interactive Project Initialization Wizard
# (Windows / PowerShell)
# =============================================================================
# Run this after setup.ps1 to configure your project's mechanical settings.
# Handles structured inputs: project name, stack, tracker keys, domain keywords.
# For AI-powered content generation (domain boundaries, architecture docs),
# run /init in Claude Code or @.cursor/prompts/init.md in Cursor afterwards.
#
# Usage:
#   .\.initium\scripts\init.ps1                     # interactive mode
#   .\.initium\scripts\init.ps1 -NonInteractive     # use environment variables (for CI)
#
# If blocked by execution policy, run once as Administrator:
#   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
# =============================================================================

param(
    [switch]$NonInteractive
)

$ErrorActionPreference = 'Stop'

# UTF-8 without BOM writer — avoids encoding issues on both PS 5.1 and PS 7+
$utf8NoBom = New-Object System.Text.UTF8Encoding $false

function Write-Info    { param($msg) Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Ok      { param($msg) Write-Host "[OK]   $msg" -ForegroundColor Green }
function Write-Warn    { param($msg) Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Section { param($msg) Write-Host "`n-- $msg ----------------------------------------" -ForegroundColor Blue }

function Slugify {
    param($str)
    return ($str.ToLower() -replace '[^a-z0-9]', '-' -replace '-+', '-').Trim('-')
}

# Ask a free-text question. Falls back to env var or default in non-interactive mode.
function Ask {
    param($varName, $question, $default = "")
    if ($NonInteractive) {
        $envVal = [System.Environment]::GetEnvironmentVariable($varName)
        if ($envVal) { Set-Variable -Name $varName -Value $envVal -Scope Script; return }
        if ($default) { Set-Variable -Name $varName -Value $default -Scope Script; return }
        Write-Host "ERROR: `$$varName not set and no default available." -ForegroundColor Red; exit 1
    }
    $display = if ($default) { "$question [$default]" } else { $question }
    $input = Read-Host $display
    $value = if ($input) { $input } elseif ($default) { $default } else { "" }
    Set-Variable -Name $varName -Value $value -Scope Script
}

# Present a numbered choice menu. Falls back to env var or first option in non-interactive mode.
function Ask-Choice {
    param($varName, $question, [string[]]$options)
    if ($NonInteractive) {
        $envVal = [System.Environment]::GetEnvironmentVariable($varName)
        if ($envVal) { Set-Variable -Name $varName -Value $envVal -Scope Script; return }
        Set-Variable -Name $varName -Value $options[0] -Scope Script; return
    }
    Write-Host ""
    Write-Host $question -ForegroundColor White
    for ($i = 0; $i -lt $options.Length; $i++) {
        Write-Host "  $($i + 1)) $($options[$i])"
    }
    $raw = Read-Host "Choice [1]"
    $choice = if ($raw) { [int]$raw - 1 } else { 0 }
    if ($choice -lt 0 -or $choice -ge $options.Length) { $choice = 0 }
    Set-Variable -Name $varName -Value $options[$choice] -Scope Script
}

# Replace text in a file (regex pattern). Reads and rewrites the whole file.
function Replace-InFile {
    param($file, [string]$pattern, [string]$replacement)
    if (-not (Test-Path $file)) { return }
    $content = [System.IO.File]::ReadAllText($file)
    $content = [regex]::Replace($content, $pattern, [regex]::Escape($replacement))
    [System.IO.File]::WriteAllText($file, $content, $utf8NoBom)
}

# Replace a literal string in a file (no regex).
function Replace-Literal {
    param($file, [string]$old, [string]$new)
    if (-not (Test-Path $file)) { return }
    $content = [System.IO.File]::ReadAllText($file)
    $content = $content.Replace($old, $new)
    [System.IO.File]::WriteAllText($file, $content, $utf8NoBom)
}

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "============================================================"
Write-Host "  AI-Native Project Initialization Wizard"
Write-Host "============================================================"
Write-Host "  This wizard configures the mechanical project settings."
Write-Host "  Run /init in Claude Code afterwards for AI-powered"
Write-Host "  content generation (domain, architecture, CI steps)."
Write-Host "============================================================"
Write-Host ""

# ---------------------------------------------------------------------------
Write-Section "Project Identity"
# ---------------------------------------------------------------------------

Ask "PROJECT_NAME" "Project name"
while (-not $PROJECT_NAME) {
    Write-Warn "Project name cannot be empty."
    Ask "PROJECT_NAME" "Project name"
}

$PROJECT_SLUG = Slugify $PROJECT_NAME

Ask-Choice "PROJECT_TYPE" "Project type" @(
    "REST API", "GraphQL API", "Web App (full-stack)", "Frontend (SPA)",
    "CLI Tool", "Library / SDK", "Microservice", "Mobile App", "Other"
)

Ask "PROJECT_PURPOSE" "One-sentence description (what it does and for whom)"

# ---------------------------------------------------------------------------
Write-Section "Technology Stack"
# ---------------------------------------------------------------------------

Ask-Choice "PRIMARY_LANGUAGE" "Primary language" @(
    "TypeScript", "Python", "Go", "Java", ".NET / C#", "Kotlin", "Swift", "Dart (Flutter)", "Other"
)

$FRAMEWORK   = ""
$RUNTIME     = ""
$INSTALL_CMD = ""
$TEST_CMD    = ""
$LINT_CMD    = ""
$BUILD_CMD   = ""

switch ($PRIMARY_LANGUAGE) {
    "TypeScript" {
        Ask-Choice "FRAMEWORK" "Framework"  @("Fastify", "Express", "NestJS", "Next.js", "Hono", "Other")
        Ask-Choice "RUNTIME"   "Runtime"    @("Node.js 22", "Bun 1.x", "Deno", "Other")
        $INSTALL_CMD = "bun install"; $TEST_CMD = "bun test"; $LINT_CMD = "bun lint"; $BUILD_CMD = "bun build"
    }
    "Python" {
        Ask-Choice "FRAMEWORK" "Framework"  @("FastAPI", "Django", "Flask", "None (scripts/library)", "Other")
        $RUNTIME = "Python 3.12"
        $INSTALL_CMD = "pip install -e '.[dev]'"; $TEST_CMD = "pytest"; $LINT_CMD = "ruff check ."; $BUILD_CMD = "python -m build"
    }
    "Go" {
        Ask-Choice "FRAMEWORK" "Web framework (if applicable)" @("None (stdlib)", "Gin", "Echo", "Fiber", "Chi")
        $RUNTIME = "Go 1.23"
        $INSTALL_CMD = "go mod tidy"; $TEST_CMD = "go test ./..."; $LINT_CMD = "golangci-lint run"; $BUILD_CMD = "go build ./..."
    }
    "Java" {
        Ask-Choice "FRAMEWORK" "Framework"  @("Spring Boot 3", "Quarkus", "Micronaut", "Plain Java", "Other")
        $RUNTIME = "Java 21"
        $INSTALL_CMD = "mvn install -DskipTests"; $TEST_CMD = "mvn test"; $LINT_CMD = "mvn checkstyle:check"; $BUILD_CMD = "mvn package"
    }
    ".NET / C#" {
        Ask-Choice "FRAMEWORK" "Framework"  @("ASP.NET Core Minimal API", "ASP.NET Core MVC", "Other")
        $RUNTIME = ".NET 8"
        $INSTALL_CMD = "dotnet restore"; $TEST_CMD = "dotnet test"; $LINT_CMD = "dotnet format --verify-no-changes"; $BUILD_CMD = "dotnet build"
    }
    default {
        Ask "FRAMEWORK"   "Framework (leave blank if none)"
        Ask "RUNTIME"     "Runtime / version"
        Ask "INSTALL_CMD" "Install command"
        Ask "TEST_CMD"    "Test command"
        Ask "LINT_CMD"    "Lint command"
        Ask "BUILD_CMD"   "Build command"
    }
}

Ask-Choice "DATABASE" "Database" @(
    "PostgreSQL", "MySQL / MariaDB", "MongoDB", "SQLite", "Redis (primary)", "None", "Other"
)

# ---------------------------------------------------------------------------
Write-Section "Issue Tracker"
# ---------------------------------------------------------------------------

Ask-Choice "TRACKER" "Issue tracker" @(
    "GitHub Issues", "JIRA (cloud)", "JIRA (server / on-prem)", "Linear", "None"
)

$JIRA_URL         = ""
$JIRA_PROJECT_KEY = ""
$LINEAR_TEAM_ID   = ""
$GITHUB_OWNER     = ""
$GITHUB_REPO      = ""
$TRACKER_PROVIDER = "github"

switch -Wildcard ($TRACKER) {
    "GitHub Issues" {
        Ask "GITHUB_OWNER" "GitHub organization or username"
        Ask "GITHUB_REPO"  "GitHub repository name" $PROJECT_SLUG
        $TRACKER_PROVIDER = "github"
    }
    "JIRA*" {
        Ask "JIRA_URL"         "JIRA base URL (e.g. https://mycompany.atlassian.net)"
        Ask "JIRA_PROJECT_KEY" "JIRA project key (e.g. PROJ)"
        Ask "GITHUB_OWNER"     "GitHub organization (for PR/escalation)"
        Ask "GITHUB_REPO"      "GitHub repository name" $PROJECT_SLUG
        $TRACKER_PROVIDER = "jira"
    }
    "Linear" {
        Ask "LINEAR_TEAM_ID" "Linear team ID"
        Ask "GITHUB_OWNER"   "GitHub organization (for PR/escalation)"
        Ask "GITHUB_REPO"    "GitHub repository name" $PROJECT_SLUG
        $TRACKER_PROVIDER = "linear"
    }
    "None" {
        Ask "GITHUB_OWNER" "GitHub organization (used for PRs and escalations)"
        Ask "GITHUB_REPO"  "GitHub repository name" $PROJECT_SLUG
        $TRACKER_PROVIDER = "github"
    }
}

# ---------------------------------------------------------------------------
Write-Section "Escalation & Alerts"
# ---------------------------------------------------------------------------

Ask-Choice "ESCALATION_CHANNEL" "Primary escalation channel" @(
    "Slack", "Email", "GitHub Issues only", "PagerDuty"
)

$SLACK_CHANNEL    = ""
$ESCALATION_EMAIL = ""

switch ($ESCALATION_CHANNEL) {
    "Slack" { Ask "SLACK_CHANNEL"    "Slack channel name (e.g. #dev-alerts)" "#dev-alerts" }
    "Email" { Ask "ESCALATION_EMAIL" "Escalation email address" }
}

# ---------------------------------------------------------------------------
Write-Section "Domain Keywords"
# ---------------------------------------------------------------------------

Write-Host ""
Write-Info "Domain keywords help the autonomous agent classify issues correctly."
Write-Info "Enter comma-separated keywords or leave blank to fill in later."
Write-Host ""

Ask "INCLUDE_KEYWORDS" "In-domain keywords (nouns/verbs for your system's core concepts)"
Ask "EXCLUDE_KEYWORDS" "Out-of-scope keywords (adjacent systems this project does NOT own)"

# ---------------------------------------------------------------------------
Write-Section "Applying Configuration"
# ---------------------------------------------------------------------------

# --- agent.config.yaml ---
if (Test-Path "agent.config.yaml") {
    Write-Info "Updating agent.config.yaml..."

    Replace-Literal "agent.config.yaml" `
        'id: "TODO: my-project-agent"' `
        "id: `"$PROJECT_SLUG-agent`""

    Replace-Literal "agent.config.yaml" `
        'name: "TODO: My Project Dev Agent"' `
        "name: `"$PROJECT_NAME Dev Agent`""

    Replace-Literal "agent.config.yaml" `
        "provider: jira" `
        "provider: $TRACKER_PROVIDER"

    if ($JIRA_PROJECT_KEY) {
        Replace-Literal "agent.config.yaml" 'project_key: "TODO"' "project_key: `"$JIRA_PROJECT_KEY`""
        Replace-Literal "agent.config.yaml" 'project = "TODO"'    "project = `"$JIRA_PROJECT_KEY`""
    }

    if ($JIRA_URL) {
        Replace-Literal "agent.config.yaml" '${JIRA_URL}' $JIRA_URL
    }

    if ($LINEAR_TEAM_ID) {
        Replace-Literal "agent.config.yaml" 'team_id: "TODO"' "team_id: `"$LINEAR_TEAM_ID`""
    }

    if ($GITHUB_OWNER) {
        Replace-Literal "agent.config.yaml" 'owner: "TODO"' "owner: `"$GITHUB_OWNER`""
    }

    if ($GITHUB_REPO) {
        Replace-Literal "agent.config.yaml" 'repo: "TODO"' "repo: `"$GITHUB_REPO`""
    }

    if ($INCLUDE_KEYWORDS) {
        $yamlInclude = ($INCLUDE_KEYWORDS -split '\s*,\s*' | ForEach-Object { "`"$_`"" }) -join ', '
        Replace-Literal "agent.config.yaml" 'strong_include_keywords: []' "strong_include_keywords: [$yamlInclude]"
    }

    if ($EXCLUDE_KEYWORDS) {
        $yamlExclude = ($EXCLUDE_KEYWORDS -split '\s*,\s*' | ForEach-Object { "`"$_`"" }) -join ', '
        Replace-Literal "agent.config.yaml" 'hard_exclude_keywords: []' "hard_exclude_keywords: [$yamlExclude]"
    }

    switch ($ESCALATION_CHANNEL) {
        "Email"              { Replace-Literal "agent.config.yaml" "primary_channel: slack" "primary_channel: email" }
        "GitHub Issues only" { Replace-Literal "agent.config.yaml" "primary_channel: slack" "primary_channel: github-issue" }
    }

    if ($SLACK_CHANNEL) {
        Replace-Literal "agent.config.yaml" 'channel: "#dev-agent-alerts"' "channel: `"$SLACK_CHANNEL`""
    }

    if ($ESCALATION_EMAIL) {
        Replace-Literal "agent.config.yaml" `
            'to: []  # TODO: ["dev-lead@company.com"]' `
            "to: [`"$ESCALATION_EMAIL`"]"
    }

    if ($GITHUB_OWNER) {
        Replace-Literal "agent.config.yaml" `
            'assignees: []  # TODO: ["username"]' `
            "assignees: [`"$GITHUB_OWNER`"]"
    }

    Write-Ok "agent.config.yaml updated."
} else {
    Write-Warn "agent.config.yaml not found — skipping."
}

# --- AGENTS.md ---
if (Test-Path "AGENTS.md") {
    Write-Info "Updating AGENTS.md..."
    Replace-Literal "AGENTS.md" "TODO: Project Name"                                                      $PROJECT_NAME
    Replace-Literal "AGENTS.md" "TODO: e.g., REST API / Web App / CLI Tool / Library"                    $PROJECT_TYPE
    Replace-Literal "AGENTS.md" "TODO: One or two sentences describing what this project does and for whom." $PROJECT_PURPOSE
    Replace-Literal "AGENTS.md" "TODO: e.g., TypeScript, Python, Go"                                     $PRIMARY_LANGUAGE
    Replace-Literal "AGENTS.md" "TODO: e.g., bun install / pip install -e `".[dev]`" / go mod tidy"      $INSTALL_CMD
    Replace-Literal "AGENTS.md" "TODO: e.g., bun test / pytest / go test ./..."                          $TEST_CMD
    Replace-Literal "AGENTS.md" "TODO: e.g., bun lint / ruff check . / golangci-lint run"                $LINT_CMD
    Replace-Literal "AGENTS.md" "TODO: e.g., bun build / python -m build / go build ./..."               $BUILD_CMD
    if ($FRAMEWORK) { Replace-Literal "AGENTS.md" "TODO: e.g., Next.js 14, FastAPI, Gin" $FRAMEWORK }
    if ($RUNTIME)   { Replace-Literal "AGENTS.md" "TODO: e.g., Node.js 22, Python 3.12, Go 1.23"  $RUNTIME }
    Write-Ok "AGENTS.md updated."
}

# --- .cursor/rules/00-project-overview.mdc ---
if (Test-Path ".cursor/rules/00-project-overview.mdc") {
    Write-Info "Updating .cursor\rules\00-project-overview.mdc..."
    Replace-Literal ".cursor/rules/00-project-overview.mdc" "TODO: Project Name" $PROJECT_NAME
    Replace-Literal ".cursor/rules/00-project-overview.mdc" `
        "TODO: e.g., SaaS web app / internal tool / open-source library / CLI" `
        $PROJECT_TYPE
    if ($PROJECT_PURPOSE) {
        # Replace the purpose placeholder line (may contain trailing context)
        $content = [System.IO.File]::ReadAllText(".cursor/rules/00-project-overview.mdc")
        $content = [regex]::Replace(
            $content,
            "TODO: Describe what the project does and who uses it[^`n]*",
            $PROJECT_PURPOSE
        )
        [System.IO.File]::WriteAllText(".cursor/rules/00-project-overview.mdc", $content, $utf8NoBom)
    }
    Write-Ok ".cursor\rules\00-project-overview.mdc updated."
}

# --- Write .project-config.yaml for AI tools to reference ---
Write-Info "Writing .project-config.yaml..."

$projectConfigContent = @"
# =============================================================================
# .project-config.yaml -- Machine-readable project configuration
# Generated by .initium/scripts/init.ps1 -- do not edit manually; re-run init.ps1 to update
# =============================================================================
project:
  name: "$PROJECT_NAME"
  slug: "$PROJECT_SLUG"
  type: "$PROJECT_TYPE"
  purpose: "$PROJECT_PURPOSE"

stack:
  language: "$PRIMARY_LANGUAGE"
  framework: "$FRAMEWORK"
  runtime: "$RUNTIME"
  database: "$DATABASE"
  commands:
    install: "$INSTALL_CMD"
    test: "$TEST_CMD"
    lint: "$LINT_CMD"
    build: "$BUILD_CMD"

tracker:
  provider: "$TRACKER_PROVIDER"
  jira_url: "$JIRA_URL"
  jira_project_key: "$JIRA_PROJECT_KEY"
  linear_team_id: "$LINEAR_TEAM_ID"
  github_owner: "$GITHUB_OWNER"
  github_repo: "$GITHUB_REPO"

domain:
  include_keywords: "$INCLUDE_KEYWORDS"
  exclude_keywords: "$EXCLUDE_KEYWORDS"

escalation:
  channel: "$ESCALATION_CHANNEL"
  slack_channel: "$SLACK_CHANNEL"
  email: "$ESCALATION_EMAIL"
"@

[System.IO.File]::WriteAllText(".project-config.yaml", $projectConfigContent, $utf8NoBom)
Write-Ok ".project-config.yaml written."

# ---------------------------------------------------------------------------
Write-Section "Summary"
# ---------------------------------------------------------------------------

Write-Host ""
Write-Host "Project configured: $PROJECT_NAME" -ForegroundColor Green
Write-Host ""
Write-Host "  Updated files:"
Write-Host "    [OK] agent.config.yaml"
Write-Host "    [OK] AGENTS.md"
Write-Host "    [OK] .cursor\rules\00-project-overview.mdc"
Write-Host "    [OK] .project-config.yaml (reference for AI tools)"
Write-Host ""
Write-Host "  Not yet populated (run AI command below):"
Write-Host "    [!]  docs\context\project-brief.md"
Write-Host "    [!]  docs\context\domain-boundaries.md  <- critical for autonomous agent"
Write-Host "    [!]  docs\context\domain-glossary.md"
Write-Host "    [!]  docs\context\tech-stack.md"
Write-Host "    [!]  docs\architecture\overview.md"
Write-Host "    [!]  .github\workflows\ci.yml"
Write-Host ""
Write-Host "Next step -- AI-powered initialization:" -ForegroundColor Cyan
Write-Host ""
Write-Host "  In Claude Code:   /init $PROJECT_NAME -- $PROJECT_PURPOSE"
Write-Host "  In Cursor:        @.cursor/prompts/init.md"
Write-Host "                    (then describe your project in the message)"
Write-Host ""
Write-Host "  Or target specific sections:"
Write-Host "  /init domain: <describe what your system manages and for whom>"
Write-Host "  /init stack: $PRIMARY_LANGUAGE, $FRAMEWORK, $DATABASE"
Write-Host "  /init ci: <describe your deployment target and pipeline>"
Write-Host ""
Write-Host "Then validate: .\.initium\scripts\validate.ps1" -ForegroundColor Cyan
Write-Host ""
