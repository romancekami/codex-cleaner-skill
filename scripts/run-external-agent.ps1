param(
    [string]$Root = "",
    [switch]$IncludeSystemTemp,
    [switch]$SkipRuntimeIntegrity,
    [switch]$SkipRuntimeDryRun
)

$ErrorActionPreference = "Stop"

$scriptRoot = $PSScriptRoot
$skillRoot = Split-Path -Parent $scriptRoot
. (Join-Path $scriptRoot "codex-cleaner-env.ps1")

if (-not $Root) {
    $Root = Get-CodexCleanerDefaultRoot
}

function Invoke-Step {
    param(
        [string]$Name,
        [scriptblock]$Body
    )

    Write-Output ""
    Write-Output ("## {0}" -f $Name)
    try {
        & $Body
    } catch {
        throw ("{0} failed: {1}" -f $Name, $_.Exception.Message)
    }
}

Write-Output "# Codex Cleaner external-agent dry-run"
Write-Output ""
Write-Output "- Host: generic agent / PowerShell"
Write-Output "- Platform: $(Get-CodexCleanerPlatform)"
Write-Output "- Skill root: $skillRoot"
Write-Output "- Target root: $Root"
Write-Output "- Write actions: none"

Invoke-Step -Name "Health check" -Body {
    & (Join-Path $scriptRoot "health-check.ps1") -Root $Root -SkillRoot $skillRoot
}

Invoke-Step -Name "Storage audit" -Body {
    & (Join-Path $scriptRoot "audit-codex.ps1") -Root $Root -RetentionDays 14 -Top 10
}

if (-not $SkipRuntimeIntegrity) {
    Invoke-Step -Name "Runtime integrity audit" -Body {
        & (Join-Path $scriptRoot "runtime-integrity.ps1") -Root $Root
    }
}

if (-not $SkipRuntimeDryRun) {
    Invoke-Step -Name "Runtime cleanup dry-run" -Body {
        if ($IncludeSystemTemp) {
            & (Join-Path $scriptRoot "cleanup-runtime.ps1") -Root $Root -IncludeSystemTemp -MaxItems 12
        } else {
            & (Join-Path $scriptRoot "cleanup-runtime.ps1") -Root $Root -MaxItems 12
        }
    }
}

Write-Output ""
Write-Output "Result: dry-run complete. No files or directories were removed."
