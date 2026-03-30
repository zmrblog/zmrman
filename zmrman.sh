#!/usr/bin/env bash

# ===========================================
# 追梦人博客 - 服务器综合管理脚本 v4.2 (精简版)
# ===========================================

# 颜色定义 
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# 全局变量
LOG_FILE="/tmp/install_manager_$(date +%Y%m%d_%H%M%S).log"
IPV4_ADDR=""
SCRIPT_VERSION="4.2"

# =========================================== 
# 工具函数
# ===========================================

log() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local color=""
    case $level in
        "INFO")  color="${GREEN}" ;;
        "WARN")  color="${YELLOW}" ;;
        "ERROR") color="${RED}" ;;
    esac
    echo -e "${color}[$level]${NC} $message" >&2
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

check_root() {
    [[ $EUID -ne 0 ]] && log "ERROR" "请以 root 权限运行此脚本！" && exit 1 
}

detect_network() {
    IPV4_ADDR=$(curl -s4m5 icanhazip.com 2>/dev/null || curl -s4m5 ip.sb 2>/dev/null || echo "未知")
}

check_command() {
    local cmd=$1
    local package=$2
    if ! command -v "$cmd" &>/dev/null; then
        if command -v apt &>/dev/null; then
            apt update -qq && apt install -y -qq "$package"
        elif command -v yum &>/dev/null; then
            yum install -y -q "$package"
        elif command -v dnf &>/dev/null; then
            dnf install -y -q "$package"
        fi
    fi
}

get_pkg_manager() {
    if command -v apt &>/dev/null; then echo "apt"
    elif command -v dnf &>/dev/null; then echo "dnf"
    elif command -v yum &>/dev/null; then echo "yum"
    else echo "unknown"; fi
}

# =========================================== 
# 功能模块
# ===========================================

# 1. BBR安装
install_bbr() {
    log "INFO" "正在安装 byJoey BBR-v3..."
    bash <(curl -L -s https://raw.githubusercontent.com/byJoey/Actions-bbr-v3/refs/heads/main/install.sh)
}

# 2. BBR v3 终极优化
install_bbr_ultimate() {
    log "INFO" "正在执行 BBR v3 终极优化..."
    bash <(curl -fsSL "https://raw.githubusercontent.com/Eric86777/vps-tcp-tune/main/install-alias.sh")
}

# 3. 系统重装
install_reinstall_system() {
    log "INFO" "正在下载重装脚本..."
    check_command "curl" "curl"
    curl -fsSL -o reinstall.sh https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh && \
    chmod +x reinstall.sh
    echo -e "${YELLOW}请根据提示选择要安装的系统版本：${NC}"
    # 这里保留版本选择交互，但删除了初始的 Y/n 警告
    ./reinstall.sh
}

# 4. Hysteria2 安装
install_hysteria() {
    log "INFO" "正在安装 Hysteria2..."
    bash <(curl -fsSL https://raw.githubusercontent.com/Misaka-blog/hysteria-install/main/hy2/hysteria.sh)
}

# 5. Sing-box 安装
install_singbox() {
    log "INFO" "正在安装 Sing-box (yonggekkk)..."
    bash <(wget -qO- https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/sb.sh)
}

# 6. 宝塔面板
install_baota() {
    log "INFO" "正在安装宝塔面板..."
    curl -sSO https://bt11.btmb.cc/install/install_panel.sh && bash install_panel.sh bt11.btmb.cc
}

# 7. 修改SSH端口
modify_ssh_port() {
    read -p "请输入新端口 (1-65535): " new_port 
    if [[ "$new_port" =~ ^[0-9]+$ ]] && [ "$new_port" -ge 1 ] && [ "$new_port" -le 65535 ]; then
        local bak_file="/etc/ssh/sshd_config.bak.$(date +%s)"
        cp /etc/ssh/sshd_config "$bak_file"
        sed -i '/^[[:space:]]*Port/d' /etc/ssh/sshd_config
        echo "Port $new_port" >> /etc/ssh/sshd_config
        
        # 自动放行防火墙
        if command -v ufw >/dev/null; then ufw allow "$new_port/tcp"; fi
        if command -v firewall-cmd >/dev/null; then firewall-cmd --permanent --add-port="$new_port/tcp" && firewall-cmd --reload; fi

        if systemctl restart sshd 2>/dev/null || systemctl restart ssh; then
            log "INFO" "SSH端口已修改为 $new_port"
            echo -e "${GREEN}✅ SSH端口修改成功！${NC}"
        else
            cp "$bak_file" /etc/ssh/sshd_config
            systemctl restart sshd
            log "ERROR" "修改失败，已还原配置"
        fi
    fi
}

# 8. Docker管理
docker_management() {
    if ! command -v docker &>/dev/null; then
        log "INFO" "正在安装 Docker..."
        curl -fsSL https://get.docker.com | bash
        systemctl enable --now docker
    fi
    # 原脚本中复杂的 docker_management 循环逻辑在此简化调用
    log "INFO" "Docker 环境已就绪"
}

# 9. 设置 Swap (新增)
setup_swap() {
    log "INFO" "正在配置 Swap 虚拟内存..."
    read -p "请输入想要设置的 Swap 大小 (单位MB，如1024): " swap_size
    if ! [[ "$swap_size" =~ ^[0-9]+$ ]]; then
        log "ERROR" "输入无效"
        return
    fi
    
    # 检查并删除旧 swap
    if grep -q "swapfile" /etc/fstab; then
        swapoff /swapfile 2>/dev/null
        sed -i '/swapfile/d' /etc/fstab
        rm -f /swapfile
    fi

    # 创建新 swap
    fallocate -l "${swap_size}M" /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=$swap_size
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    
    log "INFO" "Swap 设置完成: ${swap_size}MB"
    echo -e "${GREEN}✅ Swap 设置完成！${NC}"
}

# 10. 时区同步
timezone_management() {
    log "INFO" "设置时区为上海..."
    timedatectl set-timezone Asia/Shanghai
    echo -e "${GREEN}✓ 时区已设置为 Asia/Shanghai${NC}"
}

# ===========================================
# 主界面
# ===========================================

main_menu() {
    check_root
    detect_network
    
    while true; do
        clear
        echo -e "\n${CYAN}${BOLD}═══════════════════════════════════════════════════════════════════${NC}"
        echo -e "          ${PURPLE}${BOLD}追梦人博客 - 服务器综合管理脚本 v${SCRIPT_VERSION}${NC}         "
        echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════════════════${NC}"
        echo -e "\n${GREEN} 1. 安装BBR加速 (byJoey)      2. BBR v3 终极优化${NC}"
        echo -e "${BLUE} 3. 系统重装 (直接进入)       4. 安装Hysteria代理${NC}"
        echo -e "${BLUE} 5. 安装Sing-box (yg)         6. 安装宝塔面板${NC}"
        echo -e "${PURPLE} 7. 修改SSH端口               8. 安装/检查Docker${NC}"
        echo -e "${YELLOW} 9. 设置Swap (虚拟内存)       10. 同步上海时间${NC}"
        echo -e "${YELLOW} 11. 查看脚本日志             12. 重启系统${NC}"
        echo -e "${RED} 0. 退出脚本${NC}"
        echo -e "\n${CYAN} IP: ${IPV4_ADDR} | 内存: $(free -m | awk 'NR==2{printf "%s/%sMB", $3,$2}') ${NC}"
        echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════════════════${NC}"
        
        read -p "请选择操作 [0-12]: " choice 

        case $choice in 
            1) install_bbr ;;
            2) install_bbr_ultimate ;;
            3) install_reinstall_system ;;
            4) install_hysteria ;;
            5) install_singbox ;;
            6) install_baota ;;
            7) modify_ssh_port ;;
            8) docker_management ;;
            9) setup_swap ;;
            10) timezone_management ;;
            11) [[ -f "$LOG_FILE" ]] && tail -n 50 "$LOG_FILE" || echo "暂无日志" ;;
            12) reboot ;;
            0) exit 0 ;;
            *) echo -e "${RED}无效输入${NC}"; sleep 1 ;;
        esac 
        echo -e "\n"
        read -n 1 -s -r -p "按任意键返回主菜单..."
    done 
}

main_menu
