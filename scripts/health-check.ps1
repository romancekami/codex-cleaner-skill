param(
    [string]$Root = "",
    [string]$SkillRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "codex-cleaner-env.ps1")

if (-not $Root) {
    $Root = Get-CodexCleanerDefaultRoot
}

function Write-Check {
    param(
        [string]$Name,
        [string]$Status,
        [string]$Message
    )

    Write-Output ("- {0}: {1} - {2}" -f $Status, $Name, $Message)
}

function Test-ScriptSyntax {
    param([string]$Path)

    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors) | Out-Null
    return @($errors)
}

$failures = 0
$warnings = 0

Write-Output "# Codex cleaner health check"
Write-Output ""
Write-Output "- Write actions: none"
Write-Output "- Platform: $(Get-CodexCleanerPlatform)"
Write-Output "- PowerShell: $($PSVersionTable.PSVersion)"
Write-Output ""

$resolvedRoot = (Resolve-Path -LiteralPath $Root -ErrorAction SilentlyContinue).Path
$expectedRoot = (Resolve-Path -LiteralPath (Get-CodexCleanerDefaultRoot) -ErrorAction SilentlyContinue).Path

if (-not $resolvedRoot) {
    $failures += 1
    Write-Check -Name ".codex root" -Status "FAIL" -Message "Root not found: $Root"
} elseif (-not ($resolvedRoot -ieq $expectedRoot)) {
    $failures += 1
    Write-Check -Name ".codex root" -Status "FAIL" -Message "Refusing root outside current user's .codex: $resolvedRoot"
} else {
    Write-Check -Name ".codex root" -Status "OK" -Message $resolvedRoot
}

$requiredScripts = @(
    "codex-cleaner-env.ps1",
    "detect-environment.ps1",
    "audit-codex.ps1",
    "cleanup-runtime.ps1",
    "apply-daily-retention.ps1",
    "runtime-integrity.ps1",
    "health-check.ps1",
    "run-external-agent.ps1",
    "publish-skillhub.ps1"
)

foreach ($scriptName in $requiredScripts) {
    $scriptPath = Join-Path (Join-Path $SkillRoot "scripts") $scriptName
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
        $failures += 1
        Write-Check -Name $scriptName -Status "FAIL" -Message "Script file is missing."
        continue
    }

    $syntaxErrors = Test-ScriptSyntax -Path $scriptPath
    if ($syntaxErrors.Count -gt 0) {
        $failures += 1
        Write-Check -Name $scriptName -Status "FAIL" -Message ("PowerShell parse errors: {0}" -f $syntaxErrors.Count)
    } else {
        Write-Check -Name $scriptName -Status "OK" -Message "Syntax check passed."
    }
}

if (Get-Command codex -ErrorAction SilentlyContinue) {
    Write-Check -Name "Codex CLI" -Status "OK" -Message "Available on PATH for archive/delete execution."
} else {
    $warnings += 1
    Write-Check -Name "Codex CLI" -Status "WARN" -Message "Not found on PATH; dry-run can still work, but archive/delete execution must stop."
}

Write-Output ""
if ($failures -gt 0) {
    Write-Output "Result: FAIL. Fix the failed checks before running cleanup or retention execution."
    exit 1
}

if ($warnings -gt 0) {
    Write-Output "Result: WARN. Dry-run is allowed, but execution may be blocked until warnings are resolved."
    exit 0
}

Write-Output "Result: OK. Health check passed."
