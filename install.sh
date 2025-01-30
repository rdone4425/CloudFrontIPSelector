#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 版本信息
VERSION="1.0.0"

# 工作目录
WORK_DIR="$HOME/cloudfront-docker"
DATA_DIR="$WORK_DIR/data"
CONFIG_FILE="$WORK_DIR/config.conf"
HISTORY_DIR="$DATA_DIR/history"
MAIN_SCRIPT="$WORK_DIR/cloudfront_selector.sh"

# 打印信息函数
info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查sudo权限
check_sudo() {
    if ! sudo -v &> /dev/null; then
        error "需要sudo权限来创建软链接"
        return 1
    fi
    return 0
}

# 创建软链接函数
create_symlink() {
    local target="/usr/local/bin/cfs"
    if [ ! -L "$target" ]; then
        if check_sudo; then
            sudo ln -s "$MAIN_SCRIPT" "$target"
            info "已创建快捷命令: cfs"
        fi
    fi
}

# 删除软链接函数
remove_symlink() {
    local target="/usr/local/bin/cfs"
    if [ -L "$target" ]; then
        if check_sudo; then
            sudo rm "$target"
            info "已删除快捷命令"
        fi
    fi
}

# 检查文件是否需要下载
check_download_needed() {
    local file="$1"
    local url="$2"
    
    # 如果文件不存在，需要下载
    if [ ! -f "$file" ]; then
        return 0
    fi
    
    # 如果文件存在但不完整，需要下载
    if [ ! -s "$file" ]; then
        return 0
    fi
    
    # 检查文件的MD5值
    local remote_md5=$(curl -sSL "${url}.md5" 2>/dev/null)
    if [ -n "$remote_md5" ]; then
        local local_md5=$(md5sum "$file" | cut -d' ' -f1)
        if [ "$remote_md5" != "$local_md5" ]; then
            return 0
        fi
    fi
    
    return 1
}

# 下载文件函数
download_file() {
    local url="$1"
    local target="$2"
    
    if check_download_needed "$target" "$url"; then
        info "下载文件: $url"
        curl -sSL "$url" -o "$target"
        if [ $? -eq 0 ]; then
            info "下载完成"
            return 0
        else
            error "下载失败"
            return 1
        fi
    else
        info "文件已存在且完整，跳过下载"
        return 0
    fi
}

# 检查系统类型
check_system() {
    if [ -f "/etc/openwrt_version" ]; then
        echo "openwrt"
    elif [ -f "/etc/lsb-release" ] && grep -q "Ubuntu" /etc/lsb-release; then
        echo "ubuntu"
    elif [ -f "/etc/debian_version" ]; then
        echo "debian"
    elif [ -f "/etc/redhat-release" ]; then
        echo "redhat"
    else
        echo "unknown"
    fi
}

# 检查命令是否存在
check_command() {
    if ! command -v $1 &> /dev/null; then
        error "$1 未安装"
        return 1
    fi
    return 0
}

# 检查是否是首次安装
is_first_install() {
    [ ! -f "$MAIN_SCRIPT" ]
}

# 主要安装逻辑
main() {
    # 创建工作目录
    mkdir -p "$WORK_DIR"
    
    # 如果是首次安装，下载所需文件
    if is_first_install; then
        # 下载主程序
        local main_url="https://raw.githubusercontent.com/rdone4425/CloudFrontIPSelector/main/cloudfront_selector.sh"
        download_file "$main_url" "$MAIN_SCRIPT"
        
        if [ $? -eq 0 ]; then
            chmod +x "$MAIN_SCRIPT"
            
            # 确保文件写入完成
            sync
            sleep 1
            
            # 创建软链接
            create_symlink
            
            info "安装完成"
            echo -e "现在你可以使用 'cfs' 命令来启动程序"
        else
            error "安装失败"
            exit 1
        fi
    fi
    
    # 运行主程序
    if [ -x "$MAIN_SCRIPT" ]; then
        exec "$MAIN_SCRIPT" "$@"
    else
        error "主程序不存在或没有执行权限"
        exit 1
    fi
}

# 检查是否通过管道执行
if [ ! -t 0 ]; then
    # 创建工作目录
    mkdir -p "$WORK_DIR"
    
    # 从标准输入保存到临时文件
    TMP_FILE=$(mktemp)
    cat > "$TMP_FILE"
    
    # 检查临时文件是否有效
    if [ -s "$TMP_FILE" ]; then
        mv "$TMP_FILE" "$MAIN_SCRIPT"
        chmod +x "$MAIN_SCRIPT"
        
        # 确保文件写入完成
        sync
        
        info "安装完成"
        create_symlink
        echo -e "现在你可以使用 'cfs' 命令来启动程序"
    else
        error "接收到的数据无效"
        rm -f "$TMP_FILE"
        exit 1
    fi
    
    # 清理并退出
    sleep 1
    exit
fi

# 执行主函数
main "$@"
