param(
    [string]$CandidatesJson,
    [string]$CandidatesPath,
    [int]$ArchiveAfterDays = 14,
    [int]$DeleteAfterDays = 30,
    [switch]$ExecuteArchive,
    [switch]$ExecuteDelete,
    [datetime]$Now = (Get-Date)
)

$ErrorActionPreference = "Stop"

if ($ArchiveAfterDays -ge $DeleteAfterDays) {
    throw "ArchiveAfterDays must be less than DeleteAfterDays."
}

if (($CandidatesJson -and $CandidatesPath) -or (-not $CandidatesJson -and -not $CandidatesPath)) {
    throw "Provide exactly one of -CandidatesJson or -CandidatesPath."
}

if ($CandidatesPath) {
    $CandidatesJson = Get-Content -Raw -LiteralPath $CandidatesPath
}

$parsedCandidates = ConvertFrom-Json -InputObject $CandidatesJson
if ($null -eq $parsedCandidates) {
    $candidates = @()
} elseif ($parsedCandidates -is [array]) {
    $candidates = @($parsedCandidates)
} elseif ($null -ne $parsedCandidates.PSObject.Properties["threads"]) {
    $candidates = @($parsedCandidates.threads)
} else {
    $candidates = @($parsedCandidates)
}

function New-Title {
    param([int[]]$CodePoints)

    return [string]::Concat(($CodePoints | ForEach-Object { [char]$_ }))
}

$allowedTitles = @(
    (New-Title @(0x41, 0x49, 0x20, 0x5E94, 0x7528, 0x7AEF, 0x65E5, 0x62A5)),
    (New-Title @(0x47, 0x69, 0x74, 0x48, 0x75, 0x62, 0x20, 0x5DE5, 0x5177, 0x65E5, 0x62A5))
)

function Get-CreatedAt {
    param($Value)

    if ($null -eq $Value) {
        return $null
    }

    if ($Value -is [int] -or $Value -is [long] -or $Value -is [double]) {
        return [DateTimeOffset]::FromUnixTimeSeconds([int64]$Value).LocalDateTime
    }

    $parsed = [datetime]::MinValue
    if ([datetime]::TryParse([string]$Value, [ref]$parsed)) {
        return $parsed
    }

    return $null
}

function Invoke-CodexCommand {
    param(
        [string]$Verb,
        [string]$ThreadId
    )

    if ($Verb -eq "archive") {
        & codex archive $ThreadId
        if ($LASTEXITCODE -ne 0) {
            throw "codex archive failed for thread $ThreadId with exit code $LASTEXITCODE."
        }
        return
    }

    if ($Verb -eq "delete") {
        & codex delete --force $ThreadId
        if ($LASTEXITCODE -ne 0) {
            throw "codex delete failed for thread $ThreadId with exit code $LASTEXITCODE."
        }
        return
    }

    throw "Unknown command: $Verb"
}

$uuidPattern = "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
$results = @()

foreach ($candidate in $candidates) {
    $id = [string]$candidate.id
    $title = [string]$candidate.title
    $status = [string]$candidate.status
    $createdAt = Get-CreatedAt $candidate.createdAt
    $action = "keep"
    $reason = "within retention window"
    $ageDays = $null

    if ($null -ne $candidate.PSObject.Properties["preview"]) {
        $action = "skip"
        $reason = "preview/content is not allowed as input"
    } elseif ($id -notmatch $uuidPattern) {
        $action = "skip"
        $reason = "invalid UUID"
    } elseif ($allowedTitles -notcontains $title) {
        $action = "skip"
        $reason = "title is not on the daily-report whitelist"
    } elseif ($candidate.isCurrent -eq $true) {
        $action = "skip"
        $reason = "current thread"
    } elseif ($candidate.isPinned -eq $true) {
        $action = "skip"
        $reason = "pinned thread"
    } elseif ($status -match "running|active|in_progress") {
        $action = "skip"
        $reason = "thread appears to be running"
    } elseif ($null -eq $createdAt) {
        $action = "skip"
        $reason = "missing or invalid createdAt"
    } else {
        $ageDays = ($Now - $createdAt).TotalDays
        if ($ageDays -gt $DeleteAfterDays) {
            $action = "delete"
            $reason = "older than $DeleteAfterDays days"
        } elseif ($ageDays -gt $ArchiveAfterDays) {
            $action = "archive"
            $reason = "older than $ArchiveAfterDays days"
        }
    }

    $results += [pscustomobject]@{
        id = $id
        title = $title
        createdAt = $createdAt
        ageDays = $ageDays
        action = $action
        reason = $reason
    }
}

$archiveItems = @($results | Where-Object { $_.action -eq "archive" })
$deleteItems = @($results | Where-Object { $_.action -eq "delete" })
$skipItems = @($results | Where-Object { $_.action -eq "skip" })
$keepItems = @($results | Where-Object { $_.action -eq "keep" })

if ($ExecuteArchive -or $ExecuteDelete) {
    if (-not (Get-Command codex -ErrorAction SilentlyContinue)) {
        throw "Codex CLI was not found on PATH. Stop before archive/delete execution."
    }
}

Write-Output "# Daily report retention"
Write-Output ""
Write-Output "- Candidates: $($results.Count)"
Write-Output "- Keep: $($keepItems.Count)"
Write-Output "- Archive: $($archiveItems.Count)"
Write-Output "- Delete: $($deleteItems.Count)"
Write-Output "- Skip: $($skipItems.Count)"
Write-Output "- Execute archive: $($ExecuteArchive.IsPresent)"
Write-Output "- Execute delete: $($ExecuteDelete.IsPresent)"
Write-Output ""

foreach ($item in @($archiveItems + $deleteItems + $skipItems)) {
    $age = if ($null -eq $item.ageDays) { "n/a" } else { "{0:N1}" -f $item.ageDays }
    Write-Output ("- {0}: {1} ageDays={2} id={3} reason={4}" -f $item.action, $item.title, $age, $item.id, $item.reason)
}

if ($ExecuteArchive) {
    foreach ($item in $archiveItems) {
        Invoke-CodexCommand -Verb "archive" -ThreadId $item.id
    }
}

if ($ExecuteDelete) {
    foreach ($item in $deleteItems) {
        Invoke-CodexCommand -Verb "delete" -ThreadId $item.id
    }
}

if (-not $ExecuteArchive -and -not $ExecuteDelete) {
    Write-Output ""
    Write-Output "Dry-run only. No archive or delete commands were executed."
}
