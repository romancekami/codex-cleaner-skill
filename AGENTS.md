Codex Cleaner is a PowerShell cleanup skill for OpenAI Codex Desktop local data. Windows is fully supported; macOS is supported for `.codex` audit and conservative cleanup, with Desktop/runtime areas kept audit-only until locally confirmed.

Use this folder from Codex, OpenCode, Hermes, Claude Code, or another agent by running the scripts directly. Do not assume the host agent understands Codex skill frontmatter.

If the user writes Chinese or prefers Chinese, final summaries should be in Simplified Chinese. Group cleanup advice as:

- `现在可做`: low-risk dry-run or already-whitelisted cleanup.
- `需要确认`: review-only or category-switch cleanup candidates.
- `不要触碰`: protected data, runtime internals, or third-party apps.

Default workflow:

```powershell
# Windows: powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-external-agent.ps1
# macOS / PowerShell 7: pwsh -NoProfile -File ./scripts/run-external-agent.ps1
```

Safety rules:

- Start with health check, audit, and dry-run only.
- Use `detect-environment.ps1` first when the OS or install path is uncertain.
- Use `runtime-integrity.ps1` to inspect app runtime `bin`, `runtimes`, `.staging-*`, running process references, and config references before discussing runtime cleanup.
- Do not delete `.jsonl`, SQLite, config, credentials, skills, plugins, memories, or automation files directly.
- Do not delete complete Codex AppData/Library `bin` hash directories or complete `runtimes` directories from this skill.
- Do not clean CC Switch or CodeX++ directories.
- If Codex Desktop is running, keep AppData/runtime/database cleanup audit-only.
- Only execute cleanup after the user reviews the dry-run output and explicitly asks for that exact category.
