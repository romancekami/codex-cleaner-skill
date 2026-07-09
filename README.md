# Codex Cleaner Skill

安全审计和清理 Codex Desktop 本地存储的跨平台 Skill。

[English](README_EN.md) | 简体中文

`codex-cleaner` 的目标不是“自动把东西全删掉”，而是帮你先看清楚 Codex Desktop 在本机占用了哪些空间，再用 dry-run 和明确确认来处理低风险候选项。

## 适合什么场景

- Codex Desktop 会话、日报、缓存、临时文件越来越多，想先审计占用。
- 想给固定日报任务设置保留策略，例如 14 天后归档、30 天后删除。
- 想检查 `.codex`、Codex Desktop runtime、用户临时目录里有没有可清理候选。
- 想在 Codex 关闭后，用 OpenCode、Hermes、Claude Code 等其他 Agent 运行只读检查。

## 安全边界

默认行为是只读审计或 dry-run，不会直接删除文件。

这个 Skill 默认不会直接删除：

- `sessions` / `archived_sessions`
- SQLite / state 数据库
- `config.toml`、`auth.json`、credentials
- 完整 runtime 目录
- `skills`、`plugins`、`memories`、`automations`
- CC Switch、CodeX++ 等第三方应用目录

真正执行清理前，必须先看 dry-run 输出，再明确确认具体清理类别。

## 支持平台

- Windows：完整支持 `.codex`、AppData/runtime 审计、用户 temp dry-run、保守 `.codex` 清理。
- macOS：支持 `.codex` 审计、日报保留策略、用户 temp dry-run、保守 `.codex` 清理；`~/Library` 下的 Codex Desktop/runtime 区域默认只审计。
- Linux / 其他系统：可以先运行环境检测；Desktop/runtime 路径需要根据本地环境确认。

## 安装

把本仓库复制到 Codex skills 目录：

```powershell
# Windows
$HOME\.codex\skills\codex-cleaner
```

```bash
# macOS
~/.codex/skills/codex-cleaner
```

## 快速开始

在 skill 目录下运行健康检查：

```powershell
# Windows
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\health-check.ps1
```

```bash
# macOS / PowerShell 7
pwsh -NoProfile -File ./scripts/health-check.ps1
```

运行环境检测：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\detect-environment.ps1
```

运行完整只读 dry-run 入口：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-external-agent.ps1
```

刚做过完整审计后，如果只是复验或常规轻量检查，可以用快速入口。它保留健康检查和 runtime cleanup dry-run，但跳过较慢的存储审计和 runtime integrity 扫描：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-external-agent.ps1 -Fast -IncludeSystemTemp
```

macOS 或 PowerShell 7：

```bash
pwsh -NoProfile -File ./scripts/run-external-agent.ps1
```

## 日报保留策略

内置脚本支持对指定日报线程做保留规划：

- 超过 14 天：归档
- 超过 30 天：删除
- 只匹配精确白名单标题
- 跳过当前线程、置顶线程、运行中线程、非法 UUID、缺失时间的候选
- 输入只允许 metadata，不允许传入正文、preview 或旧 thread 内容

默认先 dry-run。只有确认后才执行 archive/delete。

归档后建议重新拉取线程 metadata 并重复 dry-run，直到 `Archive: 0`、`Delete: 0`。Codex 线程列表可能在归档较新的日报后露出更旧的同标题日报。

## 发布到 SkillHub

推荐更新顺序：

1. 修改仓库文件，并运行必要验证。
2. 提交并推送 GitHub。
3. 用发布脚本生成干净 zip 包，再调用 SkillHub CLI 发布。

不要直接把仓库目录交给 `skillhub publish .`。SkillHub 服务端会拒绝 `.gitignore`、`.gitattributes`、无扩展名 `LICENSE` 等文件。发布脚本默认检查当前 git 工作区已提交且已推送，然后只打包 SkillHub 需要的文件。

先预检：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\publish-skillhub.ps1 -DryRun -Changelog "更新说明"
```

正式发布：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\publish-skillhub.ps1 -Changelog "更新说明"
```

脚本会从 `SKILL.md` 读取 `slug` 和 `version`，生成临时 zip，并执行：

```powershell
skillhub publish <zip> --version <version> --changelog "更新说明" --json
```

如需只测试本地打包、但尚未 commit/push，可加 `-SkipGitCheck`；正式发布不建议跳过。

## 清理策略

推荐输出分三类：

- `现在可做`：低风险 dry-run 或已白名单候选，但写操作仍需确认。
- `需要确认`：可能可清理，但需要人工审查、开启类别开关，或先关闭 Codex。
- `不要触碰`：会话、数据库、认证配置、完整 runtime、技能源码、插件、记忆、自动化等高风险区域。

## 开源协议

MIT License。详见 [LICENSE](LICENSE)。
