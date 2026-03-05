# 远程测试使用手册

本文档详细说明如何使用远程测试脚本 [scripts/remote-test.sh](scripts/remote-test.sh) 在真实 Linux 服务器环境中测试 traffic-replayer 与流量采集分析系统等的联调。

## 目录

- [概述](#概述)
- [前置条件](#前置条件)
- [基本用法](#基本用法)
- [参数说明](#参数说明)
- [使用场景](#使用场景)
- [故障排查](#故障排查)
- [附录](#附录)

## 概述

远程测试脚本用于在真实 Linux 服务器环境中测试 traffic-replayer 与流量采集分析系统等的联调。

**主要功能**：
- 自动配置测试环境（veth 网卡对）
- 编译并验证 traffic-replayer
- 执行流量回放和捕获
- 分析测试结果（成功/失败/丢包率）

**适用场景**：
- 真实服务器环境的功能验证
- 与流量采集分析系统的联调测试
- 网络配置和性能测试
- 模拟生产环境的测试

## 前置条件

### 1. 系统要求

- **操作系统**：Ubuntu 18.04+, CentOS 7+, Debian 10+, RHEL 7+
- **网卡**：支持混杂模式的网卡
- **权限**：root 权限

### 2. 必需工具

```bash
# Ubuntu/Debian
sudo apt-get install -y iproute2 tcpdump

# CentOS/RHEL
sudo yum install -y iproute tcpdump
```

## 基本用法

### 测试所有文件

```bash
# 在项目根目录执行
sudo ./scripts/remote-test.sh
```

这将递归测试 [docker/local-test/data/](docker/local-test/data/) 目录及其所有子目录下的 PCAP/PCAPNG 文件。

### 测试单个文件

```bash
# 完整路径
sudo ./scripts/remote-test.sh docker/local-test/data/http_simple.pcap

# 子目录中的文件
sudo ./scripts/remote-test.sh docker/local-test/data/http/simple.pcap
```

### 自定义网络接口

```bash
# 指定发送和接收接口
sudo ./scripts/remote-test.sh \
  --send-interface veth2 \
  --recv-interface veth3 \
  docker/local-test/data/test.pcap
```

### 跳过环境配置

```bash
# 如果环境已配置好，跳过 veth 创建步骤
sudo ./scripts/remote-test.sh --skip-env-setup
```

### 使用自定义 replayer 二进制文件

```bash
sudo ./scripts/remote-test.sh \
  --replayer-bin /opt/traffic-replayer/bin/traffic-replayer
```

### 调整回放速度

```bash
# 2 倍速回放
sudo ./scripts/remote-test.sh --speed 2.0

# 0.5 倍速（慢放）
sudo ./scripts/remote-test.sh --speed 0.5
```

### 重写 IP 地址

```bash
# 将所有 IP 地址重写到指定 CIDR 网段
sudo ./scripts/remote-test.sh --cidr 192.168.1.0/24
```

## 参数说明

| 参数 | 说明 | 默认值 | 示例 |
|------|------|--------|------|
| `-s, --send-interface` | 发送接口名称 | veth0 | `--send-interface eth1` |
| `-r, --recv-interface` | 接收接口名称 | veth1 | `--recv-interface eth2` |
| `--skip-env-setup` | 跳过环境配置步骤 | false | `--skip-env-setup` |
| `--replayer-bin` | traffic-replayer 可执行文件路径 | bin/traffic-replayer | `--replayer-bin /opt/replayer` |
| `--speed` | 流量回放速度倍率 | 1.0 | `--speed 2.0` |
| `--cidr` | 重写 IP 地址 CIDR 网段 | 不重写 | `--cidr 192.168.1.0/24` |
| `PCAP 文件` | 要测试的 PCAP 文件路径 | 测试所有文件 | `data/test.pcap` |
| `-h, --help` | 显示帮助信息 | - | `--help` |

## 使用场景

### 场景 1：首次环境验证

**需求**：在新服务器上验证 traffic-replayer 是否正常工作

```bash
# 使用默认配置测试所有文件
sudo ./scripts/remote-test.sh
```

**预期输出**：
```
======================================
Traffic Replayer 远程联调测试
======================================
[INFO] 运行模式: test (仅测试环境)
[INFO] 发送接口: veth0
[INFO] 接收接口: veth1

[STEP] [1/5] 配置测试环境
[INFO] ✓ veth 网卡对创建成功
...
[INFO] ✓ 测试通过: 成功捕获所有数据包 (100/100)
```

### 场景 2：与流量采集分析系统联调

**需求**：测试 traffic-replayer 和流量采集分析系统的配合工作

**步骤 1：配置环境**
```bash
# 配置测试环境（只需执行一次）
sudo ./scripts/setup-env.sh --mode test
```

**步骤 2：启动流量采集分析系统**
```bash
# 配置流量采集分析系统监听 veth1 接口
sudo XXX --interface veth1 --output /tmp/xxx.log
```

**步骤 3：运行测试（跳过环境配置）**
```bash
# 跳过环境配置，直接测试
sudo ./scripts/remote-test.sh --skip-env-setup
```

**步骤 4：验证流量采集分析系统输出**
```bash
# 检查流量采集分析系统是否成功捕获流量
cat /tmp/xxx.log
```

### 场景 3：自定义网络拓扑测试

**需求**：使用已有的网络接口进行测试

```bash
# 假设已经配置了 eth1 和 eth2
sudo ./scripts/remote-test.sh \
  --send-interface eth1 \
  --recv-interface eth2 \
  --skip-env-setup \
  docker/local-test/data/http_simple.pcap
```

### 场景 4：多文件批量测试

**需求**：批量测试多个 PCAP 文件

```bash
# 将所有测试文件放入测试目录或子目录
cp /path/to/*.pcap docker/local-test/data/

# 或者使用子目录组织
mkdir -p docker/local-test/data/http docker/local-test/data/dns
cp /path/to/http*.pcap docker/local-test/data/http/
cp /path/to/dns*.pcap docker/local-test/data/dns/

# 批量测试（会递归搜索所有子目录）
sudo ./scripts/remote-test.sh
```

**预期输出**：
```
========================================
测试总结
========================================
总计: 10
通过: 8
失败: 2
========================================
```

### 场景 5：调试失败的测试

**需求**：某个测试失败，需要查看详细日志

```bash
# 运行测试
sudo ./scripts/remote-test.sh docker/local-test/data/failed_test.pcap

# 查看详细日志
cat test/logs/test-failed_test_*.log

# 查看捕获的数据包
tcpdump -r test/output/captured_failed_test_*.pcap -n | head -20
```

### 场景 6：IP 地址重写测试

**需求**：测试流量在不同 IP 段的行为

```bash
# 测试内网 IP 段
sudo ./scripts/remote-test.sh \
  --cidr 10.0.0.0/8 \
  docker/local-test/data/http_simple.pcap

# 验证 IP 是否重写成功
tcpdump -r test/output/captured_http_simple_*.pcap -n | grep "10.0.0"
```

## 故障排查

### 问题 1：权限不足

**错误信息**：
```
[ERROR] 此脚本需要 root 权限，请使用 sudo 运行
```

**解决方法**：
```bash
sudo ./scripts/remote-test.sh
```

### 问题 2：缺少依赖

**错误信息**：
```
[ERROR] 缺少必要的命令: tcpdump ip
[INFO] 请先安装: sudo apt-get install iproute2 tcpdump
```

**解决方法**：
```bash
# Ubuntu/Debian
sudo apt-get install -y iproute2 tcpdump

# CentOS/RHEL
sudo yum install -y iproute tcpdump
```

### 问题 3：环境配置失败

**错误信息**：
```
[ERROR] 环境配置失败
```

**解决方法**：
```bash
# 手动配置环境
sudo ./scripts/setup-env.sh --mode test

# 验证 veth 网卡是否创建成功
ip link show veth0
ip link show veth1

# 重新运行测试（跳过环境配置）
sudo ./scripts/remote-test.sh --skip-env-setup
```

### 问题 4：traffic-replayer 未编译

**错误信息**：
```
[WARN] 找不到 traffic-replayer: bin/traffic-replayer
[INFO] 正在构建 traffic-replayer...
[ERROR] 构建 traffic-replayer 失败
```

**解决方法**：
```bash
# 手动编译
cd /path/to/traffic-replayer
make build

# 验证编译结果
ls -lh bin/traffic-replayer

# 重新运行测试
sudo ./scripts/remote-test.sh
```

### 问题 5：tcpdump 启动失败

**错误信息**：
```
[ERROR] tcpdump 启动失败
```

**可能原因和解决方法**：

**原因 1：接口不存在**
```bash
# 检查接口是否存在
ip link show veth1

# 如果不存在，重新配置环境
sudo ./scripts/setup-env.sh --mode test
```

**原因 2：权限不足**
```bash
# 确保使用 sudo 运行
sudo ./scripts/remote-test.sh
```

**原因 3：接口未启动**
```bash
# 手动启动接口
sudo ip link set veth1 up
sudo ip link set veth1 promisc on
```

### 问题 6：流量回放失败

**错误信息**：
```
[ERROR] 流量回放失败
```

**解决方法**：
```bash
# 检查日志详情
cat test/logs/test-*.log

# 手动测试 traffic-replayer
sudo bin/traffic-replayer replay \
  --file docker/local-test/data/test.pcap \
  --iface veth0 \
  --verbose

# 检查 PCAP 文件是否有效
tcpdump -r docker/local-test/data/test.pcap -c 10
```

### 问题 7：丢包严重

**现象**：
```
[INFO] 发送数据包: 10000
[INFO] 捕获数据包: 5000
[ERROR] ✗ 测试失败: 50% 丢包率
```

**可能原因和解决方法**：

**原因 1：回放速度过快**
```bash
# 降低回放速度
sudo ./scripts/remote-test.sh --speed 0.5
```

**原因 2：系统资源不足**
```bash
# 检查系统负载
top
free -h

# 优化系统内核参数（生产环境）
sudo ./scripts/setup-env.sh --mode prod --interface veth0
```

**原因 3：网卡缓冲区过小**
```bash
# 增加网卡缓冲区
sudo ethtool -G veth1 rx 4096 2>/dev/null || echo "Not supported"
```

### 问题 8：清理测试环境

```bash
# 清理 veth 网卡对
sudo ./scripts/setup-env.sh --cleanup

# 或者手动删除
sudo ip link delete veth0

# 清理测试输出
rm -rf test/output/* test/logs/*
```

### 问题 9：查看详细调试信息

```bash
# 运行测试
sudo ./scripts/remote-test.sh docker/local-test/data/test.pcap

# 查看完整日志
cat test/logs/test-test_*.log

# 分析捕获的数据包
tcpdump -r test/output/captured_test_*.pcap -n -v

# 对比原始和捕获的数据包
echo "原始数据包:"
tcpdump -r docker/local-test/data/test.pcap -n | head -10
echo "捕获数据包:"
tcpdump -r test/output/captured_test_*.pcap -n | head -10
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

- `test/output/captured_*.pcap`：捕获的流量文件
- `test/logs/test-*.log`：每个测试的详细日志

#### 验证测试结果

```bash
# 统计数据包数量
tcpdump -r test/output/captured_*.pcap | wc -l

# 查看数据包详情
tcpdump -r test/output/captured_*.pcap -n -v

# 提取特定协议
tcpdump -r test/output/captured_*.pcap -n 'tcp port 80'

# 分析 IP 地址分布
tcpdump -r test/output/captured_*.pcap -n | awk '{print $3}' | sort | uniq -c
```

### C. 性能优化建议

#### 系统内核参数

```bash
# 使用生产模式配置进行优化
sudo ./scripts/setup-env.sh --mode prod --interface veth0
```

#### 禁用不必要的网卡卸载功能

```bash
sudo ethtool -K veth1 rx off tx off
```

### D. 常用命令参考

```bash
# 查看网络接口
ip link show

# 查看接口统计
ip -s link show veth0

# 监控实时流量
sudo tcpdump -i veth1 -n

# 查看接口是否处于混杂模式
ip link show veth1 | grep PROMISC

# 查看进程资源占用
top -p $(pgrep traffic-replayer)
```