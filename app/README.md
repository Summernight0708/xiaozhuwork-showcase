# 小猪作业应用源码

## 项目结构

| 目录 | 内容 |
| --- | --- |
| `src/` | Vue Web 应用：项目、成员、任务、提交、验收、文件、贡献与报告 |
| `src-ops/` | Ops 管理界面 |
| `src-shared/` | 共享类型与工具 |
| `supabase/migrations/` | PostgreSQL 数据库迁移、业务函数与权限策略 |
| `supabase/functions/` | Edge Functions 与共享后端逻辑 |
| `supabase/tests/` | 数据库与 Edge Function 测试 |
| `android/` | Capacitor Android 工程 |
| `tests/` | 单元、端到端及专项测试 |
| `scripts/` | 构建、发布检查及开发工具 |

## 环境

- Node.js 24 与 Corepack。
- pnpm 版本由 `package.json` 的 `packageManager` 指定。
- 使用本地 Supabase 时，准备 Docker 和 Supabase CLI。
- Android 构建使用 Android SDK 与对应 Java 环境。

## 安装与配置

在 `app/` 目录运行：

```bash
corepack pnpm install --frozen-lockfile
```

以 `.env.example` 为模板创建 `.env.local`，填写自己的开发环境参数：

```dotenv
VITE_SUPABASE_URL=<开发环境的 API URL>
VITE_SUPABASE_PUBLISHABLE_KEY=<开发环境的 publishable key>
```

也可通过 `VITE_SUPABASE_ANON_KEY` 配置兼容的 anon key。

本地 Supabase 的启动与状态命令已配置在项目脚本中：

```bash
corepack pnpm db:start
corepack pnpm db:status
```

将本地实例输出的 API URL 与客户端 key 填入 `.env.local`。首次创建本地实例时，Supabase 根据 `supabase/migrations/` 建立数据库结构。

## 启动

```bash
corepack pnpm dev
```

Ops 管理界面：

```bash
corepack pnpm dev:ops
```

## 检查与构建

```bash
corepack pnpm typecheck
corepack pnpm typecheck:ops
corepack pnpm test
corepack pnpm build
corepack pnpm build:ops
```

数据库测试：

```bash
corepack pnpm db:test
```

Android 调试构建：

```bash
corepack pnpm android:debug
```

命令对应的具体工具和参数见 `package.json`。
