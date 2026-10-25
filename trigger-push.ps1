<#
.SYNOPSIS
    TrendRadar 一键手动触发推送（标准方案）
.DESCRIPTION
    GitHub 平台 bug：新建仓库的 schedule cron 定时触发可能永不生效（2026-01 起平台级问题，
    见 github community #201008）。因此手动触发是本系统「定时推送」的标准替代方案。

    本脚本自动完成完整链路并逐步验证：
      0. 前置检查（gh 认证 + wewe-rss 存活，挂了自动拉起）
      1. 刷新微信文章（让同步拿到最新内容）
      2. 同步 RSS 到 GitHub（commit + push；push 失败自动用 gh token 兜底）
      3. 触发 GitHub Actions（gh workflow run crawler.yml）
      4. 轮询等待运行完成，核对日志（有 [推送] = 成功；无新增 = 正常跳过）
    exit code: 0 = 成功（含「无新增正常跳过」）；1 = 失败
.NOTES
    用法：powershell -ExecutionPolicy Bypass -File D:\Develop\TrendRadar\trigger-push.ps1
    依赖：gh 已认证（gh auth status）、wewe-rss 可被拉起（keep-wewe-rss-alive.ps1）
#>

$ErrorActionPreference = 'Continue'
$repoRoot      = 'D:\Develop\TrendRadar'
$weweEnvLocal  = 'D:\Develop\wewe-rss\apps\server\.env.local'

function Write-Step($msg) { Write-Output "`n===== $msg =====" }
function Test-WeweAlive {
    try {
        $code = curl.exe -s -o NUL -w "%{http_code}" --connect-timeout 5 --max-time 15 "http://localhost:4000/feeds/all.rss" 2>$null
        return ($code -eq "200")
    } catch { return $false }
}

# ── 0. 前置检查 ──────────────────────────────────────────────
Write-Step "0. 前置检查"
gh auth status 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Output "[FAIL] gh 未认证，请先执行: gh auth login"
    exit 1
}
Write-Output "[OK] gh 已认证"

if (-not (Test-WeweAlive)) {
    Write-Output "[WARN] wewe-rss 未运行（4000 无响应），尝试自动拉起..."
    powershell -NoProfile -ExecutionPolicy Bypass -File "$repoRoot\keep-wewe-rss-alive.ps1" | Out-Null
    if (-not (Test-WeweAlive)) {
        Write-Output "[FAIL] wewe-rss 拉起失败，请先解决服务问题（见 AGENTS.md 第 2 节）"
        exit 1
    }
}
Write-Output "[OK] wewe-rss 运行中"

# ── 1. 刷新微信文章 ──────────────────────────────────────────
Write-Step "1. 刷新微信文章"
$auth = ""
if (Test-Path $weweEnvLocal) {
    $m = Select-String -Path $weweEnvLocal -Pattern '^AUTH_CODE=(.+)$'
    if ($m) { $auth = $m.Matches[0].Groups[1].Value.Trim().Trim('"') }
}
if ($auth) {
    try {
        Invoke-RestMethod -Uri "http://localhost:4000/trpc/feed.refreshArticles" -Method Post `
            -Headers @{ Authorization = $auth } -ContentType "application/json" -Body '{}' -TimeoutSec 300 | Out-Null
        Write-Output "[OK] 刷新已触发，等待 30 秒让文章落库..."
        Start-Sleep -Seconds 30
    } catch {
        Write-Output "[WARN] 刷新失败（不阻塞，继续）: $($_.Exception.Message)"
    }
} else {
    Write-Output "[WARN] 未找到 AUTH_CODE（$weweEnvLocal），跳过刷新"
}

# ── 2. 同步 RSS 到 GitHub ────────────────────────────────────
Write-Step "2. 同步 RSS 到 GitHub"
powershell -NoProfile -ExecutionPolicy Bypass -File "$repoRoot\sync-wechat-rss.ps1" 2>&1 | Select-Object -Last 6

# 若 sync 因凭据问题只 commit 未 push，用 gh token 兜底
git -C $repoRoot fetch origin --quiet 2>$null
$unpushed = git -C $repoRoot log --oneline origin/master..HEAD 2>$null
if ($unpushed) {
    Write-Output "[INFO] 检测到未推送提交，用 gh token 兜底推送..."
    $tok = gh auth token
    git -C $repoRoot push "https://x-access-token:$tok@github.com/LQC20504-collab/TrendRadar.git" master 2>&1 | Select-Object -Last 2
    if ($LASTEXITCODE -eq 0) {
        Write-Output "[OK] 兜底推送成功"
    } else {
        Write-Output "[FAIL] 兜底推送失败，请手动执行: git push origin master"
        exit 1
    }
} else {
    Write-Output "[OK] 无未推送提交（内容无变化或已推送）"
}

# ── 3. 触发 GitHub Actions ───────────────────────────────────
Write-Step "3. 触发 GitHub Actions"
$runUrl = gh workflow run crawler.yml 2>&1
Write-Output $runUrl
Start-Sleep -Seconds 8
$line = gh run list --workflow=crawler.yml --limit 1 2>$null
$fields = $line -split "`t"
$runId = $fields[6]
if (-not $runId -or $runId -notmatch '^\d+$') {
    Write-Output "[FAIL] 未找到新运行，请检查: gh run list --workflow=crawler.yml --limit 5"
    exit 1
}
Write-Output "[OK] 新运行 ID: $runId"

# ── 4. 等待运行完成并验证 ────────────────────────────────────
Write-Step "4. 等待运行完成并验证推送"
$status = ""
for ($i = 1; $i -le 36; $i++) {
    Start-Sleep -Seconds 10
    $l = gh run list --workflow=crawler.yml --limit 1 2>$null
    $lf = $l -split "`t"
    $status = $lf[0]
    $conclusion = $lf[1]
    Write-Output ("    轮询 ${i}/36: 状态=$status 结论=$conclusion")
    if ($status -eq "completed") { break }
}
if ($status -ne "completed") {
    Write-Output "[FAIL] 运行超时未完成（15 分钟内），请查看: gh run view $runId --log"
    exit 1
}
Write-Output "[INFO] 运行结论: $conclusion"

$job = gh api "repos/LQC20504-collab/TrendRadar/actions/runs/$runId/jobs" --jq '.jobs[0].id' 2>$null
if ($job) {
    $log = gh api --allow-escape-sequences "repos/LQC20504-collab/TrendRadar/actions/jobs/$job/logs" 2>$null
    if ($log -match "\[推送\] 准备发送") {
        if ($log -match "\[AI\] 分析完成") {
            Write-Output "[OK] 推送成功：文章已发送，AI 总结已产出"
        } else {
            Write-Output "[OK] 推送成功：文章已发送（AI 总结本轮未产出，见日志）"
        }
    } elseif ($log -match "\[RSS\] 检测到 0 条新增" -or $log -match "没有新增") {
        Write-Output "[OK] 本轮无新增内容，正常跳过推送（非故障）"
    } else {
        Write-Output "[WARN] 无法确认推送结果，请人工核对: gh run view $runId --log"
    }
} else {
    Write-Output "[WARN] 未取到 job 日志，请人工核对: gh run view $runId --log"
}
Write-Output "`n===== 完成 ====="
exit 0


