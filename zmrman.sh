#!/usr/bin/env bash

# ===========================================
# 追梦人博客 - 服务器综合管理脚本
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
LOG_FILE="/tmp/zmrman_$(date +%Y%m%d_%H%M%S).log"
IPV4_ADDR=""
SCRIPT_VERSION="4.3"

# =========================================== 
# 核心逻辑 (权限/网络/环境)
# ===========================================

# 权限检测与开启 root 登录
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${YELLOW}检测到当前登录用户非 root，正在开启 root 用户登录功能...${NC}"
        echo -e "${CYAN}请输入要设置的 root 用户密码：${NC}"
        sudo passwd root
        
        # 修改 SSH 配置允许 root 登录及密码验证
        sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config
        sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/g' /etc/ssh/sshd_config
        
        # 重启 SSH 服务
        sudo systemctl restart sshd || sudo service ssh restart
        
        echo -e "${GREEN}✓ root 登录权限已开启并设置密码成功！${NC}"
        echo -e "${YELLOW}请使用 root 用户重新 SSH 连接服务器后运行本脚本。${NC}"
        exit 0
    fi
}

detect_network() {
    IPV4_ADDR=$(curl -s4m5 icanhazip.com 2>/dev/null || curl -s4m5 ip.sb 2>/dev/null || echo "未知")
}

check_command() {
    local cmd=$1
    local package=$2
    if ! command -v "$cmd" &>/dev/null; then
        if command -v apt &>/dev/null; then
            apt update -qq && apt install -y -qq "$package" >> "$LOG_FILE" 2>&1
        elif command -v yum &>/dev/null; then
            yum install -y -q "$package" >> "$LOG_FILE" 2>&1
        fi
    fi
}

# =========================================== 
# 功能模块
# ===========================================

# 1. BBR加速 (保留 byJoey 版本)
install_bbr() {
    echo -e "${BLUE}正在执行 BBR 加速安装 (过程详见日志)...${NC}"
    check_command "curl" "curl"
    bash <(curl -l -s https://raw.githubusercontent.com/byJoey/Actions-bbr-v3/refs/heads/main/install.sh)
}

# 2. 系统重装 (逻辑优化与修复)
install_reinstall_system() {
    echo -e "${RED}${BOLD}⚠️  警告：重装系统将清空所有数据！${NC}"
    read -p "确认继续吗？(Y/n): " confirm
    [[ "${confirm^^}" != "Y" ]] && return 

    echo -e "\n${CYAN}请选择系统版本：${NC}"
    echo -e " 1. Debian 13 (Trixie - 测试版)"
    echo -e " 2. Debian 12 (Bookworm - 稳定版)"
    echo -e " 3. Ubuntu 24.04 (Noble - LTS)"
    echo -e " 4. Ubuntu 22.04 (Jammy - LTS)"
    echo -e " 5. 自定义镜像地址 (支持 .gz / .iso / .xz / .raw)"
    echo -e " 0. 返回主菜单"
    
    read -p "请输入序号: " sys_choice
    
    local os_type=""
    local os_ver=""
    local custom_url=""

    case $sys_choice in
        1) os_type="debian"; os_ver="13" ;;
        2) os_type="debian"; os_ver="12" ;;
        3) os_type="ubuntu"; os_ver="24.04" ;;
        4) os_type="ubuntu"; os_ver="22.04" ;;
        5) 
            read -p "请输入自定义镜像下载直连地址: " custom_url
            [[ -z "$custom_url" ]] && return
            ;;
        0|*) return ;;
    esac

    check_command "curl" "curl"
    echo -e "${YELLOW}正在下载重装脚本...${NC}"
    curl -fsSL -O https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh >> "$LOG_FILE" 2>&1
    chmod +x reinstall.sh

    if [[ -n "$custom_url" ]]; then
        echo -e "${YELLOW}正在启动 DD 重装: $custom_url${NC}"
        # 修复点：作者脚本使用 --img 标记 DD 镜像地址
        bash reinstall.sh dd --img "$custom_url"
    else
        echo -e "${YELLOW}正在启动系统重装: $os_type $os_ver${NC}"
        bash reinstall.sh "$os_type" "$os_ver"
    fi
}

# 3. 宝塔面板
install_baota() {
    echo -e "${BLUE}正在安装宝塔面板 (过程详见日志)...${NC}"
    curl -sSO https://bt11.btmb.cc/install/install_panel.sh
    bash install_panel.sh bt11.btmb.cc >> "$LOG_FILE" 2>&1
}

# 4. 修改SSH端口
modify_ssh_port() {
    read -p "请输入新的 SSH 端口号: " new_port 
    if [[ "$new_port" =~ ^[0-9]+$ ]]; then
        sed -i "/Port/d" /etc/ssh/sshd_config
        echo "Port $new_port" >> /etc/ssh/sshd_config
        systemctl restart sshd >> "$LOG_FILE" 2>&1
        echo -e "${GREEN}✓ SSH 端口已修改为 $new_port${NC}"
    fi
}

# 5. Sing-box
install_singbox() {
    echo -e "${BLUE}正在调用 Sing-box 安装脚本...${NC}"
    bash <(wget -qO- https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/sb.sh)
}

# 6. Swap设置
set_swap() {
    read -p "请输入想要设置的 Swap 大小 (单位MB): " size
    if [[ "$size" -gt 0 ]]; then
        swapoff -a >> "$LOG_FILE" 2>&1
        dd if=/dev/zero of=/swapfile bs=1M count=$size >> "$LOG_FILE" 2>&1
        chmod 600 /swapfile
        mkswap /swapfile >> "$LOG_FILE" 2>&1
        swapon /swapfile >> "$LOG_FILE" 2>&1
        sed -i '/\/swapfile/d' /etc/fstab
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
        echo -e "${GREEN}✓ Swap 设置成功，当前大小: ${size}MB${NC}"
    fi
}

# 7. Docker管理
docker_management() {
    if ! command -v docker &>/dev/null; then
        echo -e "${YELLOW}未检测到 Docker，正在自动安装...${NC}"
        curl -fsSL https://get.docker.com | bash >> "$LOG_FILE" 2>&1
    fi
    docker ps -a
}

# ===========================================
# 主菜单
# ===========================================

main_menu() {
    check_root
    detect_network
    
    while true; do
        clear
        echo -e "\n${CYAN}${BOLD}═══════════════════════════════════════════════════════════════════${NC}"
        echo -e "          ${PURPLE}${BOLD}追梦人博客 - 服务器综合管理脚本 v${SCRIPT_VERSION}${NC}         "
        echo -e "          ${YELLOW}后台日志: ${LOG_FILE}${NC}"
        echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════════════════${NC}"
        
        echo -e "\n${GREEN} 1. 安装 BBR 加速 (byJoey)${NC}"
        echo -e "${BLUE} 2. 系统一键重装 (Debian 13/12, Ubuntu 24/22)${NC}"
        echo -e "${BLUE} 3. 安装宝塔面板 (bt11.btmb.cc)${NC}"
        echo -e "${PURPLE} 4. 修改 SSH 端口${NC}"
        echo -e "${PURPLE} 5. 安装 Sing-box 节点 (yonggekkk)${NC}"
        echo -e "${GREEN} 6. Docker 综合管理 (安装/查看容器)${NC}"
        echo -e "${GREEN} 7. 设置 Swap 虚拟内存${NC}"
        echo -e "${YELLOW} 8. 同步上海时区${NC}"
        echo -e "${RED} 9. 重启系统${NC}"
        echo -e " 0. 退出脚本"
        
        echo -e "\n${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
        echo -e " 🌐 当前 IP: ${GREEN}${IPV4_ADDR}${NC}"
        echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
        
        read -p "请选择操作 [0-9]: " choice 

        case $choice in 
            1) install_bbr ;;
            2) install_reinstall_system ;;
            3) install_baota ;;
            4) modify_ssh_port ;;
            5) install_singbox ;;
            6) docker_management ;;
            7) set_swap ;;
            8) timedatectl set-timezone Asia/Shanghai >> "$LOG_FILE" 2>&1 && echo "时区已同步至上海" ;;
            9) read -p "确认立即重启？(Y/n): " r && [[ "${r^^}" == "Y" ]] && reboot ;;
            0) exit 0 ;;
            *) echo -e "${RED}无效输入，请重新选择${NC}" && sleep 1 ;;
        esac 
        echo -e "\n"
        read -n 1 -s -r -p "按任意键返回主菜单..."
    done 
}

# 脚本入口
main_menu
