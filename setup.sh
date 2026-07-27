#!/bin/bash
set -e

echo "========================================"
echo "  Dobby iOS 静态库一键编译脚本"
echo "========================================"

if [ ! -d "dobby" ]; then
    echo "[1/3] 正在克隆 Dobby 源码..."
    git clone https://github.com/jmpews/Dobby.git --depth=1 dobby
else
    echo "[1/3] Dobby 目录已存在，跳过克隆"
fi

cd dobby

echo "[2/3] 正在编译 Dobby iOS arm64 静态库..."
python3 scripts/platform_builder.py --platform=iphoneos --arch=arm64

echo "[3/3] 编译完成，查找产物..."
echo ""
echo "----- 找到的库文件 -----"
find . -name "*.a" -o -name "*.framework" | head -20
echo "-----------------------"
echo ""

echo "========================================"
echo "  完成！"
echo "========================================"
