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

# 版本信息
VERSION="1.0.0"

# 工作目录
WORK_DIR="$HOME/cloudfront-docker"
DATA_DIR="$WORK_DIR/data"
CONFIG_FILE="$WORK_DIR/config.conf"
HISTORY_DIR="$DATA_DIR/history"

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

# 安装docker-compose
install_docker_compose() {
    info "检查docker-compose..."
    COMPOSE_INSTALLED=0
    
    # 检查docker compose插件
    if command -v docker &> /dev/null && docker compose version &> /dev/null; then
        info "docker compose插件已安装"
        COMPOSE_INSTALLED=1
    else
        # 检查独立版本
        if command -v docker-compose &> /dev/null; then
            info "docker-compose已安装"
            COMPOSE_INSTALLED=1
        else
            info "安装docker-compose..."
            case $SYS_TYPE in
                openwrt)
                    opkg install docker-compose
                    ;;
                ubuntu|debian)
                    # 安装插件版本
                    apt-get update
                    apt-get install -y docker-compose-plugin
                    
                    # 如果插件安装失败，安装独立版本
                    if ! docker compose version &> /dev/null; then
                        curl -L "https://github.com/docker/compose/releases/download/v2.5.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
                        chmod +x /usr/local/bin/docker-compose
                    fi
                    ;;
                redhat)
                    yum install -y docker-compose-plugin
                    
                    # 如果插件安装失败，安装独立版本
                    if ! docker compose version &> /dev/null; then
                        curl -L "https://github.com/docker/compose/releases/download/v2.5.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
                        chmod +x /usr/local/bin/docker-compose
                    fi
                    ;;
            esac
            
            # 验证安装
            if command -v docker-compose &> /dev/null || (command -v docker &> /dev/null && docker compose version &> /dev/null); then
                info "docker-compose安装成功"
                COMPOSE_INSTALLED=1
            else
                error "docker-compose安装失败"
                return 1
            fi
        fi
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
    install_docker_compose || exit 1
}

# 创建配置文件
create_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        cat > "$CONFIG_FILE" << EOL
# CloudFront IP选择器配置文件
THRESHOLD=150           # 延迟阈值(ms)
PING_COUNT=5           # Ping次数
MIN_IPS=5              # 最少IP数量
TIMEOUT=300            # 等待超时时间(秒)
TEST_PARALLEL=5        # 并行测试数量
SAVE_HISTORY=true      # 是否保存历史记录
MAX_LOG_SIZE=10485760  # 日志文件最大大小(字节)
EOL
    fi
}

# 加载配置
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    fi
}

# 保存历史结果
save_history() {
    if [ "$SAVE_HISTORY" = "true" ] && [ -f "$DATA_DIR/result.txt" ]; then
        mkdir -p "$HISTORY_DIR"
        local timestamp=$(date +%Y%m%d_%H%M%S)
        cp "$DATA_DIR/result.txt" "$HISTORY_DIR/result_${timestamp}.txt"
        info "结果已保存到历史记录"
    fi
}

# 日志轮转
rotate_logs() {
    local log_file="$DATA_DIR/cloudfront.log"
    if [ -f "$log_file" ]; then
        local size=$(stat -f%z "$log_file" 2>/dev/null || stat -c%s "$log_file" 2>/dev/null)
        if [ -n "$size" ] && [ $size -gt ${MAX_LOG_SIZE:-10485760} ]; then
            mv "$log_file" "${log_file}.1"
            touch "$log_file"
            info "日志已轮转"
        fi
    fi
}

# 检查更新
check_update() {
    info "检查更新..."
    local latest_version=$(curl -s https://api.github.com/repos/rdone4425/CloudFrontIPSelector/releases/latest | grep tag_name | cut -d'"' -f4)
    if [ -n "$latest_version" ] && [ "$latest_version" != "$VERSION" ]; then
        info "发现新版本: $latest_version (当前版本: $VERSION)"
        echo -n "是否更新? [y/N] "
        read -r answer
        if [[ $answer =~ ^[Yy]$ ]]; then
            update_script
        fi
    else
        info "已是最新版本"
    fi
}

# 更新脚本
update_script() {
    info "开始更新..."
    local temp_file="/tmp/cloudfront_update.sh"
    if curl -sSL https://raw.githubusercontent.com/rdone4425/CloudFrontIPSelector/main/1.sh -o "$temp_file"; then
        chmod +x "$temp_file"
        cp "$temp_file" "$WORK_DIR/setup_cloudfront.sh"
        info "更新完成,请重新运行脚本"
        exit 0
    else
        error "更新失败"
    fi
}

# 备份数据
backup_data() {
    local backup_dir="$WORK_DIR/backups"
    mkdir -p "$backup_dir"
    local backup_file="$backup_dir/cloudfront_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
    
    cd "$WORK_DIR" && tar -czf "$backup_file" data config.conf 2>/dev/null
    if [ $? -eq 0 ]; then
        info "备份已保存到: $backup_file"
    else
        error "备份失败"
    fi
}

# 恢复备份
restore_backup() {
    local backup_dir="$WORK_DIR/backups"
    if [ ! -d "$backup_dir" ]; then
        error "没有找到备份目录"
        return 1
    fi
    
    echo -e "\n${GREEN}可用的备份:${NC}"
    local i=1
    local backups=()
    while IFS= read -r file; do
        echo "$i) $(basename "$file")"
        backups[$i]="$file"
        ((i++))
    done < <(ls -1 "$backup_dir"/*.tar.gz 2>/dev/null)
    
    if [ ${#backups[@]} -eq 0 ]; then
        error "没有找到备份文件"
        return 1
    fi
    
    echo -n "请选择要恢复的备份 [1-$((i-1))]: "
    read -r choice
    
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -lt "$i" ]; then
        local backup_file="${backups[$choice]}"
        cd "$WORK_DIR" && tar -xzf "$backup_file"
        if [ $? -eq 0 ]; then
            info "已从 $(basename "$backup_file") 恢复数据"
        else
            error "恢复失败"
        fi
    else
        error "无效的选择"
    fi
}

# 显示历史记录
show_history() {
    if [ ! -d "$HISTORY_DIR" ]; then
        warn "没有历史记录"
        return
    fi
    
    echo -e "\n${GREEN}历史记录:${NC}"
    local i=1
    local history_files=()
    while IFS= read -r file; do
        local timestamp=$(basename "$file" | sed 's/result_\([0-9]\{8\}_[0-9]\{6\}\)\.txt/\1/')
        local formatted_time=$(date -d "${timestamp:0:8} ${timestamp:9:2}:${timestamp:11:2}:${timestamp:13:2}" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$timestamp")
        echo "$i) $formatted_time"
        history_files[$i]="$file"
        ((i++))
    done < <(ls -1 "$HISTORY_DIR"/result_*.txt 2>/dev/null)
    
    if [ ${#history_files[@]} -eq 0 ]; then
        warn "没有历史记录"
        return
    fi
    
    echo -n "请选择要查看的记录 [1-$((i-1))]: "
    read -r choice
    
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -lt "$i" ]; then
        echo -e "\n${GREEN}=== 历史记录 ====${NC}"
        cat "${history_files[$choice]}"
        echo -e "\n按回车键继续..."
        read
    else
        error "无效的选择"
    fi
}

# 配置参数
configure_settings() {
    while true; do
        clear
        echo -e "\n${GREEN}=== 配置参数 ===${NC}"
        echo "1. 延迟阈值 (当前: ${THRESHOLD:-150}ms)"
        echo "2. Ping次数 (当前: ${PING_COUNT:-5})"
        echo "3. 最少IP数量 (当前: ${MIN_IPS:-5})"
        echo "4. 等待超时时间 (当前: ${TIMEOUT:-300}秒)"
        echo "5. 并行测试数量 (当前: ${TEST_PARALLEL:-5})"
        echo "6. 保存历史记录 (当前: ${SAVE_HISTORY:-true})"
        echo "0. 返回主菜单"
        
        echo -n "请选择要修改的选项 [0-6]: "
        read -r choice
        
        case $choice in
            1)
                echo -n "请输入新的延迟阈值(ms): "
                read -r value
                if [[ "$value" =~ ^[0-9]+$ ]]; then
                    sed -i "s/THRESHOLD=.*/THRESHOLD=$value/" "$CONFIG_FILE"
                fi
                ;;
            2)
                echo -n "请输入新的Ping次数: "
                read -r value
                if [[ "$value" =~ ^[0-9]+$ ]]; then
                    sed -i "s/PING_COUNT=.*/PING_COUNT=$value/" "$CONFIG_FILE"
                fi
                ;;
            3)
                echo -n "请输入新的最少IP数量: "
                read -r value
                if [[ "$value" =~ ^[0-9]+$ ]]; then
                    sed -i "s/MIN_IPS=.*/MIN_IPS=$value/" "$CONFIG_FILE"
                fi
                ;;
            4)
                echo -n "请输入新的超时时间(秒): "
                read -r value
                if [[ "$value" =~ ^[0-9]+$ ]]; then
                    sed -i "s/TIMEOUT=.*/TIMEOUT=$value/" "$CONFIG_FILE"
                fi
                ;;
            5)
                echo -n "请输入新的并行测试数量: "
                read -r value
                if [[ "$value" =~ ^[0-9]+$ ]]; then
                    sed -i "s/TEST_PARALLEL=.*/TEST_PARALLEL=$value/" "$CONFIG_FILE"
                fi
                ;;
            6)
                echo -n "是否保存历史记录 (true/false): "
                read -r value
                if [[ "$value" =~ ^(true|false)$ ]]; then
                    sed -i "s/SAVE_HISTORY=.*/SAVE_HISTORY=$value/" "$CONFIG_FILE"
                fi
                ;;
            0)
                return
                ;;
            *)
                warn "无效的选择"
                sleep 1
                ;;
        esac
        
        load_config
    done
}

# 创建必要的目录和文件
create_files() {
    info "创建工作目录..."
    mkdir -p "$WORK_DIR"
    mkdir -p "$DATA_DIR"
    mkdir -p "$HISTORY_DIR"
    
    # 创建配置文件
    create_config
    
    # 加载配置
    load_config
    
    info "创建docker-compose.yml..."
    cat > "$WORK_DIR/docker-compose.yml" << EOL
services:
  cloudfront-selector:
    image: docker.442595.xyz/python:3.9-alpine
    container_name: cloudfront-selector
    network_mode: "host"
    volumes:
      - ./data:/data
      - ./cloudfront_selector.py:/app/cloudfront_selector.py
    environment:
      - THRESHOLD=${THRESHOLD:-150}
      - PING_COUNT=${PING_COUNT:-5}
      - RESULT_DIR=/data
      - TEST_PARALLEL=${TEST_PARALLEL:-5}
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
from concurrent.futures import ThreadPoolExecutor

class CloudFrontSelector:
    def __init__(self):
        self.threshold = int(os.getenv('THRESHOLD', 150))
        self.ping_count = int(os.getenv('PING_COUNT', 5))
        self.test_parallel = int(os.getenv('TEST_PARALLEL', 5))
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
            
            with ThreadPoolExecutor(max_workers=self.test_parallel) as executor:
                futures = []
                for ip in test_ips:
                    if not self.is_cn_ip(ip):
                        self.log(f"测试IP: {ip}")
                        futures.append(executor.submit(self.test_ip, ip))
                
                for ip, future in zip(test_ips, futures):
                    try:
                        latency = future.result()
                        if latency and latency < self.threshold:
                            results.append((ip, latency))
                            self.log(f"发现低延迟IP: {ip} ({latency:.1f}ms)")
                    except Exception as e:
                        self.log(f"测试IP {ip} 时出错: {str(e)}")
        
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
            
            # 优先测试亚洲区域
            for prefix in data['prefixes']:
                if prefix['service'] == 'CLOUDFRONT':
                    ip_range = prefix['ip_prefix']
                    region = prefix.get('region', '')
                    
                    if region in ['ap-northeast-1', 'ap-southeast-1', 'ap-northeast-2', 'ap-southeast-2']:
                        self.log(f"测试亚洲区IP段: {ip_range} (区域: {region})")
                        results = self.test_ip_range(ip_range)
                        all_results.extend(results)
            
            # 如果找到的IP不够，测试其他地区
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

# 检查Docker状态
check_docker_status() {
    if command -v docker &> /dev/null; then
        echo -e "${GREEN}已安装${NC}"
        return 0
    else
        echo -e "${RED}未安装${NC}"
        return 1
    fi
}

# 检查Docker Compose状态
check_compose_status() {
    if command -v docker-compose &> /dev/null || (command -v docker &> /dev/null && docker compose version &> /dev/null); then
        echo -e "${GREEN}已安装${NC}"
        return 0
    else
        echo -e "${RED}未安装${NC}"
        return 1
    fi
}

# 安装Docker和Docker Compose
install_docker_menu() {
    while true; do
        clear
        echo -e "\n${GREEN}=== Docker 安装 ===${NC}"
        echo -e "Docker 状态: $(check_docker_status)"
        echo -e "Docker Compose 状态: $(check_compose_status)"
        echo -e "\n请选择安装方式:"
        echo "1. 使用官方安装脚本 (推荐)"
        echo "2. 使用系统包管理器"
        echo "0. 返回主菜单"
        
        echo -n "请选择 [0-2]: "
        read -r choice
        
        case $choice in
            1)
                info "使用官方脚本安装Docker..."
                curl -fsSL https://get.docker.com | sh
                if [ $? -eq 0 ]; then
                    info "Docker安装成功"
                    # 启动Docker服务
                    systemctl enable docker || true
                    systemctl start docker || service docker start
                    # 安装Docker Compose
                    install_docker_compose
                else
                    error "Docker安装失败"
                fi
                sleep 2
                ;;
            2)
                info "使用包管理器安装Docker..."
                install_docker
                sleep 2
                ;;
            0)
                return
                ;;
            *)
                warn "无效的选择"
                sleep 1
                ;;
        esac
    done
}

# 主菜单
show_menu() {
    while true; do
        clear
        echo -e "\n${GREEN}=== CloudFront IP选择器 v${VERSION} ===${NC}"
        echo -e "\n系统状态:"
        echo -e "Docker: $(check_docker_status)"
        echo -e "Docker Compose: $(check_compose_status)"
        
        if ! check_command docker || ! (command -v docker-compose &> /dev/null || docker compose version &> /dev/null); then
            echo -e "\n${YELLOW}请先安装 Docker 和 Docker Compose${NC}"
            echo "1. 安装 Docker"
            echo "0. 退出"
            
            echo -n "请选择操作 [0-1]: "
            read -r choice
            
            case $choice in
                1)
                    install_docker_menu
                    ;;
                0)
                    echo -e "${GREEN}感谢使用，再见！${NC}"
                    exit 0
                    ;;
                *)
                    warn "请输入0-1之间的数字"
                    sleep 1
                    ;;
            esac
            continue
        fi
        
        echo -e "\n功能菜单:"
        echo "1. 启动服务"
        echo "2. 停止服务"
        echo "3. 查看日志"
        echo "4. 查看结果"
        echo "5. 重启服务"
        echo "6. 查看历史记录"
        echo "7. 配置参数"
        echo "8. 备份/恢复"
        echo "9. 检查更新"
        echo "0. 退出"
        
        echo -e "\n当前状态:"
        if docker ps | grep -q "cloudfront-selector"; then
            echo -e "${GREEN}服务正在运行${NC}"
        else
            echo -e "${YELLOW}服务未运行${NC}"
        fi
        
        rotate_logs
        
        echo -n "请选择操作 [0-9]: "
        read -r choice
        
        case $choice in
            1)
                if [ ! -f "$WORK_DIR/docker-compose.yml" ]; then
                    create_files
                fi
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
                    save_history
                    echo -e "\n按回车键继续..."
                    read
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
            6)
                show_history
                ;;
            7)
                configure_settings
                ;;
            8)
                clear
                echo -e "\n${GREEN}=== 备份/恢复 ===${NC}"
                echo "1. 创建备份"
                echo "2. 恢复备份"
                echo "0. 返回"
                echo -n "请选择操作 [0-2]: "
                read -r subchoice
                case $subchoice in
                    1) backup_data ;;
                    2) restore_backup ;;
                esac
                ;;
            9)
                check_update
                sleep 2
                ;;
            0)
                echo -e "${GREEN}感谢使用，再见！${NC}"
                exit 0
                ;;
            *)
                warn "请输入0-9之间的数字"
                sleep 1
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
        info "通过管道执行安装..."
        
        # 创建工作目录
        WORK_DIR="$HOME/cloudfront-docker"
        mkdir -p "$WORK_DIR"
        
        # 保存脚本
        tee "$WORK_DIR/setup_cloudfront.sh" > /dev/null
        chmod +x "$WORK_DIR/setup_cloudfront.sh"
        
        # 直接进入菜单
        show_menu
        exit 0
    fi
    
    # 直接显示菜单
    show_menu
}

# 直接运行主函数，传递所有参数
main "$@"
