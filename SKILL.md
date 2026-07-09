---
name: codex-cleaner
description: "Audit and safely clean Codex Desktop storage on Windows and macOS, centered on .codex plus Codex Desktop runtime/cache/temp leftovers. Use when the user asks to inspect Codex disk usage, reduce old Codex sessions, clean daily report history, archive old Codex threads, delete expired daily-report sessions, remove Codex temp/cache/junk files, or design a safe Codex retention policy."
---

# Codex Cleaner

Use this skill to inspect Codex Desktop local storage safely, manage old daily-report threads, and clean low-risk Codex runtime leftovers. The main user-data root is `<home>/.codex`; Windows Desktop runtime areas are under `%LOCALAPPDATA%`, while macOS Desktop runtime areas are treated as audit-only candidates under `~/Library`. V4 audits Codex Desktop runtime/log areas and user temp leftovers; V5 adds a read-only coverage map and risk classification; V6 adds a generic external-agent dry-run entrypoint for OpenCode, Hermes, Claude Code, and similar tools; V7 adds a read-only runtime-integrity audit for app runtime `bin` and `runtimes`; V8 adds platform detection and macOS audit-first support. Default to dry-run. Do not edit SQLite data or read full old thread contents.

Use the appropriate PowerShell prefix:

- Windows: `powershell -NoProfile -ExecutionPolicy Bypass -File`
- macOS or PowerShell 7: `pwsh -NoProfile -File`

Run examples from the skill folder. Examples below use `<ps>` as the prefix placeholder.

## Chinese Output Rules

When the user writes Chinese or prefers Chinese, use these Chinese cleanup groups:

- `现在可做`: low-risk dry-run or already-whitelisted cleanup, still requiring confirmation before any write action.
- `需要确认`: items that may be cleanable but need user review, a category switch, or Codex fully closed first.
- `不要触碰`: sessions, SQLite/state databases, auth/config, skills/plugins source, memories, automations, complete AppData `bin` or `runtimes`, Windows package state, and third-party apps.

Avoid English-only labels such as `Can run now`, `Manual-review`, or `Avoid` in the final user-facing answer. If a script prints English labels, translate them in the final summary.

## External Agent Use

If Codex Desktop is closed and another agent is running this folder, do not rely on Codex-only skill loading. Run the PowerShell scripts directly from the skill directory:

```powershell
<ps> ./scripts/run-external-agent.ps1
```

This external-agent entrypoint runs health check, storage audit, and runtime cleanup dry-run only. It performs no deletion. To include user TEMP Codex leftovers in the dry-run candidate list:

```powershell
<ps> ./scripts/run-external-agent.ps1 -IncludeSystemTemp
```

For non-Codex agents, also read `AGENTS.md` in this folder before running any cleanup command.

## Platform Support

- Windows: full supported path set for `.codex`, Codex Desktop AppData/runtime audit, user temp dry-run, and conservative `.codex` cleanup.
- macOS: supported for `.codex` audit, daily-report retention planning, user temp dry-run, and conservative `.codex` cleanup when PowerShell 7 (`pwsh`) is available. `~/Library` Codex Desktop/runtime areas are audit-only until confirmed on the user's machine.
- Linux or unknown platforms: run environment detection first; treat Desktop/runtime paths as local adaptation work unless the script reports a mapped path.
- Never clean complete app runtime directories cross-platform by default. Runtime cleanup must stay category-based and dry-run first.

## Workflow

1. Run the health check first. It is read-only:

```powershell
<ps> ./scripts/health-check.ps1
```

If the health check reports `FAIL`, stop and report the failing check. If it reports `WARN`, dry-run is still allowed, but archive/delete execution must stop until the warning is understood.

2. Run environment detection when the host OS or install path is uncertain:

```powershell
<ps> ./scripts/detect-environment.ps1
```

3. Run the bundled audit script:

```powershell
<ps> ./scripts/audit-codex.ps1
```

4. Run the runtime integrity audit. It is read-only and checks app runtime health, not cleanup:

```powershell
<ps> ./scripts/runtime-integrity.ps1
```

5. Summarize only the useful findings:

- `.codex` total size
- largest known subdirectories
- Codex Desktop app runtime/log/cache areas
- user TEMP Codex leftovers
- V5 coverage map with handling (`safe`, `manual-review`, `avoid`) and reason
- runtime-integrity findings for `bin`, `runtimes`, `.staging-*`, running process references, and `config.toml` references
- old session-file count by file mtime
- cleanup suggestions grouped as `现在可做`, `需要确认`, and `不要触碰`

6. For Codex runtime junk, run the runtime cleanup planner. It defaults to dry-run:

```powershell
<ps> ./scripts/cleanup-runtime.ps1
```

CHECKPOINT / STOP: before running `-Execute`, confirm the dry-run output shows only expected candidates. V3 execution only removes whitelisted expired `.tmp` entries by default:

```powershell
<ps> ./scripts/cleanup-runtime.ps1 -Execute
```

V4 can also list user TEMP Codex leftovers such as old `codex-clipboard-*.png`, `codex-*-readonly`, and `openai-docs-cache`. These remain manual-review unless the user explicitly asks for TEMP cleanup after seeing the dry-run:

```powershell
<ps> ./scripts/cleanup-runtime.ps1 -IncludeSystemTemp
```

7. For daily-report retention, list thread metadata only. Do not read full thread bodies, long previews, or rollout JSON. Match only exact titles:

- `AI 应用端日报`
- `GitHub 工具日报`

8. Apply this retention policy:

- Older than `14` days: archive.
- Older than `30` days: delete.
- Skip pinned threads, the current thread, non-report work threads, ambiguous titles, invalid UUIDs, and running threads.

9. Use this retention execution chain:

- `dry-run`: run the retention script without execution switches and show the keep/archive/delete/skip counts.
- `user confirmation`: ask for confirmation only when the dry-run contains archive or delete candidates.
- `execute`: run `-ExecuteArchive` or `-ExecuteArchive -ExecuteDelete` only after confirmation.

10. For repeatable retention checks, pass sanitized metadata to the bundled retention script. Do not include `preview` or message content. Each item must use this minimal shape:

```json
[
  {
    "id": "11111111-1111-1111-1111-111111111111",
    "title": "AI 应用端日报",
    "createdAt": "2026-07-01T05:00:00+08:00",
    "status": "completed",
    "isCurrent": false,
    "isPinned": false
  }
]
```

```powershell
<ps> ./scripts/apply-daily-retention.ps1 -CandidatesJson '<json>'
```

Run without execution switches first.

CHECKPOINT / STOP: before archiving, confirm the dry-run only lists exact-title daily reports older than `14` days:

```powershell
<ps> ./scripts/apply-daily-retention.ps1 -CandidatesJson '<json>' -ExecuteArchive
```

CHECKPOINT / STOP: only use deletion when the user explicitly asks to execute cleanup and the dry-run lists exact-title daily reports older than `30` days:

```powershell
<ps> ./scripts/apply-daily-retention.ps1 -CandidatesJson '<json>' -ExecuteArchive -ExecuteDelete
```

## Safety Rules

- Do not run ad hoc recursive deletion commands. The only allowed recursive removal is through `cleanup-runtime.ps1 -Execute` after its dry-run and checkpoint, and only for candidates the script has validated under its allowed `.codex` roots.
- Do not delete `.jsonl`, SQLite, config, credentials, plugin, skill, or memory files directly.
- Do not modify `config.toml`, `auth.json`, `sqlite`, `automations`, `skills`, or `memories` during cleanup.
- Runtime cleanup may only execute on validated candidates under `.codex\.tmp` by default.
- Treat `.codex\backups` and `.codex\cache` as manual-review unless the user explicitly asks for those categories after seeing dry-run output.
- V4 may scan Codex Desktop app runtime areas and user temp Codex leftovers, but cleanup execution outside `.codex/.tmp` requires an explicit category switch and user confirmation.
- V5 coverage-map entries are audit guidance, not permission to delete. Keep AppData runtime, Windows app package state, SQLite/state databases, and session files as `manual-review` or `avoid` unless a later version adds a specific validated workflow.
- V7/V8 runtime-integrity findings are read-only diagnostics. They do not authorize deleting complete `bin` hash directories, complete `runtimes` directories, macOS `~/Library` runtime directories, or config references.
- Exclude third-party apps from this skill, including CC Switch (`com.ccswitch.desktop`) and CodeX++ (`com.bigpizzav3.codexplusplus.manager`).
- Do not run `codex delete` by hand when the retention script can validate the candidate first.
- Do not execute deletion unless the user has explicitly asked for actual cleanup after seeing or accepting the dry-run rule.
- If a path is unexpected, stop and ask before suggesting any action.

## Failure Stops

- Do not hide script errors. If a script throws or returns a non-zero command failure, report the failing step and the error message before suggesting the next action.
- If thread metadata contains `preview`, message content, or rollout JSON, stop and rebuild a metadata-only candidate list.
- If `codex` CLI is unavailable, stop before archive/delete execution and report that deletion cannot be performed safely in this run.
- If a dry-run lists a non-whitelisted title, current thread, pinned thread, running thread, invalid UUID, or missing `createdAt`, do not override the skip.
- If runtime cleanup shows candidates outside `.codex/.tmp` without an explicit user request for that category, keep them as manual-review.
- If a candidate path is under CC Switch or CodeX++, stop and do not treat it as a Codex Desktop cleanup item.
- If Codex appears to be running, keep runtime/app-support/database cleanup as audit-only unless the user has explicitly accepted that specific category after a dry-run.
- If `runtime-integrity.ps1` reports running process references under app runtime paths, do not propose runtime cleanup in that run.

## Output Shape

Keep the response short:

- `当前状态`: total size and largest areas.
- `运行清理`: temp/cache/backup candidates and whether the run was dry-run.
- `日报保留`: counts for keep, archive, delete, and skipped candidates.
- `清理建议`: group recommendations under `现在可做`, `需要确认`, and `不要触碰`.
- `验证`: command or tool used, and whether any write action occurred.
