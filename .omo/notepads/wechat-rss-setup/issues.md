# issues.md

<!-- Auto-created 2026-07-31 19:32 - Atlas orchestration notepad -->


## [2026-07-31 20:10] H1 二维码流程教训（用户反馈）
- 问题: Atlas 生成登录二维码后继续派发 Task 7，二维码 60s 过期，用户没来得及扫 → 用户不满："二维码失效了，你都不停下来等我"
- 根因: 微信登录二维码时效仅 ~60s；生成后必须立即停下来等用户扫码，不能并行推进其他任务
- 教训: H1 人工门禁期间，禁止派发任何其他任务。每次生成新二维码后：打开图片 → 明确告知用户 → 停止一切 task() 派发，原地轮询等待
- 当前状态: 最新二维码 uuid=031WLYaw3eXw100K 已生成并打开（D:\Develop\TrendRadar\wewe-login-qrcode.png），account.list 仍为空，用户尚未扫码成功
- 后续: 若用户报告过期，重新生成；不要主动推进 Task 7（用户明确要求停下等待）

## [2026-07-31 20:14] H1 扫码完成 + 账号入库成功
- 用户扫码成功：getLoginResult(uuid=031WLYaw3eXw100K) → success，vid=936122071，username=Dogy，token 已获取
- **tRPC batch body 格式坑（已解决）**: batch 调用 body 必须是 `{"0": <裸input>}`（arrayToDict 输出，无 `{"json":...}` 包装层）；`{"0":{"json":{...}}}` 会导致服务端解出空 input → 400 invalid_type received undefined。单调用（非 batch）body 为裸 input 对象。
- 成功示例: `POST /trpc/account.add?batch=1` body=`{"0":{"id":"936122071","token":"<token>","name":"Dogy","status":1}}` + `Authorization: <AUTH_CODE>` → 200，account 入库
- account.list 现返回 items:[{id:936122071, name:Dogy, status:1}]；/feeds/all.rss 返回 200 但无 <item>（feed 记录为空）
- **H1 剩余**: 步骤 4 用户需在 wewe-rss UI 添加 GIS/遥感公众号源（公众号源→添加→粘贴分享链接 ≤2-3 个）；Task 6 的"聚合源有内容"场景依赖此步
- wewe-rss feed 架构: Account(登录凭据) ≠ Feed(公众号)；feed 需单独创建，文章经 `getMpArticles`(xid+token) 拉取；cron `35 5,17 * * *` 定时刷新，也可 `GET /feeds/:id.rss?update=true` 手动触发

## [2026-07-31 21:10] 推送式架构注意点
- feeds/all.rss 快照中的 item 链接是旧 trycloudflare 域名（已失效）；RSS 解析/过滤不受影响，但若 fetcher 对 item 链接做二次请求会失败——E2E 时若抓不到内容优先检查 fetcher 对链接的使用方式
- 推送时效性依赖手动/定时运行 sync-wechat-rss.ps1（当前手动）；如需实时可后续加 Windows 计划任务（未实现，等用户确认）

## [2026-08-01 23:20] ✅ 19 个公众号全部添加 + 推送链路端到端验证通过
- 状态: 19/19 新 feed 全部入库 (getMpInfo → feed.add → refreshArticles), 账号 status 全程 1
- 账号续期: 22:35 批次首项 401 → 判定 token 作废 → createLoginUrl 扫码 → getLoginResult 获新 token → UPDATE accounts 表 → 恢复
- 配置: config.yaml 微信源 3→22 条 + sync-wechat-rss.ps1 4→23 文件, commit 07a9f42 已推送
- 同步: sync-wechat-rss.ps1 拉取 23 源, 17 个新源各 10 item, commit e8cffd0 已推送
- Actions: run 30705698528 成功, 17 微信源抓取 + ntfy 增量推送 2 批次成功
- 遗留: 5 个 0 文章源 (麻辣GIS/极思客栈/CityPlus/空间智能软件技术大会/超爱GIS) 待公众号发布后自动恢复 (其中超爱GIS 在首次刷新后为 0, 已确认 feed 入库正常)
- 教训: wewe-rss token 会被平台不定期作废 (非 24h 冷却可解), 恢复 = createLoginUrl 扫码续期, 流程已记录 learnings.md
