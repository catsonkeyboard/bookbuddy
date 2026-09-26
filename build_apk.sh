#!/usr/bin/env bash
# ==============================================================================
# BookBuddy App - Android APK 一键自动化打包脚本
# 完美兼容 macOS 默认 Bash 3.2 / Linux / Zsh
# 支持自动环境检测、Debug/Release模式切换、自动安装到模拟器/真机
# ==============================================================================

set -e

# 颜色高亮
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo -e "${BLUE}======================================================${NC}"
echo -e "${BLUE}       📖 BookBuddy 绘本工坊 - Android APK 打包脚本      ${NC}"
echo -e "${BLUE}======================================================${NC}"

# 1. 环境变量配置 (国内加速镜像)
export PUB_HOSTED_URL="https://pub.flutter-io.cn"
export FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"

# 清理当前会话所有残留的终端代理环境变量，防止把 Gradle 带偏
unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY

# 清理 Gradle 启动时的 JVM 代理参数
GRADLE_NO_PROXY_OPTS="-Dhttp.proxyHost= -Dhttp.proxyPort= -Dhttps.proxyHost= -Dhttps.proxyPort="
export GRADLE_OPTS="$GRADLE_NO_PROXY_OPTS"

echo -e "\n${GREEN}🚀 已启用国内高速镜像源 (并强制净化终端与 JVM 代理设置):${NC}"
echo -e "   • PUB_HOSTED_URL = $PUB_HOSTED_URL"
echo -e "   • FLUTTER_STORAGE_BASE_URL = $FLUTTER_STORAGE_BASE_URL"
echo -e "   • Gradle/Android 仓库 = 阿里云 Maven 镜像 (Google/Central/Gradle-Plugin)"

if [ -d "$HOME/development/flutter/bin" ]; then
    export PATH="$HOME/development/flutter/bin:$PATH"
fi

# 自动适配 macOS 与 Windows Android SDK 路径
if [ -d "${ANDROID_HOME:-}" ]; then
    export PATH="$PATH:$ANDROID_HOME/platform-tools"
elif [ -d "$HOME/Library/Android/sdk" ]; then
    export ANDROID_HOME="$HOME/Library/Android/sdk"
    export PATH="$PATH:$ANDROID_HOME/platform-tools"
elif [ -d "$HOME/AppData/Local/Android/Sdk" ]; then
    export ANDROID_HOME="$HOME/AppData/Local/Android/Sdk"
    export PATH="$PATH:$ANDROID_HOME/platform-tools"
elif [ -n "${LOCALAPPDATA:-}" ] && [ -d "$LOCALAPPDATA/Android/Sdk" ]; then
    export ANDROID_HOME="$LOCALAPPDATA/Android/Sdk"
    export PATH="$PATH:$ANDROID_HOME/platform-tools"
fi

if [ -z "${JAVA_HOME:-}" ]; then
    for jdk in /c/Program\ Files/Microsoft/jdk-17* /c/Program\ Files/Java/jdk-17*; do
        if [ -d "$jdk" ]; then
            export JAVA_HOME="$jdk"
            break
        fi
    done
fi

# 2. 检查依赖工具
echo -e "\n${YELLOW}🔍 正在检查基础构建环境...${NC}"

if ! command -v flutter &> /dev/null; then
    echo -e "${RED}❌ 未检测到 flutter 命令，请确认 Flutter SDK 安装路径！${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Flutter 环境就绪: $(flutter --version | head -n 1)${NC}"

# 3. 确定构建模式与日志级别 (默认直接开启实时详细输出，告别死机假象)
BUILD_MODE="debug"
BUILD_MODE_DISPLAY="DEBUG"
VERBOSE_FLAG="--verbose"

for arg in "$@"; do
    case "$arg" in
        release|--release|-r)
            BUILD_MODE="release"
            BUILD_MODE_DISPLAY="RELEASE"
            ;;
        --quiet|-q)
            VERBOSE_FLAG=""
            ;;
    esac
done

echo -e "\n${YELLOW}📦 准备构建模式: [${BUILD_MODE_DISPLAY}]${NC}"
if [ -n "$VERBOSE_FLAG" ]; then
    echo -e "${BLUE}🔍 实时进度模式已默认开启 (每一步构建日志实时滚动，绝不卡顿黑屏)${NC}"
    echo -e "${BLUE}   (若需静默输出，可传入 -q 或 --quiet 参数)${NC}"
fi

# 4. 获取依赖
echo -e "\n${YELLOW}📥 正在同步 Flutter 依赖库...${NC}"
flutter pub get

# 5. 执行打包构建 (针对 Redmi Pad 等现代 Android 设备，精准编译 64 位 arm64 架构，编译速度提升数倍且体积减半)
echo -e "\n${YELLOW}🚀 正在编译 Android ARM64 APK (目标平台: android-arm64)...${NC}"
echo -e "${GREEN}⚡ 实时编译输出流已启动，各项任务进度将直接滚动打印在下方：${NC}\n"

if [ "$BUILD_MODE" = "release" ]; then
    flutter build apk --release --target-platform android-arm64 $VERBOSE_FLAG
    APK_PATH="$SCRIPT_DIR/build/app/outputs/flutter-apk/app-release.apk"
else
    flutter build apk --debug --target-platform android-arm64 $VERBOSE_FLAG
    APK_PATH="$SCRIPT_DIR/build/app/outputs/flutter-apk/app-debug.apk"
fi

# 6. 构建结果检查
if [ -f "$APK_PATH" ]; then
    FILE_SIZE=$(ls -lh "$APK_PATH" | awk '{print $5}')
    echo -e "\n${GREEN}======================================================${NC}"
    echo -e "${GREEN}🎉 APK 打包成功！${NC}"
    echo -e "${GREEN}📁 文件路径: ${APK_PATH}${NC}"
    echo -e "${GREEN}⚖️  文件大小: ${FILE_SIZE}${NC}"
    echo -e "${GREEN}======================================================${NC}"

    # 7. 检测是否有连接的 Android 设备或平板模拟器，提示一键安装
    if command -v adb &> /dev/null; then
        ONLINE_DEVICES=$(adb devices | grep -v "List" | grep "device$" | wc -l | tr -d ' ')
        if [ "$ONLINE_DEVICES" -gt "0" ]; then
            echo -e "\n${BLUE}📱 检测到已有 $ONLINE_DEVICES 台 Android 设备/模拟器已连接！${NC}"
            read -p "是否直接安装到该设备？(y/N): " -n 1 -r REPLY
            echo
            case "$REPLY" in
                [yY]*)
                    echo -e "${YELLOW}正在安装到设备...${NC}"
                    adb install -r "$APK_PATH"
                    echo -e "${GREEN}✅ 安装完成！可直接在 Android 平板/模拟器上打开 BookBuddy 体验。${NC}"
                    ;;
                *)
                    echo -e "${YELLOW}已跳过安装。${NC}"
                    ;;
            esac
        else
            echo -e "\n${YELLOW}💡 提示: 当前未连接 Android 真机。若需安装到模拟器，可运行:${NC}"
            echo -e "   flutter emulators --launch Pixel_Tablet"
            echo -e "   adb install -r \"$APK_PATH\""
        fi
    fi
else
    echo -e "${RED}❌ 打包失败，未找到输出文件: $APK_PATH${NC}"
    exit 1
fi
