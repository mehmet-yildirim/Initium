<#
.SYNOPSIS
    Apply Initium updates to your derived project (Windows PowerShell / PowerShell 7)

.DESCRIPTION
    Fetches upstream Initium, resolves the target version (latest release tag by default),
    classifies every changed file by ownership (skeleton_owned / merge_required /
    project_owned), auto-applies safe files, removes files Initium deleted (only when
    unmodified locally), and prompts for manual review on files you have customised.

    Files listed under fileOwnership.project_owned in your local initium.json are never
    written. On the first sync (no commit recorded yet — e.g. adopting Initium in an existing
    repository) existing files that match no Initium version are kept, missing merge_required
    files are added, and missing project-owned templates are created.

    Exit codes: 0 success / up to date, 1 error, 10 update available (-Check only).

.PARAMETER Auto
    Non-interactive: apply skeleton_owned files, skip merge_required files, never prompt.

.PARAMETER DryRun
    Show what would change; apply nothing.

.PARAMETER Check
    Report whether an Initium update is available, then exit (10 = update available).

.PARAMETER Json
    With -Check, print the result as JSON.

.PARAMETER Ref
    Sync to a specific Initium tag or branch.

.PARAMETER Channel
    Default target when -Ref is not given: 'tags' (latest release) or 'main'.
    Defaults to agent.config.yaml -> initium_sync.channel, else 'tags'.

.EXAMPLE
    .\.initium\scripts\sync.ps1
    .\.initium\scripts\sync.ps1 -Auto
    .\.initium\scripts\sync.ps1 -Check -Json
    .\.initium\scripts\sync.ps1 -Ref v1.2.0
#>

[CmdletBinding()]
param(
    [switch]$Auto,
    [switch]$DryRun,
    [switch]$Check,
    [switch]$Json,
    [string]$Ref = '',
    [ValidateSet('', 'tags', 'main')]
    [string]$Channel = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$SkeletonJson        = '.initium/initium.json'
$SkeletonRemote      = 'skeleton'
$AgentConfig         = 'agent.config.yaml'
$ExitUpdateAvailable = 10

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
# With -Json, human-readable output goes to stderr so stdout carries only the JSON result.
function Write-Line {
    param([string]$Msg, [ConsoleColor]$Color = [ConsoleColor]::Gray)
    if ($Json) { [Console]::Error.WriteLine($Msg) } else { Write-Host $Msg -ForegroundColor $Color }
}
function Write-Info    { param($Msg) Write-Line "[INFO]  $Msg" Cyan }
function Write-OK      { param($Msg) Write-Line "[OK]    $Msg" Green }
function Write-Warn    { param($Msg) Write-Line "[WARN]  $Msg" Yellow }
function Write-Err     { param($Msg) Write-Line "[ERROR] $Msg" Red; exit 1 }
function Write-Heading { param($Msg) Write-Line "`n$Msg" White; Write-Line ('─' * 60) }

# Native git stderr must not become a terminating error (Windows PowerShell 5.1 behaviour).
function Invoke-Git {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & git @args 2>$null
        $script:GitExit = $LASTEXITCODE
        return $output
    } finally {
        $ErrorActionPreference = $previous
    }
}

function Test-GitObject { param([string]$Spec) Invoke-Git cat-file -e $Spec | Out-Null; return ($script:GitExit -eq 0) }

function Test-Interactive { return (-not $Auto) -and [Environment]::UserInteractive -and -not [Console]::IsInputRedirected }

function Confirm-Yes {
    param([string]$Prompt, [bool]$DefaultYes = $false)
    if (-not (Test-Interactive)) { return $DefaultYes }
    $hint = if ($DefaultYes) { '[Y/n]' } else { '[y/N]' }
    $answer = Read-Host "$Prompt $hint"
    if ([string]::IsNullOrWhiteSpace($answer)) { return $DefaultYes }
    return ($answer -match '^[Yy]')
}

function Get-YamlValue {
    param([string]$Section, [string]$Key)
    if (-not (Test-Path $AgentConfig)) { return '' }
    $inSection = $false
    foreach ($line in Get-Content $AgentConfig) {
        if ($line -match "^$Section\s*:") { $inSection = $true; continue }
        if ($inSection -and $line -match '^[^\s#]') { break }
        if ($inSection -and $line -match "^\s+$Key\s*:\s*([^#\s]+)") { return $Matches[1].Trim('"', "'") }
    }
    return ''
}

function Test-InList {
    param([string]$File, $List)
    foreach ($entry in @($List)) {
        if (-not $entry) { continue }
        if ($File -eq $entry) { return $true }
        if ($entry.EndsWith('/') -and $File.StartsWith($entry)) { return $true }
    }
    return $false
}

# Writes the exact bytes from the target commit into the working tree (index untouched).
function Write-FromTarget {
    param([string]$File)
    $dir = Split-Path $File -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Invoke-Git restore --source=$Target --worktree -- $File | Out-Null
    if ($script:GitExit -ne 0) { Write-Err "Could not write $File from $TargetRef" }
}

if (-not $Channel) { $Channel = Get-YamlValue 'initium_sync' 'channel' }
if (-not $Channel) { $Channel = 'tags' }
if ($Channel -notin @('tags', 'main')) { Write-Err "Invalid channel '$Channel' (expected: tags | main)" }

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
Write-Heading 'Pre-flight Checks'

if (-not (Test-Path $SkeletonJson)) { Write-Err '.initium/initium.json not found. Is this an Initium-based project?' }
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Write-Err 'git is required but not found in PATH.' }

$dirty = Invoke-Git status --porcelain --untracked-files=no
if ($dirty) {
    Write-Warn 'Your working tree has uncommitted changes.'
    if (-not $DryRun -and -not $Check) {
        if (-not (Test-Interactive)) { Write-Err 'Commit or stash your changes before a non-interactive sync.' }
        if (-not (Confirm-Yes 'Continue anyway?')) { exit 1 }
    }
}

Write-OK "Working directory: $(Get-Location)"

# ---------------------------------------------------------------------------
# Read initium.json
# ---------------------------------------------------------------------------
$localJson       = Get-Content $SkeletonJson -Raw | ConvertFrom-Json
$SkeletonRepo    = $localJson.skeleton.repository
$CurrentCommit   = $localJson.skeleton.commit
$CurrentVersion  = $localJson.skeleton.version
$LocalOwned      = @($localJson.fileOwnership.skeleton_owned)

Write-Info "Initium repo    : $SkeletonRepo"
Write-Info "Current version : $CurrentVersion"
Write-Info "Last synced at  : $($localJson.skeleton.syncedAt)"
Write-Info "Channel         : $(if ($Ref) { $Ref } else { $Channel })"

# ---------------------------------------------------------------------------
# Set up Initium remote and resolve the target
# ---------------------------------------------------------------------------
Write-Heading 'Connecting to Initium Repository'

$existingRemote = Invoke-Git remote get-url $SkeletonRemote
if ($script:GitExit -ne 0) {
    Write-Info "Adding Initium remote: $SkeletonRepo"
    Invoke-Git remote add $SkeletonRemote $SkeletonRepo | Out-Null
} elseif ("$existingRemote".Trim() -ne $SkeletonRepo) {
    Write-Warn "Remote '$SkeletonRemote' points to $("$existingRemote".Trim()) (initium.json says $SkeletonRepo)"
    if ((Confirm-Yes 'Update remote URL?') -or -not (Test-Interactive)) {
        Invoke-Git remote set-url $SkeletonRemote $SkeletonRepo | Out-Null
        Write-Info "Remote URL updated to $SkeletonRepo"
    }
}

function Get-LatestReleaseTag {
    $refs = Invoke-Git ls-remote --tags --refs --sort=-v:refname $SkeletonRemote 'v*'
    foreach ($line in @($refs)) {
        $tag = ($line -split '\s+')[1] -replace '^refs/tags/', ''
        if ($tag -match '^v\d+\.\d+\.\d+$') { return $tag }
    }
    return ''
}

# Fetched refs live under refs/initium/ so upstream tags never mix with project tags.
function Receive-Ref {
    param([string]$Kind, [string]$Name)
    Invoke-Git fetch --quiet --no-tags $SkeletonRemote "+refs/$Kind/${Name}:refs/initium/$Name" | Out-Null
    return ($script:GitExit -eq 0)
}

Write-Info 'Fetching Initium...'
$TargetVersion = ''
if ($Ref) {
    Invoke-Git ls-remote --exit-code --tags --refs $SkeletonRemote "refs/tags/$Ref" | Out-Null
    if ($script:GitExit -eq 0) {
        Receive-Ref 'tags' $Ref | Out-Null; $TargetVersion = $Ref -replace '^v', ''
    } elseif (-not (Receive-Ref 'heads' $Ref)) {
        Write-Err "Ref '$Ref' not found in $SkeletonRepo"
    }
    $TargetRef = $Ref
} elseif ($Channel -eq 'tags') {
    $TargetRef = Get-LatestReleaseTag
    if ($TargetRef) {
        Receive-Ref 'tags' $TargetRef | Out-Null; $TargetVersion = $TargetRef -replace '^v', ''
    } else {
        Write-Warn 'No release tags found in Initium — falling back to main'
        $TargetRef = 'main'; Receive-Ref 'heads' 'main' | Out-Null
    }
} else {
    $TargetRef = 'main'; Receive-Ref 'heads' 'main' | Out-Null
}

$Target = "$(Invoke-Git rev-parse "refs/initium/$TargetRef^{commit}")".Trim()
if ($script:GitExit -ne 0 -or -not $Target) { Write-Err "Could not resolve $TargetRef" }
$TargetShort = "$(Invoke-Git rev-parse --short $Target)".Trim()
if (-not $TargetVersion) {
    $versionLine = @(Invoke-Git show "${Target}:.initium/docs/UPDATES.md") | Where-Object { $_ -match '^## v' } | Select-Object -First 1
    $TargetVersion = if ($versionLine) { ($versionLine -replace '^## v', '').Split(' ')[0] } else { 'unknown' }
}

Write-OK "Target: $TargetRef ($TargetShort, version $TargetVersion)"

$updateAvailable = ($CurrentCommit -ne $Target)

if ($Check) {
    if ($Json) {
        [ordered]@{ current = $CurrentVersion; latest = $TargetVersion; ref = $TargetRef; commit = $Target; updateAvailable = $updateAvailable } |
            ConvertTo-Json -Compress | Write-Output
    }
    if ($updateAvailable) {
        Write-Info "Update available: $CurrentVersion -> $TargetVersion"
        Write-Info "Run '.\.initium\scripts\sync.ps1' to apply updates."
        exit $ExitUpdateAvailable
    }
    Write-OK 'Already up to date.'
    exit 0
}

if (-not $updateAvailable) {
    Write-OK "Already up to date — Initium $TargetVersion matches your last sync."
    if (-not (Confirm-Yes 'Force re-sync anyway?')) { Write-Info 'Nothing to do.'; exit 0 }
} else {
    Write-Info "Update available: $CurrentVersion -> $TargetVersion"
}

# ---------------------------------------------------------------------------
# Show changelog
# ---------------------------------------------------------------------------
Write-Heading 'What Changed in Initium'
Write-Host ''
Write-Host 'Commits since your last sync:'
$log = Invoke-Git log --oneline "${CurrentCommit}..$Target"
if ($script:GitExit -ne 0) { $log = Invoke-Git log --oneline $Target --max-count=20 }
$log | ForEach-Object { Write-Host $_ }
Write-Host ''
Write-Info "Full migration notes: $SkeletonRepo/blob/$TargetRef/.initium/docs/UPDATES.md"
Write-Host ''
if (-not (Confirm-Yes 'Continue with sync?' -DefaultYes $true)) { Write-Info 'Sync cancelled.'; exit 0 }

# ---------------------------------------------------------------------------
# Ownership lists come from the target version so new files are included.
# ---------------------------------------------------------------------------
$remoteJson    = (Invoke-Git show "${Target}:.initium/initium.json") -join "`n" | ConvertFrom-Json
$SkeletonOwned = @($remoteJson.fileOwnership.skeleton_owned)
$ProjectOwned  = @($remoteJson.fileOwnership.project_owned)
$MergeRequired = @($remoteJson.fileOwnership.merge_required)
$RemovedList   = if ($remoteJson.fileOwnership.PSObject.Properties.Name -contains 'removed') { @($remoteJson.fileOwnership.removed) } else { @() }

$FirstSync = -not (Test-GitObject "$CurrentCommit^{commit}")
if (-not $FirstSync) {
    $changedFiles = @(Invoke-Git diff --name-only $CurrentCommit $Target | Where-Object { $_ })
} else {
    $changedFiles = @(Invoke-Git ls-tree -r --name-only $Target | Where-Object { $_ })
}

$applied = 0; $skipped = 0
$updatedFiles = @(); $addedFiles = @(); $removedFiles = @(); $keptModified = @(); $needsMerge = @()
$protected = @(); $existingKept = @()
$LocalProjectOwned = @($localJson.fileOwnership.project_owned)

# True when the local file is byte-identical to some version Initium shipped at this path.
function Test-InitiumVersion {
    param([string]$File)
    $localBlob = "$(Invoke-Git hash-object -- $File)".Trim()
    $history = @(Invoke-Git log --format= --raw --no-abbrev $Target -- $File)
    foreach ($line in $history) {
        $fields = "$line" -split '\s+'
        if ($fields.Count -ge 4 -and $fields[3] -eq $localBlob) { return $true }
    }
    return $false
}

function Add-FromTarget {
    param([string]$File, [string]$Label)
    if ($DryRun) {
        Write-Host "  [DRY-RUN WOULD ADD] $File" -ForegroundColor Green
    } else {
        Write-FromTarget $File
        Write-OK "  ${Label}: $File"
    }
    $script:addedFiles += $File
    $script:applied++
}

# ---------------------------------------------------------------------------
# Apply skeleton_owned files (changed + missing locally)
# ---------------------------------------------------------------------------
Write-Heading 'Applying Initium-Owned Files (safe overwrite)'

$candidates = @($changedFiles | Where-Object { Test-InList $_ $SkeletonOwned })
$candidates += @($SkeletonOwned | Where-Object { $_ -and -not $_.EndsWith('/') -and -not (Test-Path $_) })
foreach ($file in ($candidates | Select-Object -Unique)) {
    if (-not (Test-GitObject "${Target}:$file")) { continue }
    if (Test-InList $file $LocalProjectOwned) { $protected += $file; continue }
    if ($FirstSync -and (Test-Path $file -PathType Leaf) -and -not (Test-InitiumVersion $file)) {
        Write-Warn "  Existing project file kept: $file"
        $existingKept += $file
        continue
    }
    $isNew = -not (Test-Path $file)
    $action = if ($isNew) { 'Added' } else { 'Updated' }
    if ($DryRun) {
        Write-Host "  [DRY-RUN WOULD $($action.ToUpper())] $file" -ForegroundColor Green
    } else {
        Write-FromTarget $file
        Write-OK "  ${action}: $file"
    }
    if ($isNew) { $addedFiles += $file } else { $updatedFiles += $file }
    $applied++
}

# ---------------------------------------------------------------------------
# Remove files that Initium deleted — only when identical to Initium's last version
# ---------------------------------------------------------------------------
Write-Heading 'Removing Files Deleted from Initium'

foreach ($file in (@($RemovedList) + $LocalOwned | Where-Object { $_ -and -not $_.EndsWith('/') } | Select-Object -Unique)) {
    if (-not (Test-Path $file -PathType Leaf)) { continue }
    if (Test-GitObject "${Target}:$file") { continue }
    $deletingCommit = "$(Invoke-Git log -1 --format=%H $Target -- $file)".Trim()
    if (-not $deletingCommit -or -not (Test-GitObject "$deletingCommit^:$file")) { continue }

    $upstreamBlob = "$(Invoke-Git rev-parse "$deletingCommit^:$file")".Trim()
    $localBlob    = "$(Invoke-Git hash-object -- $file)".Trim()
    if ($upstreamBlob -eq $localBlob) {
        if ($DryRun) {
            Write-Host "  [DRY-RUN WOULD REMOVE] $file" -ForegroundColor Green
        } else {
            Invoke-Git ls-files --error-unmatch -- $file | Out-Null
            if ($script:GitExit -eq 0) { Invoke-Git rm -q -- $file | Out-Null } else { Remove-Item $file -Force }
            Write-OK "  Removed: $file"
        }
        $removedFiles += $file
        $applied++
    } else {
        Write-Warn "  Removed in Initium but modified locally — kept: $file"
        $keptModified += $file
    }
}
if ($removedFiles.Count -eq 0 -and $keptModified.Count -eq 0) { Write-Info 'No removed files to clean up.' }

# ---------------------------------------------------------------------------
# Merge-required files
# ---------------------------------------------------------------------------
Write-Heading 'Merge-Required Files (manual review needed)'

foreach ($file in $changedFiles) {
    if (-not (Test-InList $file $MergeRequired) -or -not (Test-GitObject "${Target}:$file")) { continue }
    if (Test-InList $file $LocalProjectOwned) { $protected += $file; continue }
    if ($FirstSync -and -not (Test-Path $file)) { Add-FromTarget $file 'Added (no local version)'; continue }
    $needsMerge += $file
}

if ($needsMerge.Count -eq 0) {
    Write-Info 'No merge-required files changed in this Initium update.'
} else {
    Write-Warn 'These files changed in Initium but require manual merge because your project has likely customised them:'
    foreach ($file in $needsMerge) { Write-Host "  -> $file" -ForegroundColor Yellow }
    Write-Host "  View the Initium version with: git show refs/initium/${TargetRef}:<file>"

    if (-not $DryRun) {
        foreach ($file in $needsMerge) {
            if (-not (Test-Interactive)) {
                Write-Warn "  Skipped (non-interactive): $file — merge manually"
                $skipped++
                continue
            }
            Write-Host ''
            Write-Host ('━' * 60)
            Write-Host " MERGE: $file" -ForegroundColor Yellow
            Write-Host ('━' * 60)
            Invoke-Git diff "${Target}:$file" $file | ForEach-Object { Write-Host $_ }
            Write-Host 'Options:'
            Write-Host '  a) Overwrite with Initium version (discards your changes)'
            Write-Host '  s) Skip this file (merge manually later)'
            Write-Host '  c) Open side-by-side in VS Code diff'
            $choice = Read-Host 'Choice [a/S/c]'

            switch ($choice.ToLower()) {
                'a' {
                    Write-FromTarget $file
                    Write-OK "  Overwritten: $file"
                    $applied++
                }
                'c' {
                    $tmpFile = [System.IO.Path]::GetTempFileName()
                    [System.IO.File]::WriteAllText($tmpFile, ((Invoke-Git show "${Target}:$file") -join "`n") + "`n")
                    if (Get-Command code -ErrorAction SilentlyContinue) {
                        code --diff $tmpFile $file
                        Read-Host 'VS Code diff opened. Save your file after merging, then press Enter'
                    } else {
                        Write-Warn '  VS Code not found. Showing diff output only.'
                        Invoke-Git diff "${Target}:$file" $file | ForEach-Object { Write-Host $_ }
                    }
                    Remove-Item $tmpFile -ErrorAction SilentlyContinue
                    Write-Warn "  Review complete. Stage manually if you edited: git add $file"
                    $skipped++
                }
                default {
                    Write-Warn "  Skipped: $file — merge manually"
                    $skipped++
                }
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Project-owned templates changed in Initium (informational only)
# ---------------------------------------------------------------------------
# First sync: create project-owned templates the repository does not have yet.
$adoptSkip = @('README.md', 'README.tr.md', 'LICENSE', 'CODE_OF_CONDUCT.md', 'CHANGELOG.md', '.env', '.initium/initium.json')
if ($FirstSync) {
    Write-Heading 'Adding Missing Project Templates (first sync)'
    $templatesAdded = 0
    foreach ($entry in $ProjectOwned) {
        foreach ($file in @(Invoke-Git ls-tree -r --name-only $Target -- $entry | Where-Object { $_ })) {
            if ($adoptSkip -contains $file -or (Test-Path $file)) { continue }
            Add-FromTarget $file 'Added template'
            $templatesAdded++
        }
    }
    if ($templatesAdded -eq 0) { Write-Info 'All project templates already exist.' }
}

$projectTemplateChanges = @(if (-not $FirstSync) { $changedFiles | Where-Object { Test-InList $_ $ProjectOwned } })
if ($projectTemplateChanges.Count -gt 0) {
    Write-Heading 'Initium Template Files Changed (for your reference)'
    Write-Warn 'These project-owned files were updated in the Initium template:'
    foreach ($file in $projectTemplateChanges) {
        Write-Host "  i  $file  -> git show refs/initium/${TargetRef}:$file" -ForegroundColor Cyan
    }
}

# ---------------------------------------------------------------------------
# Update initium.json — targeted replacements keep the file's formatting intact
# ---------------------------------------------------------------------------
if (-not $DryRun) {
    Write-Heading 'Updating initium.json'
    $today = Get-Date -Format 'yyyy-MM-dd'
    $content = [System.IO.File]::ReadAllText((Resolve-Path $SkeletonJson))
    $content = $content -replace '"commit":\s*"[^"]*"', "`"commit`": `"$Target`""
    $content = $content -replace '"syncedAt":\s*"[^"]*"', "`"syncedAt`": `"$today`""
    $content = $content -replace '"version":\s*"[^"]*"', "`"version`": `"$TargetVersion`""
    [System.IO.File]::WriteAllText((Resolve-Path $SkeletonJson), $content)
    Write-OK "initium.json updated (version=$TargetVersion, commit=$TargetShort)"
}

# ---------------------------------------------------------------------------
# Run validator
# ---------------------------------------------------------------------------
if (-not $DryRun -and $applied -gt 0 -and (Test-Path '.initium/scripts/validate.ps1')) {
    Write-Heading 'Validating Configuration'
    try { & ./.initium/scripts/validate.ps1 } catch { Write-Warn 'Validator found issues — review above' }
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Heading 'Sync Complete'
Write-Host "  Applied (auto)   : $applied files ($($removedFiles.Count) removed)" -ForegroundColor Green
Write-Host "  Skipped (manual) : $skipped files — merge these manually" -ForegroundColor Yellow
if ($keptModified.Count -gt 0) {
    Write-Host "  Kept (modified)  : $($keptModified.Count) files removed in Initium but changed locally" -ForegroundColor Yellow
}
if ($projectTemplateChanges.Count -gt 0) {
    Write-Host "  Template notices : $($projectTemplateChanges.Count) project-owned files changed in Initium" -ForegroundColor Cyan
}
if ($protected.Count -gt 0) {
    Write-Host "  Protected        : $($protected.Count) files listed in your local project_owned" -ForegroundColor Cyan
}
if ($existingKept.Count -gt 0) {
    Write-Host "  Existing kept    : $($existingKept.Count) project files differ from Initium and were not overwritten:" -ForegroundColor Yellow
    foreach ($file in $existingKept) { Write-Host "      $file" }
    Write-Host "    Compare: git diff refs/initium/${TargetRef}:<file> <file>"
    Write-Host '    Keep yours permanently: add the path to fileOwnership.project_owned in .initium/initium.json'
    Write-Host "    Take Initium's: delete the file and run the sync again"
}
Write-Host ''
if (-not $DryRun) {
    Write-Host 'Suggested next steps:'
    Write-Host '  1. Review changes:  git diff'
    Write-Host "  2. Stage and commit: git add -A; git commit -m 'chore: sync Initium to $TargetVersion'"
    if ($skipped -gt 0) { Write-Host '  3. Merge skipped files manually, then commit' }
} else {
    Write-Host '  (Dry run — no files changed)'
}
Write-Host ''
