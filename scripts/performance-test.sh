#!/bin/bash

##############################################################################
# 流量重放工具 - 性能测试脚本
# 用于测试目标网口或流量采集分析系统的性能
##############################################################################

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 打印带颜色的消息
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 默认配置
PCAP_FILE="${PCAP_FILE:-docker/local-test/data/http_simple.pcap}"
IFACE="${IFACE:-en0}"
DURATION="${DURATION:-30s}"
STATS_INTERVAL="${STATS_INTERVAL:-5s}"
BINARY="./bin/traffic-replayer"

# 显示帮助信息
show_help() {
    cat << EOF
流量重放工具 - 性能测试脚本

用法: $0 [选项] [测试编号]

选项:
  -f, --file <path>       指定 PCAP 文件路径 (默认: $PCAP_FILE)
  -i, --iface <name>      指定网络接口 (默认: $IFACE)
  -d, --duration <time>   指定测试持续时间 (默认: $DURATION)
  -s, --stats <time>      指定统计报告间隔 (默认: $STATS_INTERVAL)
  -h, --help              显示此帮助信息

测试编号:
  all       运行所有测试 (默认)
  1         基准测试（单并发）
  2         并发测试（5并发）
  3         高并发测试（10并发）
  4         速率限制测试（10000 PPS）
  5         带宽限制测试（100 Mbps）
  6         循环次数测试（重放100次）

示例:
  sudo $0                                   # 运行所有测试
  sudo $0 1                                  # 只运行测试1
  sudo $0 -f capture.pcap -i eth0 3         # 使用自定义参数运行测试3

环境变量:
  PCAP_FILE      PCAP 文件路径
  IFACE          网络接口名称
  DURATION       测试持续时间
  STATS_INTERVAL 统计报告间隔

EOF
    exit 0
}

# 检查权限
check_permission() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要 root 权限运行"
        echo "请使用: sudo $0"
        exit 1
    fi
}

# 检查二进制文件
check_binary() {
    if [[ ! -f "$BINARY" ]]; then
        log_error "找不到二进制文件: $BINARY"
        echo "请先编译: make build"
        exit 1
    fi
}

# 检查 PCAP 文件
check_pcap() {
    if [[ ! -f "$PCAP_FILE" ]]; then
        log_error "找不到 PCAP 文件: $PCAP_FILE"
        exit 1
    fi
}

# 检查网络接口
check_interface() {
    if ! ip link show "$IFACE" &> /dev/null && ! ifconfig "$IFACE" &> /dev/null; then
        log_error "网络接口不存在: $IFACE"
        echo "可用的网络接口:"
        if command -v ip &> /dev/null; then
            ip link show
        else
            ifconfig -a | grep "^[a-z]" | cut -d: -f1
        fi
        exit 1
    fi
}

# 测试1: 基准测试 - 单并发
test_baseline() {
    log_info "========================================="
    log_info "测试1: 基准测试（单并发）"
    log_info "========================================="
    
    $BINARY perf --file "$PCAP_FILE" --iface "$IFACE" \
        --duration "$DURATION" \
        --concurrency 1 \
        --ignore-timestamp \
        --stats-interval "$STATS_INTERVAL"
    
    echo ""
    read -p "按回车键继续下一个测试..."
}

# 测试2: 并发测试 - 5并发
test_concurrency_5() {
    log_info "========================================="
    log_info "测试2: 并发测试（5并发）"
    log_info "========================================="
    
    $BINARY perf --file "$PCAP_FILE" --iface "$IFACE" \
        --duration "$DURATION" \
        --concurrency 5 \
        --ignore-timestamp \
        --stats-interval "$STATS_INTERVAL"
    
    echo ""
    read -p "按回车键继续下一个测试..."
}

# 测试3: 高并发测试 - 10并发
test_concurrency_10() {
    log_info "========================================="
    log_info "测试3: 高并发测试（10并发）"
    log_info "========================================="
    
    $BINARY perf --file "$PCAP_FILE" --iface "$IFACE" \
        --duration "$DURATION" \
        --concurrency 10 \
        --ignore-timestamp \
        --stats-interval "$STATS_INTERVAL"
    
    echo ""
    read -p "按回车键继续下一个测试..."
}

# 测试4: 速率限制测试 - 10000 PPS
test_rate_limit_pps() {
    log_info "========================================="
    log_info "测试4: 速率限制测试（10000 PPS）"
    log_info "========================================="
    
    $BINARY perf --file "$PCAP_FILE" --iface "$IFACE" \
        --duration "$DURATION" \
        --concurrency 5 \
        --pps 10000 \
        --ignore-timestamp \
        --stats-interval "$STATS_INTERVAL"
    
    echo ""
    read -p "按回车键继续下一个测试..."
}

# 测试5: 带宽限制测试 - 100 Mbps
test_rate_limit_bps() {
    log_info "========================================="
    log_info "测试5: 带宽限制测试（100 Mbps）"
    log_info "========================================="
    
    # 100 Mbps = 12.5 MBps = 12500000 bytes/sec
    $BINARY perf --file "$PCAP_FILE" --iface "$IFACE" \
        --duration "$DURATION" \
        --concurrency 5 \
        --bps 12500000 \
        --ignore-timestamp \
        --stats-interval "$STATS_INTERVAL"
    
    echo ""
    read -p "按回车键继续下一个测试..."
}

# 测试6: 循环次数测试
test_loop_count() {
    log_info "========================================="
    log_info "测试6: 循环次数测试（重放100次）"
    log_info "========================================="
    
    $BINARY perf --file "$PCAP_FILE" --iface "$IFACE" \
        --loops 100 \
        --concurrency 3 \
        --ignore-timestamp \
        --stats-interval "$STATS_INTERVAL"
    
    echo ""
}

# 主函数
main() {
    local test_num="all"
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--file)
                PCAP_FILE="$2"
                shift 2
                ;;
            -i|--iface)
                IFACE="$2"
                shift 2
                ;;
            -d|--duration)
                DURATION="$2"
                shift 2
                ;;
            -s|--stats)
                STATS_INTERVAL="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            [1-6]|all)
                test_num="$1"
                shift
                ;;
            *)
                log_error "未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # 执行检查
    log_info "执行环境检查..."
    check_permission
    check_binary
    check_pcap
    check_interface
    
    log_info "环境检查通过!"
    log_info "PCAP 文件: $PCAP_FILE"
    log_info "网络接口: $IFACE"
    log_info "测试持续时间: $DURATION"
    log_info "统计间隔: $STATS_INTERVAL"
    echo ""
    
    # 根据测试编号执行相应测试
    case $test_num in
        1)
            test_baseline
            ;;
        2)
            test_concurrency_5
            ;;
        3)
            test_concurrency_10
            ;;
        4)
            test_rate_limit_pps
            ;;
        5)
            test_rate_limit_bps
            ;;
        6)
            test_loop_count
            ;;
        all)
            test_baseline
            test_concurrency_5
            test_concurrency_10
            test_rate_limit_pps
            test_rate_limit_bps
            test_loop_count
            ;;
    esac
    
    log_info "========================================="
    log_info "所有测试完成！"
    log_info "========================================="
}

# 运行主函数
main "$@"
