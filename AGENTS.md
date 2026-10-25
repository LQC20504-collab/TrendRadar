# AGENTS.md — TrendRadar 微信公众号聚合推送运维手册

> 本文件供 AI 助手（及人类）在**后续会话**中快速恢复上下文：启动 wewe-rss、验证服务、同步 RSS、触发 GitHub Actions 推送。
> 用户会在需要时直接说「帮我启动」——按本手册执行即可。

---

## 1. 系统架构（推送式，零隧道）

```
微信公众号 → wewe-rss（本地 4000 端口，SQLite）
                │  定时/手动刷新文章
                ▼
   http://localhost:4000/feeds/*.rss   （聚合源 all.rss + 按账号源 MP_WXS_*.rss）
                │
                ▼  sync-wechat-rss.ps1（拉取 23 个源 → 提交 → push）
   GitHub 仓库 LQC20504-collab/TrendRadar 的 feeds/ 目录
                │
                ▼  GitHub Actions（crawler.yml，cron "17,47 * * * *"）
   起临时 http.server:9000 服务 feeds/ → fetcher 抓取 → 翻译 → 推送微信/飞书
```

- 旧方案（cloudflared 隧道 + WECHAT_RSS_URL Secret）已弃用，勿回退。
- **核心脆弱点**：wewe-rss 服务停掉 → 同步脚本拉不到新文章 → 推送停滞。根因排查从检查 4000 端口开始。

---

## 2. 启动 wewe-rss（用户最常见的请求）

### 2.0 前置检查
- Node `v24.16.0`、pnpm `11.17.0` 已装。
- wewe-rss 仓库位于 `D:\Develop\wewe-rss`（独立 git 仓库，HEAD e751c64，勿与 TrendRadar 混淆）。

### 2.1 是否已在运行
```powershell
Get-NetTCPConnection -LocalPort 4000 -State Listen -ErrorAction SilentlyContinue
# 有输出（LocalPort 4000, OwningProcess <pid>）= 已在运行，跳过 2.2/2.3
# 无输出 = 未运行，继续 2.2
```

### 2.2 常规启动（已 build 过，正常场景）
```powershell
# 方式 A（推荐，本次实测最稳）：直接 node 跑 dist/main，workdir=apps/server 以加载 .env.local
Start-Process "C:\Program Files\nodejs\node.exe" -ArgumentList "dist/main" -WorkingDirectory "D:\Develop\wewe-rss\apps\server" -WindowStyle Hidden
# 方式 B（备选）：pnpm --filter，CWD 必须在仓库根
#   Start-Process pnpm -ArgumentList "--filter","server","start:prod" -WorkingDirectory "D:\Develop\wewe-rss" -WindowStyle Hidden
```
- 启动后轮询验证（约 20-40s 起服务）：
```powershell
for ($i=1; $i -le 12; $i++) { Start-Sleep -Seconds 5; $c=curl.exe -s -o NUL -w "%{http_code}" --connect-timeout 5 --max-time 15 http://localhost:4000/feeds/all.rss 2>$null; if ($c -eq "200") { Write-Output "HTTP 200 (attempt ${i})"; break } }
```
- **重要**：wewe-rss 进程存活只有数小时（约半天），每次会话开始先查 4000 端口，死了就重启（见 2.1）。
- 标准输出/错误落盘：`C:\Users\20504\AppData\Local\Temp\opencode\wewe-server-stdout.log` / `wewe-server-stderr.log`（手动启动时建议重定向：`*> ...\wewe-server-stdout.log`）。

### 2.3 初始化仪式（仅全新克隆 / dist 缺失 / schema 被改坏时）
执行顺序严格如下（详见 `.omo\plans\wechat-rss-setup.md` Task 4）：

```powershell
# ① env.local（apps/server/.env.local，含 AUTH_CODE，勿提交）
#    DATABASE_URL="file:../data/wewe-rss.db"
#    DATABASE_TYPE="sqlite"
#    PORT=4000
#    AUTH_CODE=<随机值>

# ② schema swap（prisma-sqlite 目录存在时执行）
if (Test-Path "apps/server/prisma-sqlite") {
  Remove-Item -Recurse -Force "apps/server/prisma"
  Rename-Item "apps/server/prisma-sqlite" "apps/server/prisma"
}

# ③ generate（workdir=apps/server）— 注意用 --schema 显式指定
npx prisma generate --schema apps/server/prisma/schema.prisma
# ④ migrate deploy（workdir=apps/server）— 禁止用 start:migrate:prod（那是 MySQL 默认 migrate）
npx prisma migrate deploy --schema apps/server/prisma/schema.prisma
# ⑤ build（workdir=仓库根）
pnpm run -r build
# ⑥ 启动（见 2.2）
```
- 校验：`apps/server/dist/main.js` 存在；`apps/server/data/wewe-rss.db` 存在且 >0KB；`schema.prisma` 的 datasource provider 为 `sqlite`。

### 2.4 验证服务
```powershell
curl.exe -s -o NUL -w "%{http_code}" --connect-timeout 5 --max-time 15 http://localhost:4000/feeds/all.rss
# 期望 200。200 = 服务正常。
# 非 200 → 查 stderr 日志（常见：MySQL 连接错误 = CWD 错误 env 未加载；端口占用）。
```

---

## 3. 同步 RSS 到 GitHub（新文章入库后）

```powershell
cd D:\Develop\TrendRadar
powershell -ExecutionPolicy Bypass -File sync-wechat-rss.ps1 -SmokeTest   # 只查环境，不改任何东西
powershell -ExecutionPolicy Bypass -File sync-wechat-rss.ps1              # 完整同步：拉 23 源 + commit + push
powershell -ExecutionPolicy Bypass -File sync-wechat-rss.ps1 -NoPush      # 拉取+commit 不 push（调试）
```
- 同步 23 个文件：`feeds/all.rss`（主源，失败即中止）+ 22 个 `feeds/MP_WXS_*.rss`（失败仅告警）。
- **幂等**：脚本先下载到临时文件，剔除 `<lastBuildDate>` + 统一 LF 后与 HEAD 比较；无实质变化 → SKIP（退出码 0，不产生空转提交）。
- 提交信息格式：`chore(rss): 同步微信公众号聚合源 (YYYY-MM-DD HH:mm)`。
- 日志：`.omo\logs\sync-wechat-rss-<时间戳>.log`。
- 前置：wewe-rss 可达（HTTP 200）+ git 仓库 + `gh` 已认证。

---

## 4. 触发 / 检查 GitHub Actions 推送

> ⚠️ **2026-08-13 起（重要）**：GitHub 平台 bug —— 新建仓库的 schedule cron 定时触发可能永不生效
> （workflow 显示 active、workflow_dispatch 正常，但 schedule 事件从未触发；见 github community #201008，
> 官方答复「向默认分支 push 可重同步」实测无效）。**结论：不依赖 cron，一律手动触发。**

### 4.0 标准手动触发（推荐，一键脚本）
```powershell
powershell -ExecutionPolicy Bypass -File D:\Develop\TrendRadar\trigger-push.ps1
```
脚本自动完成：① 检查 gh 认证 + wewe-rss 存活（挂了自动拉起）→ ② 刷新微信文章 → ③ 同步 RSS 到 GitHub
（commit+push，push 失败自动用 gh token 兜底）→ ④ 触发 `gh workflow run crawler.yml` → ⑤ 轮询等待并核对日志。
- 退出码 0 = 成功（含「无新增正常跳过」）；1 = 失败（具体 FAIL 步骤见输出）。
- 兜底推送（非交互环境 GCM 弹不出凭据时）：
  `git push "https://x-access-token:$(gh auth token)@github.com/LQC20504-collab/TrendRadar.git" master`

### 4.0b 原始命令（不用脚本时逐条执行）
```powershell
gh workflow run crawler.yml                                    # 手动触发一次
gh run list --workflow=crawler.yml --limit 5                   # 查看最近运行
gh run view <run-id> --log | Select-String "检测到|推送|翻译"    # 看关键日志行
```
- 推送链路日志关键词：`[RSS] 检测到 N 条新文章` → `[AI] 分析完成` → `[推送] 准备发送：RSS N 条` → `[翻译] 开始翻译内容到 中文...`。
- 无新增时日志为「没有新增 RSS 条目」→ 跳过推送（正常行为，勿当故障）。
- **注意**：`gh run view --log` 的日志 zip 可能为二进制乱码，必要时用 `gh api repos/LQC20504-collab/TrendRadar/actions/jobs/<job-id>/logs` 拉取。

### 4.1 7 天试用期自毁机制（已移除，2026-08-13）
- `crawler.yml` 的 `Check Expiration` 步骤已于 2026-08-13 删除（commit 42eb596），**不再自毁禁用**。
- 若 workflow 意外被禁用（手动误操作等），恢复：`gh workflow enable crawler.yml` + `gh workflow run crawler.yml`。
- 旧恢复流程（删 runs 重试）不再需要；详细历史见 git log。

---

## 5. 账号 / Token 维护（出问题时）

### 5.1 症状 → 根因
| 症状 | 根因 | 处置 |
|---|---|---|
| 服务 4000 端口无监听 | wewe-rss 进程死了（上次事件主因：08-01 23:18 后停服） | 按第 2 节重启 |
| 刷新报 500「暂无可用读书账号」 | 账号 status=0（token 失效被 interceptor 置 0，或手动误置） | 看 5.2/5.3 |
| tRPC 返回 401 | token 失效（平台侧） | 看 5.2 扫码续期 |

### 5.2 扫码续期流程（token 失效时，完整闭环）

**标准流程（推荐，一键脚本，杜绝二维码过期）**：
```powershell
python D:\Develop\TrendRadar\login_and_persist.py
```
- 脚本自动完成：① 生成二维码（createLoginUrl）→ ② 渲染 PNG 并 **os.startfile 弹出到屏幕** → ③ 立即后台轮询 getLoginResult（最长 3 分钟）→ ④ 扫码成功后自动 `account.edit` 持久化 token + status=1。
- **关键教训（08-13 踩坑）**：二维码有效期极短（约 1 分钟）。若「生成二维码 → 等用户回复 → 再轮询」两步分开，uuid 必过期。必须让脚本生成后**立即弹窗 + 立即轮询**，用户扫完自动闭环。
- **关键教训（08-14 修复，勿回退）**：`account.edit` 的 `id` 必须是**字符串**（zod 校验 `z.string()`），脚本已改为 `str(vid)`；传数字会报 HTTP 400 导致持久化失败（症状：LOGIN_OK 有、PERSIST_OK 无、status 仍为 0）。二维码文件名已改为带 UUID（`wewe-login-qr-<uuid>.png`），避免旧图缓存。
- **关键教训（08-14 事件）**：微信读书 token 与网络出口环境绑定。若系统代理/Clash TUN 模式在登录后被切换（出口 IP 变化），微信会在数小时后作废会话（WeReadError401 → status=0）。**登录与运行期间必须保持网络状态一致**，勿中途开关代理。
- 脚本日志落盘 `D:\Develop\TrendRadar\login.log`（含 UUID / LOGIN_OK / TOKEN / PERSIST_OK）；运行中勿中止，若中途被杀，token 可能已取到但未持久化 → 从日志取 token 手动补持久化（见下方手动步骤 ③，用 save_token.py 或直接 account.edit）。
- 运行方式：`Start-Process python -ArgumentList "-u","D:\Develop\TrendRadar\login_and_persist.py" -WorkingDirectory "D:\Develop\TrendRadar" -WindowStyle Hidden`（`-u` 关缓冲保证实时刷日志）。

**手动分步（脚本不可用时）**
```powershell
# ① 生成登录二维码（AUTH_CODE 见 apps/server/.env.local，作 Authorization 值，无 Bearer 前缀）
#    POST http://localhost:4000/trpc/platform.createLoginUrl   body: {}  （裸对象，勿用 {"0":{}} 批量包裹）
#    → 返回 uuid + scanUrl（https://open.weixin.qq.com/connect/confirm?uuid=<uuid>）
#    用 Python qrcode 库渲染成 PNG（参考 D:\Develop\TrendRadar\gen_qr.py），请用户微信扫码
# ② 轮询登录结果（GET 查询，input 用裸对象，勿批量包裹）
#    GET http://localhost:4000/trpc/platform.getLoginResult?input={"id":"<uuid>"}
#    → 成功时返回新 token + vid + username（参考 D:\Develop\TrendRadar\get_login_result.py）
# ③ 关键：getLoginResult 只调微信 API 返回结果，【不写数据库】！
#    必须手动持久化 + 启用账号（mutation，body 裸对象）：
#    POST http://localhost:4000/trpc/account.edit
#      body: {"id":"<vid>","data":{"token":"<新token>","status":1}}
#    （参考 D:\Develop\TrendRadar\save_token.py，改 token 后运行）
# ④ 校验：刷新文章 feed.refreshArticles 不再报「暂无可用读书账号」
```
- 常用账号：id=`936122071`（username=Dogy）。
- 幂等性：同一 uuid 轮询多次结果一致，可安全重试。
- PowerShell 里手拼 JSON 容易被转义破坏 → **用 Python urllib 脚本**最可靠（脚本见 D:\Develop\TrendRadar\ 根目录）。

### 5.3 账号状态快捷检查 / 恢复（node:sqlite，避免 tRPC 循环调用）
```powershell
node D:\Develop\TrendRadar\dbcheck.js   # 只读查看账号 status（根目录已建，勿依赖 Temp）
# 恢复 status=1（无现成 dbreset.js，直接内联改）：
#   node -e 需注意 PowerShell 转义，建议写成临时 .js 文件执行
```
- 数据库位置：`D:\Develop\wewe-rss\apps\server\data\wewe-rss.db`（无 sqlite3.exe，用 node:sqlite 或 Python）。
- 表结构（实测）：`accounts(id, token, name, status, created_at, updated_at)` / `feeds` / `articles`。
- 文章总数/最新文章查询用 Python sqlite3 或 node:sqlite（参考 `node D:\Develop\TrendRadar\dbcheck.js`，其中打印 ARTICLES 计数）。

---

## 6. 跨午夜去重（历史 bug，已修复勿回退）

- 修复提交：`67f22ad`（`trendradar/storage/sqlite_mixin.py` L1103-1112）。
- 原 bug：仅按 `"HH:MM"` 字符串比较时间 → 跨午夜（如 23:59 与 00:01）去重失效，重复推送。
- 现逻辑：**日期+时间组合比较**。
- 相关常量：L20 `RSS_DEDUP_LOOKBACK_DAYS = 7`。

---

## 7. 关键路径 / 文件速查

| 项 | 位置 |
|---|---|
| wewe-rss 仓库 | `D:\Develop\wewe-rss`（独立 git 仓库） |
| wewe-rss 服务端 | `D:\Develop\wewe-rss\apps\server`（`pnpm --filter server start:prod`） |
| 服务端配置 | `apps/server/.env.local`（DATABASE_TYPE=sqlite, PORT=4000, AUTH_CODE — **勿提交**） |
| SQLite 数据库 | `apps/server/data/wewe-rss.db` |
| 同步脚本 | `D:\Develop\TrendRadar\sync-wechat-rss.ps1` |
| 仓库 feeds | `D:\Develop\TrendRadar\feeds\`（all.rss + 22 个 MP_WXS_*.rss） |
| CI 工作流 | `D:\Develop\TrendRadar\.github\workflows\crawler.yml`（cron "17,47 * * * *"） |
| 去重逻辑 | `D:\Develop\TrendRadar\trendradar\storage\sqlite_mixin.py` |
| **数据源配置** | `D:\Develop\TrendRadar\config\config.yaml` → `rss.feeds`（增删源步骤见第 9 节） |
| 公众号源清单 | 同一份 `rss.feeds` + `sync-wechat-rss.ps1` 的 `$Feeds` 哈希表（两处都要加） |
| 运维计划 | `D:\Develop\TrendRadar\.omo\plans\wechat-rss-setup.md`（含完整初始化仪式与验收记录） |
| 运维脚本（根目录） | `login_and_persist.py`（一键扫码续期，推荐）/ `create_login.py`（生成 uuid）/ `gen_qr.py`（渲染二维码）/ `get_login_result.py`（轮询）/ `save_token.py`（手动持久化）/ `dbcheck.js`（账号状态） |
| 临时脚本 | `C:\Users\20504\AppData\Local\Temp\opencode\`（dbcheck.js / dbreset.js / gen_qr.py / save_token.py / get_login_result.py / check_articles.py） |

---

## 8. 常见问题速答

- **「帮我启动」** → 第 2 节（2.1 检查 → 2.2 启动 → 2.4 验证 200）。
- **启动后没新文章** → 先 `feed.refreshArticles`（POST body `{}`）手动刷新一次，再跑 sync 脚本（第 3 节）。
- **Actions 没跑 / 没推送** → 先看本机 wewe-rss 是否在跑 + feeds 是否更新（第 3 节），再 `gh workflow run crawler.yml`（第 4 节）。
- **500「暂无可用读书账号」** → 第 5.1 表：账号 status=0 → `node D:\Develop\TrendRadar\dbcheck.js` 确认 → 按 5.2 一键脚本续期。

---

## 9. 新增数据源（期刊 / 网站 / 公众号）

### 9.1 先判断走哪条路

| 源类型 | 做法 | 要改的地方 |
|---|---|---|
| 有官方 RSS 的期刊 / 网站 | 直连抓 | `config/config.yaml` → `rss.feeds` 加一段 |
| 微信公众号 | 必须经本地 wewe-rss 转成 RSS | `rss.feeds` **+** `sync-wechat-rss.ps1` 的 `$Feeds` |
| 没有 RSS 的网站 | 先用 RSSHub 等转换出 feed，再按第一类加 | 同第一类（`url` 填转换后的地址） |

> `config/config.en.yaml` 是上游英文模板，**不是生效配置**，只在 `config.yaml` 里加。

### 9.2 加期刊（ScienceDirect / T&F / Wiley 等）

1. **查 ISSN**：期刊官网 "Journal information" 里的一串数字（如 Sustainable Cities and Society = 2210-6707）。
2. **拼 RSS 地址**：
   - ScienceDirect：`https://rss.sciencedirect.com/publication/science/<ISSN 去掉连字符>`
     → 例：2210-6707 → `https://rss.sciencedirect.com/publication/science/22106707`
   - Taylor & Francis：`https://www.tandfonline.com/feed/rss/<期刊代码>`
   - Wiley / Springer 也有各自 `.../feed` 路径，直接搜「<期刊名> RSS」。
3. **验证**（必做，别省）：
   ```powershell
   curl.exe -s -o NUL -w "%{http_code}`n" --max-time 25 "https://rss.sciencedirect.com/publication/science/22106707"
   # 期望 200；再确认 `<title>` 是目标期刊、`<lastBuildDate>` 是近期
   ```
4. **写进 `rss.feeds`**（位置：`config/config.yaml` 的期刊分组，约 L278 后）：
   ```yaml
   - id: "j-<短横线小写标识>"
     name: "<期刊全名>"
     url: "<上面验证过的地址>"
     max_age_days: 2
   ```
5. **`max_age_days: 2`** 对「条目自带日期」的源有效（新源首抓全部算新增，限 2 天可避免一次推几十条）。
   ⚠️ **ScienceDirect 的 RSS 条目没有 `pubDate`**（日期只写在 description 文本里，解析后 `published_at` 为空）→
   `max_age_days` 对它**实际不生效**，抓多少条就都是「新增」。这类源要用 **`max_items`** 兜底（真实运行默认 50）：
   ```yaml
       max_items: 20     # 首次灌水闸门；30 分钟一轮，正常情况下远达不到上限
   ```
   已实测：Sustainable Cities and Society 单次返回 100 条、`published_at` 全为空。

### 9.3 加微信公众号

1. 先在 wewe-rss 里能抓到该号（它自己会生成 `MP_WXS_<id>.rss`）。
2. 取到 `<id>` 后，`config.yaml` 加：
   ```yaml
   - id: "wechat-<短横线小写标识>"
     name: "<公众号名>"
     url: "${WECHAT_RSS_URL}/feeds/MP_WXS_<id>.rss"
     max_age_days: 3
   ```
3. **同一 id 还要加进 `sync-wechat-rss.ps1` 的 `$Feeds` 哈希表**（约 L60-83，键 `feeds/MP_WXS_<id>.rss`）。
   漏了这步 → 文章在本地有、但 `feeds/` 不会同步到仓库，Actions 抓不到。
4. 跑一次 `sync-wechat-rss.ps1`，确认 `feeds/` 下出现新文件（第 3 节）。

### 9.4 提交 → 生效

```powershell
git add config/config.yaml sync-wechat-rss.ps1   # 公众号源才需要第二个
git commit -m "feat(rss): 新增 <源名>"
git push                                          # 或用 trigger-push.ps1 一键（第 4 节）
gh workflow run crawler.yml                       # 立刻验证，别等 cron（第 4 节：cron 不可靠）
```
- 本地先看效果：`uv run python -m trendradar`，日志里看 `[RSS] 检测到 N 条新文章`。
- 生效点在 **Actions 下一次运行**，不是 commit 本身。

### 9.5 几条硬规矩

- **`id` 是稳定键**（去重 / 配置引用都靠它）：改 `id` = 当成一个全新源；只改名请只改 `name`。
- **删源**：删掉 `rss.feeds` 那段即可，数据库里的历史文章不受影响；公众号源还要删 `$Feeds` 里那行 + `feeds/` 下对应文件（可选）。
- **新源首推会比较多**：属正常，`max_age_days` 调小即可；多源叠加时注意 `rss.feeds` 单次抓取总量与 `ai_analysis.max_news_for_analysis`（默认 150 条）的配额。
