# sync-wechat-rss.ps1
# ═══════════════════════════════════════════════════════════════════════════════
# 微信公众号聚合源 · 推送式同步脚本（替代旧方案：cloudflared 隧道 + WECHAT_RSS_URL Secret）
#
# 架构说明：
#   旧方案：本地起 cloudflared 隧道暴露公网 URL → 写入 GitHub Secret WECHAT_RSS_URL
#           → GitHub Actions workflow 远程抓取。缺点：隧道在国内网络不稳定、URL 频繁漂移。
#   新方案（本脚本）：本地定时/手动执行 → 拉取 wewe-rss 聚合源与 3 个按账号源
#           → 提交并 push 到 GitHub 仓库 → workflow 起临时 http.server 服务这些文件
#           供 fetcher 抓取。零公网依赖、零隧道、零 Secret。
#
# 默认同步 4 个文件（与 config.yaml 中 3 个 per-account 微信源对应）：
#   feeds/all.rss               ← ${WECHAT_RSS_URL}/feeds/all.rss             （聚合源，失败即中止）
#   feeds/MP_WXS_3901345172.rss ← ${WECHAT_RSS_URL}/feeds/MP_WXS_3901345172.rss （地研联，失败仅告警）
#   feeds/MP_WXS_2394767200.rss ← ${WECHAT_RSS_URL}/feeds/MP_WXS_2394767200.rss （麻辣GIS，失败仅告警）
#   feeds/MP_WXS_3015957868.rss ← ${WECHAT_RSS_URL}/feeds/MP_WXS_3015957868.rss （GIS前沿，失败仅告警）
#
# 用法：
#   .\sync-wechat-rss.ps1                # 完整同步（拉取 4 个源 + commit + push）
#   .\sync-wechat-rss.ps1 -SmokeTest     # 只检查环境（wewe-rss 可达性 + git + gh），不做任何修改
#   .\sync-wechat-rss.ps1 -NoPush        # 拉取 + commit，不 push（调试用）
#
# 参数：
#   -FeedUrl/-RssFile  单文件模式（向后兼容）：任一提供时仅同步这一对，行为与旧版一致；
#                      两者均省略时走默认的 4 文件同步。
# ═══════════════════════════════════════════════════════════════════════════════

param(
    [switch]$SmokeTest,
    [switch]$NoPush,
    [string]$FeedUrl = "",   # 单文件模式：源地址（默认留空 = 4 文件模式）
    [string]$RssFile = ""    # 单文件模式：仓库内 RSS 文件相对路径（默认留空 = 4 文件模式）
)

$ErrorActionPreference = "Stop"

# ── 路径解析 ──────────────────────────────────────────────
$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$logDir = Join-Path $repoRoot ".omo\logs"
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logFile = Join-Path $logDir "sync-wechat-rss-$timestamp.log"

if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

function Write-Log {
    param([string]$Msg, [string]$Level = "INFO")
    $line = "[$(Get-Date -Format 'HH:mm:ss')] [$Level] $Msg"
    Write-Host $line
    Add-Content -Path $logFile -Value $line -Encoding UTF8
}

# ── 0. 模式与源表 ─────────────────────────────────────────
# 单文件模式（-FeedUrl/-RssFile 任一提供）：只同步这一对，行为与旧版一致；
# 否则默认同步 4 个文件（all.rss 聚合源 + 3 个按账号源）。
$SingleFileMode = ($FeedUrl -ne "" -or $RssFile -ne "")
if ($SingleFileMode) {
    if ($FeedUrl -eq "") { $FeedUrl = "http://localhost:4000/feeds/all.rss" }
    if ($RssFile -eq "") { $RssFile = "feeds/all.rss" }
    $Feeds = @{ $RssFile = $FeedUrl }
}
else {
    $Feeds = [ordered]@{
        "feeds/all.rss"               = "http://localhost:4000/feeds/all.rss"
        "feeds/MP_WXS_3901345172.rss" = "http://localhost:4000/feeds/MP_WXS_3901345172.rss"
        "feeds/MP_WXS_2394767200.rss" = "http://localhost:4000/feeds/MP_WXS_2394767200.rss"
        "feeds/MP_WXS_3015957868.rss" = "http://localhost:4000/feeds/MP_WXS_3015957868.rss"
    }
}
# 主源：聚合源 all.rss（单文件模式即用户指定的那一对），失败时中止整个同步
$PrimaryRel = if ($SingleFileMode) { $RssFile } else { "feeds/all.rss" }
$PrimaryUrl = $Feeds[$PrimaryRel]

# ── 1. 前置检查 ───────────────────────────────────────────
Write-Log "=== 前置检查 ==="

# 1.1 wewe-rss 服务可达性（/feeds 路径无需鉴权；主源不可达则中止）
try {
    $status = curl.exe -s -o NUL -w "%{http_code}" --connect-timeout 5 --max-time 15 $PrimaryUrl
    if ($status -ne "200") { throw "HTTP $status" }
    Write-Log "OK  wewe-rss 服务可达: $PrimaryUrl (HTTP 200)"
}
catch {
    Write-Log "ERR wewe-rss 服务不可达: $PrimaryUrl ($_)" "ERROR"
    Write-Log "    请先启动 wewe-rss（pnpm --filter server start:prod，CWD=D:\Develop\wewe-rss）" "ERROR"
    exit 1
}

# 1.1b 附加源可达性（非致命：单个账号源挂掉不阻塞整体同步）
if (-not $SingleFileMode) {
    foreach ($rel in $Feeds.Keys) {
        if ($rel -eq $PrimaryRel) { continue }
        $s = curl.exe -s -o NUL -w "%{http_code}" --connect-timeout 5 --max-time 15 $Feeds[$rel]
        if ($s -eq "200") { Write-Log "OK  附加源可达: $($Feeds[$rel]) (HTTP 200)" }
        else { Write-Log "WARN 附加源不可达: $($Feeds[$rel]) (HTTP $s)，本次同步将跳过该源" "WARN" }
    }
}

# 1.2 git 仓库
if (-not (Test-Path (Join-Path $repoRoot ".git"))) {
    Write-Log "ERR 不是 git 仓库: $repoRoot" "ERROR"
    exit 1
}
Write-Log "OK  git 仓库存在: $repoRoot"

# 1.3 gh 认证（push 需要）
if (-not $SmokeTest) {
    gh auth status 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Log "ERR gh 未认证，无法 push。请先执行 gh auth login" "ERROR"
        exit 1
    }
    Write-Log "OK  gh 已认证"
}

# SmokeTest：仅环境检查，到此结束
if ($SmokeTest) {
    Write-Log "OK  SmokeTest 通过（仅检查环境，未做任何修改）"
    Write-Log "    日志: $logFile"
    exit 0
}

# ── 幂等比较辅助 ──────────────────────────────────────────
# wewe-rss 每次请求都会刷新 <lastBuildDate> 字段，若直接比较全文件
# 则永远"有变化"，每次运行都会产生空转提交。故先剔除该字段再比较。
function Normalize-Rss([string]$s) {
    $s = [regex]::Replace($s, '<lastBuildDate>[^<]*</lastBuildDate>', '')
    return $s.Replace("`r`n", "`n").Replace("`r", "`n")
}

# ── 2. 逐文件拉取（先到临时文件，避免无变化时污染工作区）────
function Sync-OneFeed {
    param(
        [string]$Url,
        [string]$RelFile,      # 仓库内相对路径，如 feeds/all.rss
        [bool]$AbortOnError    # 主源（all.rss）失败即中止；账号源失败仅告警继续
    )
    $rssAbsPath = Join-Path $repoRoot $RelFile
    $rssDir = Split-Path -Parent $rssAbsPath
    if (-not (Test-Path $rssDir)) { New-Item -ItemType Directory -Path $rssDir -Force | Out-Null }

    $base = [IO.Path]::GetFileNameWithoutExtension($RelFile)
    $tmpRss = Join-Path $env:TEMP "wewe-rss-download-$base.rss"
    $headTmp = Join-Path $env:TEMP "wewe-rss-head-$base.rss"

    # 2.1 下载
    curl.exe -s --connect-timeout 10 --max-time 60 -o $tmpRss $Url
    if ($LASTEXITCODE -ne 0) {
        Remove-Item $tmpRss -Force -ErrorAction SilentlyContinue
        if ($AbortOnError) {
            Write-Log "ERR 拉取失败 (curl exit $LASTEXITCODE): $Url" "ERROR"
            exit 1
        }
        Write-Log "ERR 拉取失败 (curl exit $LASTEXITCODE): $Url，跳过该源继续" "ERROR"
        return $false
    }

    # 2.2 校验内容：必须含 <rss 且 ≥1 <item>
    $content = Get-Content -Path $tmpRss -Raw -Encoding UTF8
    if ($content -notmatch "<rss" -or $content -notmatch "<item>") {
        if ($AbortOnError) {
            Write-Log "ERR RSS 内容无效（缺 <rss 或 <item>），已保存到 $rssAbsPath 供检查" "ERROR"
            Copy-Item $tmpRss $rssAbsPath -Force
            Remove-Item $tmpRss -Force -ErrorAction SilentlyContinue
            exit 1
        }
        Write-Log "ERR RSS 内容无效（缺 <rss 或 <item>）: $Url，跳过该源继续" "ERROR"
        Remove-Item $tmpRss -Force -ErrorAction SilentlyContinue
        return $false
    }
    $itemCount = ([regex]::Matches($content, "<item>")).Count
    Write-Log "OK  拉取成功: $itemCount 个 item -> $RelFile"

    # 2.3 幂等检查：与 HEAD 版本比较（剔除 lastBuildDate）
    Push-Location $repoRoot
    cmd /c "git show HEAD:$RelFile > `"$headTmp`" 2>NUL"
    Pop-Location
    $headContent = ""
    if (Test-Path $headTmp) {
        $headContent = Get-Content -Path $headTmp -Raw -Encoding UTF8
        Remove-Item $headTmp -Force -ErrorAction SilentlyContinue
    }

    if ((Normalize-Rss $content) -ceq (Normalize-Rss $headContent)) {
        Write-Log "SKIP $RelFile 无变化（仅 lastBuildDate 更新）"
        Remove-Item $tmpRss -Force -ErrorAction SilentlyContinue
        return $false
    }

    # 2.4 有实质变化才写盘（保持原始字节，LF 换行不变）并暂存
    Copy-Item $tmpRss $rssAbsPath -Force
    Remove-Item $tmpRss -Force -ErrorAction SilentlyContinue
    git -C $repoRoot add -- $RelFile
    if ($LASTEXITCODE -ne 0) { Write-Log "ERR git add 失败: $RelFile" "ERROR"; exit 1 }
    Write-Log "OK  $RelFile 有实质变化，已暂存"
    return $true
}

Write-Log "=== 拉取 RSS ==="
$changedFiles = @()
foreach ($rel in $Feeds.Keys) {
    $abort = ($SingleFileMode -or $rel -eq $PrimaryRel)
    if (Sync-OneFeed -Url $Feeds[$rel] -RelFile $rel -AbortOnError $abort) {
        $changedFiles += $rel
    }
}

# ── 3. commit（只提交 feeds/ 下实际变化的文件，不带入其他未跟踪文件）────
if ($changedFiles.Count -eq 0) {
    Write-Log "SKIP 所有 RSS 内容无变化（仅 lastBuildDate 更新），跳过 commit/push"
    Write-Log "    日志: $logFile"
    exit 0
}

Write-Log "=== git commit ==="
$commitMsg = "chore(rss): 同步微信公众号聚合源 ($(Get-Date -Format 'yyyy-MM-dd HH:mm'))"
git -C $repoRoot commit -m $commitMsg -- $changedFiles
if ($LASTEXITCODE -ne 0) { Write-Log "ERR git commit 失败" "ERROR"; exit 1 }
Write-Log "OK  commit: $commitMsg"
Write-Log "    变更文件: $($changedFiles -join ', ')"

if ($NoPush) {
    Write-Log "SKIP -NoPush 指定，跳过 push"
    Write-Log "    日志: $logFile"
    exit 0
}

# ── 4. push ───────────────────────────────────────────────
Write-Log "=== git push ==="
git -C $repoRoot push origin master
if ($LASTEXITCODE -ne 0) {
    Write-Log "ERR git push 失败" "ERROR"
    Write-Log "    本地已 commit（$commitMsg），可手动 git push 或重跑脚本" "ERROR"
    exit 1
}
Write-Log "OK  push 成功: origin master"
Write-Log "    日志: $logFile"
exit 0
