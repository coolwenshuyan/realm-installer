#!/bin/bash

# =========================================================
# Realm 一键安装与管理脚本
# 功能：安装 Realm、添加转发规则、管理服务
# 适配：Debian / Ubuntu
# 快捷指令：安装后输入 realm 即可打开菜单
# =========================================================

# 定义颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

# 检查是否为 root 用户
[[ $EUID -ne 0 ]] && echo -e "${RED}错误: 必须使用 root 用户运行此脚本！${PLAIN}" && exit 1

# 脚本的 Raw 链接 (用于安装自身及更新)
# 请将下方地址替换为你自己的 GitHub 用户名和仓库名
SCRIPT_URL="https://raw.githubusercontent.com/coolwenshuyan/realm-installer/main/install.sh"

# === 关键路径定义 ===
# 配置文件路径
CONFIG_FILE="/etc/realm/config.toml"
# Systemd 服务文件路径
SERVICE_FILE="/etc/systemd/system/realm.service"
# Realm 二进制核心程序路径 (改名为 realm-bin，避免与快捷命令冲突)
BIN_PATH="/usr/local/bin/realm-bin"
# 快捷管理命令路径 (用户输入 realm 即运行此脚本)
MENU_PATH="/usr/local/bin/realm"

# 安装快捷管理命令：优先复制当前脚本，失败时回退到 GitHub 下载，并校验结果非空
install_menu_script() {
    local src="${BASH_SOURCE[0]}"

    if [[ -n "$src" && -f "$src" && -s "$src" ]]; then
        cp "$src" "$MENU_PATH"
    else
        curl -fLso "$MENU_PATH" "$SCRIPT_URL"
    fi

    chmod +x "$MENU_PATH"

    if [[ ! -s "$MENU_PATH" ]]; then
        echo -e "${RED}快捷命令安装失败：$MENU_PATH 为空文件。${PLAIN}"
        return 1
    fi

    return 0
}

# 1. 安装 Realm
install_realm() {
    echo -e "${GREEN}正在开始安装 Realm...${PLAIN}"
    
    # 更新系统并安装必要工具
    apt-get update -y
    apt-get install -y wget tar ufw curl

    # 检测架构
    ARCH=$(uname -m)
    if [[ $ARCH == "x86_64" ]]; then
        DOWNLOAD_URL="https://github.com/zhboner/realm/releases/latest/download/realm-x86_64-unknown-linux-gnu.tar.gz"
    elif [[ $ARCH == "aarch64" ]]; then
        DOWNLOAD_URL="https://github.com/zhboner/realm/releases/latest/download/realm-aarch64-unknown-linux-gnu.tar.gz"
    else
        echo -e "${RED}不支持的架构: $ARCH${PLAIN}"
        exit 1
    fi

    # 下载并安装 Realm 核心程序
    wget -O realm.tar.gz "$DOWNLOAD_URL"
    tar -xvf realm.tar.gz
    chmod +x realm
    # 移动并重命名为 realm-bin
    mv realm "$BIN_PATH"
    rm realm.tar.gz

    # 安装快捷命令
    echo -e "${GREEN}正在配置快捷管理命令...${PLAIN}"
    if ! install_menu_script; then
        echo -e "${RED}请检查网络或脚本来源后重试。${PLAIN}"
        exit 1
    fi

    # 创建配置目录
    mkdir -p /etc/realm

    # 初始化基础配置文件
    if [[ ! -f "$CONFIG_FILE" ]]; then
        cat > "$CONFIG_FILE" <<EOF
[network]
no_tcp = false
use_udp = true
EOF
    fi

    # 创建 Systemd 服务 (指向 realm-bin)
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=realm
After=network-online.target
Wants=network-online.target systemd-networkd-wait-online.service

[Service]
Type=simple
User=root
Restart=on-failure
RestartSec=5s
DynamicUser=true
ExecStart=$BIN_PATH -c $CONFIG_FILE

[Install]
WantedBy=multi-user.target
EOF

    # 启动服务
    systemctl daemon-reload
    systemctl enable --now realm

    echo -e "${GREEN}Realm 安装成功！${PLAIN}"
    echo -e "${YELLOW}==============================================${PLAIN}"
    echo -e "${GREEN}以后只需输入命令 ${RED}realm${GREEN} 即可再次打开此菜单！${PLAIN}"
    echo -e "${YELLOW}==============================================${PLAIN}"
    echo -e "${YELLOW}请选择 [2] 继续添加转发规则。${PLAIN}"
}

# 辅助函数：解析配置文件，将所有规则读入全局数组 RULES_LISTEN / RULES_REMOTE
get_rules() {
    RULES_LISTEN=()
    RULES_REMOTE=()
    local listen_val=""
    local remote_val=""
    local in_ep=0

    while IFS= read -r line; do
        if [[ "$line" =~ ^\[\[endpoints\]\] ]]; then
            if [[ $in_ep -eq 1 && -n "$listen_val" ]]; then
                RULES_LISTEN+=("$listen_val")
                RULES_REMOTE+=("$remote_val")
            fi
            in_ep=1
            listen_val=""
            remote_val=""
        elif [[ $in_ep -eq 1 ]]; then
            if [[ "$line" =~ ^listen[[:space:]]*=[[:space:]]*\"(.+)\" ]]; then
                listen_val="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ ^remote[[:space:]]*=[[:space:]]*\"(.+)\" ]]; then
                remote_val="${BASH_REMATCH[1]}"
            fi
        fi
    done < "$CONFIG_FILE"

    # 处理最后一个 endpoint
    if [[ $in_ep -eq 1 && -n "$listen_val" ]]; then
        RULES_LISTEN+=("$listen_val")
        RULES_REMOTE+=("$remote_val")
    fi
}

# 2. 添加转发规则
add_rule() {
    if [[ ! -f "$BIN_PATH" ]]; then
        echo -e "${RED}请先安装 Realm！${PLAIN}"
        return
    fi

    echo -e "${GREEN}=== 添加新的转发规则 ===${PLAIN}"
    
    read -p "请输入中转机(本机)监听端口 (例如 6666): " listen_port
    read -p "请输入落地机 IP 地址: " remote_ip
    read -p "请输入落地机端口: " remote_port

    # 写入配置
    cat >> "$CONFIG_FILE" <<EOF

[[endpoints]]
listen = "0.0.0.0:$listen_port"
remote = "$remote_ip:$remote_port"
EOF

    # 开放防火墙
    ufw allow "$listen_port"/tcp
    ufw allow "$listen_port"/udp
    echo -e "${GREEN}防火墙已放行端口: $listen_port${PLAIN}"

    # 重启服务
    systemctl restart realm
    echo -e "${GREEN}规则添加成功！服务已重启。${PLAIN}"
}

# 3. 删除转发规则
delete_rule() {
    if [[ ! -f "$BIN_PATH" ]]; then
        echo -e "${RED}请先安装 Realm！${PLAIN}"
        return
    fi

    get_rules
    local total=${#RULES_LISTEN[@]}

    if [[ $total -eq 0 ]]; then
        echo -e "${YELLOW}当前没有任何转发规则。${PLAIN}"
        return
    fi

    echo -e "${GREEN}=== 删除转发规则 ===${PLAIN}"
    for i in "${!RULES_LISTEN[@]}"; do
        echo -e "  ${GREEN}[$((i+1))]${PLAIN} 监听: ${RULES_LISTEN[$i]}  →  远端: ${RULES_REMOTE[$i]}"
    done
    echo "-----------------------------------"

    read -p "请输入要删除的规则编号 [1-$total]: " choice

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [[ $choice -lt 1 ]] || [[ $choice -gt $total ]]; then
        echo -e "${RED}无效的编号！${PLAIN}"
        return
    fi

    local listen_addr="${RULES_LISTEN[$((choice-1))]}"
    local port="${listen_addr##*:}"

    # 用 awk 删除第 choice 个 [[endpoints]] 块（跳过该块直到下一个块或 EOF）
    awk -v n="$choice" '
        BEGIN { ep=0; skip=0 }
        /^\[\[endpoints\]\]/ { ep++; skip=(ep==n); }
        !skip { print }
    ' "$CONFIG_FILE" | sed '/^$/N;/^\n$/d' > /tmp/realm_tmp.toml
    mv /tmp/realm_tmp.toml "$CONFIG_FILE"

    ufw delete allow "$port"/tcp 2>/dev/null
    ufw delete allow "$port"/udp 2>/dev/null
    echo -e "${GREEN}防火墙端口 $port 已关闭。${PLAIN}"

    systemctl restart realm
    echo -e "${GREEN}规则 [$choice] 删除成功！服务已重启。${PLAIN}"
}

# 4. 修改转发规则
modify_rule() {
    if [[ ! -f "$BIN_PATH" ]]; then
        echo -e "${RED}请先安装 Realm！${PLAIN}"
        return
    fi

    get_rules
    local total=${#RULES_LISTEN[@]}

    if [[ $total -eq 0 ]]; then
        echo -e "${YELLOW}当前没有任何转发规则。${PLAIN}"
        return
    fi

    echo -e "${GREEN}=== 修改转发规则 ===${PLAIN}"
    for i in "${!RULES_LISTEN[@]}"; do
        echo -e "  ${GREEN}[$((i+1))]${PLAIN} 监听: ${RULES_LISTEN[$i]}  →  远端: ${RULES_REMOTE[$i]}"
    done
    echo "-----------------------------------"

    read -p "请输入要修改的规则编号 [1-$total]: " choice

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [[ $choice -lt 1 ]] || [[ $choice -gt $total ]]; then
        echo -e "${RED}无效的编号！${PLAIN}"
        return
    fi

    local old_listen="${RULES_LISTEN[$((choice-1))]}"
    local old_remote="${RULES_REMOTE[$((choice-1))]}"
    local old_port="${old_listen##*:}"

    echo -e "${YELLOW}当前规则: 监听 $old_listen  →  远端 $old_remote${PLAIN}"
    read -p "请输入新的监听端口 (直接回车保持 $old_port): " new_port
    [[ -z "$new_port" ]] && new_port="$old_port"
    read -p "请输入新的落地机 IP 地址: " new_ip
    read -p "请输入新的落地机端口: " new_remote_port

    # 先删除旧规则
    awk -v n="$choice" '
        BEGIN { ep=0; skip=0 }
        /^\[\[endpoints\]\]/ { ep++; skip=(ep==n); }
        !skip { print }
    ' "$CONFIG_FILE" | sed '/^$/N;/^\n$/d' > /tmp/realm_tmp.toml
    mv /tmp/realm_tmp.toml "$CONFIG_FILE"

    # 关闭旧端口防火墙
    ufw delete allow "$old_port"/tcp 2>/dev/null
    ufw delete allow "$old_port"/udp 2>/dev/null

    # 追加新规则
    cat >> "$CONFIG_FILE" <<EOF

[[endpoints]]
listen = "0.0.0.0:$new_port"
remote = "$new_ip:$new_remote_port"
EOF

    ufw allow "$new_port"/tcp
    ufw allow "$new_port"/udp
    echo -e "${GREEN}防火墙端口已更新: $old_port → $new_port${PLAIN}"

    systemctl restart realm
    echo -e "${GREEN}规则 [$choice] 修改成功！服务已重启。${PLAIN}"
}

# 5. 查看状态
check_status() {
    if [[ ! -f "$SERVICE_FILE" ]]; then
         echo -e "${RED}Realm 未安装！${PLAIN}"
         return
    fi
    systemctl status realm
    echo -e "${YELLOW}当前配置文件内容 ($CONFIG_FILE):${PLAIN}"
    cat "$CONFIG_FILE"
}

# 6. 更新脚本
update_script() {
    echo -e "${GREEN}正在从 GitHub 更新脚本...${PLAIN}"
    curl -o "$MENU_PATH" -Ls "$SCRIPT_URL"
    chmod +x "$MENU_PATH"
    echo -e "${GREEN}脚本更新完成！请重新运行 realm 命令。${PLAIN}"
    echo -e "${YELLOW}注意：若使用的是本地修改版，更新后将恢复为 GitHub 原版。${PLAIN}"
    exit 0
}

# 7. 卸载
uninstall_realm() {
    systemctl stop realm
    systemctl disable realm
    rm -f "$SERVICE_FILE"
    rm -f "$BIN_PATH"     # 删除核心程序
    rm -f "$MENU_PATH"    # 删除快捷命令
    rm -rf /etc/realm
    systemctl daemon-reload
    echo -e "${GREEN}Realm 已彻底卸载。${PLAIN}"
}

# 主菜单
show_menu() {
    clear
    echo -e "${GREEN}Realm 一键管理脚本 (适用于 BWG/Linux)${PLAIN}"
    echo -e "${YELLOW}快捷命令: realm${PLAIN}"
    echo "-----------------------------------"
    echo "1. 安装 Realm"
    echo "2. 添加转发规则"
    echo "3. 删除转发规则"
    echo "4. 修改转发规则"
    echo "5. 查看运行状态 & 配置文件"
    echo "6. 更新本脚本"
    echo "7. 卸载 Realm"
    echo "0. 退出"
    echo "-----------------------------------"
    read -p "请输入数字 [0-7]: " num

    case "$num" in
        1) install_realm ;;
        2) add_rule ;;
        3) delete_rule ;;
        4) modify_rule ;;
        5) check_status ;;
        6) update_script ;;
        7) uninstall_realm ;;
        0) exit 0 ;;
        *) echo -e "${RED}请输入正确的数字！${PLAIN}" ;;
    esac
}

# 运行菜单
show_menu
