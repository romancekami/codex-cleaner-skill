$ErrorActionPreference = "Stop"

function Get-CodexCleanerPlatform {
    if ($env:OS -eq "Windows_NT" -or $PSVersionTable.PSEdition -eq "Desktop") {
        return "Windows"
    }
    if ((Get-Variable -Name IsMacOS -Scope Global -ErrorAction SilentlyContinue) -and $IsMacOS) {
        return "macOS"
    }
    if ((Get-Variable -Name IsLinux -Scope Global -ErrorAction SilentlyContinue) -and $IsLinux) {
        return "Linux"
    }
    return "Unknown"
}

function Get-CodexCleanerHomePath {
    $homePath = if ($env:USERPROFILE) { $env:USERPROFILE } elseif ($env:HOME) { $env:HOME } else { [Environment]::GetFolderPath("UserProfile") }
    if (-not $homePath) {
        throw "Unable to determine the current user's home directory."
    }
    return $homePath
}

function Get-CodexCleanerDefaultRoot {
    return Join-Path (Get-CodexCleanerHomePath) ".codex"
}

function Get-CodexCleanerTempPath {
    $tempPath = if ($env:TEMP) { $env:TEMP } elseif ($env:TMPDIR) { $env:TMPDIR } else { [System.IO.Path]::GetTempPath() }
    if (-not $tempPath) {
        throw "Unable to determine the current user's temp directory."
    }
    return $tempPath
}

function Test-CodexCleanerPathUnder {
    param(
        [string]$Path,
        [string]$Parent
    )

    $resolvedPath = (Get-Item -LiteralPath $Path -Force).FullName.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $resolvedParent = (Get-Item -LiteralPath $Parent -Force).FullName.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $separator = [System.IO.Path]::DirectorySeparatorChar
    return $resolvedPath.StartsWith($resolvedParent + $separator, [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-CodexCleanerCodexProcess {
    $platform = Get-CodexCleanerPlatform

    if ($platform -eq "Windows") {
        try {
            $processes = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue
            foreach ($process in $processes) {
                $name = ""
                $commandLine = ""
                if ($null -ne $process.Name) { $name = [string]$process.Name }
                if ($null -ne $process.CommandLine) { $commandLine = [string]$process.CommandLine }

                if ($name -match "(?i)^codex(\.exe)?$") { return $true }
                if ($commandLine -match "(?i)OpenAI\.Codex_|OpenAI\\Codex|\\codex\.exe") { return $true }
            }
        } catch {
            return $false
        }
        return $false
    }

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

            if ($name -match "(?i)^codex$") { return $true }
            if ($path -match "(?i)(OpenAI|Codex)") { return $true }
        }
    } catch {
        return $false
    }

    return $false
}

function Get-CodexCleanerDesktopAreas {
    $platform = Get-CodexCleanerPlatform
    $homePath = Get-CodexCleanerHomePath

    if ($platform -eq "Windows" -and $env:LOCALAPPDATA) {
        return @(
            [pscustomobject]@{ Name = "openai-codex-runtime"; Path = (Join-Path $env:LOCALAPPDATA "OpenAI\Codex"); Handling = "manual-review"; Reason = "Codex Desktop AppData runtime/log area." },
            [pscustomobject]@{ Name = "codex-desktop-logs"; Path = (Join-Path $env:LOCALAPPDATA "Codex"); Handling = "manual-review"; Reason = "Codex Desktop AppData runtime/log area." },
            [pscustomobject]@{ Name = "windows-app-package-state"; Path = (Join-Path $env:LOCALAPPDATA "Packages\OpenAI.Codex_2p2nqsd0c76g0"); Handling = "avoid"; Reason = "Windows app package state." }
        )
    }

    if ($platform -eq "macOS") {
        return @(
            [pscustomobject]@{ Name = "openai-codex-application-support"; Path = (Join-Path $homePath "Library/Application Support/OpenAI/Codex"); Handling = "manual-review"; Reason = "macOS Application Support candidate; audit only." },
            [pscustomobject]@{ Name = "codex-application-support"; Path = (Join-Path $homePath "Library/Application Support/Codex"); Handling = "manual-review"; Reason = "macOS Application Support candidate; audit only." },
            [pscustomobject]@{ Name = "openai-codex-cache"; Path = (Join-Path $homePath "Library/Caches/OpenAI/Codex"); Handling = "manual-review"; Reason = "macOS cache candidate; audit only." },
            [pscustomobject]@{ Name = "codex-logs"; Path = (Join-Path $homePath "Library/Logs/Codex"); Handling = "manual-review"; Reason = "macOS logs candidate; audit only." }
        )
    }

    return @()
}

function Get-CodexCleanerRuntimeRoot {
    $platform = Get-CodexCleanerPlatform
    $homePath = Get-CodexCleanerHomePath

    if ($platform -eq "Windows" -and $env:LOCALAPPDATA) {
        return Join-Path $env:LOCALAPPDATA "OpenAI\Codex"
    }
    if ($platform -eq "macOS") {
        return Join-Path $homePath "Library/Application Support/OpenAI/Codex"
    }

    return $null
}

function Get-CodexCleanerThirdPartyAreas {
    $platform = Get-CodexCleanerPlatform
    $homePath = Get-CodexCleanerHomePath

    if ($platform -eq "Windows" -and $env:LOCALAPPDATA) {
        return @(
            [pscustomobject]@{ Name = "CodeX++"; Path = (Join-Path $env:LOCALAPPDATA "com.bigpizzav3.codexplusplus.manager") },
            [pscustomobject]@{ Name = "CC Switch"; Path = (Join-Path $env:LOCALAPPDATA "com.ccswitch.desktop") }
        )
    }

    if ($platform -eq "macOS") {
        return @(
            [pscustomobject]@{ Name = "CodeX++"; Path = (Join-Path $homePath "Library/Application Support/com.bigpizzav3.codexplusplus.manager") },
            [pscustomobject]@{ Name = "CC Switch"; Path = (Join-Path $homePath "Library/Application Support/com.ccswitch.desktop") }
        )
    }

    return @()
}
