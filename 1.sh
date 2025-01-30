#!/bin/bash

# 如果是通过管道执行，先保存脚本
if [ ! -t 0 ]; then
    # 创建工作目录
    WORK_DIR="$HOME/cloudfront-docker"
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR"
    
    # 保存脚本并继续执行
    tee setup_cloudfront.sh | bash
    exit 0
fi

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 工作目录
WORK_DIR="$HOME/cloudfront-docker"
DATA_DIR="$WORK_DIR/data"

# 打印信息
info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
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

# 安装Docker
install_docker() {
    info "检查Docker安装..."
    if ! check_command docker; then
        info "开始安装Docker..."
        
        # 获取系统类型
        SYS_TYPE=$(check_system)
        
        case $SYS_TYPE in
            openwrt)
                opkg update
                opkg install docker
                /etc/init.d/docker enable
                /etc/init.d/docker start
                ;;
            ubuntu)
                # 安装依赖
                apt-get update
                apt-get install -y ca-certificates curl gnupg
                
                # 添加Docker官方GPG密钥
                install -m 0755 -d /etc/apt/keyrings
                curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
                chmod a+r /etc/apt/keyrings/docker.gpg
                
                # 添加Docker仓库
                echo \
                "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
                "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
                tee /etc/apt/sources.list.d/docker.list > /dev/null
                
                # 安装Docker
                apt-get update
                apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
                
                # 启动Docker
                systemctl enable docker || true
                systemctl start docker || service docker start
                ;;
            debian)
                # 安装依赖
                apt-get update
                apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
                
                # 添加Docker GPG密钥
                curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
                
                # 添加Docker仓库
                echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
                
                # 安装Docker
                apt-get update
                apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
                
                # 启动Docker
                systemctl enable docker || true
                systemctl start docker || service docker start
                ;;
            redhat)
                # 安装依赖
                yum install -y yum-utils
                
                # 添加Docker仓库
                yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
                
                # 安装Docker
                yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
                
                # 启动Docker
                systemctl enable docker || true
                systemctl start docker || service docker start
                ;;
            *)
                error "不支持的系统类型"
                exit 1
                ;;
        esac
        
        sleep 3
        
        if ! check_command docker; then
            error "Docker安装失败"
            exit 1
        fi
    fi
    info "Docker已安装"
    
    # 安装docker-compose
    if ! check_command docker-compose; then
        info "安装docker-compose..."
        case $SYS_TYPE in
            openwrt)
                opkg install docker-compose
                ;;
            ubuntu|debian|redhat)
                # 首先尝试安装 Docker Compose 插件
                if [ "$SYS_TYPE" = "ubuntu" ] || [ "$SYS_TYPE" = "debian" ]; then
                    apt-get install -y docker-compose-plugin || true
                elif [ "$SYS_TYPE" = "redhat" ]; then
                    yum install -y docker-compose-plugin || true
                fi
                
                # 如果插件安装失败，安装独立版本
                if ! command -v docker compose &> /dev/null; then
                    info "安装独立版本 docker-compose..."
                    # 确保目标目录存在且有写权限
                    if [ ! -w "/usr/local/bin" ]; then
                        error "没有写入权限，尝试使用sudo"
                        exit 1
                    fi
                    
                    # 下载docker-compose
                    curl -L "https://github.com/docker/compose/releases/download/v2.5.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
                    
                    # 检查下载是否成功
                    if [ ! -f "/usr/local/bin/docker-compose" ]; then
                        error "docker-compose 下载失败"
                        exit 1
                    fi
                    
                    # 添加执行权限
                    chmod +x /usr/local/bin/docker-compose
                    
                    # 验证安装
                    if ! command -v docker-compose &> /dev/null; then
                        error "docker-compose 安装失败"
                        exit 1
                    fi
                fi
                ;;
        esac
        
        # 最终验证
        if ! check_command docker-compose && ! command -v docker compose &> /dev/null; then
            error "docker-compose 安装失败"
            exit 1
        fi
    fi
    info "docker-compose已安装"
}

# 创建必要的目录和文件
create_files() {
    info "创建工作目录..."
    mkdir -p "$WORK_DIR"
    mkdir -p "$DATA_DIR"
    
    info "创建docker-compose.yml..."
    cat > "$WORK_DIR/docker-compose.yml" << 'EOL'
version: '3'

services:
  cloudfront-selector:
    image: docker.442595.xyz/python:3.9-alpine
    container_name: cloudfront-selector
    network_mode: "host"
    volumes:
      - ./data:/data
      - ./cloudfront_selector.py:/app/cloudfront_selector.py
    environment:
      - THRESHOLD=150
      - PING_COUNT=5
      - RESULT_DIR=/data
    command: >
      sh -c "
        apk add --no-cache curl iputils jq bc &&
        pip install requests netaddr &&
        python /app/cloudfront_selector.py
      "
    restart: unless-stopped
EOL
    
    info "创建Python脚本..."
    cat > "$WORK_DIR/cloudfront_selector.py" << 'EOL'
#!/usr/bin/env python3
import os
import json
import time
import subprocess
import requests
from datetime import datetime
from netaddr import IPNetwork

class CloudFrontSelector:
    def __init__(self):
        self.threshold = int(os.getenv('THRESHOLD', 150))
        self.ping_count = int(os.getenv('PING_COUNT', 5))
        self.result_dir = os.getenv('RESULT_DIR', '/data')
        self.result_file = f"{self.result_dir}/result.txt"
        self.log_file = f"{self.result_dir}/cloudfront.log"
        
        # 中国IP段前缀，用于排除
        self.cn_prefixes = [
            '120.', '111.', '116.', '180.',
            '123.', '140.', '183.', '101.',
            '106.', '112.', '113.', '114.',
            '117.', '121.', '122.', '125.',
            '182.', '211.', '218.', '222.',
            '36.', '39.', '42.', '58.',
            '59.', '60.', '61.', '124.',
            '202.', '203.', '210.', '220.',
            '221.', '223.'
        ]
        
        os.makedirs(self.result_dir, exist_ok=True)
    
    def log(self, message):
        timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        with open(self.log_file, 'a') as f:
            f.write(f"{timestamp} {message}\n")
        print(f"{timestamp} {message}")
    
    def is_cn_ip(self, ip):
        return any(ip.startswith(prefix) for prefix in self.cn_prefixes)
    
    def test_ip(self, ip, retries=3):
        best_latency = None
        for _ in range(retries):
            try:
                cmd = f"ping -c {self.ping_count} {ip}"
                result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
                
                if result.returncode == 0:
                    for line in result.stdout.split('\n'):
                        if 'avg' in line:
                            avg = float(line.split('/')[4])
                            if best_latency is None or avg < best_latency:
                                best_latency = avg
            except:
                continue
            time.sleep(0.5)
        return best_latency
    
    def test_ip_range(self, ip_range):
        results = []
        try:
            network = IPNetwork(ip_range)
            test_ips = [str(ip) for ip in list(network)[1:6]]
            
            for ip in test_ips:
                if not self.is_cn_ip(ip):
                    self.log(f"测试IP: {ip}")
                    latency = self.test_ip(ip)
                    if latency and latency < self.threshold:
                        results.append((ip, latency))
                        self.log(f"发现低延迟IP: {ip} ({latency:.1f}ms)")
        except Exception as e:
            self.log(f"测试IP段 {ip_range} 时出错: {str(e)}")
        return results
    
    def save_results(self, results):
        with open(self.result_file, 'w') as f:
            for ip, latency in sorted(results, key=lambda x: x[1]):
                f.write(f"{ip} {latency:.1f}\n")
    
    def run(self):
        self.log("开始运行CloudFront IP选择器...")
        self.log("获取CloudFront IP列表...")
        all_results = []
        
        try:
            response = requests.get('https://ip-ranges.amazonaws.com/ip-ranges.json')
            data = response.json()
            
            for prefix in data['prefixes']:
                if prefix['service'] == 'CLOUDFRONT':
                    ip_range = prefix['ip_prefix']
                    region = prefix.get('region', '')
                    
                    if region in ['ap-northeast-1', 'ap-southeast-1', 'ap-northeast-2', 'ap-southeast-2']:
                        self.log(f"测试亚洲区IP段: {ip_range} (区域: {region})")
                        results = self.test_ip_range(ip_range)
                        all_results.extend(results)
            
            if len(all_results) < 10:
                self.log("测试其他地区的IP...")
                for prefix in data['prefixes']:
                    if prefix['service'] == 'CLOUDFRONT':
                        ip_range = prefix['ip_prefix']
                        if not any(ip_range.startswith(p) for p in self.cn_prefixes):
                            self.log(f"测试IP段: {ip_range}")
                            results = self.test_ip_range(ip_range)
                            all_results.extend(results)
                            
                            if len(all_results) >= 20:
                                break
        
        except Exception as e:
            self.log(f"获取IP列表失败: {str(e)}")
        
        self.save_results(all_results)
        
        self.log(f"测试完成,找到 {len(all_results)} 个低延迟IP")
        self.log(f"结果保存在: {self.result_file}")

if __name__ == "__main__":
    selector = CloudFrontSelector()
    selector.run()
EOL
}

# 检查docker compose命令
get_compose_cmd() {
    if command -v docker-compose &> /dev/null; then
        echo "docker-compose"
    elif command -v docker &> /dev/null && docker compose version &> /dev/null; then
        echo "docker compose"
    else
        echo ""
    fi
}

# 启动服务
start_service() {
    info "启动CloudFront IP选择器服务..."
    cd "$WORK_DIR"
    
    if [ -f "docker-compose.yml" ]; then
        COMPOSE_CMD=$(get_compose_cmd)
        if [ -z "$COMPOSE_CMD" ]; then
            error "未找到可用的docker compose命令"
            exit 1
        fi
        
        $COMPOSE_CMD down 2>/dev/null
        $COMPOSE_CMD up -d
        
        if [ $? -eq 0 ]; then
            info "服务启动成功"
            info "使用以下命令查看日志:"
            echo "  cd $WORK_DIR && $COMPOSE_CMD logs -f"
            info "结果文件位置:"
            echo "  $DATA_DIR/result.txt"
        else
            error "服务启动失败"
            exit 1
        fi
    else
        error "配置文件不存在"
        exit 1
    fi
}

# 处理Ctrl+C信号
handle_sigint() {
    echo -e "\n${YELLOW}正在退出...${NC}"
    exit 0
}

# 主菜单
show_menu() {
    # 确保是在终端中运行
    if [ ! -t 0 ] || [ ! -t 1 ]; then
        error "请在终端中运行此命令"
        exit 1
    fi

    # 获取compose命令(只在第一次调用时获取)
    if [ -z "$COMPOSE_CMD" ]; then
        COMPOSE_CMD=$(get_compose_cmd)
        if [ -z "$COMPOSE_CMD" ]; then
            error "未找到可用的docker compose命令"
            exit 1
        fi
    fi

    # 重置终端设置
    stty sane

    while true; do
        clear
        echo -e "\n${GREEN}=== CloudFront IP选择器 ===${NC}"
        echo "1. 启动服务"
        echo "2. 停止服务"
        echo "3. 查看日志"
        echo "4. 查看结果"
        echo "5. 重启服务"
        echo "0. 退出"
        echo -e "\n当前状态:"
        if docker ps | grep -q "cloudfront-selector"; then
            echo -e "${GREEN}服务正在运行${NC}"
        else
            echo -e "${YELLOW}服务未运行${NC}"
        fi
        
        echo -n "请选择操作 [0-5]: "
        read choice </dev/tty
        
        # 调试信息
        echo "DEBUG: 输入值: '$choice'"
        
        # 检查是否为空
        if [ -z "$choice" ]; then
            warn "请输入一个数字"
            sleep 1
            continue
        fi
        
        # 检查是否为数字
        if ! [[ "$choice" =~ ^[0-5]$ ]]; then
            warn "请输入0-5之间的数字"
            sleep 1
            continue
        fi
        
        case $choice in
            1)
                start_service
                sleep 2
                ;;
            2)
                cd "$WORK_DIR" && $COMPOSE_CMD down
                info "服务已停止"
                sleep 2
                ;;
            3)
                clear
                cd "$WORK_DIR" && $COMPOSE_CMD logs -f
                ;;
            4)
                clear
                if [ -f "$DATA_DIR/result.txt" ]; then
                    echo -e "\n${GREEN}=== 测试结果 ===${NC}"
                    cat "$DATA_DIR/result.txt"
                    echo -e "\n按回车键继续..."
                    read </dev/tty
                else
                    warn "结果文件不存在"
                    sleep 2
                fi
                ;;
            5)
                cd "$WORK_DIR" && $COMPOSE_CMD restart
                info "服务已重启"
                sleep 2
                ;;
            0)
                echo -e "${GREEN}感谢使用，再见！${NC}"
                exit 0
                ;;
        esac
    done
}

# 主函数
main() {
    # 设置信号处理
    trap handle_sigint SIGINT
    
    # 检查是否通过管道执行
    if [ ! -t 0 ]; then
        info "开始安装CloudFront IP选择器..."
        
        # 检查并安装Docker
        install_docker
        
        # 创建必要的文件
        create_files
        
        # 启动服务
        start_service
        
        # 下载并保存脚本
        info "保存脚本..."
        curl -sSL https://raw.githubusercontent.com/rdone4425/CloudFrontIPSelector/main/1.sh -o "$WORK_DIR/setup_cloudfront.sh"
        if [ $? -eq 0 ]; then
            chmod +x "$WORK_DIR/setup_cloudfront.sh"
            
            # 提示用户如何进入交互模式
            echo -e "\n${GREEN}=== 安装完成 ===${NC}"
            echo -e "请执行以下命令进入交互模式："
            echo -e "  cd $WORK_DIR && ./setup_cloudfront.sh --menu"
        else
            error "脚本保存失败"
            echo -e "请手动下载脚本："
            echo -e "  cd $WORK_DIR"
            echo -e "  curl -sSL https://raw.githubusercontent.com/rdone4425/CloudFrontIPSelector/main/1.sh -o setup_cloudfront.sh"
            echo -e "  chmod +x setup_cloudfront.sh"
        fi
        
        exit 0
    else
        # 检查是否是菜单模式
        if [ "$1" = "--menu" ]; then
            # 显示菜单
            show_menu
        else
            # 直接执行完整流程
            info "开始安装CloudFront IP选择器..."
            
            # 检查并安装Docker
            install_docker
            
            # 创建必要的文件
            create_files
            
            # 启动服务
            start_service
            
            # 显示菜单
            show_menu
        fi
    fi
}

# 直接运行主函数，传递所有参数
main "$@"
