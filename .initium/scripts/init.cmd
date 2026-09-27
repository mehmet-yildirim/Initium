@echo off
:: =============================================================================
:: Initium -- Interactive Project Initialization Wizard
:: (Windows Batch)
:: =============================================================================
:: Run this after setup.cmd to configure your project's mechanical settings.
:: No special permissions required -- runs on any Windows system.
::
:: File replacements use inline PowerShell (-Command flag, NOT a .ps1 file),
:: which is not subject to execution policy restrictions.
::
:: Usage:
::   .initium\scripts\init.cmd
:: =============================================================================

setlocal enabledelayedexpansion

echo.
echo ============================================================
echo   AI-Native Project Initialization Wizard
echo ============================================================
echo   This wizard configures the mechanical project settings.
echo   Run /init in Claude Code afterwards for AI-powered
echo   content generation (domain, architecture, CI steps).
echo ============================================================
echo.

:: ---------------------------------------------------------------------------
:: PROJECT IDENTITY
:: ---------------------------------------------------------------------------
echo.
echo -- Project Identity ----------------------------------------
echo.

:ask_project_name
set /p "PROJECT_NAME=Project name: "
if "!PROJECT_NAME!"=="" (
    echo [WARN] Project name cannot be empty.
    goto ask_project_name
)

:: Slugify: lowercase, replace non-alphanumeric with dash, collapse dashes
for /f "delims=" %%S in ('powershell -NoProfile -Command "('!PROJECT_NAME!'.ToLower() -replace '[^a-z0-9]','-' -replace '-+','-').Trim('-')"') do set "PROJECT_SLUG=%%S"

echo.
echo Project type:
echo   1) REST API
echo   2) GraphQL API
echo   3) Web App (full-stack)
echo   4) Frontend (SPA)
echo   5) CLI Tool
echo   6) Library / SDK
echo   7) Microservice
echo   8) Mobile App
echo   9) Other
set /p "PT_CHOICE=Choice [1]: "
if "!PT_CHOICE!"=="" set PT_CHOICE=1
if "!PT_CHOICE!"=="1" set "PROJECT_TYPE=REST API"
if "!PT_CHOICE!"=="2" set "PROJECT_TYPE=GraphQL API"
if "!PT_CHOICE!"=="3" set "PROJECT_TYPE=Web App (full-stack)"
if "!PT_CHOICE!"=="4" set "PROJECT_TYPE=Frontend (SPA)"
if "!PT_CHOICE!"=="5" set "PROJECT_TYPE=CLI Tool"
if "!PT_CHOICE!"=="6" set "PROJECT_TYPE=Library / SDK"
if "!PT_CHOICE!"=="7" set "PROJECT_TYPE=Microservice"
if "!PT_CHOICE!"=="8" set "PROJECT_TYPE=Mobile App"
if "!PT_CHOICE!"=="9" set "PROJECT_TYPE=Other"
if not defined PROJECT_TYPE set "PROJECT_TYPE=REST API"

echo.
set /p "PROJECT_PURPOSE=One-sentence description (what it does and for whom): "

:: ---------------------------------------------------------------------------
:: TECHNOLOGY STACK
:: ---------------------------------------------------------------------------
echo.
echo -- Technology Stack ----------------------------------------
echo.
echo Primary language:
echo   1) TypeScript
echo   2) Python
echo   3) Go
echo   4) Java
echo   5) .NET / C#
echo   6) Kotlin
echo   7) Swift
echo   8) Dart (Flutter)
echo   9) Other
set /p "LANG_CHOICE=Choice [1]: "
if "!LANG_CHOICE!"=="" set LANG_CHOICE=1
if "!LANG_CHOICE!"=="1" set "PRIMARY_LANGUAGE=TypeScript"
if "!LANG_CHOICE!"=="2" set "PRIMARY_LANGUAGE=Python"
if "!LANG_CHOICE!"=="3" set "PRIMARY_LANGUAGE=Go"
if "!LANG_CHOICE!"=="4" set "PRIMARY_LANGUAGE=Java"
if "!LANG_CHOICE!"=="5" set "PRIMARY_LANGUAGE=.NET / C#"
if "!LANG_CHOICE!"=="6" set "PRIMARY_LANGUAGE=Kotlin"
if "!LANG_CHOICE!"=="7" set "PRIMARY_LANGUAGE=Swift"
if "!LANG_CHOICE!"=="8" set "PRIMARY_LANGUAGE=Dart (Flutter)"
if "!LANG_CHOICE!"=="9" set "PRIMARY_LANGUAGE=Other"
if not defined PRIMARY_LANGUAGE set "PRIMARY_LANGUAGE=TypeScript"

set FRAMEWORK=
set RUNTIME=
set INSTALL_CMD=
set TEST_CMD=
set LINT_CMD=
set BUILD_CMD=

if "!PRIMARY_LANGUAGE!"=="TypeScript" (
    echo.
    echo Framework:
    echo   1) Fastify  2) Express  3) NestJS  4) Next.js  5) Hono  6) Other
    set /p "FW_CHOICE=Choice [1]: "
    if "!FW_CHOICE!"=="" set FW_CHOICE=1
    if "!FW_CHOICE!"=="1" set FRAMEWORK=Fastify
    if "!FW_CHOICE!"=="2" set FRAMEWORK=Express
    if "!FW_CHOICE!"=="3" set FRAMEWORK=NestJS
    if "!FW_CHOICE!"=="4" set FRAMEWORK=Next.js
    if "!FW_CHOICE!"=="5" set FRAMEWORK=Hono
    if "!FW_CHOICE!"=="6" set FRAMEWORK=Other
    if not defined FRAMEWORK set FRAMEWORK=Fastify
    echo.
    echo Runtime:
    echo   1) Node.js 22  2) Bun 1.x  3) Deno  4) Other
    set /p "RT_CHOICE=Choice [1]: "
    if "!RT_CHOICE!"=="" set RT_CHOICE=1
    if "!RT_CHOICE!"=="1" set RUNTIME=Node.js 22
    if "!RT_CHOICE!"=="2" set RUNTIME=Bun 1.x
    if "!RT_CHOICE!"=="3" set RUNTIME=Deno
    if "!RT_CHOICE!"=="4" set RUNTIME=Other
    if not defined RUNTIME set "RUNTIME=Node.js 22"
    set INSTALL_CMD=bun install& set TEST_CMD=bun test& set LINT_CMD=bun lint& set BUILD_CMD=bun build
)

if "!PRIMARY_LANGUAGE!"=="Python" (
    echo.
    echo Framework:
    echo   1) FastAPI  2) Django  3) Flask  4) None (scripts/library)  5) Other
    set /p "FW_CHOICE=Choice [1]: "
    if "!FW_CHOICE!"=="" set FW_CHOICE=1
    if "!FW_CHOICE!"=="1" set FRAMEWORK=FastAPI
    if "!FW_CHOICE!"=="2" set FRAMEWORK=Django
    if "!FW_CHOICE!"=="3" set FRAMEWORK=Flask
    if "!FW_CHOICE!"=="4" set "FRAMEWORK=None"
    if "!FW_CHOICE!"=="5" set FRAMEWORK=Other
    if not defined FRAMEWORK set FRAMEWORK=FastAPI
    set "RUNTIME=Python 3.12"
    set "INSTALL_CMD=pip install -e .[dev]"& set TEST_CMD=pytest& set "LINT_CMD=ruff check ."& set "BUILD_CMD=python -m build"
)

if "!PRIMARY_LANGUAGE!"=="Go" (
    echo.
    echo Web framework:
    echo   1) None (stdlib)  2) Gin  3) Echo  4) Fiber  5) Chi
    set /p "FW_CHOICE=Choice [1]: "
    if "!FW_CHOICE!"=="" set FW_CHOICE=1
    if "!FW_CHOICE!"=="1" set "FRAMEWORK=None (stdlib)"
    if "!FW_CHOICE!"=="2" set FRAMEWORK=Gin
    if "!FW_CHOICE!"=="3" set FRAMEWORK=Echo
    if "!FW_CHOICE!"=="4" set FRAMEWORK=Fiber
    if "!FW_CHOICE!"=="5" set FRAMEWORK=Chi
    if not defined FRAMEWORK set "FRAMEWORK=None (stdlib)"
    set "RUNTIME=Go 1.23"
    set "INSTALL_CMD=go mod tidy"& set "TEST_CMD=go test ./..."& set "LINT_CMD=golangci-lint run"& set "BUILD_CMD=go build ./..."
)

if "!PRIMARY_LANGUAGE!"=="Java" (
    echo.
    echo Framework:
    echo   1) Spring Boot 3  2) Quarkus  3) Micronaut  4) Plain Java  5) Other
    set /p "FW_CHOICE=Choice [1]: "
    if "!FW_CHOICE!"=="" set FW_CHOICE=1
    if "!FW_CHOICE!"=="1" set "FRAMEWORK=Spring Boot 3"
    if "!FW_CHOICE!"=="2" set FRAMEWORK=Quarkus
    if "!FW_CHOICE!"=="3" set FRAMEWORK=Micronaut
    if "!FW_CHOICE!"=="4" set "FRAMEWORK=Plain Java"
    if "!FW_CHOICE!"=="5" set FRAMEWORK=Other
    if not defined FRAMEWORK set "FRAMEWORK=Spring Boot 3"
    set "RUNTIME=Java 21"
    set "INSTALL_CMD=mvn install -DskipTests"& set "TEST_CMD=mvn test"& set "LINT_CMD=mvn checkstyle:check"& set "BUILD_CMD=mvn package"
)

if "!PRIMARY_LANGUAGE!"==".NET / C#" (
    echo.
    echo Framework:
    echo   1) ASP.NET Core Minimal API  2) ASP.NET Core MVC  3) Other
    set /p "FW_CHOICE=Choice [1]: "
    if "!FW_CHOICE!"=="" set FW_CHOICE=1
    if "!FW_CHOICE!"=="1" set "FRAMEWORK=ASP.NET Core Minimal API"
    if "!FW_CHOICE!"=="2" set "FRAMEWORK=ASP.NET Core MVC"
    if "!FW_CHOICE!"=="3" set FRAMEWORK=Other
    if not defined FRAMEWORK set "FRAMEWORK=ASP.NET Core Minimal API"
    set "RUNTIME=.NET 8"
    set "INSTALL_CMD=dotnet restore"& set "TEST_CMD=dotnet test"& set "LINT_CMD=dotnet format --verify-no-changes"& set "BUILD_CMD=dotnet build"
)

if not defined FRAMEWORK (
    set /p "FRAMEWORK=Framework (leave blank if none): "
    set /p "RUNTIME=Runtime / version: "
    set /p "INSTALL_CMD=Install command: "
    set /p "TEST_CMD=Test command: "
    set /p "LINT_CMD=Lint command: "
    set /p "BUILD_CMD=Build command: "
)

echo.
echo Database:
echo   1) PostgreSQL  2) MySQL / MariaDB  3) MongoDB
echo   4) SQLite      5) Redis (primary)  6) None  7) Other
set /p "DB_CHOICE=Choice [1]: "
if "!DB_CHOICE!"=="" set DB_CHOICE=1
if "!DB_CHOICE!"=="1" set DATABASE=PostgreSQL
if "!DB_CHOICE!"=="2" set "DATABASE=MySQL / MariaDB"
if "!DB_CHOICE!"=="3" set DATABASE=MongoDB
if "!DB_CHOICE!"=="4" set DATABASE=SQLite
if "!DB_CHOICE!"=="5" set "DATABASE=Redis (primary)"
if "!DB_CHOICE!"=="6" set DATABASE=None
if "!DB_CHOICE!"=="7" set DATABASE=Other
if not defined DATABASE set DATABASE=PostgreSQL

:: ---------------------------------------------------------------------------
:: ISSUE TRACKER
:: ---------------------------------------------------------------------------
echo.
echo -- Issue Tracker -------------------------------------------
echo.
echo Issue tracker:
echo   1) GitHub Issues  2) JIRA (cloud)  3) JIRA (server / on-prem)
echo   4) Linear         5) None
set /p "TR_CHOICE=Choice [1]: "
if "!TR_CHOICE!"=="" set TR_CHOICE=1

set JIRA_URL=
set JIRA_PROJECT_KEY=
set LINEAR_TEAM_ID=
set GITHUB_OWNER=
set GITHUB_REPO=
set TRACKER_PROVIDER=github

if "!TR_CHOICE!"=="1" (
    set TRACKER=GitHub Issues
    echo.
    set /p "GITHUB_OWNER=GitHub organization or username: "
    set /p "GITHUB_REPO=GitHub repository name [!PROJECT_SLUG!]: "
    if "!GITHUB_REPO!"=="" set GITHUB_REPO=!PROJECT_SLUG!
)
if "!TR_CHOICE!"=="2" (
    set "TRACKER=JIRA (cloud)"
    set TRACKER_PROVIDER=jira
    echo.
    set /p "JIRA_URL=JIRA base URL (e.g. https://mycompany.atlassian.net): "
    set /p "JIRA_PROJECT_KEY=JIRA project key (e.g. PROJ): "
    set /p "GITHUB_OWNER=GitHub organization (for PR/escalation): "
    set /p "GITHUB_REPO=GitHub repository name [!PROJECT_SLUG!]: "
    if "!GITHUB_REPO!"=="" set GITHUB_REPO=!PROJECT_SLUG!
)
if "!TR_CHOICE!"=="3" (
    set "TRACKER=JIRA (server / on-prem)"
    set TRACKER_PROVIDER=jira
    echo.
    set /p "JIRA_URL=JIRA base URL (e.g. https://jira.mycompany.com): "
    set /p "JIRA_PROJECT_KEY=JIRA project key (e.g. PROJ): "
    set /p "GITHUB_OWNER=GitHub organization (for PR/escalation): "
    set /p "GITHUB_REPO=GitHub repository name [!PROJECT_SLUG!]: "
    if "!GITHUB_REPO!"=="" set GITHUB_REPO=!PROJECT_SLUG!
)
if "!TR_CHOICE!"=="4" (
    set TRACKER=Linear
    set TRACKER_PROVIDER=linear
    echo.
    set /p "LINEAR_TEAM_ID=Linear team ID: "
    set /p "GITHUB_OWNER=GitHub organization (for PR/escalation): "
    set /p "GITHUB_REPO=GitHub repository name [!PROJECT_SLUG!]: "
    if "!GITHUB_REPO!"=="" set GITHUB_REPO=!PROJECT_SLUG!
)
if "!TR_CHOICE!"=="5" (
    set TRACKER=None
    echo.
    set /p "GITHUB_OWNER=GitHub organization (used for PRs and escalations): "
    set /p "GITHUB_REPO=GitHub repository name [!PROJECT_SLUG!]: "
    if "!GITHUB_REPO!"=="" set GITHUB_REPO=!PROJECT_SLUG!
)
if not defined TRACKER set "TRACKER=GitHub Issues"

:: ---------------------------------------------------------------------------
:: ESCALATION & ALERTS
:: ---------------------------------------------------------------------------
echo.
echo -- Escalation and Alerts -----------------------------------
echo.
echo Primary escalation channel:
echo   1) Slack  2) Email  3) GitHub Issues only  4) PagerDuty
set /p "ESC_CHOICE=Choice [1]: "
if "!ESC_CHOICE!"=="" set ESC_CHOICE=1

set SLACK_CHANNEL=
set ESCALATION_EMAIL=

if "!ESC_CHOICE!"=="1" (
    set ESCALATION_CHANNEL=Slack
    echo.
    set /p "SLACK_CHANNEL=Slack channel name [#dev-alerts]: "
    if "!SLACK_CHANNEL!"=="" set SLACK_CHANNEL=#dev-alerts
)
if "!ESC_CHOICE!"=="2" (
    set ESCALATION_CHANNEL=Email
    echo.
    set /p "ESCALATION_EMAIL=Escalation email address: "
)
if "!ESC_CHOICE!"=="3" set "ESCALATION_CHANNEL=GitHub Issues only"
if "!ESC_CHOICE!"=="4" set ESCALATION_CHANNEL=PagerDuty
if not defined ESCALATION_CHANNEL set ESCALATION_CHANNEL=Slack

:: ---------------------------------------------------------------------------
:: DOMAIN KEYWORDS
:: ---------------------------------------------------------------------------
echo.
echo -- Domain Keywords -----------------------------------------
echo.
echo Domain keywords help the autonomous agent classify issues correctly.
echo Enter comma-separated keywords or leave blank to fill in later.
echo.
set /p "INCLUDE_KEYWORDS=In-domain keywords (core concepts of your system): "
set /p "EXCLUDE_KEYWORDS=Out-of-scope keywords (adjacent systems this project does NOT own): "

:: ---------------------------------------------------------------------------
:: APPLY CONFIGURATION
:: ---------------------------------------------------------------------------
echo.
echo -- Applying Configuration ----------------------------------
echo.

:: --- agent.config.yaml ---
if exist "agent.config.yaml" (
    echo [INFO] Updating agent.config.yaml...

    set "REPLACE_FILE=agent.config.yaml"

    set "REPLACE_OLD=id: "TODO: my-project-agent""
    set "REPLACE_NEW=id: "!PROJECT_SLUG!-agent""
    call :replace_literal

    set "REPLACE_OLD=name: "TODO: My Project Dev Agent""
    set "REPLACE_NEW=name: "!PROJECT_NAME! Dev Agent""
    call :replace_literal

    set "REPLACE_OLD=provider: jira"
    set "REPLACE_NEW=provider: !TRACKER_PROVIDER!"
    call :replace_literal

    if defined JIRA_PROJECT_KEY (
        set "REPLACE_OLD=project_key: "TODO""
        set "REPLACE_NEW=project_key: "!JIRA_PROJECT_KEY!""
        call :replace_literal

        set "REPLACE_OLD=project = "TODO""
        set "REPLACE_NEW=project = "!JIRA_PROJECT_KEY!""
        call :replace_literal
    )

    if defined JIRA_URL (
        set "REPLACE_OLD=${JIRA_URL}"
        set "REPLACE_NEW=!JIRA_URL!"
        call :replace_literal
    )

    if defined LINEAR_TEAM_ID (
        set "REPLACE_OLD=team_id: "TODO""
        set "REPLACE_NEW=team_id: "!LINEAR_TEAM_ID!""
        call :replace_literal
    )

    if defined GITHUB_OWNER (
        set "REPLACE_OLD=owner: "TODO""
        set "REPLACE_NEW=owner: "!GITHUB_OWNER!""
        call :replace_literal

        set "REPLACE_OLD=assignees: []  # TODO: ["username"]"
        set "REPLACE_NEW=assignees: ["!GITHUB_OWNER!"]"
        call :replace_literal
    )

    if defined GITHUB_REPO (
        set "REPLACE_OLD=repo: "TODO""
        set "REPLACE_NEW=repo: "!GITHUB_REPO!""
        call :replace_literal
    )

    if defined INCLUDE_KEYWORDS (
        for /f "delims=" %%K in ('powershell -NoProfile -Command "('!INCLUDE_KEYWORDS!' -split '\s*,\s*' | ForEach-Object { '\"{0}\"' -f $_ }) -join ', '"') do set YAML_INCLUDE=%%K
        set "REPLACE_OLD=strong_include_keywords: []"
        set "REPLACE_NEW=strong_include_keywords: [!YAML_INCLUDE!]"
        call :replace_literal
    )

    if defined EXCLUDE_KEYWORDS (
        for /f "delims=" %%K in ('powershell -NoProfile -Command "('!EXCLUDE_KEYWORDS!' -split '\s*,\s*' | ForEach-Object { '\"{0}\"' -f $_ }) -join ', '"') do set YAML_EXCLUDE=%%K
        set "REPLACE_OLD=hard_exclude_keywords: []"
        set "REPLACE_NEW=hard_exclude_keywords: [!YAML_EXCLUDE!]"
        call :replace_literal
    )

    if "!ESCALATION_CHANNEL!"=="Email" (
        set "REPLACE_OLD=primary_channel: slack"
        set "REPLACE_NEW=primary_channel: email"
        call :replace_literal
    )
    if "!ESCALATION_CHANNEL!"=="GitHub Issues only" (
        set "REPLACE_OLD=primary_channel: slack"
        set "REPLACE_NEW=primary_channel: github-issue"
        call :replace_literal
    )

    if defined SLACK_CHANNEL (
        set "REPLACE_OLD=channel: "#dev-agent-alerts""
        set "REPLACE_NEW=channel: "!SLACK_CHANNEL!""
        call :replace_literal
    )

    if defined ESCALATION_EMAIL (
        set "REPLACE_OLD=to: []  # TODO: ["dev-lead@company.com"]"
        set "REPLACE_NEW=to: ["!ESCALATION_EMAIL!"]"
        call :replace_literal
    )

    echo [OK]   agent.config.yaml updated.
) else (
    echo [WARN] agent.config.yaml not found -- skipping.
)

:: --- AGENTS.md ---
if exist "AGENTS.md" (
    echo [INFO] Updating AGENTS.md...
    set "REPLACE_FILE=AGENTS.md"

    set "REPLACE_OLD=TODO: Project Name"
    set "REPLACE_NEW=!PROJECT_NAME!"
    call :replace_literal

    set "REPLACE_OLD=TODO: e.g., REST API / Web App / CLI Tool / Library"
    set "REPLACE_NEW=!PROJECT_TYPE!"
    call :replace_literal

    set "REPLACE_OLD=TODO: One or two sentences describing what this project does and for whom."
    set "REPLACE_NEW=!PROJECT_PURPOSE!"
    call :replace_literal

    set "REPLACE_OLD=TODO: e.g., TypeScript, Python, Go"
    set "REPLACE_NEW=!PRIMARY_LANGUAGE!"
    call :replace_literal

    if defined FRAMEWORK (
        set "REPLACE_OLD=TODO: e.g., Next.js 14, FastAPI, Gin"
        set "REPLACE_NEW=!FRAMEWORK!"
        call :replace_literal
    )
    if defined RUNTIME (
        set "REPLACE_OLD=TODO: e.g., Node.js 22, Python 3.12, Go 1.23"
        set "REPLACE_NEW=!RUNTIME!"
        call :replace_literal
    )
    if defined INSTALL_CMD (
        set "REPLACE_OLD=TODO: e.g., bun install / pip install -e ".[dev]" / go mod tidy"
        set "REPLACE_NEW=!INSTALL_CMD!"
        call :replace_literal
    )
    if defined TEST_CMD (
        set "REPLACE_OLD=TODO: e.g., bun test / pytest / go test ./..."
        set "REPLACE_NEW=!TEST_CMD!"
        call :replace_literal
    )
    if defined LINT_CMD (
        set "REPLACE_OLD=TODO: e.g., bun lint / ruff check . / golangci-lint run"
        set "REPLACE_NEW=!LINT_CMD!"
        call :replace_literal
    )
    if defined BUILD_CMD (
        set "REPLACE_OLD=TODO: e.g., bun build / python -m build / go build ./..."
        set "REPLACE_NEW=!BUILD_CMD!"
        call :replace_literal
    )

    echo [OK]   AGENTS.md updated.
)

:: --- .cursor/rules/00-project-overview.mdc ---
if exist ".cursor\rules\00-project-overview.mdc" (
    echo [INFO] Updating .cursor\rules\00-project-overview.mdc...
    set "REPLACE_FILE=.cursor\rules\00-project-overview.mdc"

    set "REPLACE_OLD=TODO: Project Name"
    set "REPLACE_NEW=!PROJECT_NAME!"
    call :replace_literal

    set "REPLACE_OLD=TODO: e.g., SaaS web app / internal tool / open-source library / CLI"
    set "REPLACE_NEW=!PROJECT_TYPE!"
    call :replace_literal

    if defined PROJECT_PURPOSE (
        :: Replace the purpose line (may have trailing context) using a regex via PowerShell
        powershell -NoProfile -Command "$f='.cursor/rules/00-project-overview.mdc'; $c=[IO.File]::ReadAllText($f); $c=[regex]::Replace($c,'TODO: Describe what the project does and who uses it[^\n]*','%PROJECT_PURPOSE%'); [IO.File]::WriteAllText($f,$c,[Text.UTF8Encoding]::new($false))"
    )

    echo [OK]   .cursor\rules\00-project-overview.mdc updated.
)

:: --- Write .project-config.yaml ---
echo [INFO] Writing .project-config.yaml...

(
echo # =============================================================================
echo # .project-config.yaml -- Machine-readable project configuration
echo # Generated by .initium/scripts/init.cmd -- do not edit manually; re-run init.cmd to update
echo # =============================================================================
echo project:
echo   name: "!PROJECT_NAME!"
echo   slug: "!PROJECT_SLUG!"
echo   type: "!PROJECT_TYPE!"
echo   purpose: "!PROJECT_PURPOSE!"
echo.
echo stack:
echo   language: "!PRIMARY_LANGUAGE!"
echo   framework: "!FRAMEWORK!"
echo   runtime: "!RUNTIME!"
echo   database: "!DATABASE!"
echo   commands:
echo     install: "!INSTALL_CMD!"
echo     test: "!TEST_CMD!"
echo     lint: "!LINT_CMD!"
echo     build: "!BUILD_CMD!"
echo.
echo tracker:
echo   provider: "!TRACKER_PROVIDER!"
echo   jira_url: "!JIRA_URL!"
echo   jira_project_key: "!JIRA_PROJECT_KEY!"
echo   linear_team_id: "!LINEAR_TEAM_ID!"
echo   github_owner: "!GITHUB_OWNER!"
echo   github_repo: "!GITHUB_REPO!"
echo.
echo domain:
echo   include_keywords: "!INCLUDE_KEYWORDS!"
echo   exclude_keywords: "!EXCLUDE_KEYWORDS!"
echo.
echo escalation:
echo   channel: "!ESCALATION_CHANNEL!"
echo   slack_channel: "!SLACK_CHANNEL!"
echo   email: "!ESCALATION_EMAIL!"
) > .project-config.yaml

echo [OK]   .project-config.yaml written.

:: ---------------------------------------------------------------------------
:: SUMMARY
:: ---------------------------------------------------------------------------
echo.
echo -- Summary -------------------------------------------------
echo.
echo Project configured: !PROJECT_NAME!
echo.
echo   Updated files:
echo     [OK] agent.config.yaml
echo     [OK] AGENTS.md
echo     [OK] .cursor\rules\00-project-overview.mdc
echo     [OK] .project-config.yaml (reference for AI tools)
echo.
echo   Not yet populated (run AI command below):
echo     [!]  docs\context\project-brief.md
echo     [!]  docs\context\domain-boundaries.md  ^<-- critical for autonomous agent
echo     [!]  docs\context\domain-glossary.md
echo     [!]  docs\context\tech-stack.md
echo     [!]  docs\architecture\overview.md
echo     [!]  .github\workflows\ci.yml
echo.
echo Next step -- AI-powered initialization:
echo.
echo   In Claude Code:   /init !PROJECT_NAME! -- !PROJECT_PURPOSE!
echo   In Cursor:        @.cursor/prompts/init.md
echo                     (then describe your project in the message)
echo.
echo   Or target specific sections:
echo   /init domain: ^<describe what your system manages and for whom^>
echo   /init stack: !PRIMARY_LANGUAGE!, !FRAMEWORK!, !DATABASE!
echo   /init ci: ^<describe your deployment target and pipeline^>
echo.
echo Then validate: .initium\scripts\validate.cmd
echo.
goto :eof

:: ---------------------------------------------------------------------------
:: :replace_literal
:: Replaces REPLACE_OLD with REPLACE_NEW in REPLACE_FILE.
:: Uses inline PowerShell (-Command) -- does NOT require execution policy.
:: ---------------------------------------------------------------------------
:replace_literal
powershell -NoProfile -Command ^
  "$f=$Env:REPLACE_FILE; $old=$Env:REPLACE_OLD; $new=$Env:REPLACE_NEW; ^
   if (Test-Path $f) { ^
     $c=[IO.File]::ReadAllText($f); ^
     $c=$c.Replace($old,$new); ^
     [IO.File]::WriteAllText($f,$c,[Text.UTF8Encoding]::new($false)) ^
   }"
goto :eof
