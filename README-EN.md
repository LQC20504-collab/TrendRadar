<div align="center" id="trendradar">

# 📡 TrendRadar — GIS / Remote Sensing Edition

Hot-topic news monitoring and AI analysis focused on **GIS / Remote Sensing / Digital Earth / Geomatics postgraduate exam**.

> This repository is a customized fork of the upstream project [sansan0/TrendRadar](https://github.com/sansan0/TrendRadar) (master branch).
> It keeps the full upstream feature set (hotlists, RSS feeds, AI analysis, MCP conversational analysis)
> and tailors the data sources and keyword configuration for the GIS / remote sensing domain.

[![Version](https://img.shields.io/badge/version-v6.10.0-blue.svg)](https://github.com/sansan0/TrendRadar)
[![MCP](https://img.shields.io/badge/MCP-v4.1.0-green.svg)](https://github.com/sansan0/TrendRadar)
[![License](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](LICENSE)
[![Upstream](https://img.shields.io/badge/upstream-sansan0%2FTrendRadar-black.svg)](https://github.com/sansan0/TrendRadar)

</div>

---

## ✨ Customizations in this fork

Code stays in sync with the upstream master; changes are configuration-level:

| Item | Description |
|------|-------------|
| **Domain keywords** | `config/frequency_words.txt` rewritten for GIS / remote sensing / digital earth / geomatics exam (regex syntax + group aliases) |
| **RSS feeds** | NASA / ESA / EOS / SpaceNews / GPS World / XYHT / GeoConnexion / Geospatial World / GIS Lounge / GIS Geography / Planet Labs / Maxar / Google AI Blog, etc. |
| **WeChat Official Account feeds** | Forwarded via local [WeWe RSS](https://github.com/cooderl/wewe-rss); point `WECHAT_RSS_URL` at your service |
| **Content filtering** | Global filter removes gaming / streaming / entertainment content, so "map" never matches CS game videos |
| **Notification channels** | **Feishu (Lark)** + **ntfy** enabled by default (others can be enabled in `config.yaml`) |
| **AI config** | Zhipu GLM-4-Flash via an OpenAI-compatible API; AI analysis and AI translation on by default |
| **Push mode** | `incremental` — only newly appeared items, zero duplicates |

## 🚀 Quick Start

### Ⓐ GitHub Actions (default deployment for this repo)

1. **Fork this repo** (or use it directly)
2. Configure Secrets (`Settings → Secrets and variables → Actions`):
   - `WECHAT_RSS_URL`: WeChat RSS service URL (optional if you haven't deployed WeWe RSS; other features are unaffected)
   - Notification channel: `FEISHU_WEBHOOK_URL`, `NTFY_TOPIC`, etc. — configure at least one
   - AI analysis (optional): `AI_API_KEY` (Zhipu API key)
   - Remote storage (optional): `S3_BUCKET_NAME`, `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY`, `S3_ENDPOINT_URL`
3. Manually run the **Get Hot News** workflow to test the push

> ⚠️ Same caveats as upstream:
> - Every GitHub Actions run starts from a fresh environment; without cloud storage the project runs in lightweight mode (no incremental push, no history tracking)
> - Run the **Check In** workflow periodically to renew (valid for 7 days)
> - Keep webhooks / tokens in GitHub Secrets — never put them in `config.yaml`

### Ⓑ Docker

```bash
git clone https://github.com/LQC20504-collab/TrendRadar.git
cd TrendRadar

# Edit config first, then start (push + MCP containers)
docker compose -f docker/docker-compose.yml up -d
```

Data stays in the local `output/` directory; web reports are served at `http://localhost:8080` by the built-in web server.

### Ⓒ Local (uv)

```bash
git clone https://github.com/LQC20504-collab/TrendRadar.git
cd TrendRadar

uv sync          # installs Python and dependencies automatically
uv run python -m trendradar
```

> Windows: double-click `setup-windows.bat`; macOS: run `bash setup-mac.sh` for one-click setup.

## ⚙️ Configuration files

| File | Purpose |
|------|---------|
| `config/config.yaml` | Main config: sources, notification channels, AI, storage, schedule |
| `config/frequency_words.txt` | Domain keywords (GIS / remote sensing / exam), regex + aliases |
| `config/timeline.yaml` | Schedule timeline (presets: always_on / morning_evening / office_hours / night_owl) |
| `config/ai_interests.txt` | AI filtering interests (used when `filter.method: ai`) |
| `config/ai_analysis_prompt.txt` | AI analysis prompt (customize the analysis style) |
| `config/ai_translation_prompt.txt` | AI translation prompt |

> 📖 Full configuration tutorials (platforms, keyword syntax, push modes, scheduling, cloud storage) are in the upstream docs:
> [sansan0/TrendRadar master](https://github.com/sansan0/TrendRadar?tab=readme-ov-file)

## 🧠 MCP AI analysis

MCP (Model Context Protocol)-based conversational analysis of local news data; works with Cursor, Cherry Studio, Claude Desktop and other clients:

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

- Conversation guide: `README-MCP-FAQ-EN.md`
- Cherry Studio guide: `README-Cherry-Studio.md`
- HTTP mode: run `start-http.bat` / `start-http.sh`, endpoint `http://localhost:3333/mcp`

## 🔄 Staying in sync with upstream

Code in this fork targets the upstream master branch; domain customization lives in the `config/` layer, so conflicts are rare:

```bash
git remote add upstream https://github.com/sansan0/TrendRadar.git
git fetch upstream
git merge upstream/master
```

> 📌 Upstream changelog: [sansan0/TrendRadar](https://github.com/sansan0/TrendRadar?tab=readme-ov-file#-changelog)

## 📄 License

GPL-3.0 License (same as upstream).

This project is a customized fork of [sansan0/TrendRadar](https://github.com/sansan0/TrendRadar) (master branch). Thanks to the original author for the open-source contribution.
