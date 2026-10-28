<#
.SYNOPSIS
    TrendRadar 一键手动触发推送（标准方案）
.DESCRIPTION
    GitHub 平台 bug：新建仓库的 schedule cron 定时触发可能永不生效（2026-01 起平台级问题，
    见 github community #201008）。因此手动触发是本系统「定时推送」的标准替代方案。

    2026-10-28 起，微信公众号（wewe-rss）链路已退役：不再检查/拉起本地 4000 服务、
    不再刷新微信文章、不再同步 feeds/*.rss。本脚本只保留「推代码 + 触发 Actions + 验日志」。

    本脚本自动完成完整链路并逐步验证：
      0. 前置检查（gh 认证）
      1. 推送本地提交（有未推送提交时 push；失败自动用 gh token 兜底）
      2. 触发 GitHub Actions（gh workflow run crawler.yml）
      3. 轮询等待运行完成，核对日志（有 [推送] = 成功；无新增 = 正常跳过）
    exit code: 0 = 成功（含「无新增正常跳过」）；1 = 失败
.NOTES
    用法：powershell -ExecutionPolicy Bypass -File D:\Develop\TrendRadar\trigger-push.ps1
    依赖：gh 已认证（gh auth status）
#>

$ErrorActionPreference = 'Continue'
$repoRoot = 'D:\Develop\TrendRadar'

function Write-Step($msg) { Write-Output "`n===== $msg =====" }

# ── 0. 前置检查 ──────────────────────────────────────────────
Write-Step "0. 前置检查"
gh auth status 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Output "[FAIL] gh 未认证，请先执行: gh auth login"
    exit 1
}
Write-Output "[OK] gh 已认证"

# ── 1. 推送本地提交 ─────────────────────────────────────────
Write-Step "1. 推送本地提交"
$branch = (git -C $repoRoot rev-parse --abbrev-ref HEAD).Trim()
Write-Output "[INFO] 当前分支: $branch"
if ($branch -ne 'master') {
    Write-Output "[WARN] 当前不在 master，workflow_dispatch 仍按默认分支(master)运行，推送不会影响本次推送内容"
}
git -C $repoRoot fetch origin --quiet 2>$null
$hasRemote = git -C $repoRoot rev-parse --verify --quiet "origin/$branch" 2>$null
$needPush = $false
if (-not $hasRemote) {
    Write-Output "[INFO] 远程无该分支，将首次推送"
    $needPush = $true
} else {
    $cnt = [int](git -C $repoRoot rev-list --count "origin/$branch..HEAD" 2>$null)
    $needPush = ($cnt -gt 0)
    if ($needPush) { Write-Output "[INFO] 有 $cnt 个未推送提交" } else { Write-Output "[OK] 无未推送提交" }
}
if ($needPush) {
    git -C $repoRoot push origin $branch 2>&1 | Select-Object -Last 2
    if ($LASTEXITCODE -ne 0) {
        Write-Output "[WARN] 常规推送失败（凭据问题？），改用 gh token 兜底..."
        $tok = gh auth token
        git -C $repoRoot push "https://x-access-token:$tok@github.com/LQC20504-collab/TrendRadar.git" $branch 2>&1 | Select-Object -Last 2
    }
    if ($LASTEXITCODE -eq 0) {
        Write-Output "[OK] 推送成功"
    } else {
        Write-Output "[FAIL] 推送失败，请手动执行: git push origin $branch"
        exit 1
    }
}

# ── 2. 触发 GitHub Actions ───────────────────────────────────
Write-Step "2. 触发 GitHub Actions"
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

# ── 3. 等待运行完成并验证 ────────────────────────────────────
Write-Step "3. 等待运行完成并验证推送"
$status = ""
$conclusion = ""
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
