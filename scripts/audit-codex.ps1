param(
    [string]$Root = "",
    [int]$RetentionDays = 30,
    [int]$Top = 5,
    [int]$TempOlderThanDays = 3
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "codex-cleaner-env.ps1")

if (-not $Root) {
    $Root = Get-CodexCleanerDefaultRoot
}

function Format-Size {
    param([long]$Bytes)

    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
    return "$Bytes B"
}

function Get-DirectorySummary {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return [pscustomobject]@{
            Path = $Path
            Exists = $false
            Files = 0
            Bytes = 0
            Oldest = $null
            Newest = $null
        }
    }

    $files = @(Get-ChildItem -LiteralPath $Path -Force -Recurse -File -ErrorAction SilentlyContinue)
    $bytes = ($files | Measure-Object -Property Length -Sum).Sum
    if ($null -eq $bytes) { $bytes = 0 }

    return [pscustomobject]@{
        Path = $Path
        Exists = $true
        Files = $files.Count
        Bytes = [long]$bytes
        Oldest = ($files | Sort-Object LastWriteTime | Select-Object -First 1).LastWriteTime
        Newest = ($files | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
    }
}

function Get-EntryBytes {
    param([string]$Path)

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        return [long](Get-Item -LiteralPath $Path -Force).Length
    }

    if (Test-Path -LiteralPath $Path -PathType Container) {
        $sum = (Get-ChildItem -LiteralPath $Path -Force -Recurse -File -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum).Sum
        if ($null -eq $sum) { return 0 }
        return [long]$sum
    }

    return 0
}

$resolvedRoot = (Resolve-Path -LiteralPath $Root -ErrorAction SilentlyContinue).Path
if (-not ($resolvedRoot)) {
    Write-Output "# Codex storage audit"
    Write-Output ""
    Write-Output ('Root not found: `{0}`' -f $Root)
    exit 1
}

$allowedRoot = Get-CodexCleanerDefaultRoot
if (-not ($resolvedRoot -ieq (Resolve-Path -LiteralPath $allowedRoot).Path)) {
    Write-Output "# Codex storage audit"
    Write-Output ""
    Write-Output ('Refusing to audit outside the current user''s .codex root: `{0}`' -f $resolvedRoot)
    exit 2
}

$knownDirs = @(
    "sessions",
    "archived_sessions",
    "sqlite",
    "backups",
    ".tmp",
    ".sandbox-bin",
    ".sandbox",
    "vendor_imports",
    "cache",
    "plugins",
    "skills",
    "memories",
    "automations"
)

$rootSummary = Get-DirectorySummary -Path $resolvedRoot
$summaries = foreach ($name in $knownDirs) {
    Get-DirectorySummary -Path (Join-Path $resolvedRoot $name)
}
$platform = Get-CodexCleanerPlatform
$codexProcessRunning = Test-CodexCleanerCodexProcess

$desktopAreas = Get-CodexCleanerDesktopAreas
$desktopSummaries = foreach ($area in $desktopAreas) {
    $summary = Get-DirectorySummary -Path $area.Path
    $summary | Add-Member -NotePropertyName Name -NotePropertyValue $area.Name
    $summary | Add-Member -NotePropertyName Handling -NotePropertyValue $area.Handling
    $summary | Add-Member -NotePropertyName Reason -NotePropertyValue $area.Reason
    $summary
}

$excludedThirdPartyAreas = Get-CodexCleanerThirdPartyAreas

$tempCutoff = (Get-Date).AddDays(-1 * $TempOlderThanDays)
$tempPatterns = @(
    "codex-clipboard-*.png",
    "codex-*-readonly",
    "codex-skill-review-*",
    "codex-changelog-text.txt",
    "codex-browser-tab-lifecycle.jsonl",
    "openai-docs-cache"
)
$tempCandidates = @()
foreach ($pattern in $tempPatterns) {
    $tempCandidates += @(Get-ChildItem -LiteralPath (Get-CodexCleanerTempPath) -Force -ErrorAction SilentlyContinue -Filter $pattern |
        Where-Object { $_.LastWriteTime -lt $tempCutoff } |
        ForEach-Object {
            [pscustomobject]@{
                Path = $_.FullName
                Name = $_.Name
                Bytes = Get-EntryBytes -Path $_.FullName
                LastWriteTime = $_.LastWriteTime
            }
        })
}

$stateFilePatterns = @(
    "logs_*.sqlite",
    "logs_*.sqlite-wal",
    "logs_*.sqlite-shm",
    "state_*.sqlite",
    "state_*.sqlite-wal",
    "state_*.sqlite-shm",
    "goals_*.sqlite",
    "goals_*.sqlite-wal",
    "goals_*.sqlite-shm",
    "memories_*.sqlite",
    "memories_*.sqlite-wal",
    "memories_*.sqlite-shm"
)
$stateFiles = @()
foreach ($pattern in $stateFilePatterns) {
    $stateFiles += @(Get-ChildItem -LiteralPath $resolvedRoot -Force -File -ErrorAction SilentlyContinue -Filter $pattern)
}
$stateFiles += @(Get-ChildItem -LiteralPath (Join-Path $resolvedRoot "sqlite") -Force -File -ErrorAction SilentlyContinue)
$stateFiles = @($stateFiles | Sort-Object FullName -Unique)
$stateBytes = ($stateFiles | Measure-Object -Property Length -Sum).Sum
if ($null -eq $stateBytes) { $stateBytes = 0 }

$cutoff = (Get-Date).AddDays(-1 * $RetentionDays)
$sessionRoot = Join-Path $resolvedRoot "sessions"
$oldSessionFiles = @()
if (Test-Path -LiteralPath $sessionRoot -PathType Container) {
    $oldSessionFiles = @(Get-ChildItem -LiteralPath $sessionRoot -Force -Recurse -File -Filter "*.jsonl" -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $cutoff })
}

Write-Output "# Codex storage audit"
Write-Output ""
Write-Output ('- Root: `{0}`' -f $resolvedRoot)
Write-Output "- Platform: $platform"
Write-Output "- Total audited size: $(Format-Size $rootSummary.Bytes)"
Write-Output "- Total audited files: $($rootSummary.Files)"
Write-Output "- Retention window: $RetentionDays days"
Write-Output "- Old session files by mtime: $($oldSessionFiles.Count)"
Write-Output "- Codex process running: $codexProcessRunning"
Write-Output "- Write actions: none"
Write-Output ""
Write-Output "## Largest known areas"

$summaries |
    Where-Object { $_.Exists } |
    Sort-Object Bytes -Descending |
    Select-Object -First $Top |
    ForEach-Object {
        $name = Split-Path -Leaf $_.Path
        Write-Output ('- `{0}`: {1}, files: {2}' -f $name, (Format-Size $_.Bytes), $_.Files)
    }

Write-Output ""
Write-Output "## V5 coverage map"
Write-Output ('- `main-user-data`: {0}, files: {1}, handling: mixed; main `.codex` root, cleanup must stay category-based.' -f (Format-Size $rootSummary.Bytes), $rootSummary.Files)
Write-Output ('- `session-history`: {0} old session files by mtime, handling: avoid direct file deletion; use Codex archive/delete tooling.' -f $oldSessionFiles.Count)
Write-Output ('- `state-databases`: {0}, files: {1}, handling: avoid direct edits; report size only.' -f (Format-Size ([long]$stateBytes)), $stateFiles.Count)
foreach ($item in @($desktopSummaries | Where-Object { $_.Exists } | Sort-Object Bytes -Descending)) {
    Write-Output ('- `{0}`: {1}, files: {2}, handling: {3}; {4}' -f $item.Name, (Format-Size $item.Bytes), $item.Files, $item.Handling, $item.Reason)
}
if ($tempCandidates.Count -gt 0) {
    $tempBytesForCoverage = ($tempCandidates | Measure-Object -Property Bytes -Sum).Sum
    if ($null -eq $tempBytesForCoverage) { $tempBytesForCoverage = 0 }
    Write-Output ('- `user-temp-codex-leftovers`: {0}, items: {1}, handling: manual-review by default; eligible only with explicit TEMP switch.' -f (Format-Size ([long]$tempBytesForCoverage)), $tempCandidates.Count)
} else {
    Write-Output ('- `user-temp-codex-leftovers`: none older than {0} days, handling: safe to ignore.' -f $TempOlderThanDays)
}
foreach ($item in $excludedThirdPartyAreas) {
    if (Test-Path -LiteralPath $item.Path) {
        Write-Output ('- `{0}`: excluded third-party app; not a Codex Desktop cleanup target.' -f $item.Name)
    }
}
if ($codexProcessRunning) {
    Write-Output "- `process-guard`: Codex appears to be running; runtime/AppData/database cleanup should remain audit-only."
} else {
    Write-Output "- `process-guard`: no running Codex process detected by this audit."
}

Write-Output ""
Write-Output "## Cleanup suggestions"
Write-Output ""
Write-Output "### Safe"
Write-Output "- Run retention dry-run first, then archive exact-title daily reports older than the retention window through Codex tooling."
Write-Output '- Run runtime cleanup dry-run first; execute only validated expired `.tmp` candidates after CHECKPOINT / STOP.'
Write-Output ('- V4 audit also checks Codex Desktop app-support/runtime areas and user temp Codex leftovers; temp cleanup remains dry-run unless explicitly enabled.')
Write-Output ""
Write-Output "### Manual-review"

$manualReviewNames = @(".tmp", ".sandbox-bin", ".sandbox", "vendor_imports", "backups", "cache")
$manualReview = @($summaries | Where-Object {
        $_.Exists -and
        $_.Bytes -gt 0 -and
        ($manualReviewNames -contains (Split-Path -Leaf $_.Path))
    } | Sort-Object Bytes -Descending)

if ($manualReview.Count -eq 0) {
    Write-Output "- None found in the known review categories."
} else {
    foreach ($item in $manualReview) {
        $name = Split-Path -Leaf $item.Path
        Write-Output ('- `{0}`: {1}, files: {2}; inspect before removing anything.' -f $name, (Format-Size $item.Bytes), $item.Files)
    }
}

foreach ($item in @($desktopSummaries | Where-Object { $_.Exists -and $_.Handling -eq "manual-review" -and $_.Bytes -gt 0 } | Sort-Object Bytes -Descending)) {
    Write-Output ('- `{0}`: {1}, files: {2}; {3}' -f $item.Name, (Format-Size $item.Bytes), $item.Files, $item.Reason)
}

if ($tempCandidates.Count -gt 0) {
    $tempBytes = ($tempCandidates | Measure-Object -Property Bytes -Sum).Sum
    if ($null -eq $tempBytes) { $tempBytes = 0 }
    Write-Output ('- `temp-codex-leftovers`: {0}, items: {1}; dry-run candidate set from `%TEMP%`, older than {2} days.' -f (Format-Size $tempBytes), $tempCandidates.Count, $TempOlderThanDays)
}

Write-Output ""
Write-Output "### Avoid"
Write-Output '- Do not directly delete `sessions` or `archived_sessions`; use Codex archive/delete tooling.'
Write-Output '- Do not directly delete `sqlite`, state databases, config, auth, `skills`, `plugins`, `memories`, or `automations`.'
Write-Output '- Do not clean Codex install packages, complete runtime directories, or OS app package state from this skill.'
foreach ($item in @($desktopSummaries | Where-Object { $_.Exists -and $_.Handling -eq "avoid" })) {
    Write-Output ('- Avoid `{0}`: {1}, files: {2}; {3}' -f $item.Name, (Format-Size $item.Bytes), $item.Files, $item.Reason)
}
foreach ($item in $excludedThirdPartyAreas) {
    if (Test-Path -LiteralPath $item.Path) {
        Write-Output ('- Excluded third-party app: `{0}` at `{1}`.' -f $item.Name, $item.Path)
    }
}
