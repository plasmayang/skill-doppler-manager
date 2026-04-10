# Doppler Manager Skill Specification (SOTA Zero-Trust)

## 1. 概览 (Overview)
本文档是 `doppler-manager` Skill 的声明式开发规范（Spec）。该 Skill 旨在赋予 Gemini CLI 及其他 AI Agent 遵循“零落地 (Zero-Leak)”和“9-Grid 防爆隔离”架构来安全管理和注入 Doppler 机密的能力。

## 2. 目录结构设计 (Directory Structure)
遵循 Gemini CLI Skill 官方打包规范，目录树如下：

```text
doppler-manager/
├── SKILL.md                 # (必须) 核心指令、触发器与 AI 行为准则
├── references/              # (可选) 供 AI 按需读取的上下文文档
│   ├── SOP.md               # 环境初始化与人工操作指南
│   └── 9-grid-schema.md     # 9宫格作用域详细映射表 (将长列表从主文件剥离)
└── scripts/                 # (可选) 可执行脚本
    └── check_status.sh      # 检查 Doppler CLI 是否安装及登录状态
```

## 3. SKILL.md 规范 (Frontmatter & Body)

### 3.1 YAML 元数据 (Frontmatter)
用于精确触发该 Skill，必须保持单行且意图明确：

```yaml
---
name: doppler-manager
description: Manage and inject secrets using Doppler CLI. Use when executing applications that require API keys, database credentials, or when managing the 9-Grid secret architecture (Zero-Leak, JITA).
---
```

### 3.2 核心指令流 (Body - Markdown)
**原则**：遵循“渐进式展开 (Progressive Disclosure)”，主文件只保留必须的护栏规则和高频操作框架，将长文档放入 `references/`。

**核心内容区块**：
1. **绝对安全红线 (The Absolutes)**：
   - 严禁读取/打印明文。
   - 严禁操作 `.env` 文件。
   - 所有状态修改必须交由人类执行（Human-in-the-Loop）。
2. **JITA 动态授权机制 (Just-in-Time Access)**：
   - 明确 AI 的默认作用域仅为 `keys4_token-providers`。
   - 跨域访问必须使用 `ask_user` 工具申请授权。
3. **注入执行规范**：
   - 强制使用 `doppler run -p <project> -c <config> -- <command>` 包裹执行目标应用。
4. **外部引用指针**：
   - 遇到需要环境初始化或重置的场景，指示 AI 查阅 `references/SOP.md`。
   - 需要查询具体凭据归属哪个网格时，查阅 `references/9-grid-schema.md`。

## 4. 依赖资源规范 (Bundled Resources)

### 4.1 References (`references/`)
*   **`SOP.md`**：包含 Debian/MacOS 安装 Doppler CLI 的 bash 命令、全局登录 (`doppler login`) 步骤、Service Token 生成指南等**人类操作**长文本。
*   **`9-grid-schema.md`**：详细列出 1-9 号 Project 的命名、用途、包含的典型 Key（如 `keys4_private-services` 包含 `DATABASE_URL`, `REDIS_HOST`）。

### 4.2 Scripts (`scripts/`)
*   **`check_status.sh`**：
    *   **目的**：轻量级验证当前机器 Doppler 状态。
    *   **输出要求**：必须输出 LLM 友好的简短文本（如 `STATUS: OK - Authenticated to keys4_token-providers` 或 `STATUS: ERROR - CLI not found`），屏蔽长篇大论的报错日志以节省 Token。

## 5. 开发与打包流程 (Packaging Workflow)
1. 在 `.ai/skills/doppler-manager/` 下按照上述结构重构现有文件。
2. 将前面对话中生成的《Doppler 零信任机密管理 AI 协作 Prompt》精简后填入 `SKILL.md` 的 Body 部分。
3. 运行本地验证与打包命令（若环境支持）：
   `node <path-to-skill-creator>/scripts/package_skill.cjs .ai/skills/doppler-manager`
4. 安装并在交互式会话中执行 `/skills reload` 生效。
