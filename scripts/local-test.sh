#!/bin/bash
# 本地测试一键自动化脚本
# 在 Docker 中构建并运行流量回放测试

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOCAL_TEST_DIR="$PROJECT_ROOT/docker/local-test"

# 默认参数
REPLAYER_SPEED="1.0"
REPLAYER_CIDR=""
PCAP_FILE=""

# 显示帮助信息
show_help() {
    cat << EOF
本地测试脚本

用法: $0 [选项] [PCAP 文件]

选项:
  --speed SPEED    流量回放速度倍率 (默认: 1.0)
  --cidr CIDR      重写 IP 地址 CIDR 网段 (例如: 192.168.1.0/24)
  -h, --help       显示此帮助信息

参数:
  PCAP 文件          要测试的 PCAP 文件路径（可选）
                   如不指定，则测试默认目录下的所有 PCAP 文件
                   支持以下路径格式:
                   - docker/local-test/data/file.pcap (推荐)
                   - file.pcap (自动在 docker/local-test/data/ 查找)

示例:
  # 测试所有文件
  $0

  # 使用 2 倍速测试
  $0 --speed 2.0

  # 重写 IP 地址
  $0 --cidr 192.168.1.0/24

  # 测试单个文件（推荐使用完整路径）
  $0 docker/local-test/data/http_simple.pcap

  # 测试单个文件（简短形式）
  $0 http_simple.pcap

  # 组合使用
  $0 --speed 1.5 --cidr 10.0.0.0/16 docker/local-test/data/http_simple.pcap
EOF
}

# 解析参数
while [[ $# -gt 0 ]]; do
    case $1 in
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
            echo "错误: 未知选项 $1"
            show_help
            exit 1
            ;;
        *)
            PCAP_FILE="$1"
            shift
            ;;
    esac
done

cd "$PROJECT_ROOT"

echo "======================================="
echo "Traffic Replayer - Local Test"
echo "======================================="
echo ""

# 检查 Docker 是否运行
if ! docker info >/dev/null 2>&1; then
    echo "错误: Docker 未运行。请启动 Docker 后重试。"
    exit 1
fi

echo "[1/4] 清理之前的测试产物..."
rm -rf "$LOCAL_TEST_DIR/output" "$LOCAL_TEST_DIR/logs"
mkdir -p "$LOCAL_TEST_DIR/output" "$LOCAL_TEST_DIR/logs"

# 清理旧的 Docker 资源以避免网络配置冲突
cd "$LOCAL_TEST_DIR"
docker compose down -v 2>/dev/null || true

echo ""
echo "[2/4] 构建 Docker 镜像..."
docker compose build replayer-test

echo ""
echo "[3/4] 运行测试..."

# 将宿主机 PCAP 路径解析为容器内路径（单文件模式通用逻辑）
resolve_container_path() {
    local PCAP_FILE="$1"
    local CONTAINER_PCAP_FILE="$PCAP_FILE"
    if [[ "$PCAP_FILE" == docker/local-test/data/* ]]; then
        RELATIVE_PATH="${PCAP_FILE#docker/local-test/data/}"
        CONTAINER_PCAP_FILE="/test/data/$RELATIVE_PATH"
    elif [[ "$PCAP_FILE" != /* ]]; then
        if [[ "$PCAP_FILE" == */* ]]; then
            FOUND_FILE=$(find "$PROJECT_ROOT/docker/local-test/data" -type f \( -name "*.pcap" -o -name "*.pcapng" \) -path "*/$PCAP_FILE" 2>/dev/null | head -1) || true
        else
            FOUND_FILE=$(find "$PROJECT_ROOT/docker/local-test/data" -type f \( -name "*.pcap" -o -name "*.pcapng" \) -name "$PCAP_FILE" 2>/dev/null | head -1) || true
        fi
        if [ -n "$FOUND_FILE" ]; then
            RELATIVE_PATH="${FOUND_FILE#$PROJECT_ROOT/docker/local-test/data/}"
            CONTAINER_PCAP_FILE="/test/data/$RELATIVE_PATH"
        else
            echo "错误: 找不到文件 $PCAP_FILE"
            echo "请确保文件在 docker/local-test/data/ 目录下（包括子目录）"
            echo "支持的格式: .pcap, .pcapng"
            exit 1
        fi
    fi
    echo "$CONTAINER_PCAP_FILE"
}

export REPLAYER_SPEED
export REPLAYER_CIDR

if [ -n "$PCAP_FILE" ]; then
    CONTAINER_PCAP_FILE=$(resolve_container_path "$PCAP_FILE")
    echo "模式: 单文件"
    echo "  文件: $PCAP_FILE"
    echo "  容器内路径: $CONTAINER_PCAP_FILE"
    docker compose run --rm replayer-test single "$CONTAINER_PCAP_FILE"
else
    echo "模式: 全量测试"
    if [ "$REPLAYER_SPEED" != "1.0" ]; then echo "  速度倍率: $REPLAYER_SPEED"; fi
    if [ -n "$REPLAYER_CIDR" ]; then echo "  CIDR 网段: $REPLAYER_CIDR"; fi
    docker compose run --rm replayer-test test
fi

echo ""
echo "[4/4] 收集结果..."
if [ -f "$LOCAL_TEST_DIR/logs/test.log" ]; then
    echo ""
    echo "测试日志:"
    cat "$LOCAL_TEST_DIR/logs/test.log"
fi

echo ""
echo "输出文件:"
ls -lh "$LOCAL_TEST_DIR/output/" 2>/dev/null || echo "  (无输出文件)"

echo ""
echo "======================================="
echo "测试完成!"
echo "======================================="
echo ""
echo "日志: $LOCAL_TEST_DIR/logs/"
echo "输出: $LOCAL_TEST_DIR/output/"
echo ""

# 清理悬空镜像
echo "清理悬空的 Docker 镜像..."
if docker image prune -f > /dev/null 2>&1; then
    echo "✓ 已清理悬空镜像"
else
    echo "⚠ 清理镜像失败（可忽略）"
fi
echo ""

