@echo off
:: =============================================================================
:: sync.cmd — Apply Initium updates to your derived project (Windows)
:: =============================================================================
:: Delegates to sync.ps1 via PowerShell 7 (pwsh) or
:: Windows PowerShell 5.1 (powershell.exe) — both are built into Windows.
:: No bash, WSL, or any additional tool required.
::
:: Usage:
::   .initium\scripts\sync.cmd              Interactive mode
::   .initium\scripts\sync.cmd --auto       Auto-apply skeleton-owned files
::   .initium\scripts\sync.cmd --dry-run    Preview changes; apply nothing
::   .initium\scripts\sync.cmd --check      Check if update is available (exit 10 = yes)
::   .initium\scripts\sync.cmd --check --json  Same, as JSON
::   .initium\scripts\sync.cmd --ref v1.2.0 Sync to a specific tag or branch
::   .initium\scripts\sync.cmd --channel main  Track main instead of release tags
::   .initium\scripts\sync.cmd --help       Show help
:: =============================================================================

setlocal

:: Show help
if /I "%~1"=="--help" (
    echo.
    echo  sync.cmd -- Apply upstream Initium updates to this project
    echo.
    echo  Usage:
    echo    .initium\scripts\sync.cmd              Interactive mode
    echo    .initium\scripts\sync.cmd --auto       Auto-apply skeleton-owned files
    echo    .initium\scripts\sync.cmd --dry-run    Preview only; no changes applied
    echo    .initium\scripts\sync.cmd --check      Check for update availability ^(exit 10 = yes^)
    echo    .initium\scripts\sync.cmd --ref ^<tag^>  Sync to a specific tag or branch
    echo    .initium\scripts\sync.cmd --channel main   Track main instead of release tags
    echo.
    echo  What it does:
    echo    1. Adds the upstream Initium repo as a git remote ^(once^)
    echo    2. Resolves the target: latest release tag ^(default^) or main
    echo    3. skeleton_owned files  -^> applied automatically ^(safe^)
    echo    4. merge_required files  -^> shown as diff; you choose per file
    echo    5. project_owned files   -^> never touched ^(your customisations^)
    echo    6. Updates .initium/initium.json with the new version and commit SHA
    echo.
    echo  File ownership is defined in .initium\initium.json.
    echo  Full guide: .initium\docs\sync-guide.md
    echo.
    exit /b 0
)

:: Verify initium.json exists
if not exist ".initium\initium.json" (
    echo [ERROR] .initium\initium.json not found. Is this an Initium-based project?
    exit /b 1
)

:: Verify git is available
where git >nul 2>&1
if errorlevel 1 (
    echo [ERROR] git not found in PATH. Install Git for Windows: https://git-scm.com/download/win
    exit /b 1
)

:: Build PowerShell argument string from CMD arguments
set PS_ARGS=

:parse_args
if "%~1"=="" goto run
if /I "%~1"=="--auto"     set PS_ARGS=%PS_ARGS% -Auto
if /I "%~1"=="--dry-run"  set PS_ARGS=%PS_ARGS% -DryRun
if /I "%~1"=="--check"    set PS_ARGS=%PS_ARGS% -Check
if /I "%~1"=="--json"     set PS_ARGS=%PS_ARGS% -Json
if /I "%~1"=="--ref" (
    set PS_ARGS=%PS_ARGS% -Ref "%~2"
    shift
)
if /I "%~1"=="--channel" (
    set PS_ARGS=%PS_ARGS% -Channel %~2
    shift
)
shift
goto parse_args

:run
set PS_SCRIPT=%~dp0sync.ps1

:: ---------------------------------------------------------------------------
:: Attempt 1: PowerShell 7+ (pwsh) — preferred, ships with Windows 11 / 10
:: ---------------------------------------------------------------------------
where pwsh >nul 2>&1
if errorlevel 1 goto try_ps51
pwsh -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%"%PS_ARGS%
exit /b %errorlevel%

:try_ps51
:: ---------------------------------------------------------------------------
:: Attempt 2: Windows PowerShell 5.1 — built into every Windows 7+ system
:: ---------------------------------------------------------------------------
where powershell >nul 2>&1
if errorlevel 1 goto no_powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%"%PS_ARGS%
exit /b %errorlevel%

:no_powershell
:: ---------------------------------------------------------------------------
:: PowerShell missing — extremely unlikely on any modern Windows system
:: ---------------------------------------------------------------------------
echo.
echo [ERROR] PowerShell not found in PATH.
echo.
echo  PowerShell is built into Windows 7 and later. If it is missing:
echo.
echo    Option A - Restore Windows PowerShell 5.1:
echo      Open "Turn Windows features on or off" and enable
echo      "Windows PowerShell 2.0" (re-enables 5.1 on modern Windows).
echo.
echo    Option B - Install PowerShell 7:
echo      https://aka.ms/powershell
echo.
echo    Option C - Manual sync ^(no tools required^):
echo      See .initium\docs\sync-guide.md for step-by-step instructions.
echo.
exit /b 1
