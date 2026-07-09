# Codex Cleaner Skill

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

## Safety Model

Default behavior is audit-only or dry-run. Actual cleanup requires reviewing the dry-run output first and explicitly opting into the exact cleanup category. Do not use this skill to delete complete runtime directories, SQLite databases, credentials, or session files directly.
