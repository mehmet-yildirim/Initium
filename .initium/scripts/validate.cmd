@echo off
:: =============================================================================
:: AI Configuration Validator (Windows Batch)
:: Checks that all AI tool config files are present and customized.
:: No special permissions required -- runs on any Windows system.
::
:: Usage:
::   .initium\scripts\validate.cmd
:: =============================================================================

setlocal enabledelayedexpansion

set PASS=0
set WARN=0
set FAIL=0

echo.
echo ========================================
echo   AI Configuration Validator
echo ========================================

:: ---------------------------------------------------------------------------
:: File existence checks
:: ---------------------------------------------------------------------------
echo.
echo --- File Presence ---

:: Core AI tool configs
call :chk "AGENTS.md"
call :chk "CLAUDE.md"
call :chk ".cursor\rules\00-project-overview.mdc"
call :chk ".cursor\rules\01-coding-standards.mdc"
call :chk ".cursor\rules\02-architecture.mdc"
call :chk ".cursor\rules\03-testing.mdc"
call :chk ".cursor\rules\04-git-workflow.mdc"
call :chk ".cursor\rules\05-security.mdc"
call :chk ".cursor\mcp.json"
call :chk ".continue\config.yaml"
call :chk ".continue\rules\01-coding-standards.md"
call :chk ".continue\rules\02-architecture.md"
call :chk ".continue\rules\03-testing.md"
call :chk ".continue\rules\04-security.md"

:: Claude Code slash commands
call :chk ".claude\commands\init.md"
call :chk ".claude\commands\requirements.md"
call :chk ".claude\commands\architect.md"
call :chk ".claude\commands\implement.md"
call :chk ".claude\commands\review.md"
call :chk ".claude\commands\qa.md"
call :chk ".claude\commands\test.md"
call :chk ".claude\commands\debug.md"
call :chk ".claude\commands\deploy.md"
call :chk ".claude\commands\migrate.md"
call :chk ".claude\commands\db.md"
call :chk ".claude\commands\sprint.md"
call :chk ".claude\commands\docs.md"
call :chk ".claude\commands\standup.md"
call :chk ".claude\commands\security-audit.md"
call :chk ".claude\commands\triage.md"
call :chk ".claude\commands\groom.md"
call :chk ".claude\commands\loop.md"
call :chk ".claude\commands\escalate.md"
call :chk ".claude\commands\goal.md"
call :chk ".claude\commands\help.md"
call :chk ".claude\commands\codegraph.md"
call :chk ".claude\commands\refactor.md"
call :chk ".claude\commands\upgrade.md"
call :chk ".claude\commands\perf.md"
call :chk ".claude\commands\a11y.md"
call :chk ".claude\commands\eval.md"
call :chk ".claude\commands\skill.md"

:: Agent Skills (.claude\skills\<name>\SKILL.md -- single source)
call :chk ".initium\scripts\sync-skills.mjs"
where node >nul 2>&1
if errorlevel 1 (
  echo   WARN node not found -- cannot validate skills ^(requires Node.js 22+^)
  set /a WARN+=1
) else (
  node .initium/scripts/sync-skills.mjs --check >nul 2>&1
  if errorlevel 1 (
    echo   FAIL Skill frontmatter invalid or Continue rules stale -- run: node .initium/scripts/sync-skills.mjs
    set /a FAIL+=1
  ) else (
    echo   PASS Skills valid; Continue rules in sync
    set /a PASS+=1
  )
)
call :chk "opencode.json"
call :chk ".opencode\README.md"
bash .initium/scripts/sync-opencode-commands.sh --check >nul 2>&1
if errorlevel 1 (
  echo   FAIL OpenCode commands out of sync — run: bash .initium/scripts/sync-opencode-commands.sh
  set /a FAIL+=1
) else (
  echo   PASS OpenCode commands in sync with .claude/commands/
  set /a PASS+=1
)

:: Autonomous agent config & docs
call :chk "agent.config.yaml"
call :chk "docs\context\domain-boundaries.md"
call :chk "docs\agent\autonomous-workflow.md"
call :chk "docs\agent\escalation-protocol.md"
call :chk "docs\agent\decision-log-template.md"
call :chk "docs\agent\jira-server-setup.md"
call :chk "docs\agent\security-evaluator.md"
call :chk ".agent-templates\webhook-receiver.mjs"
call :chk "docs\agent\schemas\task-state.json"
call :chk "docs\agent\schemas\decision.json"
call :chk "docs\agent\schemas\requirement-analysis.json"
call :chk "docs\agent\schemas\qa-report.json"
call :chk "docs\agent\schemas\security-report.json"
call :chk ".claude\hooks\post-write.mjs"
call :chk ".claude\hooks\audit-log.mjs"
call :chk ".claude\hooks\on-stop.mjs"

:: Cursor skill rules
call :chk ".cursor\rules\skills\lang-java.mdc"
call :chk ".cursor\rules\skills\lang-dotnet.mdc"
call :chk ".cursor\rules\skills\lang-python.mdc"
call :chk ".cursor\rules\skills\lang-typescript.mdc"
call :chk ".cursor\rules\skills\lang-go.mdc"
call :chk ".cursor\rules\skills\fe-react.mdc"
call :chk ".cursor\rules\skills\fe-nextjs.mdc"
call :chk ".cursor\rules\skills\fe-vue.mdc"
call :chk ".cursor\rules\skills\fe-angular.mdc"
call :chk ".cursor\rules\skills\be-microservices.mdc"
call :chk ".cursor\rules\skills\devops-docker.mdc"
call :chk ".cursor\rules\skills\devops-cicd.mdc"
call :chk ".cursor\rules\skills\security-sast.mdc"
call :chk ".cursor\rules\skills\db-migrations.mdc"
call :chk ".cursor\rules\skills\devops-aws.mdc"
call :chk ".cursor\rules\skills\devops-gcp.mdc"
call :chk ".cursor\rules\skills\devops-onprem.mdc"
call :chk ".cursor\rules\skills\mobile-ios.mdc"
call :chk ".cursor\rules\skills\mobile-android.mdc"
call :chk ".cursor\rules\skills\mobile-kmp.mdc"
call :chk ".cursor\rules\skills\mobile-flutter.mdc"
call :chk ".cursor\rules\skills\mobile-reactnative.mdc"

:: Continue skill rules
call :chk ".continue\rules\skills\lang-java.md"
call :chk ".continue\rules\skills\lang-dotnet.md"
call :chk ".continue\rules\skills\lang-python.md"
call :chk ".continue\rules\skills\fe-react.md"
call :chk ".continue\rules\skills\fe-nextjs.md"
call :chk ".continue\rules\skills\fe-vue.md"
call :chk ".continue\rules\skills\fe-angular.md"
call :chk ".continue\rules\skills\mobile-ios.md"
call :chk ".continue\rules\skills\mobile-android.md"
call :chk ".continue\rules\skills\mobile-kmp.md"
call :chk ".continue\rules\skills\mobile-flutter.md"
call :chk ".continue\rules\skills\mobile-reactnative.md"
call :chk ".continue\rules\skills\security-sast.md"
call :chk ".continue\rules\skills\db-migrations.md"
call :chk ".continue\rules\skills\devops-aws.md"
call :chk ".continue\rules\skills\devops-gcp.md"
call :chk ".continue\rules\skills\devops-onprem.md"

:: Workflow docs
call :chk "docs\workflows\01-requirements-analysis.md"
call :chk "docs\workflows\02-feature-development.md"
call :chk "docs\workflows\03-testing-strategy.md"
call :chk "docs\workflows\04-deployment.md"
call :chk "docs\workflows\05-security-evaluation.md"
call :chk "docs\workflows\06-database-migrations.md"
call :chk "docs\workflows\07-deployment-platforms.md"
call :chk "skills\README.md"

:: Context & architecture docs
call :chk "docs\context\project-brief.md"
call :chk "docs\context\tech-stack.md"
call :chk "docs\context\domain-boundaries.md"
call :chk "docs\context\domain-glossary.md"
call :chk "docs\architecture\overview.md"

:: Scripts
call :chk ".initium\scripts\setup.sh"
call :chk ".initium\scripts\setup.cmd"
call :chk ".initium\scripts\init.sh"
call :chk ".initium\scripts\init.cmd"

:: ---------------------------------------------------------------------------
:: Customization checks (look for TODO placeholders)
:: ---------------------------------------------------------------------------
echo.
echo --- Customization (TODO placeholders remaining) ---

call :chk_todo "AGENTS.md"
call :chk_todo ".cursor\rules\00-project-overview.mdc"
call :chk_todo "docs\context\project-brief.md"
call :chk_todo "docs\context\tech-stack.md"
call :chk_todo "docs\context\domain-boundaries.md"
call :chk_todo "docs\architecture\overview.md"
call :chk_todo "agent.config.yaml"

:: ---------------------------------------------------------------------------
:: Environment check
:: ---------------------------------------------------------------------------
echo.
echo --- Environment ---

if exist ".env" (
    echo   PASS Found: .env
    set /a PASS+=1
) else (
    echo   WARN Missing .env -- copy from .env.example and fill in values
    set /a WARN+=1
)

if exist ".env.example" (
    echo   PASS Found: .env.example
    set /a PASS+=1
) else (
    echo   WARN Missing .env.example -- create one to document required variables
    set /a WARN+=1
)

:: ---------------------------------------------------------------------------
:: Git check
:: ---------------------------------------------------------------------------
echo.
echo --- Git ---

if exist ".git\" (
    echo   PASS Git repository initialized
    set /a PASS+=1
) else (
    echo   FAIL No git repository -- run: git init
    set /a FAIL+=1
)

for /f "delims=" %%R in ('git remote get-url origin 2^>nul') do set "REMOTE_URL=%%R"
if defined REMOTE_URL (
    echo   PASS Remote origin: !REMOTE_URL!
    set /a PASS+=1
) else (
    echo   WARN No remote origin set -- run: git remote add origin ^<url^>
    set /a WARN+=1
)

:: ---------------------------------------------------------------------------
:: Summary
:: ---------------------------------------------------------------------------
echo.
echo ========================================
echo   Results
echo ========================================
echo   PASS: !PASS!
echo   WARN: !WARN!
echo   FAIL: !FAIL!
echo.

if !FAIL! gtr 0 (
    echo Action required: fix FAIL items before starting development.
    exit /b 1
) else if !WARN! gtr 0 (
    echo Warnings present: review WARN items and customize as needed.
    exit /b 0
) else (
    echo All checks passed! You're ready to code.
    exit /b 0
)

:: ---------------------------------------------------------------------------
:: :chk -- check if a file exists, increment PASS or FAIL
:: ---------------------------------------------------------------------------
:chk
if exist "%~1" (
    echo   PASS Found: %~1
    set /a PASS+=1
) else (
    echo   FAIL Missing: %~1
    set /a FAIL+=1
)
goto :eof

:: ---------------------------------------------------------------------------
:: :chk_todo -- check if a file has TODO placeholders remaining
:: ---------------------------------------------------------------------------
:chk_todo
if not exist "%~1" goto :eof
findstr /c:"TODO" "%~1" >nul 2>&1
if errorlevel 1 (
    echo   PASS Customized: %~1
    set /a PASS+=1
) else (
    for /f %%C in ('findstr /c:"TODO" "%~1" 2^>nul ^| find /c /v ""') do set TODO_COUNT=%%C
    echo   WARN %~1 has !TODO_COUNT! TODO(s) remaining
    set /a WARN+=1
)
goto :eof
