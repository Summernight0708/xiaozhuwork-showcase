# 报告生成探测工具

这两份脚本用于开发过程中检查项目报告的生成结果、耗时和资源使用情况。在 `app/` 目录执行。

## PDF 生成探测

```bash
corepack pnpm probe:report-pdf
```

`scripts/probe-report-pdf.ts` 使用内置示例项目快照，调用报告渲染函数，先预热再连续生成 1,000 次 PDF，记录生成耗时、CPU 时间、内存与结果指纹。

默认输出 PDF 到 `.tmp/xiaozhuwork-report-probe.pdf`，控制台输出 JSON 指标。指定其他输出位置：

```bash
corepack pnpm probe:report-pdf ./report-probe.pdf
```

该脚本直接调用本地报告渲染模块，使用示例任务、成员和贡献记录。

## 本地 Edge Runtime 探测

```bash
corepack pnpm probe:report-edge
```

`scripts/probe-report-edge.mjs` 在本地 Supabase 环境中检查 `export-project-report` 的启动、请求响应和容器资源指标。

运行前准备：

- 启动当前项目的本地 Supabase。
- 确认本地运行容器名为 `supabase_edge_runtime_xiaozhuwork`。
- 在开发数据中准备脚本使用的报告 ID：`f8000000-0000-4000-8000-000000000001`。

脚本从本地 `supabase status` 取得连接参数，重启该本地 Edge Runtime 容器，启动报告函数并发出请求。完成后停止由脚本启动的函数进程。

输出包括函数就绪时间、请求耗时、HTTP 状态、响应摘要，以及 Linux cgroup 提供的 CPU 和内存指标。这里使用本地匿名客户端身份，HTTP 状态可用于检查对应的鉴权行为。

## CI

仓库根目录 `.github/workflows/ci.yml` 组织代码检查、类型检查、单元测试、构建与本地 Supabase 集成验证。应用命令统一从 `app/` 执行，pnpm 缓存关联 `app/pnpm-lock.yaml`。
