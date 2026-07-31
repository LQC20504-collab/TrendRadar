<div align="center" id="trendradar">

# 📡 TrendRadar — GIS / 遥感定制版

聚焦 **GIS / 遥感 / 数字地球 / 测绘考研** 方向的热点新闻监控与 AI 分析推送。

> 本仓库是上游项目 [sansan0/TrendRadar](https://github.com/sansan0/TrendRadar)（master 分支）的二次定制 fork。
> 保留上游全量功能（全网热榜、RSS 订阅、AI 分析、MCP 对话分析），
> 并按 GIS / 遥感领域的实际使用场景裁剪了数据源与关键词配置。

[![Version](https://img.shields.io/badge/version-v6.10.0-blue.svg)](https://github.com/sansan0/TrendRadar)
[![MCP](https://img.shields.io/badge/MCP-v4.1.0-green.svg)](https://github.com/sansan0/TrendRadar)
[![License](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](LICENSE)
[![Upstream](https://img.shields.io/badge/upstream-sansan0%2FTrendRadar-black.svg)](https://github.com/sansan0/TrendRadar)

</div>

---

## ✨ 本项目定制内容

代码保持与上游 master 同步，改动集中在配置层：

| 定制项 | 说明 |
|-------|------|
| **领域关键词** | `config/frequency_words.txt` 重写为 GIS / 遥感 / 数字地球 / 测绘考研方向（正则语法 + 组别名） |
| **RSS 数据源** | 预置 NASA / ESA / EOS / SpaceNews / GPS World / XYHT / GeoConnexion / Geospatial World / GIS Lounge / GIS Geography / Planet Labs / Maxar / Google AI Blog 等专业源 |
| **微信公众号源** | 通过本地 [WeWe RSS](https://github.com/cooderl/wewe-rss) 转发 GIS / 遥感公众号，`WECHAT_RSS_URL` 环境变量指向服务地址 |
| **内容过滤** | 全局过滤游戏 / 直播 / 娱乐类内容，避免「地图」等词误匹配 CS 游戏视频 |
| **通知渠道** | 默认启用**飞书** + **ntfy**（其余渠道按需在 `config.yaml` 开启） |
| **AI 配置** | 默认对接智谱 GLM-4-Flash（OpenAI 兼容接口），AI 分析与 AI 翻译默认开启 |
| **推送模式** | `incremental` 增量监控，只推送新增内容，零重复 |

## 🚀 快速开始

### Ⓐ GitHub Actions 部署（本仓库默认方式）

1. **Fork 本仓库**（或直接使用本仓库）
2. 配置 Secrets（`Settings → Secrets and variables → Actions`）：
   - `WECHAT_RSS_URL`：微信公众号 RSS 服务地址（未部署 WeWe RSS 可留空，不影响其余功能）
   - 通知渠道：`FEISHU_WEBHOOK_URL`、`NTFY_TOPIC` 等，任选其一
   - AI 分析（可选）：`AI_API_KEY`（智谱 API Key）
   - 远程云存储（可选）：`S3_BUCKET_NAME`、`S3_ACCESS_KEY_ID`、`S3_SECRET_ACCESS_KEY`、`S3_ENDPOINT_URL`
3. 在 Actions 页面手动运行 **Get Hot News** 测试推送

> ⚠️ 与上游相同的注意事项：
> - GitHub Actions 每次运行都是全新环境，不配置云存储将运行在轻量模式（无增量推送、无历史追踪）
> - 需定期手动运行 **Check In** workflow 续期（有效期 7 天）
> - webhook / Token 等敏感信息请放入 GitHub Secrets，不要写进 `config.yaml`

### Ⓑ Docker 部署

```bash
git clone https://github.com/LQC20504-collab/TrendRadar.git
cd TrendRadar

# 修改配置后启动（推送 + MCP 双容器）
docker compose -f docker/docker-compose.yml up -d
```

数据保存在本地 `output/` 目录，网页版报告通过内置 Web 服务器访问 `http://localhost:8080`。

### Ⓒ 本地部署（uv）

```bash
git clone https://github.com/LQC20504-collab/TrendRadar.git
cd TrendRadar

uv sync          # 自动安装 Python 与依赖
uv run python -m trendradar
```

> Windows 可双击 `setup-windows.bat`，macOS 可执行 `bash setup-mac.sh` 一键安装。

## ⚙️ 配置文件一览

| 文件 | 作用 |
|------|------|
| `config/config.yaml` | 主配置：数据源、通知渠道、AI、存储、调度 |
| `config/frequency_words.txt` | 领域关键词（GIS / 遥感 / 考研），支持正则与组别名 |
| `config/timeline.yaml` | 调度时间线（预设：always_on / morning_evening / office_hours / night_owl） |
| `config/ai_interests.txt` | AI 智能筛选的兴趣描述（`filter.method: ai` 时生效） |
| `config/ai_analysis_prompt.txt` | AI 分析提示词（自定义分析风格） |
| `config/ai_translation_prompt.txt` | AI 翻译提示词 |

> 📖 完整的配置教程（平台、关键词语法、推送模式、调度系统、云存储等）请参考上游文档：
> [sansan0/TrendRadar master](https://github.com/sansan0/TrendRadar?tab=readme-ov-file)

## 🧠 MCP AI 智能分析

基于 MCP (Model Context Protocol) 的本地新闻数据对话分析，支持 Cursor、Cherry Studio、Claude Desktop 等客户端：

```json
{
  "mcpServers": {
    "trendradar": {
      "command": "uv",
      "args": ["--directory", "/path/to/TrendRadar", "run", "python", "-m", "mcp_server.server"]
    }
  }
}
```

- 对话教程：`README-MCP-FAQ.md`
- Cherry Studio 图文部署：`README-Cherry-Studio.md`
- HTTP 模式：运行 `start-http.bat` / `start-http.sh`，服务地址 `http://localhost:3333/mcp`

## 🔄 与上游保持同步

本 fork 的代码目标是与上游 master 保持同步，领域定制保留在 `config/` 配置层，冲突极少：

```bash
git remote add upstream https://github.com/sansan0/TrendRadar.git
git fetch upstream
git merge upstream/master
```

> 📌 上游更新日志：[sansan0/TrendRadar 更新日志](https://github.com/sansan0/TrendRadar?tab=readme-ov-file#-更新日志)

## 📄 许可证

GPL-3.0 License（与上游一致）。

本项目基于 [sansan0/TrendRadar](https://github.com/sansan0/TrendRadar)（master 分支）fork 定制，感谢原作者的开源贡献。
