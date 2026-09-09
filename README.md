# argo-cfsm

基于 [eooce/nodejs-argo](https://github.com/eooce/nodejs-argo) 改造的 **Argo 隧道 + 多协议代理 + 服务器监控探针** 一体容器镜像。

保留原项目全部功能：VLESS / VMess / Trojan 节点、Cloudflare Argo 固定/临时隧道、订阅生成与上传、Telegram 推送、Reality / Hysteria2 / Socks5 入站；将探针从 nezha 替换为 [CF-Server-Monitor](https://github.com/huilang-me/CF-Server-Monitor) 的 Go Probe（`cf-probe`，内置版本号 `9.9.9`）。

---

## 镜像

```bash
docker pull ghcr.io/nicsrvdev/argo-cfsm:latest
```

## 与原项目的差异

| 项目 | 原项目 | 本项目 |
|------|--------|--------|
| 探针 | nezha（哪吒） | **cf-probe**（CF-Server-Monitor） |
| 探针变量 | `NEZHA_SERVER/PORT/KEY` | `CFP_ID / CFP_SECRET / CFP_URL` 等 |
| xray / cloudflared | 运行时从私有 CDN 下载 | **构建时下载并固化进镜像**，运行时零下载 |
| cf-probe | - | **构建时源码编译**，版本 `9.9.9` |
| 防检测 | 随机文件名 + 90s 清理运行副本 | 保留 |

---

## 快速使用

```bash
docker run -d --name argo-cfsm \
  -e UUID="你的UUID" \
  -e CFP_ID="CF面板服务器ID" \
  -e CFP_SECRET="CF面板密钥" \
  -e CFP_URL="https://你的worker域名/update" \
  -e ARGO_AUTH="固定隧道token(留空=临时隧道)" \
  -e ARGO_DOMAIN="固定隧道域名(留空=临时隧道)" \
  -p 3000:3000 \
  ghcr.io/nicsrvdev/argo-cfsm:latest
```

- 书签首页：`http://<主机>:3000/`
- 订阅地址：`http://<主机>:3000/sub`

---

## 环境变量

### 通用

| 变量 | 默认 | 说明 |
|------|------|------|
| `UUID` | 随机 | 节点 UUID（三协议共用） |
| `ARGO_AUTH` | 空 | 固定隧道 token/json，留空=临时隧道 |
| `ARGO_DOMAIN` | 空 | 固定隧道域名，留空=临时隧道 |
| `ARGO_PORT` | `8001` | 隧道回源端口 |
| `CFIP` | `saas.sin.fan` | 节点优选域名/IP |
| `CFPORT` | `443` | 优选域名端口 |
| `NAME` | 空 | 节点名称前缀 |
| `UPLOAD_URL` | 空 | 订阅上传地址（Merge-sub 类） |
| `PROJECT_URL` | 空 | 项目分配 URL |
| `AUTO_ACCESS` | `false` | 自动访问保活 |
| `S5_PORT` / `HY2_PORT` / `REALITY_PORT` | 空 | 额外协议端口 |
| `PORT` / `SERVER_PORT` | `3000` | 订阅 HTTP 服务端口 |
| `SUB_PATH` | `sub` | 订阅路径 |
| `FILE_PATH` | `.npm` | 运行目录 |
| `CHAT_ID` / `BOT_TOKEN` | 空 | Telegram 节点推送（两变量同填生效） |
| `SHOW_LOG` | `true` | 是否显示日志（`false` 屏蔽） |

### 探针（CF-Server-Monitor）

`CFP_ID + CFP_SECRET + CFP_URL` 三者同时填写才启动探针。

| 变量 | 默认 | 说明 |
|------|------|------|
| `CFP_ID` | 空 | 服务器 ID |
| `CFP_SECRET` | 空 | 服务器密钥 |
| `CFP_URL` | 空 | Worker 上报地址，如 `https://example.com/update` |
| `CFP_INTERVAL` | `60` | 上报间隔（秒） |
| `CFP_COLLECT` | `0` | 采样间隔（秒），`0`=WSS 自动采样 |
| `CFP_CT` / `CFP_CU` / `CFP_CM` / `CFP_BD` | 空 | 电信/联通/移动/BGP 测试节点 |
| `CFP_NODE1..4` | 空 | 自定义探测节点 |
| `CFP_IFACE` | 空 | 统计网卡，逗号分隔 |
| `CFP_RESET_DAY` | `1` | 月流量重置日 |
| `CFP_CONN_MODE` | `auto` | `auto`/`http` |
| `CFP_PING_MODE` | `tcp` | `tcp`/`icmp` |
| `CFP_DEBUG` | `0` | 调试日志 |

---

## 自定义变量构建（fork 使用）

> 构建**不会自动混淆**：Dockerfile 直接使用仓库里的 `index.js`（这是设计——源码 `index-src.js` 仅作参考，进镜像的永远是 `index.js`）。因此自行注入变量时，**必须在提交前手动混淆 `index.js`**，否则你的变量会以明文进入公开镜像。

**完整流程（取源码 → 硬编变量 → 手动混淆 → 保存 index.js → GitHub 自动构建）**：

1. **取源码**：将 `index-src.js`（干净源码，无变量）内容复制覆盖到 `index.js`
2. **硬编变量**：编辑 `index.js`，把各变量的默认值改成你的配置，例如：
   ```js
   const CFP_ID       = process.env.CFP_ID       || '你的服务器ID';
   const CFP_SECRET   = process.env.CFP_SECRET   || '你的密钥';
   const CFP_URL      = process.env.CFP_URL      || 'https://你的worker/update';
   const CFP_CT       = process.env.CFP_CT       || 'gd-ct-v4.ip.zstaticcdn.com:80';
   const CFP_CU       = process.env.CFP_CU       || 'gd-cu-v4.ip.zstaticcdn.com:80';
   const CFP_CM       = process.env.CFP_CM       || 'gd-cm-v4.ip.zstaticcdn.com:80';
   const CFP_BD       = process.env.CFP_BD       || 'ip.zstaticcdn.com';
   const ARGO_AUTH    = process.env.ARGO_AUTH    || '你的固定隧道token/JSON';
   const ARGO_DOMAIN  = process.env.ARGO_DOMAIN  || '你的固定隧道域名';
   ```
   探针变量取自 CF-Server-Monitor 面板（`SERVER_ID` → `CFP_ID`，`SECRET` → `CFP_SECRET`，Worker 地址 → `CFP_URL`）。
3. **手动混淆**：对编辑后的 `index.js` 做混淆，**覆盖保存回 `index.js`**。方式任选：
   - 本地：安装 `javascript-obfuscator` 后运行（见下方命令）
   - 在线工具： [obfuscator.io](https://obfuscator.io)（官方）、[jsfuck.com](https://jsfuck.com)、[obfuscator.io/demo](https://obfuscator.io/demo)
   - 建议混淆参数：`String Array` 开启、`String Array Threshold` = `1.0`（全量字符串进数组）、`String Array Encoding` = `base64`、`Rotate String Array` 开启
4. **确认无明文**：混淆完成后检查 `index.js` 中已搜不到你的变量明文：
   ```bash
   grep -c "你的服务器ID" index.js   # 应返回 0
   ```
5. **推送构建**：提交 `index.js` 到你的仓库 `main`。GitHub Actions 检测到 `index.js` 变更，自动构建并推送镜像到你自己的 GHCR：
   ```
   ghcr.io/<你的用户名>/nodejs:latest
   ```

> **注意**：
> - fork 后首次需在仓库 **Actions** 页面手动启用 workflow（GitHub 默认对 fork 关闭 Actions）。
> - 若跳过混淆直接提交明文源码，镜像中 `index.js` 将明文暴露你的变量（包括探针密钥、隧道 token）——请务必混淆后再推。
> - 想体验运行效果但不想暴露变量，也可以用环境变量方式部署（见「快速使用」），无需修改代码。

---

## 部署说明

本项目的部署方式有两种，**凭据处理方式不同**：

- **方式一：直接使用公开镜像**（`ghcr.io/nicsrvdev/argo-cfsm:latest`）
  - 镜像与代码**不含任何私密配置**，变量一律通过环境变量注入（见「快速使用」变量表）
  - 部署到 Render / Koyeb 等平台时，将环境变量填入平台服务配置即可
- **方式二：fork 自定义构建**
  - 变量硬编进 `index.js`，因此**镜像内含你的配置**（经混淆隐藏，非明文）——见「自定义变量构建」

> 两种方式二选一：公开镜像走环境变量；自定义构建走硬编+混淆。混淆只隐藏明文，不等于"镜像不含配置"。
- cf-probe 在容器内以 `run -config` 前台模式运行（无需 systemd），三进程各自随机文件名，90 秒后清理运行副本（进程不受影响）

### 二进制来源（构建时）

- **xray(web)** / **cloudflared(bot)**：从原项目源 `{amd64|arm64}.oooen.com/web`、`/bot` 下载静态二进制固化进镜像
- **cf-probe**：构建时从 `huilang-me/cfsm-agent` 源码编译，版本号为 `9.9.9`

构建为多平台：`linux/amd64`、`linux/arm64`。

---

## CF-Server-Monitor 面板

配合 [huilang-me/CF-Server-Monitor](https://github.com/huilang-me/CF-Server-Monitor) 使用，在面板添加服务器获取 `SERVER_ID / SECRET`，Worker 地址即 `CFP_URL`。

## License

MIT