# 创建目录
mkdir -p ~/cloudfront-docker
cd ~/cloudfront-docker

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
                systemctl enable docker
                systemctl start docker
                ;;
            redhat)
                # 安装依赖
                yum install -y yum-utils
                
                # 添加Docker仓库
                yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
                
                # 安装Docker
                yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
                
                # 启动Docker
                systemctl enable docker
                systemctl start docker
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
            debian|redhat)
                curl -L "https://github.com/docker/compose/releases/download/v2.5.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
                chmod +x /usr/local/bin/docker-compose
                ;;
        esac
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

# 启动服务
start_service() {
    info "启动CloudFront IP选择器服务..."
    cd "$WORK_DIR"
    
    if [ -f "docker-compose.yml" ]; then
        docker-compose down 2>/dev/null
        docker-compose up -d
        
        if [ $? -eq 0 ]; then
            info "服务启动成功"
            info "使用以下命令查看日志:"
            echo "  cd $WORK_DIR && docker-compose logs -f"
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

# 主菜单
show_menu() {
    echo -e "\n${GREEN}=== CloudFront IP选择器 ===${NC}"
    echo "1. 启动服务"
    echo "2. 停止服务"
    echo "3. 查看日志"
    echo "4. 查看结果"
    echo "5. 重启服务"
    echo "0. 退出"
    
    read -p "请选择操作 [0-5]: " choice
    
    case $choice in
        1)
            start_service
            ;;
        2)
            cd "$WORK_DIR" && docker-compose down
            info "服务已停止"
            ;;
        3)
            cd "$WORK_DIR" && docker-compose logs -f
            ;;
        4)
            if [ -f "$DATA_DIR/result.txt" ]; then
                echo -e "\n${GREEN}=== 测试结果 ===${NC}"
                cat "$DATA_DIR/result.txt"
            else
                warn "结果文件不存在"
            fi
            ;;
        5)
            cd "$WORK_DIR" && docker-compose restart
            info "服务已重启"
            ;;
        0)
            exit 0
            ;;
        *)
            warn "无效的选择"
            ;;
    esac
}

# 主函数
main() {
    info "开始安装CloudFront IP选择器..."
    
    # 检查并安装Docker
    install_docker
    
    # 创建必要的文件
    create_files
    
    # 启动服务
    start_service
    
    # 显示菜单
    while true; do
        show_menu
    done
}

# 直接运行主函数
main
