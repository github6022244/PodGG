#!/bin/bash
# 安装脚本 - 与 podgg.sh 位于同一仓库

# 主脚本在仓库中的路径（同一仓库下直接引用文件名）
SCRIPT_NAME="podgg.sh"
# 仓库的 raw 基础地址（替换为你的实际仓库地址）
RAW_BASE_URL="https://gitee.com/6022463/PodGG/master"

# 拼接完整的脚本下载地址
SCRIPT_URL="${RAW_BASE_URL}/${SCRIPT_NAME}"

# 安装逻辑
echo "正在安装 podgg 工具..."
if sudo curl -fsSL "$SCRIPT_URL" -o /usr/local/bin/podgg; then
    sudo chmod +x /usr/local/bin/podgg
    echo "✅ 安装成功！可直接使用 podgg 命令"
else
    echo "❌ 安装失败，请检查网络或仓库地址是否正确"
    exit 1
fi
    
