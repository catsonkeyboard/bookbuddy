<#
.SYNOPSIS
    BookBuddy App - Windows PowerShell Android APK 一键自动化打包脚本
.DESCRIPTION
    针对 Windows 环境定制，支持自动环境检测、Debug/Release 模式切换、自动编译 ARM64 APK。
.EXAMPLE
    .\build_apk.ps1                 # 构建 Debug 版本 (默认)
    .\build_apk.ps1 -Release        # 构建 Release 版本
    .\build_apk.ps1 -Quiet          # 静默输出模式
#>

[CmdletBinding()]
param (
    [switch]$Release,
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$scriptDir = $PSScriptRoot
Set-Location $scriptDir

Write-Host "======================================================" -ForegroundColor Cyan
Write-Host "       📖 BookBuddy 绘本工坊 - Android APK 打包脚本 (Windows)      " -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan

# 1. 环境变量与国内镜像配置
$env:PUB_HOSTED_URL = "https://pub.flutter-io.cn"
$env:FLUTTER_STORAGE_BASE_URL = "https://storage.flutter-io.cn"

# 清理当前会话残留代理变量，防止 Gradle 被带偏
foreach ($p in @("http_proxy","https_proxy","all_proxy","HTTP_PROXY","HTTPS_PROXY","ALL_PROXY")) {
    if (Test-Path "Env:$p") { Remove-Item "Env:$p" -ErrorAction SilentlyContinue }
}

# 强制重置 Gradle 内部代理参数
$GRADLE_NO_PROXY_OPTS = "-Dhttp.proxyHost= -Dhttp.proxyPort= -Dhttps.proxyHost= -Dhttps.proxyPort="
$env:GRADLE_OPTS = "$GRADLE_NO_PROXY_OPTS -Dorg.gradle.daemon=false -Dfile.encoding=UTF-8"

# 自动补全 JAVA_HOME
if (-not $env:JAVA_HOME -or -not (Test-Path $env:JAVA_HOME)) {
    foreach ($jdkRoot in @("C:\Program Files\Microsoft", "C:\Program Files\Java")) {
        $jdk = Get-ChildItem -Path $jdkRoot -Directory -Filter "jdk-17*" -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending | Select-Object -First 1
        if ($jdk) {
            $env:JAVA_HOME = $jdk.FullName
            break
        }
    }
}

# 自动补全 ANDROID_HOME
if (-not $env:ANDROID_HOME -or -not (Test-Path $env:ANDROID_HOME)) {
    $defaultSdk = "$env:LOCALAPPDATA\Android\Sdk"
    if (Test-Path $defaultSdk) {
        $env:ANDROID_HOME = $defaultSdk
        $env:ANDROID_SDK_ROOT = $defaultSdk
    }
}

# 自动补全 PATH (Flutter 与 platform-tools)
$flutterBin = "$env:USERPROFILE\development\flutter\bin"
if (Test-Path $flutterBin) {
    if ($env:PATH -notlike "*$flutterBin*") {
        $env:PATH = "$flutterBin;$env:PATH"
    }
}
$platformTools = "$env:ANDROID_HOME\platform-tools"
if (Test-Path $platformTools) {
    if ($env:PATH -notlike "*$platformTools*") {
        $env:PATH = "$env:PATH;$platformTools"
    }
}

Write-Host "`n🚀 已启用国内高速镜像源与构建环境:" -ForegroundColor Green
Write-Host "   • PUB_HOSTED_URL           = $env:PUB_HOSTED_URL"
Write-Host "   • FLUTTER_STORAGE_BASE_URL = $env:FLUTTER_STORAGE_BASE_URL"
Write-Host "   • JAVA_HOME                = $env:JAVA_HOME"
Write-Host "   • ANDROID_HOME             = $env:ANDROID_HOME"

# 2. 检查依赖工具
Write-Host "`n🔍 正在检查基础构建环境..." -ForegroundColor Yellow
$flutterCmd = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutterCmd) {
    Write-Host "❌ 未检测到 flutter 命令，请确认 Flutter SDK 路径已配置！" -ForegroundColor Red
    exit 1
}

$flutterVer = (& flutter --version | Select-Object -First 1)
Write-Host "✓ Flutter 就绪: $flutterVer" -ForegroundColor Green

# 3. 确定构建模式
$buildMode = if ($Release) { "release" } else { "debug" }
$buildModeUpper = $buildMode.ToUpper()

Write-Host "`n📦 准备构建模式: [$buildModeUpper]" -ForegroundColor Yellow

# 4. 获取依赖
Write-Host "`n📥 正在同步 Flutter 依赖库..." -ForegroundColor Yellow
& flutter pub get
if ($LASTEXITCODE -ne 0) {
    throw "Flutter dependency restore failed with exit code $LASTEXITCODE."
}

# 5. 执行打包构建 (ARM64)
Write-Host "`n🚀 正在编译 Android ARM64 APK (目标平台: android-arm64)..." -ForegroundColor Yellow
$buildArgs = @(
    "build", "apk",
    "--$buildMode",
    "--target-platform", "android-arm64"
)
if (-not $Quiet) {
    $buildArgs += "--verbose"
}
& flutter @buildArgs
if ($LASTEXITCODE -ne 0) {
    throw "Flutter APK build failed with exit code $LASTEXITCODE."
}

$apkPath = Join-Path $scriptDir "build\app\outputs\flutter-apk\app-$buildMode.apk"

# 6. 构建结果检查
if (Test-Path $apkPath) {
    $fileItem = Get-Item $apkPath
    $fileSizeMB = "{0:N1} MB" -f ($fileItem.Length / 1MB)

    Write-Host "`n======================================================" -ForegroundColor Green
    Write-Host "🎉 APK 打包成功！" -ForegroundColor Green
    Write-Host "📁 文件路径: $apkPath" -ForegroundColor Green
    Write-Host "⚖️  文件大小: $fileSizeMB" -ForegroundColor Green
    Write-Host "======================================================" -ForegroundColor Green

    # 7. 检测是否连接设备
    $adbCmd = Get-Command adb -ErrorAction SilentlyContinue
    if ($adbCmd) {
        $devices = (& adb devices | Where-Object { $_ -match "\tdevice$" })
        if ($devices -and $devices.Count -gt 0) {
            Write-Host "`n📱 检测到已有 $($devices.Count) 台 Android 设备/模拟器已连接！" -ForegroundColor Cyan
            $ans = Read-Host "是否直接安装到该设备？(y/N)"
            if ($ans -match "^[yY]") {
                Write-Host "正在安装到设备..." -ForegroundColor Yellow
                & adb install -r "$apkPath"
                if ($LASTEXITCODE -ne 0) {
                    throw "ADB installation failed with exit code $LASTEXITCODE."
                }
                Write-Host "✅ 安装完成！可直接在 Android 平板/模拟器上打开体验。" -ForegroundColor Green
            }
        } else {
            Write-Host "`n💡 提示: 当前未连接 Android 真机。若需安装到模拟器/设备，可用 adb install -r `"$apkPath`"" -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "`n❌ 打包失败，未找到输出文件: $apkPath" -ForegroundColor Red
    exit 1
}
