### 💡 Session 核心决策总结

1. **需求锚定**：你最初需要一个“极度安全+极度方便”、能对外提供 API 的敏感信息管理器，用于支撑诸如“铁网”项目等自动化脚本的凭据分发。
2. **路线演进**：
   * **方案 A (私有化平衡)**：Vaultwarden（偏人类密码管理）与 Infisical（偏机器密钥分发）。
   * **方案 B (极空间+CF Tunnel)**：设计了在极空间通过 Docker 部署 Infisical，并使用 Cloudflare Tunnel 暴露服务，结合 Tailscale 作为内网降级的完美防御架构。
   * **最终方案 (云端 SecretOps)**：你最终做出了极具前瞻性的决定——拥抱 **Doppler**。用极其轻量的 SaaS 取代了沉重的本地数据库维护，彻底消灭了 `.env` 文件。
3. **关键踩坑与纠偏**：
   * **UI 迷宫**：明确了 Doppler 严格的层级逻辑（必须先进入 `dev/stg/prd` 具体的环境，才能配置 Access 和 Service Token）。
   * **安全红线**：巩固了机密管理的铁律——**绝对不要将任何真实 Token 粘贴到任何聊天窗口或大语言模型中**。

---

基于我们的探索，我为你重新梳理并升级了最终版的 SOP 文档。这份文档吸收了刚才所有的踩坑经验和安全警告，你可以直接将其保存为 `docs/Doppler 云端机密管理中心接入指南.md` 并提交到你的仓库中。

***

# 🚀 Doppler 云端机密管理中心接入指南

## 架构总览
* **控制层**：使用 Doppler SaaS 作为唯一的真实数据源（SSOT），集中管理所有的环境变量、API 密钥和数据库凭证。
* **注入层**：在目标机器上部署轻量级的 Doppler CLI，通过机器到机器（M2M）的 API 通信，在应用启动瞬间将机密注入内存，实现 `.env` 文件的“零落地”。
* **网络与访问**：纯出站 HTTPS 请求，无需配置公网 IP 或防火墙入站规则，完美契合我们既有的 Tailscale 组网封闭式安全策略。

---

## 阶段一：Doppler 云端工作区初始化

### 1. 建立项目与环境拓扑
1. 登录 Doppler Web 控制台，创建一个新的 Workspace。
2. 为你的核心应用创建一个 Project（例如命名为 `iron-web-core`）。
3. Doppler 默认会提供三个环境：`dev`（开发环境）、`stg`（测试环境）和 `prd`（生产环境）。
   *(优势：可以确保本地开发使用的测试密钥与云端服务器运行的生产密钥严格物理隔离。)*

### 2. 录入核心机密 (Secrets)
1. 进入对应的环境（如 `prd`），添加项目所需的键值对。
2. 建议使用标准的大写下划线命名法，例如：
   * `GEMINI_API_KEY` = `AIzaSy...`
   * `DATABASE_URL` = `postgresql://...`
3. 保存后，Doppler 会自动进行版本控制，任何误删或修改都可以一键回滚。

### 3. 生成服务令牌 (Service Token) - ⚠️ 重点易错环节
对于运行在后台的云服务器，必须配置只读的服务令牌进行无交互验证。
1. 在项目界面的环境列表中，**首先点击进入你需要部署的具体环境**（例如点击进入 `prd`）。
2. 在该环境的顶栏或侧边栏，点击进入 **Access** 标签页。
3. 点击 **Generate**。命名（如 `debian-server-01`），权限保持默认的 **Read**。
4. 点击 **Generate Service Token**，复制以 `dp.st.` 开头的秘钥。*(注：该秘钥只显示一次，请勿通过不安全的聊天工具传输)*。

---

## 阶段二：Debian 12 云主机接入配置

### 1. 安装 Doppler CLI
在 Debian/Ubuntu 终端执行官方安装脚本：
```bash
# 更新源并安装依赖
sudo apt-get update && sudo apt-get install -y apt-transport-https ca-certificates curl gnupg

# 添加 Doppler 的 GPG 密钥和 APT 源
curl -sLf --retry 3 --tlsv1.2 --proto "=https" 'https://packages.doppler.com/public/cli/gpg.DE2A7741A397C129.key' | sudo gpg --dearmor -o /usr/share/keyrings/doppler-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/doppler-archive-keyring.gpg] https://packages.doppler.com/public/cli/deb/debian any-version main" | sudo tee /etc/apt/sources.list.d/doppler-cli.list

# 安装 CLI
sudo apt-get update && sudo apt-get install doppler
```

### 2. 配置无头服务器认证与连通性测试
在服务器终端执行以下命令进行绑定：
```bash
# 配置全局或项目级别的 Token
doppler configure set token dp.st.prd.xxxxxx
```

**✅ 连通性测试：**
为了确保 Token 有效且网络畅通，可通过以下两种方式验证：
1. **CLI 方式**：运行 `doppler secrets`，检查是否能打印出云端配置的键值对。
2. **原生 API 方式**（用于排查 CLI 故障）：
   ```bash
   # 注意 token 后面紧跟一个英文冒号
   curl -u 你的完整Token: https://api.doppler.com/v3/configs/config/secrets
   ```

---

## 阶段三：实战应用与自动化注入

### 1. 原生脚本直接注入
当你需要启动包含 Gemini API 调用的 Python 服务时，不再需要读取本地配置文件，直接在指令前加上 `doppler run --`：
```bash
doppler run -- python3 /opt/iron-web/main.py
```
Doppler 会将云端的环境变量注入给后续进程，脚本运行结束后内存即刻释放。

### 2. 结合 Docker 编排
在你的 `docker-compose.yml` 中声明需要的环境变量占位符（无需赋值）：
```yaml
version: '3'
services:
  agent-core:
    image: my-agent-image:latest
    environment:
      - GEMINI_API_KEY
```
启动容器时，让 Doppler 接管：
```bash
doppler run -- docker compose up -d
```

---

## 🛡️ 安全与运维备忘录

1. **Service Token 的作用域陷阱**：为不同的服务器或不同的功能模块生成**独立**的 Service Token，并且务必绑定到极小的环境（如专门的 `prd-database` 环境）。千万不要一个高权限 Token 走天下，一旦 Token 泄露即可撤销单点，不影响全局。
2. **断网容灾机制 (Fallback)**：Doppler CLI 具备本地加密缓存能力（Fallback 功能）。如果在拉取环境变量时服务器断网，Doppler 默认会使用上一次成功拉取的加密缓存副本启动进程，不会导致服务直接宕机。
3. **开发机体验优化**：在 WSL 或本地 macOS 开发环境中，不需要使用 Service Token。直接在终端运行 `doppler login`，通过浏览器完成 OAuth 登录后，使用 `doppler setup` 绑定当前工作目录对应的云端 Project 即可丝滑开发。