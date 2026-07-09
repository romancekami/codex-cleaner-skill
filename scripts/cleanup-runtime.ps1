param(
    [string]$Root = "",
    [int]$TempOlderThanDays = 7,
    [int]$SystemTempOlderThanDays = 3,
    [int]$BackupOlderThanDays = 30,
    [int]$CacheOlderThanDays = 30,
    [int]$MaxItems = 20,
    [switch]$Execute,
    [switch]$IncludeSystemTemp,
    [switch]$IncludeBackups,
    [switch]$IncludeCache
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

function Get-EntrySize {
    param([string]$Path)

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        return [long](Get-Item -LiteralPath $Path -Force).Length
    }

    $sum = (Get-ChildItem -LiteralPath $Path -Force -Recurse -File -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum).Sum
    if ($null -eq $sum) { return 0 }
    return [long]$sum
}

function New-Candidate {
    param(
        [string]$Category,
        [string]$Action,
        [string]$Path,
        [string]$Reason
    )

    $item = Get-Item -LiteralPath $Path -Force
    return [pscustomobject]@{
        Category = $Category
        Action = $Action
        Name = $item.Name
        Path = $item.FullName
        Bytes = Get-EntrySize -Path $item.FullName
        LastWriteTime = $item.LastWriteTime
        Reason = $Reason
    }
}

$resolvedRoot = (Resolve-Path -LiteralPath $Root -ErrorAction SilentlyContinue).Path
if (-not ($resolvedRoot)) {
    throw "Root not found: $Root"
}

$allowedRoot = (Resolve-Path -LiteralPath (Get-CodexCleanerDefaultRoot)).Path
if (-not ($resolvedRoot -ieq $allowedRoot)) {
    throw "Refusing to clean outside the current user's .codex root: $resolvedRoot"
}

$tmpRoot = Join-Path $resolvedRoot ".tmp"
$backupRoot = Join-Path $resolvedRoot "backups"
$cacheRoot = Join-Path $resolvedRoot "cache"
$systemTempRoot = (Resolve-Path -LiteralPath (Get-CodexCleanerTempPath)).Path
$tempCutoff = (Get-Date).AddDays(-1 * $TempOlderThanDays)
$systemTempCutoff = (Get-Date).AddDays(-1 * $SystemTempOlderThanDays)
$backupCutoff = (Get-Date).AddDays(-1 * $BackupOlderThanDays)
$cacheCutoff = (Get-Date).AddDays(-1 * $CacheOlderThanDays)
$candidates = @()
$platform = Get-CodexCleanerPlatform
$codexProcessRunning = Test-CodexCleanerCodexProcess

if (Test-Path -LiteralPath $tmpRoot -PathType Container) {
    $tmpChildren = Get-ChildItem -LiteralPath $tmpRoot -Force -ErrorAction SilentlyContinue
    foreach ($child in $tmpChildren) {
        if ($child.Extension -in @(".lock", ".sha")) { continue }
        if ($child.LastWriteTime -lt $tempCutoff) {
            $candidates += New-Candidate -Category "tmp" -Action "clean" -Path $child.FullName -Reason "expired .tmp entry"
        }
    }
}

$systemTempPatterns = @(
    "codex-clipboard-*.png",
    "codex-*-readonly",
    "codex-skill-review-*",
    "codex-changelog-text.txt",
    "codex-browser-tab-lifecycle.jsonl",
    "openai-docs-cache"
)
foreach ($pattern in $systemTempPatterns) {
    $tempItems = Get-ChildItem -LiteralPath $systemTempRoot -Force -ErrorAction SilentlyContinue -Filter $pattern
    foreach ($item in $tempItems) {
        if ($item.LastWriteTime -lt $systemTempCutoff) {
            $action = if ($IncludeSystemTemp) { "clean" } else { "review" }
            $candidates += New-Candidate -Category "system-temp" -Action $action -Path $item.FullName -Reason "old Codex temp entry under user TEMP"
        }
    }
}

if (Test-Path -LiteralPath $backupRoot -PathType Container) {
    $backupChildren = Get-ChildItem -LiteralPath $backupRoot -Force -Directory -ErrorAction SilentlyContinue
    foreach ($child in $backupChildren) {
        if ($child.LastWriteTime -lt $backupCutoff) {
            $action = if ($IncludeBackups) { "clean" } else { "review" }
            $candidates += New-Candidate -Category "backup" -Action $action -Path $child.FullName -Reason "old backup directory"
        }
    }
}

if (Test-Path -LiteralPath $cacheRoot -PathType Container) {
    $cacheFiles = Get-ChildItem -LiteralPath $cacheRoot -Force -Recurse -File -ErrorAction SilentlyContinue
    foreach ($file in $cacheFiles) {
        if ($file.LastWriteTime -lt $cacheCutoff) {
            $action = if ($IncludeCache) { "clean" } else { "review" }
            $candidates += New-Candidate -Category "cache" -Action $action -Path $file.FullName -Reason "old cache file"
        }
    }
}

$cleanItems = @($candidates | Where-Object { $_.Action -eq "clean" } | Sort-Object Bytes -Descending)
$reviewItems = @($candidates | Where-Object { $_.Action -eq "review" } | Sort-Object Bytes -Descending)
$cleanBytes = ($cleanItems | Measure-Object -Property Bytes -Sum).Sum
$reviewBytes = ($reviewItems | Measure-Object -Property Bytes -Sum).Sum
if ($null -eq $cleanBytes) { $cleanBytes = 0 }
if ($null -eq $reviewBytes) { $reviewBytes = 0 }

Write-Output "# Codex runtime cleanup"
Write-Output ""
Write-Output "- Root: $resolvedRoot"
Write-Output "- Platform: $platform"
Write-Output "- Dry-run: $(-not $Execute.IsPresent)"
Write-Output "- Clean candidates: $($cleanItems.Count), $(Format-Size $cleanBytes)"
Write-Output "- Manual-review candidates: $($reviewItems.Count), $(Format-Size $reviewBytes)"
Write-Output "- Rules: .codex .tmp older than $TempOlderThanDays days; user temp Codex entries older than $SystemTempOlderThanDays days; backups older than $BackupOlderThanDays days; cache older than $CacheOlderThanDays days"
Write-Output "- Codex process running: $codexProcessRunning"
Write-Output "- Excluded third-party apps: CC Switch and CodeX++ are not cleanup roots."
if ($codexProcessRunning) {
    Write-Output "- Process guard: keep AppData/runtime/database cleanup audit-only while Codex is running."
}
Write-Output ""

foreach ($item in @($cleanItems + $reviewItems) | Select-Object -First $MaxItems) {
    Write-Output ("- {0}/{1}: {2}, {3}, lastWrite={4:yyyy-MM-dd HH:mm:ss}, reason={5}" -f $item.Action, $item.Category, $item.Name, (Format-Size $item.Bytes), $item.LastWriteTime, $item.Reason)
}

if ($Execute) {
    $removedCount = 0
    foreach ($item in $cleanItems) {
        $allowedBase = switch ($item.Category) {
            "tmp" { $tmpRoot }
            "system-temp" { $systemTempRoot }
            "backup" { $backupRoot }
            "cache" { $cacheRoot }
            default { $null }
        }

        if (-not $allowedBase) {
            throw "Unexpected cleanup category: $($item.Category)"
        }

        if (-not (Test-CodexCleanerPathUnder -Path $item.Path -Parent $allowedBase)) {
            throw "Candidate is outside allowed cleanup root: $($item.Path)"
        }

        try {
            Remove-Item -LiteralPath $item.Path -Force -Recurse -ErrorAction Stop
            $removedCount += 1
        } catch {
            throw "Failed to remove cleanup candidate '$($item.Path)' category='$($item.Category)' reason='$($item.Reason)': $($_.Exception.Message)"
        }
    }

    Write-Output ""
    Write-Output "Execute completed. Removed candidates: $removedCount."
}

if (-not $Execute) {
    Write-Output ""
    Write-Output "Dry-run only. No files or directories were removed."
}
