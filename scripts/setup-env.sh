#!/bin/bash
# 远程服务器环境配置脚本
# 用于配置 Linux 服务器（Ubuntu/CentOS）的网络和环境，以支持 deeptrace 和 traffic-replayer 联调

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

log_debug() {
    if [ "$DEBUG" = "true" ]; then
        echo -e "${BLUE}[DEBUG]${NC} $*"
    fi
}

# 全局变量：用于回滚和备份
ORIGINAL_PROMISC_STATE=""
ORIGINAL_LINK_STATE=""
CHANGED_SYSCTL_PARAMS=()
BACKUP_SYSCTL_FILE="/tmp/sysctl_backup_$$.conf"

# 备份配置目录
BACKUP_DIR="/var/lib/traffic-replayer/backups"
BACKUP_TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="${BACKUP_DIR}/config_backup_${BACKUP_TIMESTAMP}.json"
LATEST_BACKUP_LINK="${BACKUP_DIR}/latest_backup.json"

# 显示帮助信息
show_help() {
    cat <<EOF
远程服务器环境配置脚本

用法: $0 [选项]

选项:
  -m, --mode MODE          运行模式: test (测试环境) 或 prod (生产环境)
                           默认: test
  -i, --interface IFACE    网络接口名称
                           测试模式默认: veth0
                           生产模式默认: 需要指定实际的镜像端口
                           支持多个网口（逗号分隔）: eth1,eth2,eth3
  --restore [BACKUP_FILE]  恢复到指定备份配置（不指定则使用最新备份）
  --list-backups           列出所有可用的备份文件
  --skip-system-tuning     跳过系统内核参数优化（仅生产模式）
  --dry-run                仅显示将要执行的操作，不实际执行
  --debug                  启用调试模式，显示详细日志
  -h, --help               显示此帮助信息

模式说明:
  test    - 测试模式：创建 veth 网卡对用于本地测试
  prod    - 生产模式：配置物理网卡的镜像端口和混杂模式，优化系统参数

示例:
  # 测试模式（默认）
  sudo $0 --mode test

  # 生产模式（配置单个镜像端口）
  sudo $0 --mode prod --interface eth1

  # 生产模式（配置多个镜像端口）
  sudo $0 --mode prod --interface eth1,eth2,eth3

  # 列出所有备份
  sudo $0 --list-backups

  # 恢复到最新备份
  sudo $0 --restore

  # 恢复到指定备份
  sudo $0 --restore /var/lib/traffic-replayer/backups/config_backup_20260128_143022.json

  # 生产模式（跳过系统优化）
  sudo $0 --mode prod --interface eth1,eth2 --skip-system-tuning

  # 查看将要执行的操作（不实际执行）
  sudo $0 --mode prod --interface eth1,eth2 --dry-run

EOF
}

# 检测操作系统类型
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    else
        log_error "无法检测操作系统类型"
        exit 1
    fi
    log_info "检测到操作系统: $OS $OS_VERSION"
}

# 检查是否为 root 用户
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "此脚本需要 root 权限，请使用 sudo 运行"
        exit 1
    fi
}

# 检查必要的命令是否存在
check_dependencies() {
    local missing_deps=()

    for cmd in ip tcpdump; do
        if ! command -v $cmd >/dev/null 2>&1; then
            missing_deps+=("$cmd")
        fi
    done

    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_error "缺少必要的命令: ${missing_deps[*]}"
        log_info "请先运行此脚本进行安装依赖"
        exit 1
    fi
}

# 备份当前系统配置
backup_system_config() {
    log_debug "备份当前 sysctl 配置到 $BACKUP_SYSCTL_FILE"
    sysctl -a > "$BACKUP_SYSCTL_FILE" 2>/dev/null || true
}

# 回滚函数：在错误时恢复原始状态
rollback_changes() {
    log_warn "检测到错误，正在回滚配置更改..."

    # 恢复网卡混杂模式
    if [ -n "$INTERFACE" ] && [ -n "$ORIGINAL_PROMISC_STATE" ]; then
        if [ "$ORIGINAL_PROMISC_STATE" = "off" ]; then
            log_debug "恢复 $INTERFACE 混杂模式为 off"
            ip link set "$INTERFACE" promisc off 2>/dev/null || true
        fi
    fi

    # 恢复网卡状态
    if [ -n "$INTERFACE" ] && [ -n "$ORIGINAL_LINK_STATE" ]; then
        if [ "$ORIGINAL_LINK_STATE" = "DOWN" ]; then
            log_debug "恢复 $INTERFACE 状态为 DOWN"
            ip link set "$INTERFACE" down 2>/dev/null || true
        fi
    fi

    # 恢复 sysctl 参数
    if [ -f "$BACKUP_SYSCTL_FILE" ] && [ ${#CHANGED_SYSCTL_PARAMS[@]} -gt 0 ]; then
        log_debug "恢复 sysctl 参数"
        for param in "${CHANGED_SYSCTL_PARAMS[@]}"; do
            local original_value=$(grep "^$param" "$BACKUP_SYSCTL_FILE" 2>/dev/null | cut -d'=' -f2- | xargs)
            if [ -n "$original_value" ]; then
                sysctl -w "$param=$original_value" >/dev/null 2>&1 || true
            fi
        done
    fi

    # 清理备份文件
    rm -f "$BACKUP_SYSCTL_FILE" 2>/dev/null || true

    log_info "回滚完成"
}

# 错误处理：捕获错误并回滚
error_handler() {
    local exit_code=$?
    log_error "脚本执行失败 (退出码: $exit_code)"
    rollback_changes
    exit $exit_code
}

# 优化系统内核参数（生产环境）
tune_system_parameters() {
    if [ "$SKIP_SYSTEM_TUNING" = "true" ]; then
        log_info "跳过系统内核参数优化"
        return
    fi

    log_info "优化系统内核参数..."

    # 备份原始配置
    backup_system_config

    # 定义需要优化的参数（针对网络抓包性能）
    declare -A SYSCTL_PARAMS=(
        # 增加网络缓冲区大小
        ["net.core.rmem_max"]="134217728"              # 128MB
        ["net.core.rmem_default"]="67108864"          # 64MB
        ["net.core.wmem_max"]="134217728"             # 128MB
        ["net.core.wmem_default"]="67108864"          # 64MB
        ["net.core.netdev_max_backlog"]="300000"      # 增大接收队列

        # 优化 TCP 缓冲区
        ["net.ipv4.tcp_rmem"]="4096 87380 134217728"  # min default max
        ["net.ipv4.tcp_wmem"]="4096 65536 134217728"
        ["net.ipv4.tcp_mem"]="786432 1048576 26777216"

        # 增加文件描述符限制
        ["fs.file-max"]="2097152"

        # 减少 TIME_WAIT 连接数（如果需要处理大量连接）
        ["net.ipv4.tcp_fin_timeout"]="15"
        ["net.ipv4.tcp_tw_reuse"]="1"
    )

    local changed_count=0
    local failed_count=0

    for param in "${!SYSCTL_PARAMS[@]}"; do
        local value="${SYSCTL_PARAMS[$param]}"
        local current_value=$(sysctl -n "$param" 2>/dev/null || echo "")

        if [ -z "$current_value" ]; then
            log_warn "无法读取参数 $param，跳过"
            continue
        fi

        # 只在值不同时才修改
        if [ "$current_value" != "$value" ]; then
            log_debug "设置 $param: $current_value -> $value"
            if [ "$DRY_RUN" = "true" ]; then
                log_info "[DRY-RUN] 将设置 $param = $value"
            else
                if sysctl -w "$param=$value" >/dev/null 2>&1; then
                    CHANGED_SYSCTL_PARAMS+=("$param")
                    ((changed_count++))
                else
                    log_warn "设置 $param 失败"
                    ((failed_count++))
                fi
            fi
        fi
    done

    # 持久化配置（写入配置文件）
    if [ "$DRY_RUN" != "true" ] && [ $changed_count -gt 0 ]; then
        local config_file="/etc/sysctl.d/99-traffic-replayer.conf"
        log_info "持久化配置到 $config_file"

        {
            echo "# Traffic Replayer 网络优化配置"
            echo "# 生成时间: $(date)"
            echo ""
            for param in "${!SYSCTL_PARAMS[@]}"; do
                echo "$param = ${SYSCTL_PARAMS[$param]}"
            done
        } > "$config_file"

        chmod 644 "$config_file"
    fi

    if [ $changed_count -gt 0 ]; then
        log_info "✓ 已优化 $changed_count 个系统参数"
    fi
    if [ $failed_count -gt 0 ]; then
        log_warn "有 $failed_count 个参数设置失败"
    fi

    # 设置进程文件描述符限制
    log_debug "配置文件描述符限制"
    if [ -f /etc/security/limits.conf ]; then
        if ! grep -q "traffic-replayer" /etc/security/limits.conf; then
            if [ "$DRY_RUN" != "true" ]; then
                {
                    echo ""
                    echo "# Traffic Replayer 文件描述符限制"
                    echo "* soft nofile 65536"
                    echo "* hard nofile 65536"
                } >> /etc/security/limits.conf
                log_info "✓ 已配置文件描述符限制"
            else
                log_info "[DRY-RUN] 将配置文件描述符限制"
            fi
        fi
    fi
}

# 创建备份目录
ensure_backup_dir() {
    if [ ! -d "$BACKUP_DIR" ]; then
        mkdir -p "$BACKUP_DIR"
        chmod 700 "$BACKUP_DIR"
        log_debug "创建备份目录: $BACKUP_DIR"
    fi
}

# 备份网卡配置
backup_interface_config() {
    local iface=$1
    local backup_data=""

    # 获取混杂模式状态
    local promisc_state="off"
    if ip link show "$iface" 2>/dev/null | grep -q PROMISC; then
        promisc_state="on"
    fi

    # 获取链路状态
    local link_state="DOWN"
    if ip link show "$iface" 2>/dev/null | grep -q 'state UP'; then
        link_state="UP"
    fi

    # 获取网卡卸载功能状态
    local offload_features=""
    if command -v ethtool >/dev/null 2>&1; then
        offload_features=$(ethtool -k "$iface" 2>/dev/null | grep -E '^(rx-checksumming|tx-checksumming|scatter-gather|tcp-segmentation-offload|generic-segmentation-offload|generic-receive-offload|large-receive-offload|rx-vlan-offload|tx-vlan-offload):' || echo "")
    fi

    # 获取环形缓冲区大小
    local ring_buffer=""
    if command -v ethtool >/dev/null 2>&1; then
        ring_buffer=$(ethtool -g "$iface" 2>/dev/null | grep -A4 "^Current hardware settings" || echo "")
    fi

    # 构建 JSON 数据
    cat <<IFACE_JSON
    "$iface": {
      "promisc_mode": "$promisc_state",
      "link_state": "$link_state",
      "offload_features": $(echo "$offload_features" | jq -Rs .),
      "ring_buffer": $(echo "$ring_buffer" | jq -Rs .)
    }
IFACE_JSON
}

# 创建完整的配置备份
create_backup() {
    local interfaces="$1"

    log_info "创建配置备份..."
    ensure_backup_dir

    # 检查 jq 是否可用
    if ! command -v jq >/dev/null 2>&1; then
        log_warn "未安装 jq，备份功能受限"
        # 简单的文本格式备份
        create_simple_backup "$interfaces"
        return
    fi

    # 开始构建 JSON
    {
        echo "{"
        echo '  "backup_timestamp": "'"$BACKUP_TIMESTAMP"'",'
        echo '  "hostname": "'"$(hostname)"'",'
        echo '  "interfaces": {'

        # 备份每个接口
        IFS=',' read -ra IFACES <<< "$interfaces"
        local first=true
        for iface in "${IFACES[@]}"; do
            iface=$(echo "$iface" | xargs)
            if [ -n "$iface" ] && ip link show "$iface" >/dev/null 2>&1; then
                if [ "$first" = true ]; then
                    first=false
                else
                    echo ","
                fi
                backup_interface_config "$iface"
            fi
        done

        echo ""
        echo "  },"

        # 备份 sysctl 参数
        echo '  "sysctl_params": {'
        sysctl -a 2>/dev/null | grep -E '^(net\.|fs\.file-max)' | while IFS='=' read -r key value; do
            key=$(echo "$key" | xargs)
            value=$(echo "$value" | xargs)
            echo "    \"$key\": \"$value\","
        done | sed '$ s/,$//'  # 移除最后一个逗号
        echo "  },"

        # 备份 limits.conf 相关配置
        echo '  "limits_config": '
        if [ -f /etc/security/limits.conf ]; then
            grep -v '^#' /etc/security/limits.conf | grep -v '^$' | jq -Rs .
        else
            echo '""'
        fi

        echo "}"
    } > "$BACKUP_FILE"

    # 创建最新备份的符号链接
    ln -sf "$BACKUP_FILE" "$LATEST_BACKUP_LINK"

    log_info "✓ 配置已备份到: $BACKUP_FILE"
}

# 简单的文本格式备份（当 jq 不可用时）
create_simple_backup() {
    local interfaces="$1"
    local simple_backup="${BACKUP_DIR}/config_backup_${BACKUP_TIMESTAMP}.txt"

    {
        echo "=== Traffic Replayer 配置备份 ==="
        echo "时间: $(date)"
        echo "主机: $(hostname)"
        echo ""
        echo "=== 网卡配置 ==="

        IFS=',' read -ra IFACES <<< "$interfaces"
        for iface in "${IFACES[@]}"; do
            iface=$(echo "$iface" | xargs)
            if [ -n "$iface" ] && ip link show "$iface" >/dev/null 2>&1; then
                echo ""
                echo "接口: $iface"
                ip link show "$iface"
                echo ""
                if command -v ethtool >/dev/null 2>&1; then
                    ethtool -k "$iface" | head -20
                    echo ""
                    ethtool -g "$iface" 2>/dev/null || true
                fi
            fi
        done

        echo ""
        echo "=== 系统参数 ==="
        sysctl -a 2>/dev/null | grep -E '^(net\.|fs\.file-max)'

        echo ""
        echo "=== Limits 配置 ==="
        if [ -f /etc/security/limits.conf ]; then
            grep -v '^#' /etc/security/limits.conf | grep -v '^$'
        fi
    } > "$simple_backup"

    ln -sf "$simple_backup" "${BACKUP_DIR}/latest_backup.txt"
    log_info "✓ 配置已备份到: $simple_backup"
}

# 列出所有备份
list_backups() {
    log_info "===== 可用的配置备份 ====="

    if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
        log_warn "未找到任何备份文件"
        return 1
    fi

    echo ""
    ls -lh "$BACKUP_DIR"/config_backup_*.{json,txt} 2>/dev/null | awk '{
        printf "  [%s %s %s] %s (%s)\n", $6, $7, $8, $9, $5
    }'

    if [ -L "$LATEST_BACKUP_LINK" ]; then
        echo ""
        log_info "最新备份: $(readlink "$LATEST_BACKUP_LINK")"
    fi

    echo ""
    log_info "使用方式: $0 --restore <备份文件路径>"
    log_info "或者: $0 --restore  (恢复最新备份)"
}

# 恢复配置
restore_from_backup() {
    local backup_file="$1"

    # 如果未指定备份文件，使用最新备份
    if [ -z "$backup_file" ]; then
        if [ -L "$LATEST_BACKUP_LINK" ]; then
            backup_file=$(readlink -f "$LATEST_BACKUP_LINK")
            log_info "使用最新备份: $backup_file"
        else
            log_error "未找到最新备份，请指定备份文件"
            exit 1
        fi
    fi

    # 检查备份文件是否存在
    if [ ! -f "$backup_file" ]; then
        log_error "备份文件不存在: $backup_file"
        exit 1
    fi

    log_info "===== 开始恢复配置 ====="
    log_info "备份文件: $backup_file"

    # 判断备份文件类型
    if [[ "$backup_file" == *.json ]]; then
        restore_from_json "$backup_file"
    else
        log_error "不支持的备份文件格式，请使用 JSON 格式的备份文件"
        log_info "提示: 如果系统未安装 jq，请先安装: apt-get install jq 或 yum install jq"
        exit 1
    fi
}

# 从 JSON 备份恢复
restore_from_json() {
    local backup_file="$1"

    if ! command -v jq >/dev/null 2>&1; then
        log_error "需要 jq 工具来恢复 JSON 格式的备份"
        log_info "请安装: apt-get install jq 或 yum install jq"
        exit 1
    fi

    # 读取备份信息
    local backup_time=$(jq -r '.backup_timestamp' "$backup_file")
    local backup_host=$(jq -r '.hostname' "$backup_file")

    log_info "备份时间: $backup_time"
    log_info "备份主机: $backup_host"

    # 警告检查
    if [ "$(hostname)" != "$backup_host" ]; then
        log_warn "警告: 当前主机 $(hostname) 与备份主机 $backup_host 不匹配"
        read -p "是否继续恢复？(y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "用户取消操作"
            exit 0
        fi
    fi

    echo ""
    log_info "开始恢复网卡配置..."

    # 恢复每个接口的配置
    local interfaces=$(jq -r '.interfaces | keys[]' "$backup_file")
    local restored_count=0
    local failed_count=0

    for iface in $interfaces; do
        log_info "\n----- 恢复接口: $iface -----"

        if ! ip link show "$iface" >/dev/null 2>&1; then
            log_warn "接口 $iface 不存在，跳过"
            ((failed_count++))
            continue
        fi

        # 恢复混杂模式
        local promisc_mode=$(jq -r ".interfaces.\"$iface\".promisc_mode" "$backup_file")
        if [ "$promisc_mode" = "on" ]; then
            ip link set "$iface" promisc on
            log_info "✓ 已启用混杂模式"
        else
            ip link set "$iface" promisc off
            log_info "✓ 已禁用混杂模式"
        fi

        # 恢复链路状态
        local link_state=$(jq -r ".interfaces.\"$iface\".link_state" "$backup_file")
        if [ "$link_state" = "UP" ]; then
            ip link set "$iface" up
            log_info "✓ 已启动接口"
        else
            ip link set "$iface" down
            log_info "✓ 已关闭接口"
        fi

        ((restored_count++))
    done

    echo ""
    log_info "===== 恢复总结 ====="
    log_info "✓ 成功恢复 $restored_count 个接口"
    if [ $failed_count -gt 0 ]; then
        log_warn "✗ 跳过 $failed_count 个接口"
    fi

    log_info "\n注意: 网卡卸载功能和环形缓冲区需要手动检查和调整"
    log_info "系统内核参数不会自动恢复，如需恢复请手动编辑 /etc/sysctl.d/99-traffic-replayer.conf"
}

# 安装必要的软件包
install_dependencies() {
    log_info "安装必要的软件包..."

    case "$OS" in
        ubuntu|debian)
            apt-get update -qq
            apt-get install -y iproute2 tcpdump net-tools ethtool jq >/dev/null 2>&1
            ;;
        centos|rhel|rocky|almalinux)
            yum install -y iproute tcpdump net-tools ethtool jq >/dev/null 2>&1
            ;;
        *)
            log_warn "未知的操作系统: $OS，跳过软件包安装"
            ;;
    esac

    log_info "软件包安装完成"
}

# 测试模式：创建 veth 网卡对
setup_test_mode() {
    local VETH0="${INTERFACE:-veth0}"
    local VETH1="veth1"

    log_info "===== 测试模式配置 ====="
    log_info "创建 veth 网卡对: $VETH0 <-> $VETH1"

    # 删除已存在的 veth 网卡对
    if ip link show "$VETH0" >/dev/null 2>&1; then
        log_info "删除已存在的 $VETH0"
        ip link delete "$VETH0" 2>/dev/null || true
    fi

    # 创建 veth 网卡对
    ip link add "$VETH0" type veth peer name "$VETH1"
    log_info "✓ 创建 veth 网卡对成功"

    # 启动网络接口
    ip link set "$VETH0" up
    ip link set "$VETH1" up
    log_info "✓ 网络接口已启动"

    # 在接收端启用混杂模式
    ip link set "$VETH1" promisc on
    log_info "✓ $VETH1 已启用混杂模式"

    # 显示网卡信息
    log_info "\n网卡配置信息:"
    ip link show "$VETH0" | sed 's/^/  /'
    ip link show "$VETH1" | sed 's/^/  /'

    log_info "\n测试环境配置完成！"
    log_info "发送端口: $VETH0 (用于 traffic-replayer)"
    log_info "接收端口: $VETH1 (用于 deeptrace 监听)"
}

# 生产模式：配置物理网卡
setup_prod_mode() {
    if [ -z "$INTERFACE" ]; then
        log_error "生产模式必须指定网络接口（使用 -i 或 --interface 参数）"
        exit 1
    fi

    log_info "===== 生产模式配置 ====="

    # 在配置前创建备份
    if [ "$DRY_RUN" != "true" ]; then
        create_backup "$INTERFACE"
    else
        log_info "[DRY-RUN] 将创建配置备份"
    fi

    # 解析接口列表（支持逗号分隔的多个接口）
    IFS=',' read -ra INTERFACES <<< "$INTERFACE"
    local interface_count=${#INTERFACES[@]}

    log_info "配置 $interface_count 个网络接口: ${INTERFACES[*]}"

    # 用于记录成功和失败的接口
    local configured_interfaces=()
    local failed_interfaces=()

    # 循环配置每个接口
    for iface in "${INTERFACES[@]}"; do
        # 去除首尾空格
        iface=$(echo "$iface" | xargs)

        log_info "
----- 配置接口: $iface -----"

        # 检查接口是否存在
        if ! ip link show "$iface" >/dev/null 2>&1; then
            log_error "网络接口 $iface 不存在"
            failed_interfaces+=("$iface")
            continue
        fi

        # 保存原始状态（用于回滚）
        local original_promisc_state
        local original_link_state

        if ip link show "$iface" | grep -q PROMISC; then
            original_promisc_state="on"
        else
            original_promisc_state="off"
        fi

        if ip link show "$iface" | grep -q 'state UP'; then
            original_link_state="UP"
        else
            original_link_state="DOWN"
        fi

        log_debug "$iface 原始状态 - 混杂模式: $original_promisc_state, 链路状态: $original_link_state"

        # 检查接口是否被占用（是否有 IP 地址配置）
        if ip addr show "$iface" | grep -q 'inet '; then
            log_warn "警告: 接口 $iface 已配置 IP 地址，这可能不是镜像端口"
            log_warn "镜像端口通常不应该配置 IP 地址"
            if [ "$DRY_RUN" != "true" ]; then
                read -p "是否继续配置 $iface？(y/N): " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    log_info "跳过配置 $iface"
                    failed_interfaces+=("$iface")
                    continue
                fi
            fi
        fi

        # 启动网络接口
        if [ "$original_link_state" != "UP" ]; then
            log_info "启动网络接口 $iface..."
            if [ "$DRY_RUN" = "true" ]; then
                log_info "[DRY-RUN] 将启动接口 $iface"
            else
                if ! ip link set "$iface" up 2>/dev/null; then
                    log_error "启动接口 $iface 失败"
                    failed_interfaces+=("$iface")
                    continue
                fi
                sleep 1
            fi
        fi
        log_info "✓ 网络接口 $iface 已启动"

        # 启用混杂模式
        log_info "启用混杂模式..."
        if [ "$DRY_RUN" = "true" ]; then
            log_info "[DRY-RUN] 将启用 $iface 混杂模式"
        else
            if ! ip link set "$iface" promisc on 2>/dev/null; then
                log_error "启用混杂模式失败"
                failed_interfaces+=("$iface")
                continue
            fi
        fi

        # 验证混杂模式
        if [ "$DRY_RUN" != "true" ]; then
            if ip link show "$iface" | grep -q PROMISC; then
                log_info "✓ 混杂模式已启用"
            else
                log_error "混杂模式未正确启用"
                failed_interfaces+=("$iface")
                continue
            fi
        fi

        # 禁用接口的卸载功能（提高抓包性能）
        log_info "优化网卡配置..."
        if [ "$DRY_RUN" = "true" ]; then
            log_info "[DRY-RUN] 将禁用网卡卸载功能"
        else
            # 尝试禁用各种卸载功能，某些功能可能不支持，所以允许失败
            local offload_features=("rx" "tx" "sg" "tso" "gso" "gro" "lro" "rxvlan" "txvlan")
            local disabled_count=0
            local failed_count=0

            for feature in "${offload_features[@]}"; do
                if ethtool -K "$iface" "$feature" off >/dev/null 2>&1; then
                    ((disabled_count++))
                else
                    ((failed_count++))
                    log_debug "禁用 $feature 失败（可能不支持）"
                fi
            done

            if [ $disabled_count -gt 0 ]; then
                log_info "✓ 已禁用 $disabled_count 个网卡卸载功能"
            fi
            if [ $failed_count -gt 0 ]; then
                log_debug "有 $failed_count 个功能禁用失败（通常是因为不支持）"
            fi
        fi

        # 增加网卡环形缓冲区大小（如果支持）
        if command -v ethtool >/dev/null 2>&1; then
            log_info "优化网卡环形缓冲区..."
            if [ "$DRY_RUN" = "true" ]; then
                log_info "[DRY-RUN] 将增大环形缓冲区大小"
            else
                # 获取当前和最大缓冲区大小
                local max_rx=$(ethtool -g "$iface" 2>/dev/null | grep -A4 "^Ring parameters" | grep "^RX:" | awk '{print $2}' | head -1)
                if [ -n "$max_rx" ] && [ "$max_rx" -gt 0 ]; then
                    if ethtool -G "$iface" rx "$max_rx" 2>/dev/null; then
                        log_info "✓ 已设置 RX 环形缓冲区为最大值: $max_rx"
                    else
                        log_debug "设置环形缓冲区失败（可能已是最大值）"
                    fi
                fi
            fi
        fi

        # 显示网卡信息
        log_info "
网卡配置信息:"
        ip link show "$iface" | sed 's/^/  /'
        echo ""
        ip addr show "$iface" | sed 's/^/  /'

        # 显示网卡统计信息
        if command -v ethtool >/dev/null 2>&1; then
            log_info "
网卡统计信息:"
            ethtool -S "$iface" 2>/dev/null | grep -E '(rx_|tx_|drop|error)' | head -10 | sed 's/^/  /' || true
        fi

        # 记录成功配置的接口
        configured_interfaces+=("$iface")
        log_info "✓ 接口 $iface 配置完成"
    done

    # 显示配置总结
    log_info "
===== 配置总结 ====="
    if [ ${#configured_interfaces[@]} -gt 0 ]; then
        log_info "✓ 成功配置 ${#configured_interfaces[@]} 个接口: ${configured_interfaces[*]}"
    fi

    if [ ${#failed_interfaces[@]} -gt 0 ]; then
        log_warn "✗ 配置失败 ${#failed_interfaces[@]} 个接口: ${failed_interfaces[*]}"
    fi

    # 如果所有接口都失败，返回错误
    if [ ${#configured_interfaces[@]} -eq 0 ]; then
        log_error "所有接口配置失败"
        return 1
    fi

    log_info "
生产环境配置完成！"
    log_info "已配置的镜像端口: ${configured_interfaces[*]}"
    log_info "
注意事项:"
    log_info "  1. 请确保交换机已配置端口镜像到这些接口"
    log_info "  2. deeptrace 可配置监听任意一个或多个接口"
    log_info "  3. 生产环境不支持使用 traffic-replayer 直接发包到这些接口"
    log_info "  4. 系统内核参数已优化，重启后自动生效"

    # 更新全局变量供后续使用
    INTERFACE="${configured_interfaces[*]}"
}

# 显示配置总结
show_summary() {
    log_info "\n======================================"
    log_info "环境配置完成"
    log_info "======================================"
    log_info "运行模式: $MODE"
    log_info "操作系统: $OS $OS_VERSION"

    if [ "$MODE" = "test" ]; then
        log_info "发送接口: ${INTERFACE:-veth0}"
        log_info "接收接口: veth1"
    else
        log_info "镜像接口: $INTERFACE"
    fi

    log_info "\n下一步:"
    if [ "$MODE" = "test" ]; then
        log_info "  1. 配置 deeptrace 监听 veth1 接口"
        log_info "  2. 使用 traffic-replayer 向 ${INTERFACE:-veth0} 发送数据包"
        log_info "  3. 运行联调测试: ./scripts/remote-test.sh"
    else
        log_info "  1. 确认交换机已配置端口镜像"
        log_info "  2. 配置 deeptrace 监听接口: $INTERFACE"
        log_info "  3. 验证 deeptrace 是否正常接收镜像流量"
        # 对于多个接口，提供每个接口的健康检查提示
        IFS=' ' read -ra IFACES <<< "$INTERFACE"
        if [ ${#IFACES[@]} -eq 1 ]; then
            log_info "  4. 运行健康检查: $0 --health-check --interface $INTERFACE"
        else
            log_info "  4. 运行健康检查（逐个检查）:"
            for iface in "${IFACES[@]}"; do
                log_info "     $0 --health-check --interface $iface"
            done
        fi
    fi
    log_info "======================================"

    # 清理备份文件
    rm -f "$BACKUP_SYSCTL_FILE" 2>/dev/null || true
}

# 健康检查功能
health_check() {
    log_info "===== 系统健康检查 ====="

    local issues_found=0

    # 检查网卡状态
    if [ -n "$INTERFACE" ]; then
        log_info "\n[1] 检查网络接口: $INTERFACE"
        if ! ip link show "$INTERFACE" >/dev/null 2>&1; then
            log_error "  ✗ 接口不存在"
            ((issues_found++))
        else
            # 检查链路状态
            if ip link show "$INTERFACE" | grep -q 'state UP'; then
                log_info "  ✓ 链路状态: UP"
            else
                log_warn "  ✗ 链路状态: DOWN"
                ((issues_found++))
            fi

            # 检查混杂模式
            if ip link show "$INTERFACE" | grep -q PROMISC; then
                log_info "  ✓ 混杂模式: 已启用"
            else
                log_error "  ✗ 混杂模式: 未启用"
                ((issues_found++))
            fi

            # 检查是否有流量
            log_info "  检查接口流量（采样 5 秒）..."
            local rx_before=$(cat /sys/class/net/"$INTERFACE"/statistics/rx_packets 2>/dev/null || echo "0")
            sleep 5
            local rx_after=$(cat /sys/class/net/"$INTERFACE"/statistics/rx_packets 2>/dev/null || echo "0")
            local rx_delta=$((rx_after - rx_before))

            if [ $rx_delta -gt 0 ]; then
                log_info "  ✓ 接收流量: $rx_delta 数据包/5 秒"
            else
                log_warn "  ! 未检测到流量（可能正常，取决于网络情况）"
            fi

            # 检查丢包统计
            local rx_dropped=$(cat /sys/class/net/"$INTERFACE"/statistics/rx_dropped 2>/dev/null || echo "0")
            local rx_errors=$(cat /sys/class/net/"$INTERFACE"/statistics/rx_errors 2>/dev/null || echo "0")
            if [ $rx_dropped -gt 1000 ] || [ $rx_errors -gt 100 ]; then
                log_warn "  ! 发现丢包: dropped=$rx_dropped, errors=$rx_errors"
                ((issues_found++))
            else
                log_info "  ✓ 丢包统计: dropped=$rx_dropped, errors=$rx_errors"
            fi
        fi
    fi

    # 检查系统资源
    log_info "\n[2] 检查系统资源"

    # 检查 CPU 负载
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    local cpu_count=$(nproc)
    log_info "  CPU 负载: $load_avg (核心数: $cpu_count)"

    # 检查内存
    local mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local mem_avail=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    local mem_usage_pct=$((100 - (mem_avail * 100 / mem_total)))
    log_info "  内存使用率: ${mem_usage_pct}%"
    if [ $mem_usage_pct -gt 90 ]; then
        log_warn "  ! 内存使用率过高"
        ((issues_found++))
    else
        log_info "  ✓ 内存充足"
    fi

    # 检查磁盘空间
    local disk_usage=$(df -h / | tail -1 | awk '{print $5}' | sed 's/%//')
    log_info "  根分区使用率: ${disk_usage}%"
    if [ $disk_usage -gt 90 ]; then
        log_warn "  ! 磁��空间不足"
        ((issues_found++))
    else
        log_info "  ✓ 磁盘空间充足"
    fi

    # 检查关键内核参数
    log_info "\n[3] 检查内核参数"
    local params_to_check=(
        "net.core.rmem_max:67108864"
        "net.core.netdev_max_backlog:10000"
        "fs.file-max:100000"
    )

    for param_check in "${params_to_check[@]}"; do
        local param="${param_check%%:*}"
        local min_value="${param_check##*:}"
        local current_value=$(sysctl -n "$param" 2>/dev/null || echo "0")

        if [ "$current_value" -ge "$min_value" ]; then
            log_info "  ✓ $param = $current_value (>= $min_value)"
        else
            log_warn "  ! $param = $current_value (建议 >= $min_value)"
            ((issues_found++))
        fi
    done

    # 检查必要的工具
    log_info "\n[4] 检查必要工具"
    local required_tools=("tcpdump" "ip" "ethtool" "sysctl")
    for tool in "${required_tools[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            log_info "  ✓ $tool 已安装"
        else
            log_error "  ✗ $tool 未安装"
            ((issues_found++))
        fi
    done

    # 总结
    log_info "\n======================================"
    if [ $issues_found -eq 0 ]; then
        log_info "${GREEN}✓ 健康检查通过，未发现问题${NC}"
        return 0
    else
        log_warn "${YELLOW}发现 $issues_found 个问题，请检查上述警告信息${NC}"
        return 1
    fi
}

# 清理函数（测试模式）
cleanup_test_mode() {
    local VETH0="${INTERFACE:-veth0}"

    log_info "清理测试环境..."

    if ip link show "$VETH0" >/dev/null 2>&1; then
        ip link delete "$VETH0" 2>/dev/null || true
        log_info "✓ 已删除 veth 网卡对"
    fi
}

# 主函数
main() {
    # 默认参数
    MODE="test"
    INTERFACE=""
    SKIP_SYSTEM_TUNING="false"
    DRY_RUN="false"
    DEBUG="false"
    HEALTH_CHECK_ONLY="false"
    RESTORE_MODE="false"
    RESTORE_FILE=""
    LIST_BACKUPS="false"

    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -m|--mode)
                MODE="$2"
                shift 2
                ;;
            -i|--interface)
                INTERFACE="$2"
                shift 2
                ;;
            --restore)
                RESTORE_MODE="true"
                if [ -n "$2" ] && [ "${2:0:1}" != "-" ]; then
                    RESTORE_FILE="$2"
                    shift 2
                else
                    shift
                fi
                ;;
            --list-backups)
                LIST_BACKUPS="true"
                shift
                ;;
            --skip-system-tuning)
                SKIP_SYSTEM_TUNING="true"
                shift
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            --debug)
                DEBUG="true"
                shift
                ;;
            --health-check)
                HEALTH_CHECK_ONLY="true"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            --cleanup)
                check_root
                cleanup_test_mode
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # 如果是列出备份
    if [ "$LIST_BACKUPS" = "true" ]; then
        list_backups
        exit $?
    fi

    # 如果是恢复模式
    if [ "$RESTORE_MODE" = "true" ]; then
        check_root
        restore_from_backup "$RESTORE_FILE"
        exit $?
    fi

    # 如果只执行健康检查
    if [ "$HEALTH_CHECK_ONLY" = "true" ]; then
        check_root
        check_dependencies
        health_check
        exit $?
    fi

    # 验证模式
    if [[ "$MODE" != "test" && "$MODE" != "prod" ]]; then
        log_error "无效的模式: $MODE (必须是 test 或 prod)"
        exit 1
    fi

    # 检查权限
    check_root

    # 检测操作系统
    detect_os

    # 检查依赖
    check_dependencies

    # 设置错误处理
    if [ "$DRY_RUN" != "true" ]; then
        trap error_handler ERR
    fi

    # 安装依赖（如果需要）
    install_dependencies

    # 生产模式下执行系统优化
    if [ "$MODE" = "prod" ]; then
        tune_system_parameters
    fi

    # 根据模式配置环境
    if [ "$MODE" = "test" ]; then
        setup_test_mode
    else
        setup_prod_mode
    fi

    # 显示总结
    show_summary

    # 生产模式下建议运行健康检查
    if [ "$MODE" = "prod" ] && [ "$DRY_RUN" != "true" ]; then
        echo ""
        log_info "建议运行健康检查以验证配置:"
        log_info "  sudo $0 --health-check --interface $INTERFACE"
    fi
}

# 运行主函数
main "$@"
