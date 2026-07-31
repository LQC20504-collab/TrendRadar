@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

echo ==========================================
echo   TrendRadar MCP 一键部署 (Windows)
echo ==========================================
echo.

REM 修复：使用脚本所在目录，而不是当前工作目录
set "PROJECT_ROOT=%~dp0"
REM 移除末尾的反斜杠
if "%PROJECT_ROOT:~-1%"=="\" set "PROJECT_ROOT=%PROJECT_ROOT:~0,-1%"

echo 📍 项目目录: %PROJECT_ROOT%
echo.

REM 切换到项目目录
cd /d "%PROJECT_ROOT%"
if %errorlevel% neq 0 (
    echo ❌ 无法访问项目目录
    pause
    exit /b 1
)

REM 验证项目结构
echo [0/4] 🔍 验证项目结构...
if not exist "pyproject.toml" (
    echo ❌ 未找到 pyproject.toml 文件: %PROJECT_ROOT%
    echo.
    echo 请检查:
    echo   1. setup-windows.bat 是否在项目根目录?
    echo   2. 项目文件是否完整?
    echo.
    echo 当前目录内容:
    dir /b
    echo.
    pause
    exit /b 1
)
echo ✅ pyproject.toml 已找到
echo.

REM 检查 Python
echo [1/4] 🐍 检查 Python...
python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo ⚠️ python 命令未找到，尝试 py 命令...
    py --version >nul 2>&1
    if %errorlevel% neq 0 (
        echo ❌ 未检测到 Python，请先安装 Python 3.10+
        echo.
        echo 下载地址（复制到浏览器打开）:
        echo   https://www.python.org/downloads/
        echo.
        echo 安装提示:
        echo   1. 勾选 "Add Python to PATH"（非常重要！）
        echo   2. 安装完成后重启此脚本
        echo.
        pause
        exit /b 1
    ) else (
        echo ✅ 已找到 py 命令（Python 启动器）
        REM 创建 python 别名，后续统一用 python
        doskey python=py $*
    )
) else (
    for /f "tokens=*" %%i in ('python --version') do echo ✅ %%i
)
echo.

REM 检查 UV
echo [2/4] 🔧 检查 UV...
where uv >nul 2>&1
if %errorlevel% neq 0 (
    echo UV 未安装，正在自动安装...
    echo.
    
    echo 尝试方法1: PowerShell 安装...
    powershell -ExecutionPolicy Bypass -Command "try { irm https://astral.sh/uv/install.ps1 | iex; exit 0 } catch { Write-Host 'PowerShell 安装失败'; exit 1 }"
    
    if %errorlevel% neq 0 (
        echo.
        echo 方法1失败，尝试方法2: pip 安装...
        python -m pip install --upgrade uv
        
        if %errorlevel% neq 0 (
            echo.
            echo ❌ 自动安装失败
            echo.
            echo 请手动安装 UV，可选方法:
            echo.
            echo   方法1 - pip:
            echo     python -m pip install uv
            echo.
            echo   方法2 - pipx:
            echo     pip install pipx
            echo     pipx install uv
            echo.
            echo   方法3 - 手动下载:
            echo     访问: https://docs.astral.sh/uv/getting-started/installation/
            echo.
            pause
            exit /b 1
        )
    )
    
    echo.
    echo ✅ UV 安装完成！
    echo.
    echo ⚠️  重要: 请按照以下步骤操作:
    echo   1. 关闭此窗口
    echo   2. 重新打开命令提示符（或 PowerShell）
    echo   3. 回到项目目录: %PROJECT_ROOT%
    echo   4. 重新运行此脚本: setup-windows.bat
    echo.
    pause
    exit /b 0
) else (
    for /f "tokens=*" %%i in ('uv --version') do echo ✅ %%i
)
echo.

echo [3/4] 📦 安装项目依赖...
echo 工作目录: %PROJECT_ROOT%
echo.

REM 确保在项目目录下执行
cd /d "%PROJECT_ROOT%"
uv sync
if %errorlevel% neq 0 (
    echo.
    echo ❌ 依赖安装失败
    echo.
    echo 可能的原因:
    echo   1. 网络连接问题
    echo   2. Python 版本不兼容（需要 ^>= 3.10）
    echo   3. pyproject.toml 文件格式错误
    echo.
    echo 故障排查:
    echo   - 检查网络连接
    echo   - 验证 Python 版本: python --version
    echo   - 尝试详细输出: uv sync --verbose
    echo.
    echo 项目目录: %PROJECT_ROOT%
    echo.
    pause
    exit /b 1
)
echo.
echo ✅ 依赖安装成功
echo.

echo [4/4] ⚙️  检查配置文件...

REM 检查 config.yaml
if not exist "config\config.yaml" (
    echo ⚠️  config\config.yaml 不存在
    if exist "config\config.example.yaml" (
        echo.
        copy "config\config.example.yaml" "config\config.yaml" >nul 2>&1
        if exist "config\config.yaml" (
            echo ✅ 已自动从 config\config.example.yaml 创建
            echo.
            echo 即将用记事本打开 config\config.yaml，请填写:
            echo   - 推送渠道的 Webhook URL（必填）
            echo   - AI API Key（可选）
            echo.
            echo 填完后保存关闭记事本即可。
            echo.
            pause
            start notepad "config\config.yaml"
        )
    )
    echo.
) else (
    echo ✅ config\config.yaml 已存在
)

REM 检查 frequency_words.txt
if not exist "config\frequency_words.txt" (
    echo ⚠️  config\frequency_words.txt 不存在！
    echo.
    echo 请创建一个该文件，每行写一个你关心的关键词。
    echo 示例内容:
    echo ----------------------------------------
    echo AI
    echo 华为
    echo 特斯拉
    echo ----------------------------------------
    echo.
    echo 如果留空，则会推送所有新闻（受推送大小限制）。
    echo.
) else (
    echo ✅ config\frequency_words.txt 已存在
)
echo.

REM 获取 UV 路径
for /f "tokens=*" %%i in ('where uv 2^>nul') do set "UV_PATH=%%i"
if not defined UV_PATH (
    set "UV_PATH=uv"
)

echo.
echo ==========================================
echo            部署完成！
echo ==========================================
echo.
echo 🧪 测试运行（确认配置无误后执行）:
echo   %PROJECT_ROOT%\run.bat
echo.
echo   或手动运行:
echo   cd /d "%PROJECT_ROOT%"
echo   uv run python -m trendradar
echo.
echo 📋 MCP 服务器配置信息（用于 Cherry Studio）:
echo.
echo   命令: %UV_PATH%
echo   工作目录: %PROJECT_ROOT%
echo.
echo   参数（逐行填入）:
echo     --directory
echo     %PROJECT_ROOT%
echo     run
echo     python
echo     -m
echo     mcp_server.server
echo.
echo 📖 详细教程: README-Cherry-Studio.md
echo.
echo.
pause