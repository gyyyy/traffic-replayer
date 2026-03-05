#!/bin/bash
# 本地测试容器入口脚本
# 设置 veth 网卡对并运行流量回放测试

set -e

VETH0="veth0"
VETH1="veth1"
LOG_FILE="/test/logs/test.log"
REPLAYER_SPEED="${REPLAYER_SPEED:-1.0}"
REPLAYER_CIDR="${REPLAYER_CIDR:-}"
WITH_DEEPTRACE="${WITH_DEEPTRACE:-false}"
DEEPTRACE_LOG="/test/logs/deeptrace.log"
DEEPTRACE_PID=""
WEB_PID=""

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

cleanup() {
    log "清理 veth 网卡对..."
    ip link delete "$VETH0" 2>/dev/null || true
    if [ -n "$WEB_PID" ]; then
        kill "$WEB_PID" 2>/dev/null || true
        wait "$WEB_PID" 2>/dev/null || true
        WEB_PID=""
    fi
    if [ -n "$DEEPTRACE_PID" ]; then
        log "停止 deeptrace (pid=$DEEPTRACE_PID)..."
        kill "$DEEPTRACE_PID" 2>/dev/null || true
        wait "$DEEPTRACE_PID" 2>/dev/null || true
        DEEPTRACE_PID=""
    fi
}

# 同时捕获 SIGTERM / SIGINT，确保 docker stop / Ctrl-C 也能触发清理
trap cleanup EXIT TERM INT

setup_veth() {
    log "设置 veth 网卡对: $VETH0 <-> $VETH1"

    # 创建 veth 网卡对
    ip link add "$VETH0" type veth peer name "$VETH1"

    # 启动网络接口
    ip link set "$VETH0" up
    ip link set "$VETH1" up

    # 在 veth1 上启用混杂模式（接收端）
    ip link set "$VETH1" promisc on

    # 验证设置
    ip link show "$VETH0"
    ip link show "$VETH1"

    log "veth 网卡对创建成功"

    # 按需启动 deeptrace（后台运行，监听 veth1）
    if [ "$WITH_DEEPTRACE" = "true" ]; then
        if ! command -v deeptrace >/dev/null 2>&1; then
            log "警告: 未找到 deeptrace 可执行文件，跳过启动"
        else
            log "启动 deeptrace（监听 $VETH1，日志: $DEEPTRACE_LOG）..."
            cd /deeptrace
            deeptrace >> "$DEEPTRACE_LOG" 2>&1 &
            DEEPTRACE_PID=$!
            cd /test
            log "deeptrace 已启动 (pid=$DEEPTRACE_PID)"
        fi
    fi
}

run_test() {
    local INPUT_PCAP="$1"
    local OUTPUT_PCAP="/test/output/captured_$(basename "$INPUT_PCAP" .pcap)_$(date +%Y%m%d_%H%M%S).pcap"

    log "开始测试输入文件: $INPUT_PCAP"

    # 在 veth1 上启动数据包捕获（仅捕获，不过滤以避免漏包）
    log "在 $VETH1 上启动 tcpdump..."
    tcpdump -i "$VETH1" -w "$OUTPUT_PCAP" -U --immediate-mode &
    TCPDUMP_PID=$!
    sleep 2

    # 在 veth0 上回放流量
    log "在 $VETH0 上回放流量..."

    # 构建 replayer 命令参数
    local REPLAYER_CMD=(traffic-replayer replay --file "$INPUT_PCAP" --iface "$VETH0" --verbose)

    # 可选参数
    if [ -n "$REPLAYER_SPEED" ] && [ "$REPLAYER_SPEED" != "1.0" ]; then
        REPLAYER_CMD+=(--speed "$REPLAYER_SPEED")
        log "使用速度倍率: $REPLAYER_SPEED"
    fi

    if [ -n "$REPLAYER_CIDR" ]; then
        REPLAYER_CMD+=(--cidr "$REPLAYER_CIDR")
        log "使用 CIDR 网段: $REPLAYER_CIDR"
    fi

    # 执行回放并等待完成
    "${REPLAYER_CMD[@]}"

    sleep 1

    # 停止 tcpdump
    log "停止 tcpdump..."
    kill "$TCPDUMP_PID" 2>/dev/null || true
    wait "$TCPDUMP_PID" 2>/dev/null || true

    # 验证结果
    log "正在验证结果..."
    INPUT_COUNT=$(tcpdump -r "$INPUT_PCAP" 2>/dev/null | wc -l)
    OUTPUT_COUNT=$(tcpdump -r "$OUTPUT_PCAP" 2>/dev/null | wc -l)

    log "输入数据包: $INPUT_COUNT"
    log "输出数据包: $OUTPUT_COUNT"

    # 检查是否至少捕获到了所有发送的数据包(可能会有额外的系统流量)
    if [ "$OUTPUT_COUNT" -ge "$INPUT_COUNT" ]; then
        log "✓ 测试通过: 已捕获所有发送的数据包 ($INPUT_COUNT/$OUTPUT_COUNT)"
        return 0
    else
        LOSS=$((100 - (OUTPUT_COUNT * 100 / INPUT_COUNT)))
        log "✗ 测试失败: ${LOSS}% 丢包率"
        return 1
    fi
}

run_all_tests() {
    log "运行所有测试..."

    local PASSED=0
    local FAILED=0

    # 使用 find 递归搜索所有 .pcap 和 .pcapng 文件（包括子目录）
    while IFS= read -r -d '' pcap; do
        log "=== 测试: $(basename "$pcap") ==="
        if run_test "$pcap"; then
            PASSED=$((PASSED + 1))
        else
            FAILED=$((FAILED + 1))
        fi
        log ""
    done < <(find /test/data -type f \( -name "*.pcap" -o -name "*.pcapng" \) -print0 | sort -z)

    log "========================================"
    log "测试总结:"
    log "  通过: $PASSED"
    log "  失败: $FAILED"
    log "========================================"

    if [ "$FAILED" -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

# 主逻辑
log "流量回放工具 - 本地测试环境"
log "================================================"

setup_veth

case "${1:-test}" in
    test)
        run_all_tests || true   # 即使部分测试失败也继续进入 web 控制台
        ;;
    single)
        if [ -z "$2" ]; then
            log "错误: 请指定 PCAP 文件"
            log "用法: docker run ... single /path/to/file.pcap"
            exit 1
        fi
        run_test "$2" || true   # 即使测试失败也继续进入 web 控制台
        ;;
    bash|shell)
        log "进入交互式 shell..."
        exec /bin/bash
        ;;
    *)
        log "未知命令: $1"
        log "可用命令: test, single <pcap>, bash"
        exit 1
        ;;
esac
# dev 模式（WITH_DEEPTRACE=true）：测试完成后自动启动 Web 控制台
# web 进程和 deeptrace 同时在后台运行，容器退出时 EXIT trap 统一清理
if [ "$WITH_DEEPTRACE" = "true" ]; then
    log "========================================"
    log "测试完成，启动 Web 控制台 (:18080)"
    log "  浏览器访问: http://localhost:18080"
    log "  Ctrl+C / docker stop 退出时 deeptrace 将自动停止"
    log "========================================"
    traffic-replayer web --addr :18080 &
    WEB_PID=$!
    wait $WEB_PID || true
fi