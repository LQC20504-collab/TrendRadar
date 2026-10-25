<#
.SYNOPSIS
    wewe-rss 保活 + 微信读书账号 token 巡检
.DESCRIPTION
    由 Windows 计划任务每 10 分钟调用一次：
    1. 4000 端口无监听 → 按 AGENTS.md 2.2 方式 A 重启 wewe-rss（日志落盘便于排障）
    2. 账号 status != 1  → 推送 ntfy 告警提醒扫码续期（30 分钟去重）
.NOTES
    注册计划任务（管理员或当前用户均可）：
    schtasks /Create /TN "TrendRadar\wewe-rss-keepalive" /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -File D:\Develop\TrendRadar\keep-wewe-rss-alive.ps1" /SC MINUTE /MO 10 /F
    手动测试：powershell -ExecutionPolicy Bypass -File D:\Develop\TrendRadar\keep-wewe-rss-alive.ps1
#>

$ErrorActionPreference = 'Continue'

$nodeExe       = 'C:\Program Files\nodejs\node.exe'
$weweServerDir = 'D:\Develop\wewe-rss\apps\server'
$repoRoot      = 'D:\Develop\TrendRadar'
$logDir        = "$env:LOCALAPPDATA\Temp\opencode"
$alertState    = "$logDir\wewe-account-alert.txt"
$ntfyTopic     = 'gis-trendradar-1567-33643'
$stamp         = Get-Date -Format "yyyyMMdd-HHmmss"

if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

# ── 1. 保活：4000 端口 ─────────────────────────────────────────
# 用 HTTP 探测替代 Get-NetTCPConnection（某些环境/权限下端口查询不可靠）
function Test-WeweAlive {
    try {
        $code = curl.exe -s -o NUL -w "%{http_code}" --connect-timeout 5 --max-time 15 "http://localhost:4000/feeds/all.rss" 2>$null
        return ($code -eq "200")
    } catch { return $false }
}

if (Test-WeweAlive) {
    Write-Output "[OK] wewe-rss 运行中 (HTTP 200)"
} else {
    Write-Output "[DOWN] 4000 端口无 HTTP 响应，重启 wewe-rss..."
    if (Test-Path "$weweServerDir\dist\main.js") {
        Start-Process $nodeExe -ArgumentList 'dist/main' -WorkingDirectory $weweServerDir -WindowStyle Hidden `
            -RedirectStandardOutput "$logDir\wewe-server-stdout-$stamp.log" `
            -RedirectStandardError  "$logDir\wewe-server-stderr-$stamp.log"
        $ok = $false
        for ($i = 1; $i -le 12; $i++) {
            Start-Sleep -Seconds 5
            if (Test-WeweAlive) { $ok = $true; break }
        }
        if ($ok) {
            Write-Output "[RESTART OK] wewe-rss 已恢复 (HTTP 200)"
            # 停机/重启期间可能积压了新文章，补跑一次同步推到 GitHub，让定时推送链路自愈
            Write-Output "[SYNC] 补跑同步脚本..."
            Start-Process -WindowStyle Hidden -FilePath powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$repoRoot\sync-wechat-rss.ps1`"" -Wait 2>&1 | Out-Null
            Write-Output "[SYNC] 同步完成"
        } else {
            Write-Output "[RESTART FAIL] 启动后仍无 HTTP 200，排查日志: $logDir\wewe-server-stderr-$stamp.log"
        }
    } else {
        Write-Output "[RESTART FAIL] $weweServerDir\dist\main.js 不存在，无法启动"
    }
}

# ── 2. 账号 token 巡检 ────────────────────────────────────────
try {
    $out = (node "$repoRoot\dbcheck.js" 2>$null | Out-String)
    $jsonPart = ($out -split "ARTICLES:")[0].Trim()
    if ($jsonPart) {
        $accounts = $jsonPart | ConvertFrom-Json
        foreach ($acc in $accounts) {
            if ($acc.status -ne 1) {
                Write-Output "[ALERT] 账号 $($acc.id) ($($acc.name)) status=$($acc.status)，token 可能已失效"
                $needAlert = $true
                if (Test-Path $alertState) {
                    try {
                        $last = Get-Content $alertState -Raw
                        $lastTime = [datetime]::ParseExact($last.Trim(), 'yyyy-MM-dd HH:mm:ss', $null)
                        if ((Get-Date) - $lastTime -lt [timespan]::FromMinutes(30)) { $needAlert = $false }
                    } catch { }
                }
                if ($needAlert) {
                    $msg = "⚠️ TrendRadar 微信读书 token 失效（账号 $($acc.name) status=0）`n请尽快运行：python D:\Develop\TrendRadar\login_and_persist.py 扫码续期"
                    try {
                        Invoke-RestMethod -Uri "https://ntfy.sh/$ntfyTopic" -Method Post -Body $msg -ContentType "text/plain" | Out-Null
                        Write-Output "[NTFY] 已发送失效告警"
                        Set-Content -Path $alertState -Value (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') -Encoding ascii
                    } catch {
                        Write-Output "[NTFY] 告警发送失败: $($_.Exception.Message)"
                    }
                }
            }
        }
    }
} catch {
    Write-Output "[CHECK] 账号巡检失败（服务未启动时属正常）: $($_.Exception.Message)"
}



