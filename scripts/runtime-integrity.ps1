param(
    [string]$Root = "",
    [string]$AppDataRoot = "",
    [int]$Top = 8,
    [int]$RuntimeWarnMB = 1024
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "codex-cleaner-env.ps1")

if (-not $Root) {
    $Root = Get-CodexCleanerDefaultRoot
}
if (-not $AppDataRoot) {
    $AppDataRoot = Get-CodexCleanerRuntimeRoot
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

    if (Test-Path -LiteralPath $Path -PathType Container) {
        $sum = (Get-ChildItem -LiteralPath $Path -Force -Recurse -File -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum).Sum
        if ($null -eq $sum) { return 0 }
        return [long]$sum
    }

    return 0
}

function Get-DirectorySummary {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return [pscustomobject]@{
            Path = $Path
            Exists = $false
            Files = 0
            Bytes = 0
            LastWriteTime = $null
        }
    }

    $item = Get-Item -LiteralPath $Path -Force
    $files = @(Get-ChildItem -LiteralPath $Path -Force -Recurse -File -ErrorAction SilentlyContinue)
    $bytes = ($files | Measure-Object -Property Length -Sum).Sum
    if ($null -eq $bytes) { $bytes = 0 }

    return [pscustomobject]@{
        Path = $item.FullName
        Exists = $true
        Files = $files.Count
        Bytes = [long]$bytes
        LastWriteTime = $item.LastWriteTime
    }
}

function Get-CodexProcessRefs {
    param([string]$RuntimeRoot)

    $refs = @()
    $platform = Get-CodexCleanerPlatform

    if ($platform -ne "Windows") {
        try {
            $processes = Get-Process -ErrorAction SilentlyContinue
            foreach ($process in $processes) {
                $name = ""
                $path = ""
                if ($null -ne $process.ProcessName) { $name = [string]$process.ProcessName }
                try {
                    if ($null -ne $process.Path) { $path = [string]$process.Path }
                } catch {
                    $path = ""
                }

                $mentionsRoot = $path.IndexOf($RuntimeRoot, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
                $isCodexProcess = $name -match "(?i)^codex$"

                if ($mentionsRoot -or $isCodexProcess) {
                    $refs += [pscustomobject]@{
                        Name = $name
                        ProcessId = $process.Id
                        RuntimePathRef = $mentionsRoot
                        ExecutablePath = $path
                    }
                }
            }
        } catch {
            return @()
        }

        return @($refs)
    }

    try {
        $processes = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue
        foreach ($process in $processes) {
            $name = ""
            $path = ""
            $commandLine = ""
            if ($null -ne $process.Name) { $name = [string]$process.Name }
            if ($null -ne $process.ExecutablePath) { $path = [string]$process.ExecutablePath }
            if ($null -ne $process.CommandLine) { $commandLine = [string]$process.CommandLine }

            $mentionsRoot = $path.StartsWith($RuntimeRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
                ($commandLine.IndexOf($RuntimeRoot, [System.StringComparison]::OrdinalIgnoreCase) -ge 0)
            $isCodexProcess = $name -match "(?i)^codex(\.exe)?$"

            if ($mentionsRoot -or $isCodexProcess) {
                $refs += [pscustomobject]@{
                    Name = $name
                    ProcessId = $process.ProcessId
                    RuntimePathRef = $mentionsRoot
                    ExecutablePath = $path
                }
            }
        }
    } catch {
        return @()
    }

    return @($refs)
}

function Get-ConfigRuntimeRefs {
    param(
        [string]$ConfigPath,
        [string]$RuntimeRoot,
        [int]$MaxRefs
    )

    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        return @()
    }

    $escapedRoot = [regex]::Escape($RuntimeRoot)
    $content = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8
    $matches = [regex]::Matches($content, "$escapedRoot[^'`"`r`n]*", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $refs = foreach ($match in $matches) {
        $value = $match.Value
        if ($value.Length -gt 140) {
            $value = $value.Substring(0, 140) + "..."
        }
        $value
    }

    return @($refs | Sort-Object -Unique | Select-Object -First $MaxRefs)
}

$resolvedRoot = (Resolve-Path -LiteralPath $Root -ErrorAction SilentlyContinue).Path
if (-not $resolvedRoot) {
    throw "Root not found: $Root"
}

$expectedRoot = (Resolve-Path -LiteralPath (Get-CodexCleanerDefaultRoot) -ErrorAction SilentlyContinue).Path
if (-not ($resolvedRoot -ieq $expectedRoot)) {
    throw "Refusing to audit outside the current user's .codex root: $resolvedRoot"
}

$platform = Get-CodexCleanerPlatform
$resolvedAppDataRoot = if ($AppDataRoot) { (Resolve-Path -LiteralPath $AppDataRoot -ErrorAction SilentlyContinue).Path } else { $null }
$expectedAppDataRoot = Get-CodexCleanerRuntimeRoot
$resolvedExpectedAppDataRoot = if ($expectedAppDataRoot) { (Resolve-Path -LiteralPath $expectedAppDataRoot -ErrorAction SilentlyContinue).Path } else { $null }

if ($resolvedAppDataRoot -and $resolvedExpectedAppDataRoot -and -not ($resolvedAppDataRoot -ieq $resolvedExpectedAppDataRoot)) {
    throw "Refusing to audit unexpected Codex AppData root: $resolvedAppDataRoot"
}

$binRoot = if ($resolvedAppDataRoot) { Join-Path $resolvedAppDataRoot "bin" } else { $null }
$runtimesRoot = if ($resolvedAppDataRoot) { Join-Path $resolvedAppDataRoot "runtimes" } else { $null }
$configPath = Join-Path $resolvedRoot "config.toml"

$appDataSummary = if ($resolvedAppDataRoot) { Get-DirectorySummary -Path $resolvedAppDataRoot } else { $null }
$binSummary = if ($binRoot) { Get-DirectorySummary -Path $binRoot } else { $null }
$runtimesSummary = if ($runtimesRoot) { Get-DirectorySummary -Path $runtimesRoot } else { $null }
$processRefs = if ($resolvedAppDataRoot) { Get-CodexProcessRefs -RuntimeRoot $resolvedAppDataRoot } else { @() }
$runtimeProcessRefs = @($processRefs | Where-Object { $_.RuntimePathRef })
$configRefs = if ($resolvedAppDataRoot) { Get-ConfigRuntimeRefs -ConfigPath $configPath -RuntimeRoot $resolvedAppDataRoot -MaxRefs $Top } else { @() }

$binDirs = @()
if ($binRoot -and (Test-Path -LiteralPath $binRoot -PathType Container)) {
    $binDirs = @(Get-ChildItem -LiteralPath $binRoot -Force -Directory -ErrorAction SilentlyContinue |
        ForEach-Object {
            $dirPath = $_.FullName
            $exeNames = @(Get-ChildItem -LiteralPath $_.FullName -Force -File -Filter "*.exe" -ErrorAction SilentlyContinue |
                Select-Object -ExpandProperty Name)
            [pscustomobject]@{
                Name = $_.Name
                Bytes = Get-EntrySize -Path $_.FullName
                Files = @(Get-ChildItem -LiteralPath $_.FullName -Force -Recurse -File -ErrorAction SilentlyContinue).Count
                LastWriteTime = $_.LastWriteTime
                Exes = ($exeNames -join ", ")
                ReferencedByProcess = (@($runtimeProcessRefs | Where-Object {
                            $_.ExecutablePath.StartsWith($dirPath, [System.StringComparison]::OrdinalIgnoreCase)
                        }).Count -gt 0)
            }
        } | Sort-Object Bytes -Descending)
}

$runtimeDirs = @()
if ($runtimesRoot -and (Test-Path -LiteralPath $runtimesRoot -PathType Container)) {
    $runtimeDirs = @(Get-ChildItem -LiteralPath $runtimesRoot -Force -Directory -ErrorAction SilentlyContinue |
        ForEach-Object {
            $summary = Get-DirectorySummary -Path $_.FullName
            [pscustomobject]@{
                Name = $_.Name
                Bytes = $summary.Bytes
                Files = $summary.Files
                LastWriteTime = $_.LastWriteTime
            }
        } | Sort-Object Bytes -Descending)
}

$stagingDirs = @()
if ($runtimesRoot -and (Test-Path -LiteralPath $runtimesRoot -PathType Container)) {
    $stagingDirs = @(Get-ChildItem -LiteralPath $runtimesRoot -Force -Recurse -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "(?i)(^\.?staging|\.staging-|staging-)" } |
        ForEach-Object {
            [pscustomobject]@{
                Name = $_.Name
                Path = $_.FullName
                Bytes = Get-EntrySize -Path $_.FullName
                LastWriteTime = $_.LastWriteTime
            }
        } | Sort-Object LastWriteTime -Descending)
}

Write-Output "# Codex runtime integrity audit"
Write-Output ""
Write-Output "- Root: $resolvedRoot"
Write-Output "- Platform: $platform"
Write-Output "- App runtime root: $(if ($resolvedAppDataRoot) { $resolvedAppDataRoot } else { 'not found' })"
Write-Output "- Write actions: none"
Write-Output "- Codex-related processes: $($processRefs.Count)"
Write-Output "- Processes referencing app runtime: $($runtimeProcessRefs.Count)"
Write-Output "- Config runtime references: $($configRefs.Count)"
Write-Output ""

Write-Output "## Runtime areas"
if ($appDataSummary) {
    Write-Output ('- `openai-codex-app-runtime`: {0}, files: {1}, handling: manual-review.' -f (Format-Size $appDataSummary.Bytes), $appDataSummary.Files)
}
if ($binSummary) {
    Write-Output ('- `bin`: {0}, files: {1}, handling: avoid direct deletion; contains executable helpers.' -f (Format-Size $binSummary.Bytes), $binSummary.Files)
}
if ($runtimesSummary) {
    Write-Output ('- `runtimes`: {0}, files: {1}, handling: avoid direct deletion; runtime may be active.' -f (Format-Size $runtimesSummary.Bytes), $runtimesSummary.Files)
    if ($runtimesSummary.Bytes -gt ($RuntimeWarnMB * 1MB)) {
        Write-Output ('- WARN: `runtimes` exceeds {0} MB; inspect staging leftovers and active references before cleanup.' -f $RuntimeWarnMB)
    }
}

Write-Output ""
Write-Output "## Bin directories"
if ($binDirs.Count -eq 0) {
    Write-Output "- None found."
} else {
    foreach ($item in @($binDirs | Select-Object -First $Top)) {
        Write-Output ('- `{0}`: {1}, files: {2}, lastWrite={3:yyyy-MM-dd HH:mm:ss}, exes=[{4}]' -f $item.Name, (Format-Size $item.Bytes), $item.Files, $item.LastWriteTime, $item.Exes)
    }
}

Write-Output ""
Write-Output "## Runtime directories"
if ($runtimeDirs.Count -eq 0) {
    Write-Output "- None found."
} else {
    foreach ($item in @($runtimeDirs | Select-Object -First $Top)) {
        Write-Output ('- `{0}`: {1}, files: {2}, lastWrite={3:yyyy-MM-dd HH:mm:ss}' -f $item.Name, (Format-Size $item.Bytes), $item.Files, $item.LastWriteTime)
    }
}

Write-Output ""
Write-Output "## Staging leftovers"
if ($stagingDirs.Count -eq 0) {
    Write-Output "- None found."
} else {
    foreach ($item in @($stagingDirs | Select-Object -First $Top)) {
        Write-Output ('- `{0}`: {1}, lastWrite={2:yyyy-MM-dd HH:mm:ss}, path=`{3}`' -f $item.Name, (Format-Size $item.Bytes), $item.LastWriteTime, $item.Path)
    }
}

Write-Output ""
Write-Output "## Active references"
if ($processRefs.Count -eq 0) {
    Write-Output "- No Codex-related process references detected."
} else {
    foreach ($item in @($processRefs | Sort-Object RuntimePathRef -Descending | Select-Object -First $Top)) {
        $scope = if ($item.RuntimePathRef) { "runtime-ref" } else { "codex-process" }
        Write-Output ('- {0}: pid={1}, name={2}' -f $scope, $item.ProcessId, $item.Name)
    }
}

Write-Output ""
Write-Output "## Config references"
if ($configRefs.Count -eq 0) {
    Write-Output "- No app runtime references found in config.toml."
} else {
    foreach ($ref in $configRefs) {
        Write-Output ('- `{0}`' -f $ref)
    }
}

Write-Output ""
Write-Output "## Recommendation"
Write-Output "- Safe: keep this audit read-only."
Write-Output "- Manual-review: stale `.staging-*` directories may be future cleanup candidates only after Codex is fully closed and dry-run is reviewed."
Write-Output '- Avoid: do not directly delete complete `bin` hash directories, complete `runtimes` directories, SQLite/state files, or config references.'
if ($runtimeProcessRefs.Count -gt 0) {
    Write-Output "- Stop: runtime paths are currently referenced by running processes, so runtime cleanup should remain audit-only."
}
