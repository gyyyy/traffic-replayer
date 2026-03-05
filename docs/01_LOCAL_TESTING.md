# 本地测试使用手册

本文档详细说明如何使用本地测试脚本 [scripts/local-test.sh](scripts/local-test.sh) 对 traffic-replayer 进行快速测试。

## 目录

- [概述](#概述)
- [前置条件](#前置条件)
- [基本用法](#基本用法)
- [参数说明](#参数说明)
- [使用场景](#使用场景)
- [手动测试](#手动测试)
- [故障排查](#故障排查)
- [附录](#附录)

## 概述

本地测试脚本通过 Docker 容器化环境快速测试 traffic-replayer 的流量回放功能。

**主要特点**：
- 完全容器化，无需配置本地环境
- 自动构建和测试
- 支持单文件或批量测试
- 自动验证回放结果

**适用场景**：
- 开发阶段的快速功能验证
- CI/CD 流程中的自动化测试
- 回归测试
- 单个 PCAP 文件的调试

## 前置条件

### 1. Docker 环境

```bash
# 检查 Docker 是否安装并运行
docker --version
docker info
```

如果未安装，请访问 [Docker 官网](https://www.docker.com/get-started) 安装 Docker Desktop 或 Docker Engine。

### 2. 测试数据

测试 PCAP/PCAPNG 文件需放置在 [docker/local-test/data/](docker/local-test/data/) 目录下。支持子目录结构，测试时会递归搜索所有 `.pcap` 和 `.pcapng` 文件。

**支持的格式**：
- `.pcap` - 传统 PCAP 格式
- `.pcapng` - PCAP Next Generation 格式

```bash
# 查看现有测试文件（包括子目录）
find docker/local-test/data/ -name "*.pcap" -o -name "*.pcapng"

# 添加自定义测试文件到根目录
cp /path/to/your.pcap docker/local-test/data/
cp /path/to/your.pcapng docker/local-test/data/

# 添加文件到子目录（支持任意层级）
mkdir -p docker/local-test/data/http
cp /path/to/http_test.pcap docker/local-test/data/http/
cp /path/to/http_test.pcapng docker/local-test/data/http/
```

## 基本用法

### 测试所有 PCAP 文件

```bash
# 在项目根目录执行
./scripts/local-test.sh
```

这将递归测试 [docker/local-test/data/](docker/local-test/data/) 目录及其所有子目录下的 PCAP/PCAPNG 文件。

### 测试单个文件

**推荐方式（使用完整路径）**：
```bash
./scripts/local-test.sh docker/local-test/data/http_simple.pcap

# 子目录中的文件
./scripts/local-test.sh docker/local-test/data/http/simple.pcap
```

**相对路径方式**：
```bash
# 指定子目录路径
./scripts/local-test.sh http/simple.pcap

# 嵌套子目录
./scripts/local-test.sh test/2024/file.pcap
```

**简短方式（仅文件名）**：
```bash
./scripts/local-test.sh http_simple.pcap
```

脚本会自动在 [docker/local-test/data/](docker/local-test/data/) 目录及其子目录中递归查找文件。如果有多个同名文件，会使用第一个找到的。

### 调整回放速度

```bash
# 2 倍速回放
./scripts/local-test.sh --speed 2.0

# 0.5 倍速（慢放）
./scripts/local-test.sh --speed 0.5

# 测试单个文件并使用 1.5 倍速
./scripts/local-test.sh --speed 1.5 docker/local-test/data/http_simple.pcap
```

### 重写 IP 地址

```bash
# 将所有 IP 地址重写到指定 CIDR 网段
./scripts/local-test.sh --cidr 192.168.1.0/24

# 组合使用多个参数
./scripts/local-test.sh --speed 2.0 --cidr 10.0.0.0/16 docker/local-test/data/http_simple.pcap
```

## 参数说明

| 参数 | 说明 | 默认值 | 示例 |
|------|------|--------|------|
| `--speed SPEED` | 流量回放速度倍率 | 1.0 | `--speed 2.0` |
| `--cidr CIDR` | 重写 IP 地址到指定 CIDR 网段 | 不重写 | `--cidr 192.168.1.0/24` |
| `PCAP 文件` | 要测试的 PCAP 文件路径（支持完整路径、相对路径或文件名） | 测试所有文件 | `http/simple.pcap` |
| `-h, --help` | 显示帮助信息 | - | `--help` |

## 使用场景

### 场景 1：快速验证功能

**需求**：验证 traffic-replayer 是否正常工作

```bash
# 使用默认配置测试所有文件
./scripts/local-test.sh
```

**预期输出**：
```
=======================================
Traffic Replayer - Local Test
=======================================

[1/4] 清理之前的测试产物...
[2/4] 构建 Docker 镜像...
[3/4] 运行测试...
测试所有 PCAP 文件
...
[4/4] 收集结果...

测试完成!
```

### 场景 2：调试特定文件

**需求**：某个 PCAP 文件回放异常，需要单独调试

```bash
# 测试单个文件
./scripts/local-test.sh docker/local-test/data/problematic.pcap

# 查看详细日志
cat docker/local-test/logs/test.log
```

### 场景 3：压力测试

**需求**：测试高速流量回放场景

```bash
# 使用 10 倍速回放大流量文件
./scripts/local-test.sh --speed 10.0 docker/local-test/data/large_traffic.pcap
```

### 场景 4：IP 地址兼容性测试

**需求**：测试流量在不同网段下的行为

```bash
# 测试公网 IP 段
./scripts/local-test.sh --cidr 203.0.113.0/24

# 测试内网 IP 段
./scripts/local-test.sh --cidr 10.10.10.0/24
```

### 场景 5：CI/CD 集成

**需求**：在 CI 流水线中自动测试

```yaml
# .github/workflows/test.yml 示例
steps:
  - name: Run Local Tests
    run: |
      ./scripts/local-test.sh
      if [ $? -ne 0 ]; then
        echo "Tests failed"
        exit 1
      fi
```

## 手动测试

需要交互式调试时，可以直接进入容器。容器启动时会自动完成 veth pair 创建，进入后可直接使用 `traffic-replayer` 命令。

### 启动交互式容器

```bash
cd docker/local-test && docker compose run --rm replayer-test bash
```

### 容器内常用操作

**mock 模式发送模拟流量**：

```bash
# 发送完整 HTTP 会话（TCP 握手 + 请求/响应 + 挥手）
traffic-replayer mock --iface veth0 --src-ip 192.168.100.123 --dst-ip 1.1.1.1 --type http --verbose

# 发送 ICMP Ping
traffic-replayer mock --iface veth0 --src-ip 10.0.0.1 --dst-ip 10.0.0.2 --type ping

# 发送 ARP
traffic-replayer mock --iface veth0 --src-ip 10.0.0.1 --dst-ip 10.0.0.2 --type arp

# 发送全部类型
traffic-replayer mock --iface veth0 --src-ip 192.168.1.10 --dst-ip 192.168.1.20 --type all

# 重复发送多次
traffic-replayer mock --iface veth0 --src-ip 192.168.1.10 --dst-ip 192.168.1.20 --type http --count 5
```

**回放 PCAP 文件**：

```bash
# 回放单个文件（测试数据已挂载在 /test/data/ 下）
traffic-replayer replay --file /test/data/http_simple.pcap --iface veth0 --verbose

# 带 IP 重写
traffic-replayer replay --file /test/data/http_simple.pcap --iface veth0 --cidr 192.168.100.0/24
```

**抓包验证**：

```bash
# 在 veth1 上实时抓包（另开终端 docker exec 进入容器）
tcpdump -i veth1 -n -v

# 保存到文件
tcpdump -i veth1 -w /test/output/manual_test.pcap
```

## 故障排查

### 问题 1：Docker 未运行

**错误信息**：
```
错误: Docker 未运行。请启动 Docker 后重试。
```

**解决方法**：
```bash
# macOS/Windows: 启动 Docker Desktop
# Linux: 启动 Docker 服务
sudo systemctl start docker
```

### 问题 2：文件未找到

**错误信息**：
```
错误: 找不到文件 test.pcap
请确保文件在 docker/local-test/data/ 目录下（包括子目录）
```

**解决方法**：
```bash
# 检查文件是否存在（包括子目录）
find docker/local-test/data/ -name "*.pcap" -o -name "*.pcapng"

# 将文件复制到正确位置
cp /path/to/your.pcap docker/local-test/data/
cp /path/to/your.pcapng docker/local-test/data/

# 或者放入子目录
mkdir -p docker/local-test/data/custom
cp /path/to/your.pcap docker/local-test/data/custom/
cp /path/to/your.pcapng docker/local-test/data/custom/
```

### 问题 3：构建失败

**错误信息**：
```
[2/4] 构建 Docker 镜像...
ERROR: [+] Building failed
```

**解决方法**：
```bash
# 清理 Docker 缓存
docker system prune -f

# 重新运行测试
./scripts/local-test.sh
```

### 问题 4：测试输出目录权限问题

**错误信息**：
```
Permission denied: docker/local-test/output/
```

**解决方法**：
```bash
# 修复目录权限
chmod -R 755 docker/local-test/output
chmod -R 755 docker/local-test/logs
```

### 问题 5：查看详细日志

```bash
# replayer 测试日志
cat docker/local-test/logs/test.log

# 查看最近的测试结果
ls -lht docker/local-test/output/
```

## 附录

### A. 测试数据准备

#### 创建自定义测试数据

```bash
# 方法 1：从现有流量中提取
tcpdump -i eth0 -w custom_traffic.pcap -c 100

# 方法 2：使用 tcpreplay 工具生成
tcprewrite --infile=original.pcap --outfile=modified.pcap --cidr=192.168.1.0/24

# 复制到测试目录
cp custom_traffic.pcap docker/local-test/data/
```

### B. 测试结果分析

#### 输出文件说明

- `docker/local-test/output/`：回放后捕获的 PCAP 文件
- `docker/local-test/logs/test.log`：replayer 测试日志

#### 验证测试结果

```bash
# 统计数据包数量
tcpdump -r docker/local-test/output/captured.pcap | wc -l

# 查看数据包详情
tcpdump -r docker/local-test/output/captured.pcap -n -v

# 提取特定协议
tcpdump -r docker/local-test/output/captured.pcap -n 'tcp port 80'

# 分析 IP 地址分布
tcpdump -r docker/local-test/output/captured.pcap -n | awk '{print $3}' | sort | uniq -c
```

### C. 性能优化建议

#### Docker 资源限制

编辑 `docker/local-test/docker-compose.yml`：

```yaml
services:
  replayer-test:
    mem_limit: 2g
    cpus: 2
```

#### 清理旧镜像

```bash
docker system prune -a
```

### D. 常用命令参考

```bash
# 查看 Docker 容器
docker ps -a

# 查看 Docker 日志
docker logs <container_id>

# 进入容器调试
docker exec -it <container_id> /bin/bash

# 清理所有测试产物
rm -rf docker/local-test/output/* docker/local-test/logs/*
```