@echo off
:: =============================================================================
:: Initium -- Project Setup Script (Windows Batch)
:: =============================================================================
:: Run this once after cloning Initium to initialize your project.
:: No special permissions required -- runs on any Windows system.
::
:: Usage:
::   .initium\scripts\setup.cmd
:: =============================================================================

setlocal enabledelayedexpansion

echo.
echo ========================================
echo   AI-Native Project Setup
echo ========================================
echo.

:: ---------------------------------------------------------------------------
:: 1. Initialize git repository (if not already a repo)
:: ---------------------------------------------------------------------------
if not exist ".git\" (
    echo [INFO] Initializing git repository...
    git init
    if !errorlevel! equ 0 (
        echo [OK]   Git repository initialized.
    ) else (
        echo [WARN] git init failed -- is Git installed?
    )
) else (
    echo [INFO] Git repository already exists, skipping init.
)

:: ---------------------------------------------------------------------------
:: 2. Remove Initium remote origin (if inherited from clone)
:: ---------------------------------------------------------------------------
for /f "delims=" %%R in ('git remote get-url origin 2^>nul') do set "REMOTE_URL=%%R"
if defined REMOTE_URL (
    echo !REMOTE_URL! | findstr /c:"Initium" >nul 2>&1
    if not errorlevel 1 (
        echo [WARN] Removing Initium remote origin: !REMOTE_URL!
        git remote remove origin
        echo [OK]   Removed. Add your own with: git remote add origin ^<url^>
    )
)

:: ---------------------------------------------------------------------------
:: 3. Create .env from .env.example if it doesn't exist
:: ---------------------------------------------------------------------------
if exist ".env.example" (
    if not exist ".env" (
        echo [INFO] Creating .env from .env.example...
        copy /y ".env.example" ".env" >nul
        echo [OK]   Created .env -- fill in your values before starting development.
    ) else (
        echo [INFO] .env already exists, skipping.
    )
) else (
    echo [WARN] No .env.example found. Create one with your required environment variables.
)

:: ---------------------------------------------------------------------------
:: 4. Validate required AI tool configurations
:: ---------------------------------------------------------------------------
echo [INFO] Checking AI tool configuration files...

set MISSING_CONFIG=0

call :check_file "AGENTS.md" "Agent instructions (all tools)"
call :check_file "CLAUDE.md" "Claude Code import of AGENTS.md"
call :check_file ".cursor\rules\00-project-overview.mdc" "Cursor project overview"
call :check_file ".continue\config.yaml" "Continue config"

if !MISSING_CONFIG! equ 1 (
    echo [WARN] Some AI config files are missing. Run: .initium\scripts\validate.cmd
)

:: ---------------------------------------------------------------------------
:: 5. Next steps
:: ---------------------------------------------------------------------------
echo.
echo ========================================
echo   Next Steps
echo ========================================
echo.
echo   STEP 1 - Run the initialization wizard:
echo   .initium\scripts\init.cmd
echo   (configures project name, stack, tracker, and domain keywords)
echo.
echo   STEP 2 - AI-powered content generation:
echo   Open Claude Code and run:  /init ^<describe your project^>
echo   Or in Cursor:              @.cursor/prompts/init.md
echo.
echo   This populates:
echo     * AGENTS.md, docs\context\, docs\architecture\overview.md
echo     * agent.config.yaml domain keywords
echo     * .github\workflows\ci.yml  (use: /init ci: ^<your stack^>)
echo.
echo   STEP 3 - Finish setup:
echo     * Edit .continue\config.yaml (add API keys)
echo     * Add git remote:  git remote add origin ^<url^>
echo     * Install dependencies: [from AGENTS.md after /init]
echo     * Validate: .initium\scripts\validate.cmd
echo     * Read the AI workflow: docs\ai-workflow.md
echo.
echo   AI commands available in Claude Code (type / to invoke):
echo   /init       - populate all TODO files from your project description
echo   /architect  - design a feature before implementing
echo   /review     - review code for issues
echo   /test       - generate tests
echo   /debug      - systematic debugging
echo.
echo [OK]   Setup complete!
goto :eof

:: ---------------------------------------------------------------------------
:: Helper: check a file exists
:: ---------------------------------------------------------------------------
:check_file
if exist "%~1" (
    echo [OK]   %~2: %~1
) else (
    echo [WARN] %~2 not found: %~1
    set MISSING_CONFIG=1
)
goto :eof
