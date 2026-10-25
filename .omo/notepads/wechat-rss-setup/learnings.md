# learnings.md

<!-- Auto-created 2026-07-31 19:32 - Atlas orchestration notepad -->


## [2026-07-31 19:34:07] Task3 cloudflared
- INSTALL: 已存在（未安装，跳过）——cloudflared version 2026.7.3 (built 2026-07-22T09:32 UTC)
- FULL PATH: C:\Users\20504\AppData\Local\cloudflared\cloudflared.exe（已在 PATH，cloudflared 裸命令可直接调用）
- CALL PATTERN（Task 7 start-tunnel.ps1 用）: cloudflared tunnel --url http://localhost:4000 --no-autoupdate
  - quick tunnel 在 >=2024 版本不再有独立 `tunnel quick` 子命令；`tunnel --help` 无 "quick" 字样
  - 触发方式 = cloudflared tunnel --url <local-url>（无参数/无命名隧道/无需 login）
  - 默认 url 是 http://localhost:8080，wewe-rss 需显式传 --url http://localhost:4000
- LIVE VERIFIED 2026-07-31 11:33: quick tunnel 成功创建 trycloudflare.com URL 并注册连接（quic, lax10）
  - 示例: https://alternate-scene-changed-hardly.trycloudflare.com（临时 URL，重启会变——Task 7 需动态提取 stdout 中的 trycloudflare URL）
- 未注册服务、未执行 login
- 证据: .omo/evidence/task-3-version.txt, task-3-help.txt

## 2026-07-31 19:36:48 Task1 冒烟测试
- Check A PASS: gh 已认证 (LQC20504-collab, scopes: gist/read:org/repo/workflow), gh api 返回 LQC20504-collab/TrendRadar
- Check B PASS: cloudflared quick tunnel 实测链路通 (edge 返回 502 因 127.0.0.1:9 无服务, 符合预期 non-000)。Tunnel 注册成功 location=lax01 protocol=quic
- Check B caveat: 本机 DNS (10.111.111.159) 对 *.trycloudflare.com 返回 NXDOMAIN (DNS 污染); 公网 DNS 8.8.8.8/223.5.5.5 正常解析到 104.16.230.132/231.132。本地 curl 需 --resolve 绕过。GitHub Actions 端用 GitHub 自身 DNS, 不受影响
- Check B 教训: 长轮询+curl 的 PowerShell 脚本被工具 90s 超时杀掉, 但 cloudflared 子进程存活; 应分离启动与轮询, 或后台任务分步执行
- Check C PASS: https://weread.111965.xyz 返回 HTTP 200, wewe-rss 默认 PLATFORM_URL 可用, 无需强制覆盖
- Task 3 已装 cloudflared (winget 幂等复用确认), 位于 C:\Users\20504\AppData\Local\cloudflared\cloudflared.exe
- 结论: 隧道方案可行 (Task 6 可执行); PLATFORM_URL 用默认值即可 (Task 8 E2E 可执行)

## [2026-07-31 19:37:48] Task2 clone+install
- Clone wewe-rss to D:\Develop\wewe-rss: 39.2s, checkout e751c64294080d83deb1610d2667bed3cfa4b393 (detached HEAD), rev-parse verified
- pnpm install attempt 1: exit 1 ERR_PNPM_IGNORED_BUILDS - pnpm 11 blocks dependency build scripts by default (1175 pkgs installed anyway, apps/server postinstall prisma generate OK)
- Fix attempt 1 (package.json pnpm.onlyBuiltDependencies): IGNORED - pnpm 11 no longer reads the 'pnpm' field in package.json, warns "settings moved to pnpm-workspace.yaml"
- Fix attempt 2 (pnpm-workspace.yaml allowBuilds: {pkg: true} for @nestjs/core, @prisma/client, @prisma/engines, esbuild, prisma, sharp): exit 0, 13.4s
- pnpm 11 migration auto-created pnpm-workspace.yaml with placeholder 'allowBuilds: X: set this to true or false' entries - need to fill true
- esbuild 0.19.3, sharp 0.34.5 (runtime load verified), prisma engines downloaded, .prisma/client generated
- Lockfile v6.0 auto-migrated by pnpm 11 (no error)
- Warning: prisma@5.10.2 vs @prisma/client@5.10.1 mismatch (upstream package.json pins, benign for now)
- Evidence: .omo/evidence/task-2-commit.txt, task-2-install.txt

## [2026-07-31 19:44:04] Task4 SQLite初始化
- 步骤1 PASS: .env.local (apps/server/) + AUTH_CODE.txt (D:\Develop\wewe-rss\) 已写, 24位随机码一致; 两处 .gitignore 均覆盖 .env* (root .gitignore 有 .env.local 显式条目, apps/server/.gitignore 有 .env), 无需改动
- 步骤2 坑: 计划中的 swap 命令在 PowerShell 5.1 下 Rename-Item -NewName 不接受路径（只接受叶子名）, 报 PSArgumentException; Remove-Item 已删 prisma/ 导致中间态损坏。修复: Move-Item 全路径 (等价语义)。幂等重跑 PASS (第二次 no-op)
- 步骤3 PASS: prisma generate exit 0, sqlite client 生成到 .pnpm/@prisma+client@5.10.1_prisma@5.10.2 (版本 mismatch 警告仍为已知无害)
- 步骤4 坑: Prisma CLI 不读 .env.local (只读 .env/prisma/.env), 首跑 P1012 DATABASE_URL not found; 修复: 进程内注入 $env:DATABASE_URL="file:../data/wewe-rss.db" (与 .env.local 同值, 未改任何配置)。migrate deploy exit 0, 2 migrations (init, has_history)
- 步骤4 重大位置偏差: db 实际在 apps/server/data/wewe-rss.db (36864B), 不是计划的仓库根 data/! Prisma 对 SQLite 相对路径按 schema.prisma 所在目录解析 (apps/server/prisma -> ../data = apps/server/data), 非进程 CWD
- 运行时一致性已验证: 用同 env 从 apps/server 跑 PrismaClient 查询 sqlite_master -> 表 [_prisma_migrations, accounts, articles, feeds], 无 stray 文件; 运行时同样 schema-relative 解析。=> 不要 relocate db, Task 5/7/8 的证据路径必须用 apps/server/data/wewe-rss.db
- 步骤5 PASS: pnpm run -r build exit 0 (nest build Done, vite build Done 18.12s, 仅 chunk>500kB 与 PURE 注释警告); 无 ERR_PNPM_IGNORED_BUILDS 复发 -> Task 2 allowBuilds 配置生效
- 步骤6 断言: db >0B PASS (36864B), dist/main.js PASS (1496B)
- 关键配置事实: apps/server/src/app.module.ts envFilePath=['.env.local','.env'] -> 运行时 NestJS 会加载 .env.local, DATABASE_URL 注入 Prisma Client, 与 migrate 路径一致

## [2026-07-31 19:47:25] Task5 启动服务（本地验证 PASS）
- 启动命令: pnpm --filter server start:prod（root package.json 的 start:server 即此命令; apps/server scripts 确认存在 start:prod=node dist/main）
- 启动方式（Task 7 start-tunnel.ps1 复用）: Start-Process cmd.exe '/c "pnpm --filter server start:prod > server.log 2>&1"' -WorkingDirectory D:\Develop\wewe-rss -WindowStyle Hidden -PassThru
  - cmd 层重定向 2>&1 -> 单文件 server.log（Start-Process 的 -RedirectStandardOutput/-RedirectStandardError 不能指向同一文件，cmd 重定向规避）
  - 服务随独立 cmd 进程存活，不依赖 agent shell 生命周期
- 启动耗时: 约 4-5s 内就绪（启动轮询 60s 内第一次即 200）
- PID: launcher cmd 32884, node 监听进程 4608（Get-NetTCPConnection -LocalPort 4000 -State Listen -> OwningProcess）
- 日志: D:\Develop\wewe-rss\server.log, 含 "Nest application successfully started" + "Server is running at http://0.0.0.0:4000"
- 验证: GET / -> 200; GET /feeds/all.rss -> 200 + XML (<?xml ...><rss version="2.0">); 无 mysql/P1001/P1012/PrismaClientKnownRequestError => SQLite client 生效
- CRON_EXPRESSION: undefined（.env.local 未设, 默认 35 5,17 * * * 预期; 日志仅提示未设, 无影响）
- 证据: .omo/evidence/task-5-local.txt, task-5-start.txt

## [2026-07-31 19:58] Atlas H1 前置验证（tRPC 调用方式实测）
- tRPC 正确调用方式：**GET** + `?batch=1&input=`（query 用 GET，POST 会报 "No mutation-procedure on path"）
- account.list 实测：`curl.exe -s "http://localhost:4000/trpc/account.list?batch=1&input={json:'{0':{limit:1000}}}' -H "Authorization: <AUTH_CODE>"` → `[{"result":{"data":{"blocks":[],"items":[]}}}]`
- 结果: H1 未完成（items 空，无账号）→ Task 6 标记阻塞 -[~]，等用户扫码订阅
- AUTH_CODE 已由 Atlas 用 Playwright 验证可登录后台（输入框→确认→/dash 成功）
- 登录界面无二维码是正常的：二维码只在 账号管理→添加读书账号 弹窗出现（微信扫码登录 + 54s 倒计时）
- PowerShell 中 tRPC body 用 @file 传参可避免引号转义问题（POST 场景）；但 query 走 GET 更简单
- tRPC POST 路径返回 404 "No mutation-procedure" 证明服务端正常解析 → 后续验证用 GET batch 格式

## [2026-07-31 20:55] Task7 start-tunnel.ps1（交付 + 4 项 QA 全 PASS）
- 交付: D:\Develop\TrendRadar\start-tunnel.ps1（UTF-8 BOM 必加，PS5.1 无 BOM 按 ANSI 读导致中文乱码）。参数: -SmokeTest / -SkipRestart / -StartWewe / -SkipSecret。退出码: 0 成功 / 2 preflight / 3 wewe 未运行 / 4 隧道 / 5 env / 6 重启 / 7 secret / 8 验证
- 流程: preflight(cloudflared+gh+AUTH_CODE+wewe:4000) → 停旧隧道(pid 文件) → Start-Tunnel(3 次重试, 因 api.trycloudflare.com 间歇 ~20s 慢, cloudflared 超时即 exit 1) → Get-TryCloudflareUrl(只在最后一个 "Requesting new quick Tunnel" 标记后匹配, 修掉读取旧 URL 的 stale bug) → 替换 .env.local SERVER_ORIGIN_URL → 停旧 wewe+重启 → gh secret set WECHAT_RSS_URL → 验证 /feeds/all.rss=200 (直连失败回落 --resolve 8.8.8.8/223.5.5.5/1.1.1.1; 本机 DNS 对 *.trycloudflare.com 是 NXDOMAIN 污染)
- PID 记录: 写真实 cloudflared.exe PID（不是 cmd 启动器 PID）; 停止时按 pid 文件精确杀, 再 Wait-Process 防句柄残留; 删除 cloudflared.log 前重试 10s（被杀进程仍持有句柄时 Delete 会失败）
- QA 结果: smoke PASS(exit 0, cf 0→0, secret 未动) / run PASS(exit 0, 46.9s, URL hans-kyle-match-expenditure, secret 12:33:53Z→12:37:24Z) / idempotent PASS(exit 0, 70.3s, URL 变 guys-settle-nutten-analysis, 旧隧道 PID 2580 按文件清理, 单监听) / down PASS(exit 3, 提示"未运行，请先启动或加 -StartWewe", secret+env 均未动)。证据: .omo/evidence/task-7-{smoke,run,idempotent,down}.txt
- 大坑（QA 环境竞态）: 并行 Task 6 会话也在跑同一脚本, 20:41-20:43 三连跑互相覆盖 env/secret/tunnel → 两个验证都挂(530/000)。down 测试证据曾被其污染。对策: 每步先查进程+最近日志再动手; down 测试用原子脚本(停→断端口空→跑→断言→恢复)
- 大坑（自伤）: 在 bash 工具命令里用 `$_.CommandLine -match 'start:prod'` 过滤进程时, 匹配到了 bash 工具自身 powershell（其命令行含脚本全文）→ Stop-Process 自杀, 命令静默无输出、后续步骤全部没执行。教训: 过滤进程用 Get-NetTCPConnection 端口定位 + ParentProcessId 数值比较, 绝不把脚本中的字面量放进 CommandLine -match
- 验证 feed 用 /feeds/all.rss 而非 /; GET http://localhost:4000/feeds/all.rss 已实测 200+XML

## [2026-07-31 21:10] Task6/7 推送式架构交付（验证全 PASS）
- Task6 登录态: account.list 返回 items:[{id:936122071, name:Dogy, status:1}] PASS；聚合源 feeds/all.rss 30 items PASS（快照链接为旧隧道域名，已失效但不影响 RSS 解析）
- 仓库内文件: `git show HEAD:feeds/all.rss` 含 <rss> + 30 <item> PASS
- http.server 链路模拟: `python -m http.server 9000 --directory D:\Develop\TrendRadar` + `requests.get('http://127.0.0.1:9000/feeds/all.rss')` → 200 / has_rss_tag=True / item_count=30 PASS（证明 workflow 内 `--directory "$GITHUB_WORKSPACE"` 方案可行）
- Task7 sync-wechat-rss.ps1（UTF-8 BOM 必加，PS5.1 无 BOM 解析失败）:
  - 参数: -SmokeTest（只检查不修改）/ -NoPush（拉取+commit 不 push）/ -FeedUrl / -RssFile
  - 幂等: `git status --porcelain -- feeds/all.rss` 为空则跳过 commit/push
  - 提交只 `git add feeds/all.rss`，绝不 `git add .`（工作区有 .omo/、.playwright-mcp/、wewe-*.png 等未跟踪文件）
  - QA: smoke PASS(exit 0) / run PASS(30 items, f61ecbe) / idempotent 二次运行跳过 / down 故障路径明确提示
- 控制台中文乱码为 GBK 显示问题，文件内容正常（UTF-8），读取用 Read 工具即可

## [2026-07-31 21:10] Task8 E2E 全链路 PASS
- 触发: `gh workflow run crawler.yml --repo LQC20504-collab/TrendRadar` → run 30633278892, head 8958e5d（推送式提交）
- 前置: config/config.yaml L145 wechat-gis 源未改；远程 feeds/all.rss 21491 字节
- 结果: conclusion=success（用户确认飞书收到推送）
- 推送内容含 **4 条 [微信公众号 - GIS/遥感] 文章**：暑期学校第1号通知、无人机倾斜摄影三维建模、TerraScan 点云、佳文赏析 GCN-Transformer-BiLSTM —— 证明仓库文件 → http.server → fetcher → 过滤 → 飞书 全链路生效
- RSS: 8/55（源 11/17）—— 17 源中 11 个产出，wechat-gis 是其中活跃源
- 本轮无热点，跳过 AI 分析（正常行为，非失败）
- 证据: .omo/evidence/task-8-workflow.txt（日志已保存，run completed）

## [2026-07-31 22:2x] 平台限流 wxs2mp 401 排查结论（librarian 调研 + 实机验证）
- **现象**: getMpInfo 首次调用成功（超爱GIS），此后连续调用（含 30 分钟后重试）全部 `WeReadError401`（-2041）；interceptor 每次 401 都把账号 status 置 INVALID，需 `node dbreset.js` 恢复
- **调研结论**（librarian 从 cooderl/wewe-rss issue #396/#406/#443/#326 + README 提取）:
  - README 明确：**"添加频率过高容易被封禁，建议24小时后再尝试"** —— 401 就是平台对账号的临时封禁，冷却期 ≈24h
  - owner 官方表态：**只有 `https://mp.weixin.qq.com/s/xxx` 分享链接可用**，`__biz` 长链接不支持（tRPC refine 拒绝是预期行为，前端按钮同样要求 /s/ 前缀）
  - issue #396 评论：新接口只活了 2 天、账号频繁失效是普遍现象（持续到 2025-11）→ 账号失效是平台侧常态，非本地部署问题
  - issue #406（57 条评论）：账号失效后无自动恢复，需重新扫码登录（createLoginUrl/getLoginResult）
  - 版本确认为 2.6.1（本地 e751c64 部署一致）；前端 UI 按行拆分链接后**无延迟连续调用** getMpInfo —— 官方 UI 本身就会触发限流，说明限制是平台硬性的
- **应对策略**（用户已确认：先只加 8 短链接，11 长链接以后再说）:
  - 等 ≥24h 冷却（2026-08-01 后再试），串行 getMpInfo → feed.add → refreshArticles，每次间隔 ≥30s，分 2-3 批
  - 超爱GIS 已解析出 MP_WXS_3531160202，可直接 feed.add 免二次解析
  - 每次调用前 `node dbcheck.js` 确认 status=1；调用后若被置 0 立即 dbreset.js 恢复
- **工具**: dbcheck.js（只读）/ dbreset.js（恢复 status=1）在 C:\Users\20504\AppData\Local\Temp\opencode\，用 node:sqlite 直连 apps/server/data/wewe-rss.db

## [2026-07-31 22:30] 待添加公众号清单（19 个，下播前存档）
- 已添加勿重复（3 个旧源）: 地研联 MP_WXS_3901345172 / 麻辣GIS MP_WXS_2394767200 / GIS前沿 MP_WXS_3015957868
- 用户决策: 先加 8 短链接，11 长链接等提供短链接后再处理
- **第一批 8 个短链接**（冷却 ≥24h 后，间隔 ≥30s 分 2-3 批添加）:
  1. 超爱GIS: https://mp.weixin.qq.com/s/QXckfIcWeNxeYcSWF9jEDA （已解析出 MP_WXS_3531160202，可直接 feed.add）
  2. GIS思维: https://mp.weixin.qq.com/s/hRc9eDIY8AIiGKS0WJh-jw
  3. 慧天地: https://mp.weixin.qq.com/s/5Lxb5QjhaaOQTn7x6bzRdw
  4. 极思客栈: https://mp.weixin.qq.com/s/K9dBYeg1-AmicUjXzVvnHw
  5. JRS国际遥感学报: https://mp.weixin.qq.com/s/Aj-Qj7_IxukOBL4LSMfSYw
  6. 世界地理研究: https://mp.weixin.qq.com/s/i1nN9_EFRv1UxusjUm2gWQ
  7. 虾神说D: https://mp.weixin.qq.com/s/e5O9A5ro6zsIU4nUY1CATw
  8. 易智瑞: https://mp.weixin.qq.com/s/CLSSdIjabCEPYUaMwXrb-w
- **第二批 11 个长链接**（官方不支持 __biz 格式，需用户从微信 App 重新分享得 /s/ 短链接）:
  9. 超图软件集团 __biz=MjM5MDk4MzYyMA==
  10. 城市水文与景观生态 __biz=Mzg5MDcwMDg1Ng==
  11. CityPlus __biz=MzI0MDIwOTAwMQ==
  12. 地图学与地理信息系统 __biz=MzU1OTI4NzIzNg==
  13. GISer学习团 __biz=MzI0MjE2MDYzNQ==
  14. 空间智能软件技术大会 __biz=Mzg5NzEzNjYzNw==
  15. 水经注GIS __biz=MzI4ODU1OTQwMg==
  16. 小猿猴GISer __biz=MzA4MzA5NTgzMw==
  17. 遥感学报 __biz=MzU2MTM4MTYzOQ==
  18. 中国地理信息产业协会 __biz=MzIzOTAxNjc3NA==
  19. 中国地理学会 __biz=MzA5NjM1MjkwNQ==
- 提醒用户换短链接的话术: 微信里打开该公众号任意一篇文章 → 右上角"..."→ 复制链接 → 发给我
- 添加流程（实测可用）: dbcheck.js 确认 status=1 → POST /trpc/platform.getMpInfo?batch=1（body={"0":{"wxsLink":"<url>"}}）→ POST /trpc/feed.add?batch=1 → POST /trpc/feed.refreshArticles?batch=1（body={"0":{"mpId":"<id>"}}）→ 每次后复查 status → 8 个全入库后跑 sync-wechat-rss.ps1 更新推送 feeds/all.rss

## [2026-08-01 14:30] 全部 19 号 /s/ 链接已备齐,待冷却期后执行
- 11 个 __biz 号用户已补齐 /s/ 短链接(2026-08-01 14:30 收到):
  1. 超图软件集团        /s/S9dGwBakqcuiB-8ESjjQ4A
  2. 城市水文与景观生态  /s/m5QmoQ1Qk7RLOtPfRUbWzw
  3. CityPlus            /s/-CVbrdI_uQjmI5UckDYnGQ
  4. 地图学与地理信息系统 /s/ROB3XJG0T78dZcNdhAL_4A
  5. GISer学习团         /s/QHa02fp3qO2ihxIDyprMgA
  6. 空间智能软件技术大会 /s/LuYsqfJxe44iEE4USkW7JQ
  7. 水经注GIS           /s/RKNITsdolfJijzybgrcMUg
  8. 小猿猴GISer         /s/ChyiwVKH_HcMCQIox5eyEA
  9. 遥感学报            /s/OnFiVecOexAHZ0WCCZ6iCQ
  10. 中国地理信息产业协会 /s/cqMAglKlDBK8cgq8vINSzQ
  11. 中国地理学会        /s/EY9Qko8vdH5Vl2t9efWH7A
 - 待确认:learnings L117「麻辣GIS /s/QXckfIcWeNxeYcSWF9jEDA -> MP_WXS_3531160202」vs 用户 2026-08-01 清单中同一链接标「超爱GIS」=> 执行 feed.add 前需用户确认公众号名
 - 执行窗口:2026-08-01 22:00 后(24h 风控冷却期结束);每步间隔 >=30s,分 2-3 批;每批前 dbcheck status=1

## [2026-08-01 23:20] ✅ 19 个新公众号全部添加成功 + 推送链路验证通过
- **关键转折**: 22:35 首项(超爱GIS)即 `WeReadError401/-2041` 熔断 —— 24h 冷却期过后账号仍被平台拒绝,判定为 **token 已被平台作废**(非临时冷却,符合 issue #406 调研"账号失效后无自动恢复")
- **续期方案(实测可用)**: `platform.createLoginUrl`(POST batch=1, body={"0":{}}) → 返回 `{uuid, scanUrl}` → 生成二维码供用户微信扫码 → `platform.getLoginResult?id=<uuid>`(**GET 查询,带 input 参数,不是 mutation!**) → 返回新 token(vid=936122071, exp 2036) → `UPDATE accounts SET token=?, status=1`
- **扫码后**: getMpInfo 立即恢复(超爱GIS → MP_WXS_3531160202 验证通过)
- **名称歧义已消解**: /s/QXckfIcWeNxeYcSWF9jEDA 平台权威解析为**超爱GIS**(MP_WXS_3531160202),与麻辣GIS(2394767200)无关
- **批量结果**(batch-add-feeds.js 分 3 批 0-8/8-14/14-19, 每步 ≥30s): 19/19 全部 getMpInfo→feed.add→refreshArticles 成功,账号 status 全程保持 1,零 401
- **新增 19 个 feed**: 超爱GIS 3531160202 / GIS思维 3236365612 / 慧天地 3204156364 / 极思客栈 3010153083 / JRS国际遥感学报 3946166084 / 世界地理研究 3200210505 / 虾神说D 3088987824 / 易智瑞 2390266245 / 超图软件集团 2390983620 / 城市水文与景观生态 3890700856 / CityPlus 3240209001 / 地图学与地理信息系统 3559287236 / GISer学习团 3242160635 / 空间智能软件技术大会 3897136637 / 水经注GIS 3288559402 / 小猿猴GISer 3083095833 / 遥感学报 3561381639 / 中国地理信息产业协会 3239016774 / 中国地理学会 3096352905
- **配置更新**: config.yaml 微信源段 3→22 条;sync-wechat-rss.ps1 $Feeds 4→23 项(含 all.rss);提交 07a9f42 推送
- **同步执行**: sync-wechat-rss.ps1 拉取 23 源,17 个新账号源产出 10 item 各,commit e8cffd0 push 成功(17 个 RSS 文件)
- **Actions 验证**: crawler.yml workflow_dispatch run 30705698528 成功 —— 17 个微信源抓取成功,5 个 0 文章源 404 属预期(麻辣GIS/极思客栈/CityPlus/空间智能软件技术大会 近期无发布,feed 已入库,新文章发布后自动恢复);ntfy 增量推送 2 批次全部成功
- **⚠️ 重要教训**: wewe-rss 账号 token 会不定期被平台作废(非 24h 冷却可解),症状=所有 wxs2mp 调用 401;恢复流程=扫码续期(见上)。建议将 createLoginUrl/getLoginResult 流程与批量脚本合并,下次失效时一键续期
- **遗留**: 5 个 0 文章源待公众号发布后验证 RSS 恢复;config.yaml 源 ID 采用拼音/英文 slug 命名(wechat-chaoai-gis 等)
