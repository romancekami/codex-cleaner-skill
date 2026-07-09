param(
    [string]$SkillRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$Version = "",
    [string]$Changelog = "",
    [string]$OutputPath = "",
    [string]$ApiHost = "",
    [switch]$DryRun,
    [switch]$SkipGitCheck
)

$ErrorActionPreference = "Stop"

function Get-FrontmatterValue {
    param(
        [string]$Text,
        [string]$Name
    )

    $match = [regex]::Match($Text, "(?m)^$([regex]::Escape($Name)):\s*(.+?)\s*$")
    if (-not $match.Success) {
        return ""
    }

    return $match.Groups[1].Value.Trim().Trim('"')
}

function Assert-GitReady {
    param([string]$Root)

    $git = Get-Command git -ErrorAction SilentlyContinue
    if (-not $git) {
        throw "git is required for the default publish guard. Use -SkipGitCheck only for local test packaging."
    }

    $inside = (& git -C $Root rev-parse --is-inside-work-tree 2>$null)
    if ($LASTEXITCODE -ne 0 -or $inside -ne "true") {
        throw "SkillRoot is not inside a git worktree: $Root"
    }

    $dirty = (& git -C $Root status --porcelain)
    if ($dirty) {
        throw "Git worktree has uncommitted changes. Commit them before publishing, or use -SkipGitCheck for a local dry-run."
    }

    & git -C $Root rev-parse --abbrev-ref --symbolic-full-name "@{u}" 1>$null 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Current branch has no upstream. Push the branch before publishing, or use -SkipGitCheck for a local dry-run."
    }

    $head = (& git -C $Root rev-parse HEAD).Trim()
    $upstream = (& git -C $Root rev-parse "@{u}").Trim()
    if ($head -ne $upstream) {
        throw "Local HEAD is not equal to upstream. Push GitHub first, then publish to SkillHub."
    }
}

function Copy-PublishFile {
    param(
        [string]$Source,
        [string]$DestinationRoot,
        [string]$RelativePath
    )

    $destination = Join-Path $DestinationRoot $RelativePath
    $parent = Split-Path -Parent $destination
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent | Out-Null
    }
    Copy-Item -LiteralPath $Source -Destination $destination
}

function New-SkillHubPackage {
    param(
        [string]$Root,
        [string]$ZipPath
    )

    $resolvedRoot = (Get-Item -LiteralPath $Root).FullName.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $stage = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-cleaner-skillhub-stage-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $stage | Out-Null

    $rootFiles = @("SKILL.md", "README.md", "README_EN.md")
    foreach ($fileName in $rootFiles) {
        $source = Join-Path $Root $fileName
        if (Test-Path -LiteralPath $source -PathType Leaf) {
            Copy-PublishFile -Source $source -DestinationRoot $stage -RelativePath $fileName
        }
    }

    $allowedDirs = @("scripts", "agents")
    $allowedExtensions = @(".ps1", ".md", ".yaml", ".yml", ".json", ".txt")
    foreach ($dirName in $allowedDirs) {
        $sourceDir = Join-Path $Root $dirName
        if (-not (Test-Path -LiteralPath $sourceDir -PathType Container)) {
            continue
        }

        Get-ChildItem -LiteralPath $sourceDir -Recurse -File -Force | ForEach-Object {
            if ($_.Name.StartsWith(".")) {
                return
            }
            if ($allowedExtensions -notcontains $_.Extension.ToLowerInvariant()) {
                return
            }

            $relative = $_.FullName.Substring($resolvedRoot.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
            Copy-PublishFile -Source $_.FullName -DestinationRoot $stage -RelativePath $relative
        }
    }

    if (-not (Test-Path -LiteralPath (Join-Path $stage "SKILL.md") -PathType Leaf)) {
        throw "Package stage is missing SKILL.md."
    }

    if (Test-Path -LiteralPath $ZipPath) {
        Remove-Item -LiteralPath $ZipPath -Force
    }

    Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $ZipPath -Force
    Remove-Item -LiteralPath $stage -Recurse -Force
}

$skillFile = Join-Path $SkillRoot "SKILL.md"
if (-not (Test-Path -LiteralPath $skillFile -PathType Leaf)) {
    throw "SKILL.md not found under SkillRoot: $SkillRoot"
}

$skillhub = Get-Command skillhub -ErrorAction SilentlyContinue
if (-not $skillhub) {
    throw "skillhub CLI is not available on PATH."
}

$skillText = Get-Content -Raw -LiteralPath $skillFile
$slug = Get-FrontmatterValue -Text $skillText -Name "slug"
if (-not $Version) {
    $Version = Get-FrontmatterValue -Text $skillText -Name "version"
}

if (-not $slug) {
    throw "SKILL.md frontmatter is missing slug."
}
if (-not $Version) {
    throw "SKILL.md frontmatter is missing version."
}
if (-not $DryRun -and -not $Changelog) {
    throw "Changelog is required for a real SkillHub publish."
}

if (-not $SkipGitCheck) {
    Assert-GitReady -Root $SkillRoot
}

if (-not $OutputPath) {
    $safeName = "{0}-{1}.zip" -f $slug, $Version
    $OutputPath = Join-Path ([System.IO.Path]::GetTempPath()) $safeName
}

New-SkillHubPackage -Root $SkillRoot -ZipPath $OutputPath

Write-Output "# SkillHub publish package"
Write-Output ("- Skill: {0}" -f $slug)
Write-Output ("- Version: {0}" -f $Version)
Write-Output ("- Package: {0}" -f $OutputPath)
Write-Output "- Excluded: .git*, LICENSE, AGENTS.md, and other non-skill root files"
Write-Output ("- Dry run: {0}" -f $DryRun.IsPresent)
Write-Output ""

$publishArgs = @("publish", $OutputPath, "--version", $Version, "--json")
if ($Changelog) {
    $publishArgs += @("--changelog", $Changelog)
}
if ($DryRun) {
    $publishArgs += "--dry-run"
}
if ($ApiHost) {
    $publishArgs += @("--host", $ApiHost)
}

& skillhub @publishArgs
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
