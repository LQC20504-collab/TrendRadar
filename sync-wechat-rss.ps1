# sync-wechat-rss.ps1
# ═══════════════════════════════════════════════════════════════════════════════
# 微信公众号聚合源 · 推送式同步脚本（替代旧方案：cloudflared 隧道 + WECHAT_RSS_URL Secret）
#
# 架构说明：
#   旧方案：本地起 cloudflared 隧道暴露公网 URL → 写入 GitHub Secret WECHAT_RSS_URL
#           → GitHub Actions workflow 远程抓取。缺点：隧道在国内网络不稳定、URL 频繁漂移。
#   新方案（本脚本）：本地定时/手动执行 → 拉取 wewe-rss 聚合源 feeds/all.rss
#           → 提交并 push 到 GitHub 仓库 → workflow 起临时 http.server 服务该文件供 fetcher 抓取。
#           零公网依赖、零隧道、零 Secret。
#
# 用法：
#   .\sync-wechat-rss.ps1                # 完整同步（拉取 + commit + push）
#   .\sync-wechat-rss.ps1 -SmokeTest     # 只检查环境（wewe-rss 可达性 + git + gh），不做任何修改
#   .\sync-wechat-rss.ps1 -NoPush        # 拉取 + commit，不 push（调试用）
#
# 参数：
#   -FeedUrl   wewe-rss 聚合源地址（默认 http://localhost:4000/feeds/all.rss）
#   -RssFile   仓库内 RSS 文件相对路径（默认 feeds/all.rss）
# ═══════════════════════════════════════════════════════════════════════════════

param(
    [switch]$SmokeTest,
    [switch]$NoPush,
    [string]$FeedUrl = "http://localhost:4000/feeds/all.rss",
    [string]$RssFile = "feeds/all.rss"
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

# ── 1. 前置检查 ───────────────────────────────────────────
Write-Log "=== 前置检查 ==="

# 1.1 wewe-rss 服务可达性（/feeds 路径无需鉴权）
try {
    $status = curl.exe -s -o NUL -w "%{http_code}" --connect-timeout 5 $FeedUrl
    if ($status -ne "200") { throw "HTTP $status" }
    Write-Log "OK  wewe-rss 服务可达: $FeedUrl (HTTP 200)"
}
catch {
    Write-Log "ERR wewe-rss 服务不可达: $FeedUrl ($_)" "ERROR"
    Write-Log "    请先启动 wewe-rss（pnpm --filter server start:prod，CWD=D:\Develop\wewe-rss）" "ERROR"
    exit 1
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

# ── 2. 拉取 RSS（先到临时文件，避免无变化时污染工作区）────
Write-Log "=== 拉取 RSS ==="
$rssAbsPath = Join-Path $repoRoot $RssFile
$rssDir = Split-Path -Parent $rssAbsPath
if (-not (Test-Path $rssDir)) { New-Item -ItemType Directory -Path $rssDir -Force | Out-Null }

$tmpRss = Join-Path $env:TEMP "wewe-rss-download.rss"
curl.exe -s --connect-timeout 10 --max-time 60 -o $tmpRss $FeedUrl
if ($LASTEXITCODE -ne 0) {
    Write-Log "ERR 拉取失败 (curl exit $LASTEXITCODE)" "ERROR"
    Remove-Item $tmpRss -Force -ErrorAction SilentlyContinue
    exit 1
}

# 校验内容：必须含 <rss 且 ≥1 <item>
$content = Get-Content -Path $tmpRss -Raw -Encoding UTF8
if ($content -notmatch "<rss" -or $content -notmatch "<item>") {
    Write-Log "ERR RSS 内容无效（缺 <rss 或 <item>），已保存到 $rssAbsPath 供检查" "ERROR"
    Copy-Item $tmpRss $rssAbsPath -Force
    Remove-Item $tmpRss -Force -ErrorAction SilentlyContinue
    exit 1
}
$itemCount = ([regex]::Matches($content, "<item>")).Count
Write-Log "OK  拉取成功: $itemCount 个 item -> $rssAbsPath"

# ── 3. 幂等检查：与 HEAD 版本比较（剔除 lastBuildDate）────
# wewe-rss 每次请求都会刷新 <lastBuildDate> 字段，若直接比较全文件
# 则永远"有变化"，每次运行都会产生空转提交。故先剔除该字段再比较。
function Normalize-Rss([string]$s) {
    $s = [regex]::Replace($s, '<lastBuildDate>[^<]*</lastBuildDate>', '')
    return $s.Replace("`r`n", "`n").Replace("`r", "`n")
}

$headTmp = Join-Path $env:TEMP "wewe-rss-head.rss"
Push-Location $repoRoot
cmd /c "git show HEAD:$RssFile > `"$headTmp`" 2>NUL"
Pop-Location
$headContent = ""
if (Test-Path $headTmp) {
    $headContent = Get-Content -Path $headTmp -Raw -Encoding UTF8
    Remove-Item $headTmp -Force -ErrorAction SilentlyContinue
}

if ((Normalize-Rss $content) -ceq (Normalize-Rss $headContent)) {
    Write-Log "SKIP RSS 内容无变化（仅 lastBuildDate 更新），跳过 commit/push"
    Remove-Item $tmpRss -Force -ErrorAction SilentlyContinue
    Write-Log "    日志: $logFile"
    exit 0
}
Write-Log "OK  RSS 内容有实质变化，继续提交"

# 有实质变化才写盘（保持原始字节，LF 换行不变）
Copy-Item $tmpRss $rssAbsPath -Force
Remove-Item $tmpRss -Force -ErrorAction SilentlyContinue

# ── 4. commit（只提交 RSS 文件，不带入其他未跟踪文件）──────
Write-Log "=== git commit ==="
git -C $repoRoot add -- $RssFile
if ($LASTEXITCODE -ne 0) { Write-Log "ERR git add 失败" "ERROR"; exit 1 }

$commitMsg = "chore(rss): 同步微信公众号聚合源 ($(Get-Date -Format 'yyyy-MM-dd HH:mm'))"
git -C $repoRoot commit -m $commitMsg -- $RssFile
if ($LASTEXITCODE -ne 0) { Write-Log "ERR git commit 失败" "ERROR"; exit 1 }
Write-Log "OK  commit: $commitMsg"

if ($NoPush) {
    Write-Log "SKIP -NoPush 指定，跳过 push"
    Write-Log "    日志: $logFile"
    exit 0
}

# ── 5. push ───────────────────────────────────────────────
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
