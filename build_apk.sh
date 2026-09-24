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

# 1. 环境变量配置
export PUB_HOSTED_URL="https://pub.flutter-io.cn"
export FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"

if [ -d "$HOME/development/flutter/bin" ]; then
    export PATH="$HOME/development/flutter/bin:$PATH"
fi

if [ -d "$HOME/Library/Android/sdk" ]; then
    export ANDROID_HOME="$HOME/Library/Android/sdk"
    export PATH="$PATH:$ANDROID_HOME/platform-tools"
fi

# 2. 检查依赖工具
echo -e "\n${YELLOW}🔍 正在检查基础构建环境...${NC}"

if ! command -v flutter &> /dev/null; then
    echo -e "${RED}❌ 未检测到 flutter 命令，请确认 Flutter SDK 安装路径！${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Flutter 环境就绪: $(flutter --version | head -n 1)${NC}"

# 3. 确定构建模式 (默认 debug，传入 release 则打 release 包)
BUILD_MODE="debug"
BUILD_MODE_DISPLAY="DEBUG"
if [ "$1" = "release" ] || [ "$1" = "--release" ] || [ "$1" = "-r" ]; then
    BUILD_MODE="release"
    BUILD_MODE_DISPLAY="RELEASE"
fi

echo -e "\n${YELLOW}📦 准备构建模式: [${BUILD_MODE_DISPLAY}]${NC}"

# 4. 获取依赖
echo -e "\n${YELLOW}📥 正在同步 Flutter 依赖库...${NC}"
flutter pub get

# 5. 执行打包构建
echo -e "\n${YELLOW}🚀 正在编译 Android APK，请稍候...${NC}"
if [ "$BUILD_MODE" = "release" ]; then
    flutter build apk --release
    APK_PATH="$SCRIPT_DIR/build/app/outputs/flutter-apk/app-release.apk"
else
    flutter build apk --debug
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
