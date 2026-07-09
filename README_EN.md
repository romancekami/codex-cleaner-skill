# Codex Cleaner Skill

[English](README_EN.md) | [简体中文](README.md)

`codex-cleaner` is a conservative Codex Desktop cleanup skill for auditing local Codex storage, planning daily-report retention, and dry-running safe cleanup candidates.

## What It Does

- Audits `<home>/.codex` without reading full thread contents.
- Helps plan daily-report retention: archive after 14 days, delete after 30 days, only after dry-run and confirmation.
- Checks Codex Desktop runtime/cache/temp areas on Windows and macOS.
- Keeps risky areas read-only by default, including sessions, SQLite/state databases, config/auth files, complete runtime directories, skills, plugins, memories, and automations.

## Platform Support

- Windows: full supported path set for `.codex`, AppData/runtime audit, user temp dry-run, and conservative `.codex` cleanup.
- macOS: supported for `.codex` audit, retention planning, user temp dry-run, and conservative `.codex` cleanup when PowerShell 7 (`pwsh`) is available. `~/Library` runtime areas are audit-only until locally confirmed.

## Quick Start

Install by copying this folder to your Codex skills directory, for example:

```powershell
# Windows
$HOME\.codex\skills\codex-cleaner
```

```bash
# macOS
~/.codex/skills/codex-cleaner
```

Run the health check from the skill folder:

```powershell
# Windows
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\health-check.ps1
```

```bash
# macOS / PowerShell 7
pwsh -NoProfile -File ./scripts/health-check.ps1
```

For a full read-only dry-run entrypoint:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-external-agent.ps1
```

```bash
pwsh -NoProfile -File ./scripts/run-external-agent.ps1
```

For repeat checks after a recent full audit, use fast mode. It keeps the health check and runtime cleanup dry-run, but skips the slower storage audit and runtime-integrity scan:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-external-agent.ps1 -Fast -IncludeSystemTemp
```

## Safety Model

Default behavior is audit-only or dry-run. Actual cleanup requires reviewing the dry-run output first and explicitly opting into the exact cleanup category. Do not use this skill to delete complete runtime directories, SQLite databases, credentials, or session files directly.

After archiving daily-report threads, refresh thread metadata and repeat the dry-run until archive/delete counts are zero. Older matching threads can appear after newer reports are archived.

## Publishing to SkillHub

Recommended update flow:

1. Change repository files and run the relevant checks.
2. Commit and push to GitHub.
3. Build a clean zip package, then publish that zip with the SkillHub CLI.

Do not publish the repository directory directly with `skillhub publish .`. The SkillHub server rejects files such as `.gitignore`, `.gitattributes`, and extensionless `LICENSE`. Use the helper script instead; it checks that git is clean and pushed, packages only the skill files, and calls `skillhub publish`.

Dry-run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\publish-skillhub.ps1 -DryRun -Changelog "Update notes"
```

Publish:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\publish-skillhub.ps1 -Changelog "Update notes"
```

The script reads `slug` and `version` from `SKILL.md`, creates a temporary zip, and runs:

```powershell
skillhub publish <zip> --version <version> --changelog "Update notes" --json
```

Use `-SkipGitCheck` only for local packaging tests before commit/push.
