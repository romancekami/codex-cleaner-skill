param(
    [string]$Root = ""
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "codex-cleaner-env.ps1")

if (-not $Root) {
    $Root = Get-CodexCleanerDefaultRoot
}

$platform = Get-CodexCleanerPlatform
$resolvedRoot = (Resolve-Path -LiteralPath $Root -ErrorAction SilentlyContinue).Path
$tempRoot = (Resolve-Path -LiteralPath (Get-CodexCleanerTempPath) -ErrorAction SilentlyContinue).Path
$runtimeRoot = Get-CodexCleanerRuntimeRoot
$desktopAreas = Get-CodexCleanerDesktopAreas
$rootDisplay = if ($resolvedRoot) { $resolvedRoot } else { "not found: $Root" }
$tempDisplay = if ($tempRoot) { $tempRoot } else { "not found" }
$runtimeDisplay = if ($runtimeRoot) { $runtimeRoot } else { "not mapped for this platform" }

Write-Output "# Codex Cleaner environment"
Write-Output ""
Write-Output "- Platform: $platform"
Write-Output "- PowerShell: $($PSVersionTable.PSVersion)"
Write-Output "- Home: $(Get-CodexCleanerHomePath)"
Write-Output "- Codex root: $rootDisplay"
Write-Output "- User temp: $tempDisplay"
Write-Output "- Runtime root: $runtimeDisplay"
Write-Output "- Write actions: none"
Write-Output ""

Write-Output "## Desktop/runtime candidates"
if ($desktopAreas.Count -eq 0) {
    Write-Output "- No desktop/runtime candidate paths are mapped for this platform yet."
} else {
    foreach ($area in $desktopAreas) {
        $exists = Test-Path -LiteralPath $area.Path -ErrorAction SilentlyContinue
        Write-Output ("- {0}: exists={1}, handling={2}, path={3}" -f $area.Name, $exists, $area.Handling, $area.Path)
    }
}

Write-Output ""
Write-Output "## Support level"
if ($platform -eq "Windows") {
    Write-Output "- Windows: full supported path set for audit and conservative dry-run cleanup."
} elseif ($platform -eq "macOS") {
    Write-Output "- macOS: supported for .codex audit, retention planning, and conservative .codex cleanup; Desktop/runtime areas remain audit-only until locally confirmed."
} else {
    Write-Output "- Other platforms: .codex audit may work, but Desktop/runtime paths are not localized by default."
}
