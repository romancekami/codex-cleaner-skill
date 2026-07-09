---
name: codex-cleaner
description: "安全审计并清理 Codex Desktop 本地存储，覆盖 Windows 和 macOS，重点处理 .codex、Codex Desktop runtime/cache/temp 残留、旧日报线程归档和保留策略。适用于查看 Codex 磁盘占用、清理低风险临时文件、归档旧日报、删除过期日报会话或设计安全的 Codex 保留策略。"
slug: codex-cleaner-romancekami
displayName: Codex Cleaner
version: 0.1.3
summary: 安全审计和清理 Codex Desktop 本地存储的跨平台 Skill
license: MIT
---

# Codex Cleaner

Codex Cleaner 用来安全检查 Codex Desktop 的本地存储占用、管理旧日报线程，并清理低风险的 Codex runtime 临时残留。主要用户数据目录是 `<home>/.codex`；Windows 的 Desktop runtime 区域位于 `%LOCALAPPDATA%`，macOS 的 Desktop/runtime 区域默认只做审计，位于 `~/Library` 下。本 Skill 支持 `.codex` 审计、覆盖范围和风险分级、外部 agent dry-run 入口、runtime integrity 只读检查、平台检测，以及 macOS 审计优先流程。默认只做 dry-run，不直接编辑 SQLite 数据，也不读取完整旧线程内容。

使用 PowerShell 脚本时，按平台选择前缀：

- Windows：`powershell -NoProfile -ExecutionPolicy Bypass -File`
- macOS 或 PowerShell 7：`pwsh -NoProfile -File`

以下示例都假设在 skill 目录中运行，并使用 `<ps>` 代表上面的 PowerShell 前缀。

## 中文输出规则

当用户使用中文或偏好中文时，最终回答必须使用这三个中文分组：

- `现在可做`：低风险 dry-run 或已经白名单的候选项；真正写入前仍需要用户确认。
- `需要确认`：可能可以清理，但需要人工审查、开启类别开关，或先完全关闭 Codex。
- `不要触碰`：会话、SQLite/state 数据库、认证和配置、skills/plugins 源码、memories、automations、完整 AppData `bin` 或 `runtimes`、Windows package state，以及第三方应用目录。

最终面向用户的总结不要只使用英文标签，例如 `Can run now`、`Manual-review` 或 `Avoid`。如果脚本输出英文标签，最终总结里要翻译成中文。

## 外部 Agent 用法

如果 Codex Desktop 已关闭，且由 OpenCode、Hermes、Claude Code 或其他 agent 运行这个目录，不要依赖 Codex 专属的 skill 加载机制。应直接从 skill 目录运行 PowerShell 脚本：

```powershell
<ps> ./scripts/run-external-agent.ps1
```

这个外部 agent 入口只运行 health check、存储审计和 runtime cleanup dry-run，不会删除任何文件。若要把用户 TEMP 目录里的 Codex 临时残留也列入 dry-run 候选：

```powershell
<ps> ./scripts/run-external-agent.ps1 -IncludeSystemTemp
```

如果刚做过完整审计，只是复验或做常规轻量检查，可以使用快速模式。它保留 health check 和 runtime cleanup dry-run，但跳过较慢的存储审计和 runtime-integrity 扫描：

```powershell
<ps> ./scripts/run-external-agent.ps1 -Fast -IncludeSystemTemp
```

非 Codex agent 运行前，也要先阅读本目录中的 `AGENTS.md`，再执行任何清理命令。

## SkillHub 发布流程

更新公开的 SkillHub 包时，按这个顺序执行：

1. 修改仓库文件，并运行必要验证。
2. commit 并 push 到 GitHub。
3. 发布干净 zip 包，不要直接发布整个仓库目录。

不要在仓库根目录直接运行 `skillhub publish .`。SkillHub 服务端会拒绝 `.gitignore`、`.gitattributes`、无扩展名 `LICENSE` 等仓库本地文件。使用内置发布脚本：

```powershell
<ps> ./scripts/publish-skillhub.ps1 -DryRun -Changelog "更新说明"
<ps> ./scripts/publish-skillhub.ps1 -Changelog "更新说明"
```

脚本会从 `SKILL.md` 读取 `slug` 和 `version`，默认检查 git 工作区干净且已推送；除非显式使用 `-SkipGitCheck`，否则不会在未提交或未推送状态下发布。脚本会构建一个只包含 SkillHub 可接受文件的临时 zip，然后调用 `skillhub publish <zip> --version <version> --changelog ... --json`。

## 平台支持

- Windows：完整支持 `.codex`、Codex Desktop AppData/runtime 审计、用户 TEMP dry-run，以及保守的 `.codex` 清理。
- macOS：支持 `.codex` 审计、日报保留策略、用户 TEMP dry-run，以及安装 PowerShell 7 (`pwsh`) 后的保守 `.codex` 清理。`~/Library` 下的 Codex Desktop/runtime 区域默认只做审计，除非已经在用户机器上确认过具体路径和风险。
- Linux 或未知平台：先运行环境检测；Desktop/runtime 路径需要根据本地环境适配，除非脚本已经报告了明确映射。
- 不要跨平台默认清理完整 app runtime 目录。runtime 清理必须保持按类别处理，并且先 dry-run。

## 工作流

1. 先运行健康检查。它是只读操作：

```powershell
<ps> ./scripts/health-check.ps1
```

如果 health check 报告 `FAIL`，停止并汇报失败项。如果报告 `WARN`，仍可继续 dry-run，但 archive/delete 等写操作必须先停止，直到 warning 被理解和处理。

2. 当宿主系统或安装路径不确定时，运行环境检测：

```powershell
<ps> ./scripts/detect-environment.ps1
```

3. 运行内置审计脚本：

```powershell
<ps> ./scripts/audit-codex.ps1
```

4. 运行 runtime integrity 审计。它是只读诊断，用来检查 app runtime 健康状态，不是清理命令：

```powershell
<ps> ./scripts/runtime-integrity.ps1
```

5. 只总结真正有用的发现：

- `.codex` 总大小
- 已知大目录
- Codex Desktop app runtime/log/cache 区域
- 用户 TEMP 里的 Codex 残留
- V5 覆盖范围图，包括处理方式（`safe`、`manual-review`、`avoid`）和原因
- runtime-integrity 对 `bin`、`runtimes`、`.staging-*`、运行进程引用和 `config.toml` 引用的检查结果
- 按文件 mtime 统计的旧 session 文件数量
- 按 `现在可做`、`需要确认`、`不要触碰` 分组的清理建议

6. 对 Codex runtime 垃圾文件，运行 runtime cleanup planner。默认是 dry-run：

```powershell
<ps> ./scripts/cleanup-runtime.ps1
```

检查点 / 停止：运行 `-Execute` 前，必须确认 dry-run 输出只包含预期候选项。V3 默认执行只会删除白名单内过期的 `.tmp` 项：

```powershell
<ps> ./scripts/cleanup-runtime.ps1 -Execute
```

V4 也可以列出用户 TEMP 中的 Codex 残留，例如旧的 `codex-clipboard-*.png`、`codex-*-readonly` 和 `openai-docs-cache`。这些默认仍属于人工确认项，只有用户在看到 dry-run 后明确要求清理 TEMP，才可以继续：

```powershell
<ps> ./scripts/cleanup-runtime.ps1 -IncludeSystemTemp
```

7. 对日报保留策略，只列出线程 metadata。不要读取完整线程正文、长 preview 或 rollout JSON。只精确匹配这些标题：

- `AI 应用端日报`
- `GitHub 工具日报`

8. 应用这个保留策略：

- 超过 `14` 天：归档。
- 超过 `30` 天：删除。
- 跳过置顶线程、当前线程、非日报工作线程、标题不明确的线程、非法 UUID 和运行中线程。

9. 使用这个保留策略执行链：

- `dry-run`：先不带执行开关运行保留脚本，并展示 keep/archive/delete/skip 计数。
- `user confirmation`：只有 dry-run 中出现 archive 或 delete 候选时，才请求用户确认。
- `execute`：确认后才运行 `-ExecuteArchive` 或 `-ExecuteArchive -ExecuteDelete`。
- `repeat`：归档后刷新线程 metadata，并重复 dry-run，直到 archive/delete 计数为 `0`。因为归档较新的日报后，更旧的同标题日报可能才会出现在列表中。

10. 对可重复的保留策略检查，把脱敏后的 metadata 传给内置脚本。不要包含 `preview` 或消息正文。每一项必须使用下面这个最小结构：

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

必须先不带执行开关运行。

检查点 / 停止：归档前，确认 dry-run 只列出超过 `14` 天且标题精确匹配的日报：

```powershell
<ps> ./scripts/apply-daily-retention.ps1 -CandidatesJson '<json>' -ExecuteArchive
```

检查点 / 停止：只有用户明确要求执行清理，且 dry-run 列出超过 `30` 天、标题精确匹配的日报时，才可以使用删除：

```powershell
<ps> ./scripts/apply-daily-retention.ps1 -CandidatesJson '<json>' -ExecuteArchive -ExecuteDelete
```

## 安全规则

- 不要运行临时拼出来的递归删除命令。唯一允许的递归删除，是用户确认 dry-run 和检查点之后，通过 `cleanup-runtime.ps1 -Execute` 删除脚本验证过、位于允许 `.codex` 根目录下的候选项。
- 不要直接删除 `.jsonl`、SQLite、config、credentials、plugin、skill 或 memory 文件。
- 清理过程中不要修改 `config.toml`、`auth.json`、SQLite、`automations`、`skills` 或 `memories`。
- runtime cleanup 默认只能执行对 `.codex\.tmp` 下已验证候选项的清理。
- `.codex\backups` 和 `.codex\cache` 默认属于 `manual-review`，除非用户在看过 dry-run 后明确要求处理这些类别。
- V4 可以扫描 Codex Desktop app runtime 区域和用户 TEMP 里的 Codex 残留，但清理 `.codex/.tmp` 之外的内容需要明确的类别开关和用户确认。
- V5 覆盖范围图只是审计建议，不是删除授权。AppData runtime、Windows package state、SQLite/state 数据库和 session 文件必须保持 `manual-review` 或 `avoid`，除非未来版本加入具体且验证过的流程。
- V7/V8 runtime-integrity 结果是只读诊断，不授权删除完整 `bin` hash 目录、完整 `runtimes` 目录、macOS `~/Library` runtime 目录或 config 引用。
- 排除第三方应用，包括 CC Switch (`com.ccswitch.desktop`) 和 CodeX++ (`com.bigpizzav3.codexplusplus.manager`)。
- 如果保留策略脚本可以先验证候选项，不要手动运行 `codex delete`。
- 除非用户看过或接受 dry-run 规则后明确要求实际清理，否则不要执行删除。
- 如果路径不符合预期，停止并先询问用户，不要继续建议操作。

## 失败停止条件

- 不要隐藏脚本错误。如果脚本抛错或返回非零退出码，先报告失败步骤和错误信息，再建议下一步。
- 如果线程 metadata 包含 `preview`、消息正文或 rollout JSON，停止并重新构建只含 metadata 的候选列表。
- 如果 `codex` CLI 不可用，在 archive/delete 执行前停止，并说明本次无法安全执行删除。
- 如果 dry-run 列出非白名单标题、当前线程、置顶线程、运行中线程、非法 UUID 或缺失 `createdAt` 的项，不要覆盖 skip 判断。
- 如果 runtime cleanup 显示 `.codex/.tmp` 之外的候选项，但用户没有明确要求处理该类别，保持为人工确认项。
- 如果候选路径位于 CC Switch 或 CodeX++ 目录下，停止，不要把它当作 Codex Desktop 清理项。
- 如果 Codex 看起来正在运行，runtime/app-support/database 清理保持只读审计，除非用户在 dry-run 后明确接受该具体类别。
- 如果 `runtime-integrity.ps1` 报告 app runtime 路径被运行中进程引用，本轮不要建议 runtime 清理。

## 输出格式

保持回答简短：

- `当前状态`：总大小和最大区域。
- `运行清理`：temp/cache/backup 候选项，以及本次是否为 dry-run。
- `日报保留`：keep、archive、delete 和 skipped 计数。
- `清理建议`：按 `现在可做`、`需要确认`、`不要触碰` 分组。
- `验证`：使用的命令或工具，以及本次是否发生写操作。
