#!/bin/bash
# 远程测试一键自动化脚本
# 用于自动配置环境并执行联调测试

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

log_step() {
    echo -e "${BLUE}[STEP]${NC} $*"
}

# 脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# 默认配置
INTERFACE_SEND="veth0"
INTERFACE_RECV="veth1"
TEST_DATA_DIR="$PROJECT_ROOT/docker/local-test/data"
OUTPUT_DIR="$PROJECT_ROOT/test/output"
LOG_DIR="$PROJECT_ROOT/test/logs"
REPLAYER_BIN="$PROJECT_ROOT/bin/traffic-replayer"
REPLAYER_SPEED="1.0"
REPLAYER_CIDR=""

# 显示帮助信息
show_help() {
    cat <<EOF
远程联调测试脚本

用法: $0 [选项] [PCAP文件]

注意:
  此脚本仅用于测试环境的自动化测试。
  生产环境请使用: scripts/setup-env.sh --mode prod --interface <接口名>

选项:
  -s, --send-interface IFACE   发送接口 (默认: veth0)
  -r, --recv-interface IFACE   接收接口 (默认: veth1)
  --skip-env-setup             跳过环境配置步骤
  --replayer-bin PATH          traffic-replayer 可执行文件路径
  --speed SPEED                流量回放速度倍率 (默认: 1.0)
  --cidr CIDR                  重写 IP 地址 CIDR 网段 (例如: 192.168.1.0/24)
  -h, --help                   显示此帮助信息

参数:
  PCAP文件                      要测试的 PCAP 文件路径（可选）
                               如不指定，则测试默认目录下的所有 PCAP 文件

示例:
  # 测试所有文件
  sudo $0

  # 测试单个文件
  sudo $0 docker/local-test/data/sample.pcap

  # 自定义接口
  sudo $0 --send-interface veth2 --recv-interface veth3 test.pcap

EOF
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

    for cmd in tcpdump ip; do
        if ! command -v $cmd >/dev/null 2>&1; then
            missing_deps+=("$cmd")
        fi
    done

    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_error "缺少必要的命令: ${missing_deps[*]}"
        log_info "请先安装: sudo apt-get install iproute2 tcpdump"
        exit 1
    fi
}

# 配置环境
setup_environment() {
    if [ "$SKIP_ENV_SETUP" = "true" ]; then
        log_info "跳过环境配置步骤"
        return
    fi

    log_step "[1/5] 配置测试环境"

    local env_script="$SCRIPT_DIR/setup-env.sh"
    if [ ! -f "$env_script" ]; then
        log_error "找不到环境配置脚本: $env_script"
        exit 1
    fi

    # 构建环境配置命令（始终使用 test 模式）
    local env_cmd="bash $env_script --mode test"
    if [ -n "$INTERFACE_SEND" ]; then
        env_cmd="$env_cmd --interface $INTERFACE_SEND"
    fi

    # 执行环境配置
    if ! $env_cmd; then
        log_error "环境配置失败"
        exit 1
    fi
}

# 检查 traffic-replayer
check_replayer() {
    log_step "[2/5] 检查 traffic-replayer"

    if [ ! -f "$REPLAYER_BIN" ]; then
        log_warn "找不到 traffic-replayer: $REPLAYER_BIN"
        log_info "正在构建 traffic-replayer..."

        cd "$PROJECT_ROOT"
        if ! make build >/dev/null 2>&1; then
            log_error "构建 traffic-replayer 失败"
            exit 1
        fi
    fi

    if [ ! -x "$REPLAYER_BIN" ]; then
        log_error "traffic-replayer 不可执行: $REPLAYER_BIN"
        exit 1
    fi

    log_info "✓ traffic-replayer 准备就绪: $REPLAYER_BIN"
}

# 准备测试目录
prepare_directories() {
    log_step "[3/5] 准备测试目录"

    mkdir -p "$OUTPUT_DIR" "$LOG_DIR"

    # 清理旧的输出文件
    rm -f "$OUTPUT_DIR"/*.pcap 2>/dev/null || true
    rm -f "$LOG_DIR"/test-*.log 2>/dev/null || true

    log_info "✓ 测试目录准备完成"
}

# 执行单个文件测试
run_single_test() {
    local INPUT_PCAP="$1"
    local TEST_NAME="$(basename "$INPUT_PCAP" .pcap)"
    local TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
    local OUTPUT_PCAP="$OUTPUT_DIR/captured_${TEST_NAME}_${TIMESTAMP}.pcap"
    local LOG_FILE="$LOG_DIR/test-${TEST_NAME}_${TIMESTAMP}.log"

    log_info "\n=== 测试: $TEST_NAME ==="
    log_info "输入文件: $INPUT_PCAP"
    log_info "输出文件: $OUTPUT_PCAP"
    log_info "日志文件: $LOG_FILE"

    # 启动 tcpdump 捕获
    log_info "启动数据包捕获 (接口: $INTERFACE_RECV)..."
    tcpdump -i "$INTERFACE_RECV" -w "$OUTPUT_PCAP" -U --immediate-mode >"$LOG_FILE" 2>&1 &
    local TCPDUMP_PID=$!
    sleep 2

    # 检查 tcpdump 是否正常运行
    if ! kill -0 $TCPDUMP_PID 2>/dev/null; then
        log_error "tcpdump 启动失败"
        cat "$LOG_FILE"
        return 1
    fi

    # 执行流量回放
    log_info "开始流量回放 (接口: $INTERFACE_SEND)..."

    # 构建 replayer 命令参数
    local REPLAYER_CMD=("$REPLAYER_BIN" replay --file "$INPUT_PCAP" --iface "$INTERFACE_SEND" --verbose)

    # 添加可选参数
    if [ -n "$REPLAYER_SPEED" ] && [ "$REPLAYER_SPEED" != "1.0" ]; then
        REPLAYER_CMD+=(--speed "$REPLAYER_SPEED")
    fi

    if [ -n "$REPLAYER_CIDR" ]; then
        REPLAYER_CMD+=(--cidr "$REPLAYER_CIDR")
    fi

    # 执行回放并等待完成
    if ! "${REPLAYER_CMD[@]}" >>"$LOG_FILE" 2>&1; then
        log_error "流量回放失败"
        kill $TCPDUMP_PID 2>/dev/null || true
        return 1
    fi

    # 等待一小段时间确保所有数据包都被捕获
    sleep 1

    # 停止 tcpdump
    log_info "停止数据包捕获..."
    kill $TCPDUMP_PID 2>/dev/null || true
    wait $TCPDUMP_PID 2>/dev/null || true

    # 验证结果
    log_info "验证测试结果..."
    local INPUT_COUNT=$(tcpdump -r "$INPUT_PCAP" 2>/dev/null | wc -l | tr -d ' ')
    local OUTPUT_COUNT=$(tcpdump -r "$OUTPUT_PCAP" 2>/dev/null | wc -l | tr -d ' ')

    log_info "发送数据包: $INPUT_COUNT"
    log_info "捕获数据包: $OUTPUT_COUNT"

    # 检查是否捕获到所有数据包
    if [ "$OUTPUT_COUNT" -ge "$INPUT_COUNT" ]; then
        log_info "${GREEN}✓ 测试通过${NC}: 成功捕获所有数据包 ($INPUT_COUNT/$OUTPUT_COUNT)"
        return 0
    else
        local LOSS=$((100 - (OUTPUT_COUNT * 100 / INPUT_COUNT)))
        log_error "✗ 测试失败: ${LOSS}% 丢包率"
        return 1
    fi
}

# 运行所有测试
run_all_tests() {
    log_step "[4/5] 运行流量回放测试"

    local PASSED=0
    local FAILED=0
    local TEST_FILES=()

    # 确定要测试的文件
    if [ -n "$SINGLE_FILE" ]; then
        if [ ! -f "$SINGLE_FILE" ]; then
            log_error "文件不存在: $SINGLE_FILE"
            exit 1
        fi
        TEST_FILES=("$SINGLE_FILE")
    else
        if [ ! -d "$TEST_DATA_DIR" ]; then
            log_error "测试数据目录不存在: $TEST_DATA_DIR"
            exit 1
        fi
        # 使用 find 递归搜索所有 .pcap 和 .pcapng 文件（包括子目录）
        mapfile -d '' TEST_FILES < <(find "$TEST_DATA_DIR" -type f \( -name "*.pcap" -o -name "*.pcapng" \) -print0 | sort -z)
        if [ ${#TEST_FILES[@]} -eq 0 ]; then
            log_error "测试数据目录中未找到 .pcap 或 .pcapng 文件: $TEST_DATA_DIR"
            exit 1
        fi
    fi

    log_info "找到 ${#TEST_FILES[@]} 个测试文件"

    # 执行测试
    for pcap in "${TEST_FILES[@]}"; do
        if run_single_test "$pcap"; then
            PASSED=$((PASSED + 1))
        else
            FAILED=$((FAILED + 1))
        fi
    done

    # 显示测试总结
    echo ""
    log_info "========================================"
    log_info "测试总结"
    log_info "========================================"
    log_info "总计: ${#TEST_FILES[@]}"
    log_info "${GREEN}通过: $PASSED${NC}"
    if [ $FAILED -gt 0 ]; then
        log_info "${RED}失败: $FAILED${NC}"
    else
        log_info "失败: $FAILED"
    fi
    log_info "========================================"

    return $FAILED
}


# 显示测试总结
show_test_summary() {
    echo ""
    log_info "======================================"
    log_info "联调测试完成"
    log_info "======================================"
    log_info "发送接口: $INTERFACE_SEND"
    log_info "接收接口: $INTERFACE_RECV"
    log_info ""
    log_info "测试结果:"
    log_info "  日志目录: $LOG_DIR"
    log_info "  输出目录: $OUTPUT_DIR"
    log_info "======================================"
}

# 清理函数
cleanup() {
    log_info "\n清理测试环境..."

    # 停止可能还在运行的 tcpdump 进程
    pkill -f "tcpdump.*$INTERFACE_RECV" 2>/dev/null || true

    if [ "$SKIP_ENV_SETUP" != "true" ]; then
        log_info "清理 veth 网卡对..."
        bash "$SCRIPT_DIR/setup-env.sh" --cleanup 2>/dev/null || true
    fi
}

# 主函数
main() {
    # 解析命令行参数
    SKIP_ENV_SETUP="false"
    SINGLE_FILE=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            -s|--send-interface)
                INTERFACE_SEND="$2"
                shift 2
                ;;
            -r|--recv-interface)
                INTERFACE_RECV="$2"
                shift 2
                ;;
            --skip-env-setup)
                SKIP_ENV_SETUP="true"
                shift
                ;;
            --replayer-bin)
                REPLAYER_BIN="$2"
                shift 2
                ;;
            --speed)
                REPLAYER_SPEED="$2"
                shift 2
                ;;
            --cidr)
                REPLAYER_CIDR="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -*)
                log_error "未知参数: $1"
                show_help
                exit 1
                ;;
            *)
                SINGLE_FILE="$1"
                shift
                ;;
        esac
    done

    # 注册清理函数
    trap cleanup EXIT

    # 显示测试配置
    echo "======================================"
    echo "Traffic Replayer 远程联调测试"
    echo "======================================"
    log_info "运行模式: test (仅测试环境)"
    log_info "发送接口: $INTERFACE_SEND"
    log_info "接收接口: $INTERFACE_RECV"
    echo ""

    # 执行测试流程
    check_root
    check_dependencies
    setup_environment
    check_replayer
    prepare_directories

    # 运行测试
    if run_all_tests; then
        show_test_summary
        exit 0
    else
        show_test_summary
        exit 1
    fi
}

# 运行主函数
main "$@"
