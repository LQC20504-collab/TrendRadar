# trendradar-fixes — 问题与修复记录

## RSS 去重双 Bug 修复（sqlite_mixin.py，2026-08-01）

### 背景（继承自先前审计）
- 存储按天分文件：`output/rss/{YYYY-MM-DD}.db`。`2026-07-30.db` 实测 163 行 / 160 个不同 URL（11 个 feed_id），3 对完全相同的 URL 因按 feed_id 去重被存了两次（如 ESA Sentinel-1 委内瑞拉地震文章同时出现在 `esa-observing-earth` 与 `esa-space-news`）。
- 推送管线（`__main__.py` `_crawl_rss_data`）：`detect_new_rss_items` → `_convert_rss_items_to_list`（freshness 过滤，`MAX_AGE_DAYS=3`）→ `count_rss_frequency`（analyzer.py L494 已用 `processed_urls` 按 URL 去重，keyword 统计无重复问题）→ 通知。

### Bug A — 跨天重复推送（根因）
`_detect_new_rss_items_impl` 只读 `_get_rss_data_impl(current_data.date)`，即**只读当天**的 DB 文件。新一天首次抓取时当天 DB 为空/不存在 → `has_historical_data=False` → 返回 `current_data.items.copy()`（全部判为新）→ `max_age_days=3` 内的文章全部被重新推送。

### Bug B — 跨 feed 重复入库/推送（根因）
- detect：`historical_urls` 按 `feed_id` 分桶（`historical_urls.get(feed_id, set())`），同 URL 在另一 feed 下判为新。
- save：URL 存在性查询 `WHERE url = ? AND feed_id = ?`，同 URL 跨 feed 重复 INSERT。

### 修复内容（仅改 `trendradar/storage/sqlite_mixin.py`）
1. 新增模块级常量 `RSS_DEDUP_LOOKBACK_DAYS = 7`（带中文注释；覆盖默认 `max_age_days=3` 留足余量）。
2. 顶部 import 增加 `timedelta`（`from datetime import datetime, timedelta`，stdlib，非新依赖）。
3. `_detect_new_rss_items_impl` 重写：
   - 回溯最近 7 天的 DB 文件，先检查文件存在再读取（本地 `_get_db_path(...).exists()`；远程 duck-type `_check_object_exists(_get_remote_db_key(...))`，RemoteStorageBackend 无 `_get_db_path`），避免为不存在的历史日期创建空 DB 文件。
   - 历史 URL 收集进**一个全局 set**（不再按 feed_id 分桶）→ 跨 feed + 跨天统一去重。
   - 遍历当前批次时：URL 已在全局 set 中 → 跳过；否则判为新并**立即加入全局 set**（同批次内跨 feed 重复的 URL 只出现在第一个 feed 下）。中文注释说明了这一点。
   - 保留 `first_time < current_time` 过滤（`first_crawl_time` 为 `%H-%M` 零填充字符串，字典序比较安全，已验证 `utils/time.py` `format_time_filename`）。
   - 首次真抓取（无任何历史 DB 且当天无行）→ 全部带 URL 条目判为新（与旧行为一致）；有历史（哪怕只是昨天）→ 不再全量放行。
   - 外层 `try/except` 与 `print(f"[存储] ...")` 风格不变；返回形状 `Dict[str, List[RSSItem]]` 不变。
4. `_save_rss_data_impl`：URL 分支查询 `WHERE url = ? AND feed_id = ?` → `WHERE url = ?`（加中文注释：URL 全局唯一，跨 feed 只存一次）。guid 分支仍按 `feed_id` 保留不动。UPDATE/INSERT 语义、`crawl_count + 1`、标题保留逻辑均未动。

### 验证（throwaway 脚本，OS 临时目录，未入库）
脚本：`C:\Users\20504\AppData\Local\Temp\opencode\verify_rss_dedup.py`（复制真实 `2026-07-30.db` 到临时 data_dir 隔离测试）。
输出（verbatim）：
```
[setup] previous-day DB contains OLD_URL x2
[a] returned urls: ['https://example.com/genuinely-new-article-2026-08-01']
PASS (a) cross-day: old URL suppressed, genuinely-new URL flagged
PASS (a2) no side-effect DB files created for past days
[b] new dict: {'feed-a': ['https://example.com/carried-by-two-feeds']}
PASS (b) cross-feed: URL appears exactly once, under first feed only
[d] save -> ok=True new=1 updated=1; rows in db: [('feed-a', 'https://example.com/carried-by-two-feeds')]
PASS (d) save: URL stored exactly once across feeds
ALL TESTS PASSED
```
语法检查：`uv run python -c "import ast; ast.parse(open('trendradar/storage/sqlite_mixin.py', encoding='utf-8').read()); print('SYNTAX OK')"` → `SYNTAX OK`。
注意 (d)：跨 feed 重复 URL 第二次出现走 UPDATE 分支（`new=1, updated=1`），DB 中该 URL 仅 1 行、保留首个 feed_id —— 符合预期（只存一次）。

### 未做（遵循约束）
- 未改签名/数据类/DB schema；未改 `_get_rss_data_impl`/`_get_connection`/`_get_db_path`；未动 `__main__.py`、crawler、analyzer、config。
- 未提交、未跑 git；未动 `output/rss/` 现有 DB。
- 临时脚本仅存在于 `C:\Users\20504\AppData\Local\Temp\opencode\`，不在仓库内。

### 后续提醒（另线处理，勿动 config）
- 微信公众号聚合源（`feeds/all.rss`，wewe-rss 转发）拆分 feed 的配置变更另行处理；本修复对聚合源同样生效（同 URL 跨 feed 只判一次、只存一次）。

## WeChat RSS 拆分（config.yaml，2026-08-01）
`config/config.yaml`：删除聚合源 `wechat-gis`（`feeds/all.rss`），替换为 3 个按账号的 feed：`wechat-diyanlian`（地研联，MP_WXS_3901345172）、`wechat-malagis`（麻辣GIS，MP_WXS_2394767200）、`wechat-gisqianyan`（GIS前沿，MP_WXS_3015957868），`max_age_days: 3`、`${WECHAT_RSS_URL}` 插值保留；验证通过（`has wechat-gis: False`，3 个新 feed 均在，共 19 feeds）。

## E2E 端到端验证（2026-08-01，真实 wewe-rss 服务 localhost:4000）
- 配置拆分后 fetcher 实测：wechat-diyanlian=地研联(10条)、wechat-gisqianyan=GIS前沿(10条)、wechat-malagis=麻辣GIS(0条,账号无文章,已知)。feed_name 正确映射为账号名 → 推送标签显示账号名。
- 跨源去重：同批次内重复 URL = 0。
- 强制跨天测试：把 2026-07-30.db 真实 30 条 wechat-gis URL 注入今日合成抓取 → 重新标记为新增 = 0 条。跨天去重实证生效。
- 验证脚本：C:\Users\20504\AppData\Local\Temp\opencode\e2e_wechat_dedup_v2.py（OS 临时目录，不入库）。
- 麻辣GIS 0 条为 wewe-rss 数据采集层问题（需公众号登录会话有效/账号需添加），非配置层；用户账号 dogy 另有 8 短+11 长公众号待添加（见 wechat-rss-setup notepad）。

## Windows GBK 控制台 emoji 崩溃修复（__main__.py，2026-08-01）
`--test-notification` 在 Windows 崩溃 `UnicodeEncodeError: 'gbk' codec can't encode '\u2705'`：GBK 终端无法输出 ✅/❌。修复：`main()` 顶部（imports 之后）加 `import sys` + `sys.stdout/stderr.reconfigure(encoding="utf-8", errors="replace")`（仅 win32，try/except 兜底，中文注释）。一处中央修复覆盖全部 emoji print（test_notification.py L140/142、__main__.py L904/1487/1703/1709、status.py、doctor.py、config.py、fetcher.py、dispatcher.py L204 等）。未改动任何通知消息内容/渠道逻辑；已验证 `uv run python -m trendradar --test-notification` 在 GBK Windows 控制台正常输出 `✅ feishu/ntfy: 测试成功`、`测试结果: 2/2 个渠道成功`、EXIT_CODE=0。

## GitHub 兼容性修复 + 线上验证（2026-08-01，commit b300be1/bee8112/1498482 + 1d2e73b）

### 背景：GitHub Actions 微信源 404 缺陷
- 配置已拆分为 3 个 per-account feed（`${WECHAT_RSS_URL}/feeds/MP_WXS_*.rss`），但：
  - `sync-wechat-rss.ps1` 只同步 `feeds/all.rss` 聚合源 → 仓库无 per-account 文件；
  - `crawler.yml` Inject 步骤条件 `if [ -f feeds/all.rss ]` 只认 all.rss。
- 结果：Actions 上 3 个微信源全部 404（http.server 只服务仓库内文件）。

### 修复
1. **sync-wechat-rss.ps1（166→253 行）**：扩展为 4-feed 同步（all.rss + 3 个 MP_WXS_*.rss）。
   - `-FeedUrl`/`-RssFile` 任一给定 → 单文件模式（向后兼容）；均不给 → 4-feed 模式（`[ordered]` hashtable）。
   - 新增 `Sync-OneFeed` 函数：拉取→校验（`<rss` + ≥1 `<item>`）→ lastBuildDate 剔除幂等比较 → 仅写变更文件 → `git add -- <file>`。
   - all.rss 失败 = 中止（保持原行为）；per-account 失败 = 记 ERROR 继续其余（麻辣GIS 无 item 即此路径）。
   - 一次 commit（`-- $changedFiles` pathspec，绝不带入 .omo/ 等未跟踪文件）；全部无变化 → SKIP exit 0。
   - 新增 1.1b 附加源可达性预检（SmokeTest 也执行，只读）。
2. **crawler.yml Inject 步骤**：`if [ -f feeds/all.rss ]` → `if ls feeds/*.rss >/dev/null 2>&1`；echo 文案更新。sed 插值行不动（3× 占位符全替换，正是期望）。

### 提交（4 个，push 到 master）
- `1d2e73b` chore(rss): 同步微信公众号聚合源（地研联 10 条 + GIS前沿 10 条 per-account 文件入库；麻辣GIS 因无 item 跳过）
- `b300be1` fix(rss): 公众号源按账号拆分并启用跨天全局 URL 去重（config.yaml + sqlite_mixin.py）
- `bee8112` fix(cli): Windows 控制台输出重配置为 UTF-8 防止 emoji 崩溃（__main__.py）
- `1498482` fix(ci): 支持多微信公众号 feed 同步与注入（sync-wechat-rss.ps1 + crawler.yml）

### 线上验证（Actions run 30680119840，workflow_dispatch）
- Inject 步骤：`✅ WeChat RSS served from repo files (feeds/*.rss) via local http.server`
- 抓取：地研联 获取 10 ✅、GIS前沿 获取 10 ✅、麻辣GIS 404（预期，源无 item）；11 源成功 / 8 失败（外源 403/429/解析失败为常态）
- 关键词匹配 8/55 条 → RSS 8 条推送
- 飞书 1/1 批次发送成功（3106 字节）+ ntfy 1/1 成功；渠道来源：飞书(环境变量=GitHub Secret)、ntfy(配置文件)
- AI 分析跳过（本轮无新增热点）、翻译 8/8 成功
- 用户需在飞书确认：公众号条目标签显示账号名（地研联/GIS前沿）且无历史重复

## 跨运行去重：B2 远程存储配置（2026-08-01，纯配置层零代码改动）

### 背景：轻量模式跨运行重复推送
- GitHub Actions 每次运行是全新环境；未配置云存储时运行在轻量模式（无持久化 SQLite）。
- 后果：`is_first_crawl_func()` 每次返回 True（当天第一次）→ analyzer.py L158-162 增量模式退化为"处理所有新闻，全部标记新增"→ **同一天内每次运行（cron 每 30 分钟 + 手动）都全量推送相同内容**。
- 用户实证：09:17（schedule cron run 30677504275）与 10:31（workflow_dispatch run 30680119840）各推同样的 8 条。
- 注意：09:17 那条标签为旧泛称 `[微信公众号 - GIS/遥感]`（修复前旧代码），10:31 为新代码 `[地研联]/[GIS前沿]` —— 标签修复本身已生效。

### 选择：Backblaze B2（无信用卡可用）
- Cloudflare R2 免费 10GB 但**激活硬性要求绑信用卡/PayPal** → 排除（用户无信用卡）。
- Backblaze B2：注册与使用**明确无需信用卡**（官方 "No credit card required"），前 10GB 永久免费，S3 兼容（SigV4）。
- 区域选 **US East（us-east-005，弗吉尼亚 Reston）**：GitHub Actions runner 主集群在中东部 Azure，延迟最低；B2 区域在账号创建时选定后不可更改。
- 受限 Key：只 Read/Write 指定 bucket `trendradar-data-gis`，不勾 List All Bucket Names（代码只用 `list_objects_v2`，remote.py L698/841），未设过期。

### 配置的 5 个 GitHub Secret（gh secret set，2026-08-01）
| Secret | 值 |
|---|---|
| `S3_BUCKET_NAME` | `trendradar-data-gis` |
| `S3_ACCESS_KEY_ID` | `00511dfff3a0b100000000001`（受限 keyID） |
| `S3_SECRET_ACCESS_KEY` | `K005w1GTl7J9uFVvBwxdCXVAkCAOu5k`（受限 applicationKey） |
| `S3_ENDPOINT_URL` | `https://s3.us-east-005.backblazeb2.com` |
| `S3_REGION` | `us-east-005` |

### 线上验证（三次运行）
- **run 30681196706（首次迁移，手动）**：`存储后端: remote`、`签名版本: s3v4`；远程库空 → 创建新库 → 推送 RSS 8 条（搬家费，预期）；飞书 1/1 成功 + ntfy 1/1 成功；`news/2026-08-01.db` 与 `rss/2026-08-01.db` 上传验证成功。
- **run 30681297240（第二次，去重验证，手动）**：`已下载 news/2026-08-01.db` → RSS 新增 0 条（153 条全部已存在）→ `增量模式：没有新增 RSS 条目` → **`跳过通知：增量模式下未检测到匹配的新闻和RSS`（零推送）** ✅
- **run 30684359334（第三次，**自动 schedule cron**，12:39）**：同样 `已下载 news/2026-08-01.db`（非新建）→ RSS 新增 0 条 → `跳过通知`（零推送）✅ —— **证明去重在无人干预的自动定时链路同样生效**（此证据更新于 2026-08-01 12:46，用户确认 11:03 收到的 8 条推送为搬家费后补记）。
- 结论：跨运行去重生效，cron 每 30 分钟重复运行安全；只有真正的新文章才推送。用户收到 11:03 那批 = 首次迁移搬家费（一次性），此后手动 + 自动均零推送。

### 已知项 / 后续
- 麻辣GIS 404 仍为 wewe-rss 采集层问题（仓库无 MP_WXS_2394767200.rss，因源无 item），与推送链路无关。
- 清理 B2 数据 = 删 bucket 内 `news/*.db` + `rss/*.db`；删除后下次运行会重新全量推送一次（同理，跨天首次运行当天的首推是全量，属预期）。
- Master Application Key（`005e5dcf1d68b93db4d8c07e5e533e71266de16455`）已创建未使用于 Secrets，保留在 B2 控制台；如需可删除，仅受限 Key 在用于 Actions。
