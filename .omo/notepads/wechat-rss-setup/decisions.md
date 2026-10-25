# decisions.md

<!-- Auto-created 2026-07-31 19:32 - Atlas orchestration notepad -->

## [2026-07-31 21:10] Decision: 弃用 Cloudflare 隧道，改推送式架构

- 用户明确弃用 cloudflared（国内网络下 QUIC 反复超时/530、URL 频繁漂移）："别用cloudflare了，有没有其他方案？"
- **最终架构（推送式）**：
  1. 本地 `sync-wechat-rss.ps1` 拉取 `http://localhost:4000/feeds/all.rss` → `feeds/all.rss` → git commit + push 到仓库 master
  2. GitHub Actions `crawler.yml` Inject step：若 `feeds/all.rss` 存在 → `python -m http.server 9000 --directory "$GITHUB_WORKSPACE"` → sed 替换 `${WECHAT_RSS_URL}` 为 `http://127.0.0.1:9000`
  3. fetcher（`requests.get(url, timeout=15)`）只支持 HTTP(S)，本地 http.server 满足需求，**零 Python 代码改动**
- 关键约束：零隧道、零公网依赖、零 Secret 主路径
- `WECHAT_RSS_URL` secret 已 `gh secret delete`（2026-07-31），现仓库 secrets 仅剩：AI_API_BASE, AI_API_KEY, AI_MODEL, FEISHU_WEBHOOK_URL, NTFY_TOPIC
- `start-tunnel.ps1`（旧架构）已删除
- crawler.yml 保留 `elif [ -n "$WECHAT_RSS_URL" ]` 回退分支做向后兼容（secret 未设置时自动跳过）
- 提交：`f61ecbe`（feeds/all.rss 30 items）→ `8958e5d`（sync-wechat-rss.ps1 + crawler.yml），已 push origin master


