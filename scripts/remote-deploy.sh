#!/bin/bash

# 远程部署脚本
# 用于将 traffic-replayer 部署到远程 Linux 服务器

set -e

COLOR_RESET='\033[0m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_RED='\033[0;31m'
COLOR_BLUE='\033[0;34m'

echo -e "${COLOR_BLUE}╔════════════════════════════════════════╗${COLOR_RESET}"
echo -e "${COLOR_BLUE}║    Traffic Replayer - 远程部署工具     ║${COLOR_RESET}"
echo -e "${COLOR_BLUE}╚════════════════════════════════════════╝${COLOR_RESET}"
echo ""

# 获取项目根目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

# 第一步：准备 Linux 版本二进制文件
BINARY="bin/traffic-replayer-linux-amd64"
NEED_BUILD=false

echo -e "${COLOR_YELLOW}🔨 步骤 1/3: 准备 Linux AMD64 版本...${COLOR_RESET}"
echo ""

if [ -f "$BINARY" ]; then
    # 显示现有文件信息
    BINARY_SIZE=$(ls -lh "$BINARY" | awk '{print $5}')
    BINARY_TIME=$(ls -l "$BINARY" | awk '{print $6, $7, $8}')
    echo -e "${COLOR_GREEN}✓ 发现已存在的 Linux 版本:${COLOR_RESET}"
    echo "   文件: $BINARY"
    echo "   大小: $BINARY_SIZE"
    echo "   时间: $BINARY_TIME"
    echo ""
    
    # 询问是否重新构建
    read -p "是否重新构建? [y/N]: " rebuild
    if [[ "$rebuild" =~ ^[Yy]$ ]]; then
        NEED_BUILD=true
    else
        echo -e "${COLOR_GREEN}✓ 使用现有的二进制文件${COLOR_RESET}"
    fi
else
    echo -e "${COLOR_YELLOW}📦 未找到 Linux 版本，需要构建${COLOR_RESET}"
    NEED_BUILD=true
fi

# 执行构建
if [ "$NEED_BUILD" = true ]; then
    echo ""
    echo -e "${COLOR_YELLOW}🔨 开始构建 (约需 2-5 分钟)...${COLOR_RESET}"
    if ! make build-linux-docker; then
        echo -e "${COLOR_RED}❌ 构建失败！${COLOR_RESET}"
        exit 1
    fi
    echo -e "${COLOR_GREEN}✓ 构建完成${COLOR_RESET}"
    
    # 再次检查二进制文件
    if [ ! -f "$BINARY" ]; then
        echo -e "${COLOR_RED}❌ 找不到二进制文件: $BINARY${COLOR_RESET}"
        exit 1
    fi
fi

# 第二步：输入远程服务器信息
echo ""
echo -e "${COLOR_YELLOW}📝 步骤 2/3: 请输入远程服务器信息${COLOR_RESET}"
echo ""

read -p "🖥️  服务器地址 (IP 或域名): " REMOTE_HOST
read -p "👤 SSH 用户名 [root]: " REMOTE_USER
REMOTE_USER=${REMOTE_USER:-root}

read -p "🔑 SSH 端口 [22]: " REMOTE_PORT
REMOTE_PORT=${REMOTE_PORT:-22}

read -p "📁 远程安装目录 [/opt/traffic-replayer]: " REMOTE_DIR
REMOTE_DIR=${REMOTE_DIR:-/opt/traffic-replayer}

echo ""
echo -e "${COLOR_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
echo -e "服务器: ${COLOR_GREEN}${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PORT}${COLOR_RESET}"
echo -e "目录:   ${COLOR_GREEN}${REMOTE_DIR}${COLOR_RESET}"
echo -e "${COLOR_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
echo ""

read -p "确认部署? [Y/n]: " confirm
if [[ ! "$confirm" =~ ^[Yy]?$ ]]; then
    echo "已取消部署"
    exit 0
fi

# 设置 SSH 连接复用，避免多次输入密码
SSH_CONTROL_PATH="/tmp/ssh-traffic-replayer-%r@%h:%p"
SSH_OPTS="-o ControlMaster=auto -o ControlPath=${SSH_CONTROL_PATH} -o ControlPersist=300"
SSH_CMD="ssh ${SSH_OPTS} -p ${REMOTE_PORT} ${REMOTE_USER}@${REMOTE_HOST}"
SCP_CMD="scp ${SSH_OPTS} -P ${REMOTE_PORT}"

# 清理函数
cleanup_ssh() {
    ssh -O exit -o ControlPath="${SSH_CONTROL_PATH}" "${REMOTE_USER}@${REMOTE_HOST}" 2>/dev/null || true
}
trap cleanup_ssh EXIT

# 第三步：部署到远程服务器
echo ""
echo -e "${COLOR_YELLOW}🚀 步骤 3/3: 部署到远程服务器${COLOR_RESET}"
echo ""
echo -e "${COLOR_YELLOW}🔗 测试 SSH 连接...${COLOR_RESET}"
echo -e "${COLOR_BLUE}💡 提示: 如果需要输入密码，只需要输入一次${COLOR_RESET}"
if ! $SSH_CMD "echo '连接成功'" > /dev/null 2>&1; then
    echo -e "${COLOR_RED}❌ SSH 连接失败！请检查服务器信息和网络连接${COLOR_RESET}"
    echo ""
    echo -e "${COLOR_YELLOW}💡 建议配置 SSH 密钥认证以避免输入密码:${COLOR_RESET}"
    echo "   ssh-copy-id -p ${REMOTE_PORT} ${REMOTE_USER}@${REMOTE_HOST}"
    exit 1
fi
echo -e "${COLOR_GREEN}✓ SSH 连接成功（后续操作将复用此连接）${COLOR_RESET}"

# 创建远程目录
echo ""
echo -e "${COLOR_YELLOW}📁 创建远程目录...${COLOR_RESET}"
$SSH_CMD "mkdir -p ${REMOTE_DIR}/{bin,logs,data}" || {
    echo -e "${COLOR_RED}❌ 创建目录失败${COLOR_RESET}"
    exit 1
}
echo -e "${COLOR_GREEN}✓ 目录创建成功${COLOR_RESET}"

# 上传二进制文件
echo ""
echo -e "${COLOR_YELLOW}📤 上传二进制文件...${COLOR_RESET}"
$SCP_CMD "$BINARY" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/bin/traffic-replayer" || {
    echo -e "${COLOR_RED}❌ 上传失败${COLOR_RESET}"
    exit 1
}
echo -e "${COLOR_GREEN}✓ 上传完成${COLOR_RESET}"

# 设置权限
echo ""
echo -e "${COLOR_YELLOW}🔐 设置执行权限...${COLOR_RESET}"
$SSH_CMD "chmod +x ${REMOTE_DIR}/bin/traffic-replayer" || {
    echo -e "${COLOR_RED}❌ 权限设置失败${COLOR_RESET}"
    exit 1
}
echo -e "${COLOR_GREEN}✓ 权限设置完成${COLOR_RESET}"

# 设置 capabilities (需要 root)
echo ""
echo -e "${COLOR_YELLOW}🔧 设置网络权限 (需要 libcap)...${COLOR_RESET}"
if $SSH_CMD "command -v setcap > /dev/null 2>&1"; then
    $SSH_CMD "setcap cap_net_raw,cap_net_admin=eip ${REMOTE_DIR}/bin/traffic-replayer" 2>/dev/null && \
        echo -e "${COLOR_GREEN}✓ 网络权限设置成功${COLOR_RESET}" || \
        echo -e "${COLOR_YELLOW}⚠️  权限设置失败，需要 root 权限运行程序${COLOR_RESET}"
else
    echo -e "${COLOR_YELLOW}⚠️  服务器未安装 libcap-dev，需要 root 权限运行程序${COLOR_RESET}"
fi

# 检查依赖
echo ""
echo -e "${COLOR_YELLOW}📦 检查运行依赖...${COLOR_RESET}"
if ! $SSH_CMD "command -v ldconfig > /dev/null && ldconfig -p | grep -q libpcap"; then
    echo -e "${COLOR_YELLOW}⚠️  未找到 libpcap 库，尝试安装...${COLOR_RESET}"
    
    # 检测系统类型并安装
    if $SSH_CMD "command -v apt-get > /dev/null 2>&1"; then
        $SSH_CMD "apt-get update -qq && apt-get install -y -qq libpcap0.8" || \
            echo -e "${COLOR_YELLOW}⚠️  安装失败，请手动安装: apt-get install libpcap0.8${COLOR_RESET}"
    elif $SSH_CMD "command -v yum > /dev/null 2>&1"; then
        $SSH_CMD "yum install -y libpcap" || \
            echo -e "${COLOR_YELLOW}⚠️  安装失败，请手动安装: yum install libpcap${COLOR_RESET}"
    else
        echo -e "${COLOR_YELLOW}⚠️  未识别的系统，请手动安装 libpcap${COLOR_RESET}"
    fi
else
    echo -e "${COLOR_GREEN}✓ libpcap 已安装${COLOR_RESET}"
fi

# 测试程序
echo ""
echo -e "${COLOR_YELLOW}🧪 测试程序...${COLOR_RESET}"
VERSION=$($SSH_CMD "${REMOTE_DIR}/bin/traffic-replayer --version" 2>&1 || echo "")
if [ -z "$VERSION" ]; then
    echo -e "${COLOR_RED}❌ 程序测试失败${COLOR_RESET}"
    exit 1
fi
echo -e "${COLOR_GREEN}✓ 程序运行正常${COLOR_RESET}"
echo "   $VERSION"

# 创建 systemd 服务文件（可选）
echo ""
read -p "📋 是否创建 systemd 服务? [y/N]: " create_service
if [[ "$create_service" =~ ^[Yy]$ ]]; then
    SERVICE_FILE="/tmp/traffic-replayer.service"
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Traffic Replayer Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${REMOTE_DIR}
ExecStart=${REMOTE_DIR}/bin/traffic-replayer replay --iface eth0 --pcap ${REMOTE_DIR}/data/sample.pcap
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

    echo -e "${COLOR_YELLOW}📤 上传服务文件...${COLOR_RESET}"
    $SCP_CMD "$SERVICE_FILE" "${REMOTE_USER}@${REMOTE_HOST}:/tmp/" || {
        echo -e "${COLOR_RED}❌ 上传失败${COLOR_RESET}"
        rm -f "$SERVICE_FILE"
        exit 1
    }
    rm -f "$SERVICE_FILE"
    
    $SSH_CMD "mv /tmp/traffic-replayer.service /etc/systemd/system/ && systemctl daemon-reload" || {
        echo -e "${COLOR_RED}❌ 服务安装失败${COLOR_RESET}"
        exit 1
    }
    
    echo -e "${COLOR_GREEN}✓ 服务文件已创建${COLOR_RESET}"
    echo ""
    echo -e "${COLOR_BLUE}使用以下命令管理服务:${COLOR_RESET}"
    echo "  启动: systemctl start traffic-replayer"
    echo "  停止: systemctl stop traffic-replayer"
    echo "  状态: systemctl status traffic-replayer"
    echo "  开机启动: systemctl enable traffic-replayer"
fi

# 部署完成
echo ""
echo -e "${COLOR_GREEN}╔════════════════════════════════════════╗${COLOR_RESET}"
echo -e "${COLOR_GREEN}║             🎉 部署成功！              ║${COLOR_RESET}"
echo -e "${COLOR_GREEN}╚════════════════════════════════════════╝${COLOR_RESET}"
echo ""
echo -e "${COLOR_BLUE}程序位置:${COLOR_RESET} ${REMOTE_DIR}/bin/traffic-replayer"
echo -e "${COLOR_BLUE}日志目录:${COLOR_RESET} ${REMOTE_DIR}/logs"
echo -e "${COLOR_BLUE}数据目录:${COLOR_RESET} ${REMOTE_DIR}/data"
echo ""

# 询问是否进行远程测试
echo -e "${COLOR_YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
echo -e "${COLOR_YELLOW}📋 接下来您想做什么？${COLOR_RESET}"
echo ""
echo "  1) 自动执行远程联调测试 (推荐)"
echo "     - 自动配置测试环境 (veth 网卡对)"
echo "     - 运行完整的测试套件"
echo "     - 验证程序功能是否正常"
echo "     - 自动清理测试环境"
echo ""
echo "  2) 手动配置测试环境"
echo "     - 配置 veth 网卡对和路由"
echo "     - 然后手动执行测试命令"
echo "     - 需要手动清理环境"
echo ""
echo "  3) 稍后手动执行"
echo "     - 返回命令行"
echo "     - 自行 SSH 到服务器操作"
echo ""
read -p "请选择 [1-3]: " test_choice

case $test_choice in
    1)
        echo ""
        echo -e "${COLOR_GREEN}🚀 准备执行远程联调测试...${COLOR_RESET}"
        echo ""
        
        # 上传测试数据
        if [ -d "docker/local-test/data" ]; then
            echo -e "${COLOR_YELLOW}📤 上传测试数据...${COLOR_RESET}"
            $SSH_CMD "mkdir -p ${REMOTE_DIR}/test-data"
            $SCP_CMD -r docker/local-test/data/* "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/test-data/" 2>&1 | grep -v "^$" || true
            echo -e "${COLOR_GREEN}✓ 测试数据上传完成${COLOR_RESET}"
            echo ""
        fi
        
        # 上传环境配置脚本
        echo -e "${COLOR_YELLOW}📤 上传环境配置脚本...${COLOR_RESET}"
        REMOTE_SETUP_SCRIPT="${REMOTE_DIR}/setup-env.sh"
        $SCP_CMD scripts/setup-env.sh "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_SETUP_SCRIPT}" || {
            echo -e "${COLOR_RED}❌ 上传脚本失败${COLOR_RESET}"
            exit 1
        }
        $SSH_CMD "chmod +x ${REMOTE_SETUP_SCRIPT}"
        echo -e "${COLOR_GREEN}✓ 环境配置脚本上传完成${COLOR_RESET}"
        echo ""
        
        # 上传测试脚本
        echo -e "${COLOR_YELLOW}📤 上传测试脚本...${COLOR_RESET}"
        REMOTE_TEST_SCRIPT="${REMOTE_DIR}/remote-test.sh"
        $SCP_CMD scripts/remote-test.sh "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_TEST_SCRIPT}" || {
            echo -e "${COLOR_RED}❌ 上传脚本失败${COLOR_RESET}"
            exit 1
        }
        $SSH_CMD "chmod +x ${REMOTE_TEST_SCRIPT}"
        echo -e "${COLOR_GREEN}✓ 测试脚本上传完成${COLOR_RESET}"
        echo ""
        
        echo -e "${COLOR_YELLOW}🧪 执行测试（这可能需要几分钟）...${COLOR_RESET}"
        echo -e "${COLOR_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
        
        # 执行远程测试
        TEST_FAILED=false
        $SSH_CMD "cd ${REMOTE_DIR} && sudo bash ${REMOTE_TEST_SCRIPT} --replayer-bin ${REMOTE_DIR}/bin/traffic-replayer test-data/*.pcap" || {
            TEST_FAILED=true
            echo ""
            echo -e "${COLOR_RED}❌ 远程测试失败${COLOR_RESET}"
        }
        
        # 清理测试环境
        echo ""
        echo -e "${COLOR_YELLOW}🧹 清理测试环境...${COLOR_RESET}"
        $SSH_CMD "cd ${REMOTE_DIR} && sudo bash ${REMOTE_SETUP_SCRIPT} --cleanup" 2>&1 | grep -E "(清理|删除|✓)" || true
        echo -e "${COLOR_GREEN}✓ 测试环境清理完成${COLOR_RESET}"
        
        # 检查测试结果
        if [ "$TEST_FAILED" = true ]; then
            echo ""
            echo -e "${COLOR_YELLOW}💡 虽然测试失败，但环境已清理。您可以手动 SSH 到服务器检查问题:${COLOR_RESET}"
            echo "   ssh -p ${REMOTE_PORT} ${REMOTE_USER}@${REMOTE_HOST}"
            echo "   cd ${REMOTE_DIR}"
            echo "   sudo bash remote-test.sh --help"
            exit 1
        fi
        
        echo ""
        echo -e "${COLOR_GREEN}✓ 远程联调测试完成！${COLOR_RESET}"
        ;;
    
    2)
        echo ""
        echo -e "${COLOR_GREEN}🔧 配置测试环境...${COLOR_RESET}"
        echo ""
        
        # 上传环境配置脚本
        echo -e "${COLOR_YELLOW}📤 上传环境配置脚本...${COLOR_RESET}"
        REMOTE_SETUP_SCRIPT="${REMOTE_DIR}/setup-env.sh"
        $SCP_CMD scripts/setup-env.sh "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_SETUP_SCRIPT}" || {
            echo -e "${COLOR_RED}❌ 上传脚本失败${COLOR_RESET}"
            exit 1
        }
        $SSH_CMD "chmod +x ${REMOTE_SETUP_SCRIPT}"
        echo -e "${COLOR_GREEN}✓ 环境配置脚本上传完成${COLOR_RESET}"
        echo ""
        
        # 上传测试脚本
        echo -e "${COLOR_YELLOW}📤 上传测试脚本...${COLOR_RESET}"
        REMOTE_TEST_SCRIPT="${REMOTE_DIR}/remote-test.sh"
        $SCP_CMD scripts/remote-test.sh "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_TEST_SCRIPT}" || {
            echo -e "${COLOR_RED}❌ 上传脚本失败${COLOR_RESET}"
            exit 1
        }
        $SSH_CMD "chmod +x ${REMOTE_TEST_SCRIPT}"
        echo -e "${COLOR_GREEN}✓ 测试脚本上传完成${COLOR_RESET}"
        echo ""
        echo ""
        
        # 执行环境配置
        echo -e "${COLOR_YELLOW}🔧 配置 veth 网卡对和路由...${COLOR_RESET}"
        $SSH_CMD "cd ${REMOTE_DIR} && sudo bash ${REMOTE_SETUP_SCRIPT} --mode test --interface veth0" || {
            echo -e "${COLOR_YELLOW}⚠️  环境配置遇到问题，但可能不影响使用${COLOR_RESET}"
        }
        
        echo ""
        echo -e "${COLOR_GREEN}✓ 测试环境配置完成！${COLOR_RESET}"
        echo ""
        echo -e "${COLOR_YELLOW}💡 手动测试命令示例:${COLOR_RESET}"
        echo ""
        echo "  # SSH 到服务器"
        echo "  ssh -p ${REMOTE_PORT} ${REMOTE_USER}@${REMOTE_HOST}"
        echo ""
        echo "  # 使用测试脚本执行完整测试 (推荐)"
        echo "  cd ${REMOTE_DIR}"
        echo "  sudo bash remote-test.sh --replayer-bin bin/traffic-replayer test-data/*.pcap"
        echo ""
        echo "  # 或手动测试单个命令:"
        echo ""
        echo "  # 回放测试"
        echo "  sudo ${REMOTE_DIR}/bin/traffic-replayer replay --iface veth0 --pcap test.pcap"
        echo ""
        echo "  # 性能测试"
        echo "  sudo ${REMOTE_DIR}/bin/traffic-replayer perf --iface veth0 --duration 30s"
        echo ""
        echo "  # 模拟流量测试"
        echo "  sudo ${REMOTE_DIR}/bin/traffic-replayer mock --iface veth0 --src-ip 192.168.100.10 --dst-ip 192.168.100.20"
        echo ""
        echo "  # 清理测试环境"
        echo "  sudo bash setup-env.sh --cleanup"
        echo ""
        ;;
    
    3)
        echo ""
        echo -e "${COLOR_BLUE}💡 手动操作指引:${COLOR_RESET}"
        echo ""
        echo "  1. SSH 连接到服务器:"
        echo "     ssh -p ${REMOTE_PORT} ${REMOTE_USER}@${REMOTE_HOST}"
        echo ""
        echo "  2. 查看程序帮助:"
        echo "     ${REMOTE_DIR}/bin/traffic-replayer --help"
        echo ""
        echo "  3. 完整测试流程 (需要测试脚本):"
        echo ""
        echo "     # 先手动上传测试资源:"
        echo "     scp -P ${REMOTE_PORT} scripts/remote-test.sh scripts/setup-env.sh ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/"
        echo "     scp -P ${REMOTE_PORT} -r docker/local-test/data/* ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/test-data/"
        echo ""
        echo "     # SSH 到服务器执行测试"
        echo "     ssh -p ${REMOTE_PORT} ${REMOTE_USER}@${REMOTE_HOST}"
        echo "     cd ${REMOTE_DIR}"
        echo "     sudo bash remote-test.sh --replayer-bin bin/traffic-replayer test-data/*.pcap"
        echo ""
        echo "  4. 基本使用示例:"
        echo ""
        echo "     # 回放 PCAP 文件"
        echo "     sudo ${REMOTE_DIR}/bin/traffic-replayer replay --iface eth0 --pcap sample.pcap"
        echo ""
        echo "     # 性能测试"
        echo "     sudo ${REMOTE_DIR}/bin/traffic-replayer perf --iface eth0 --duration 30s"
        echo ""
        echo "     # 模拟流量"
        echo "     sudo ${REMOTE_DIR}/bin/traffic-replayer mock --iface eth0 --src-ip 192.168.1.100 --dst-ip 192.168.1.200"
        echo ""
        ;;
    
    *)
        echo -e "${COLOR_YELLOW}⚠️  无效选项，跳过测试${COLOR_RESET}"
        ;;
esac

echo ""
echo -e "${COLOR_YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
echo -e "${COLOR_YELLOW}💡 下次部署无需输入密码:${COLOR_RESET}"
echo "  # 配置 SSH 密钥认证（只需一次）"
echo "  ssh-copy-id -p ${REMOTE_PORT} ${REMOTE_USER}@${REMOTE_HOST}"
echo ""
echo -e "${COLOR_BLUE}  或手动复制公钥:${COLOR_RESET}"
echo "  1. 生成密钥: ssh-keygen -t ed25519"
echo "  2. 复制公钥: cat ~/.ssh/id_ed25519.pub | ssh -p ${REMOTE_PORT} ${REMOTE_USER}@${REMOTE_HOST} 'mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys'"
echo ""
