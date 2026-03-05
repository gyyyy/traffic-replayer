# 生产环境配置手册

本文档详细说明如何使用 [scripts/setup-env.sh](scripts/setup-env.sh) 脚本在生产环境中配置 Linux 服务器以支持镜像流量采集分析，以及与 traffic-replayer 辅助集成测试。

## 目录

- [概述](#概述)
- [前置条件](#前置条件)
- [基本用法](#基本用法)
- [网络配置](#网络配置)
- [系统优化](#系统优化)
- [集成测试](#集成测试)
- [监控与维护](#监控与维护)
- [故障排查](#故障排查)
- [附录](#附录)

## 概述

`setup-env.sh` 脚本用于配置生产环境的网络接口和系统参数，确保服务器能够高效地进行流量镜像和采集。

**主要功能**：
- 配置网络接口混杂模式
- 优化系统内核参数
- 禁用网卡卸载功能以提高抓包性能
- 配置备份和恢复机制
- 健康检查和监控

**支持的运行模式**：
- **test 模式**：创建虚拟网卡对（veth）用于本地测试
- **prod 模式**：配置物理网卡的镜像端口，优化生产环境参数

## 前置条件

### 1. 操作系统要求

支持的操作系统：
- Ubuntu 18.04+
- CentOS 7+
- Debian 10+
- RHEL 7+
- Rocky Linux 8+
- AlmaLinux 8+

### 2. 硬件要求

**最低配置**：
- CPU: 4 核心
- 内存: 8GB
- 磁盘: 50GB 可用空间
- 网卡: 支持混杂模式的千兆网卡

**推荐配置**（高流量场景）：
- CPU: 8+ 核心
- 内存: 16GB+
- 磁盘: 100GB+ SSD
- 网卡: 10Gbps 网卡，支持多队列

### 3. 权限要求

所有操作需要 root 权限：

```bash
# 检查当前用户权限
id

# 如果不是 root，使用 sudo
sudo -i
```

### 4. 必需软件包

脚本会自动安装以下软件包，但也可以手动安装：

```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y iproute2 tcpdump net-tools ethtool jq

# CentOS/RHEL
sudo yum install -y iproute tcpdump net-tools ethtool jq
```

### 5. 网络拓扑要求

生产环境需要配置端口镜像（Port Mirroring/SPAN）：

```
┌───────────────┐
│   核心交换机    │
│               │
│  ┌─────────┐  │
│  │ 镜像配置 │  │  将指定端口的流量镜像到监控端口
│  └─────────┘  │
└───────┬───────┘
        │ 镜像流量
        ↓
   ┌─────────┐
   │  eth1   │  监控服务器的镜像端口
   │ (SPAN)  │
   └─────────┘
        │
   ┌────┴────┐
   │ Server  │  运行 流量采集分析系统 和 setup-env.sh
   └─────────┘
```

**关键要点**：
- 镜像端口只接收流量，不发送流量
- 镜像端口通常不配置 IP 地址
- 需要交换机支持并正确配置端口镜像功能

## 基本用法

### 生产模式配置（单个接口）

```bash
# 配置单个镜像端口
sudo ./scripts/setup-env.sh --mode prod --interface eth1
```

### 生产模式配置（多个接口）

```bash
# 配置多个镜像端口（逗号分隔）
sudo ./scripts/setup-env.sh --mode prod --interface eth1,eth2,eth3
```

### 测试模式配置

```bash
# 创建虚拟网卡对用于测试
sudo ./scripts/setup-env.sh --mode test
```

### 查看帮助信息

```bash
./scripts/setup-env.sh --help
```

### 高级选项

#### 跳过系统优化

```bash
# 仅配置网卡，跳过系统内核参数优化
sudo ./scripts/setup-env.sh --mode prod --interface eth1 --skip-system-tuning
```

#### 预览模式（不实际执行）

```bash
# 查看将要执行的操作，不实际修改系统
sudo ./scripts/setup-env.sh --mode prod --interface eth1 --dry-run
```

#### 调试模式

```bash
# 启用详细日志输出
sudo ./scripts/setup-env.sh --mode prod --interface eth1 --debug
```

### 备份与恢复

#### 列出所有备份

```bash
sudo ./scripts/setup-env.sh --list-backups
```

输出示例：
```
===== 可用的配置备份 =====

  [Jan 28 14:30] /var/lib/traffic-replayer/backups/config_backup_20260128_143022.json (2.5K)
  [Jan 27 10:15] /var/lib/traffic-replayer/backups/config_backup_20260127_101532.json (2.4K)

[INFO] 最新备份: /var/lib/traffic-replayer/backups/config_backup_20260128_143022.json
```

#### 恢复到最新备份

```bash
sudo ./scripts/setup-env.sh --restore
```

#### 恢复到指定备份

```bash
sudo ./scripts/setup-env.sh --restore /var/lib/traffic-replayer/backups/config_backup_20260128_143022.json
```

### 健康检查

```bash
# ���查单个接口
sudo ./scripts/setup-env.sh --health-check --interface eth1

# 检查多个接口
sudo ./scripts/setup-env.sh --health-check --interface eth1,eth2
```

健康检查会验证：
- 网卡状态（UP/DOWN）
- 混杂模式是否启用
- 流量统计
- 系统资源（CPU、内存、磁盘）
- 内核参数配置

### 清理测试环境

```bash
# 仅用于测试模式，删除创建的 veth 网卡对
sudo ./scripts/setup-env.sh --cleanup
```

## 参数说明

| 参数 | 说明 | 默认值 | 示例 |
|------|------|--------|------|
| `-m, --mode` | 运行模式：test 或 prod | test | `--mode prod` |
| `-i, --interface` | 网络接口名称，支持多个（逗号分隔） | test:veth0<br/>prod:必须指定 | `--interface eth1,eth2` |
| `--restore` | 恢复配置，可选指定备份文件 | - | `--restore [备份文件]` |
| `--list-backups` | 列出所有可用备份 | - | `--list-backups` |
| `--skip-system-tuning` | 跳过系统内核参数优化 | false | `--skip-system-tuning` |
| `--dry-run` | 预览模式，不实际执行 | false | `--dry-run` |
| `--debug` | 启用调试模式 | false | `--debug` |
| `--health-check` | 执行健康检查 | false | `--health-check` |
| `--cleanup` | 清理测试环境（仅测试模式） | - | `--cleanup` |
| `-h, --help` | 显示帮助信息 | - | `--help` |

## 网络配置

### 交换机端口镜像配置

在配置服务器之前，需要在交换机上配置端口镜像。不同厂商的配置方式不同：

#### Cisco 交换机配置示例

```cisco
! 创建监控会话
monitor session 1 source interface Gi1/0/1 both
monitor session 1 destination interface Gi1/0/24

! Gi1/0/1: 被监控的端口
! Gi1/0/24: 镜像端口（连接到监控服务器）
! both: 同时监控入站和出站流量
```

#### Huawei 交换机配置示例

```huawei
# 创建镜像会话
observe-port 1 interface GigabitEthernet 0/0/24

# 配置被监控端口
interface GigabitEthernet 0/0/1
  port-mirroring to observe-port 1 both
```

#### H3C 交换机配置示例

```h3c
# 创建镜像组
mirroring-group 1 local

# 配置监控端口
mirroring-group 1 mirroring-port GigabitEthernet 1/0/24 both

# 配置被监控端口
mirroring-group 1 monitor-port GigabitEthernet 1/0/1
```

### 验证端口镜像配置

在服务器上验证是否接收到镜像流量：

```bash
# 在配置脚本之前，先检查是否有流量
sudo tcpdump -i eth1 -c 10 -n

# 如果看到数据包，说明镜像配置正确
# 如果没有数据包，检查：
# 1. 交换机配置是否正确
# 2. 网线是否连接
# 3. 被监控端口是否有流量
```

### 服务器网卡配置

#### 识别网卡接口

```bash
# 列出所有网络接口
ip link show

# 查看接口详细信息
ip addr show

# 查看接口统计
ip -s link show eth1
```

#### 确认镜像端口

镜像端口的特征：
- 通常没有配置 IP 地址
- 物理连接状态为 UP
- 只接收流量，不发送流量

```bash
# 检查接口是否配置了 IP
ip addr show eth1

# 如果配置了 IP，这可能不是镜像端口
# 镜像端口示例：
# 2: eth1: <BROADCAST,MULTICAST,UP,LOWER_UP>
#     link/ether 00:1a:2b:3c:4d:5e brd ff:ff:ff:ff:ff:ff
#     (注意：没有 inet 地址)
```

### 网卡配置最佳实践

#### 1. 专用镜像接口

```bash
# 确保镜像接口不用于其他用途
# 不要在镜像接口上配置 IP 地址
# 不要在镜像接口上运行其他服务
```

#### 2. 多接口配置

如果有多个镜像端口，可以同时配置：

```bash
sudo ./scripts/setup-env.sh --mode prod --interface eth1,eth2,eth3
```

这适用于：
- 监控多个交换机端口
- 高流量场景的负载分担
- 不同网段的流量隔离

#### 3. 网卡命名规范

不同系统的网卡命名规则：

| 系统 | 命名规则 | 示例 |
|------|----------|------|
| 传统命名 | ethX | eth0, eth1, eth2 |
| 一致性命名（CentOS 7+） | enpXsY | enp0s3, enp2s0 |
| 一致性命名（Ubuntu） | ensX | ens33, ens192 |
| 虚拟网卡 | vethX | veth0, veth1 |

```bash
# 如果使用一致性命名
sudo ./scripts/setup-env.sh --mode prod --interface enp2s0
```

## 系统优化

### 内核参数优化

脚本会自动优化以下内核参数以提高网络抓包性能：

#### 网络缓冲区优化

```bash
# 增加接收缓冲区（128MB）
net.core.rmem_max = 134217728
net.core.rmem_default = 67108864

# 增加发送缓冲区（128MB）
net.core.wmem_max = 134217728
net.core.wmem_default = 67108864

# 增加接收队列长度
net.core.netdev_max_backlog = 300000
```

#### TCP 缓冲区优化

```bash
# TCP 接收缓冲区 (min, default, max)
net.ipv4.tcp_rmem = 4096 87380 134217728

# TCP 发送缓冲区 (min, default, max)
net.ipv4.tcp_wmem = 4096 65536 134217728

# TCP 内存分配
net.ipv4.tcp_mem = 786432 1048576 26777216
```

#### 文件描述符限制

```bash
# 系统级文件描述符限制
fs.file-max = 2097152

# 进程级限制（写入 /etc/security/limits.conf）
* soft nofile 65536
* hard nofile 65536
```

#### 连接优化

```bash
# 减少 TIME_WAIT 时间
net.ipv4.tcp_fin_timeout = 15

# 允许 TIME_WAIT 套接字重用
net.ipv4.tcp_tw_reuse = 1
```

### 持久化配置

系统参数会自动持久化到配置文件：

```bash
# 配置文件位置
/etc/sysctl.d/99-traffic-replayer.conf

# 查看配置
cat /etc/sysctl.d/99-traffic-replayer.conf

# 手动应用配置
sudo sysctl -p /etc/sysctl.d/99-traffic-replayer.conf
```

### 网卡硬件优化

#### 禁用卸载功能

脚本会自动禁用以下网卡卸载功能以提高抓包准确性：

```bash
# RX/TX checksumming
ethtool -K eth1 rx off tx off

# Scatter-gather
ethtool -K eth1 sg off

# TCP Segmentation Offload
ethtool -K eth1 tso off

# Generic Segmentation Offload
ethtool -K eth1 gso off

# Generic Receive Offload
ethtool -K eth1 gro off

# Large Receive Offload
ethtool -K eth1 lro off

# VLAN offloading
ethtool -K eth1 rxvlan off txvlan off
```

#### 增大环形缓冲区

```bash
# 将接收环形缓冲区设置为最大值
ethtool -G eth1 rx 4096

# 查看当前设置
ethtool -g eth1
```

### 验证系统优化

```bash
# 检查内核参数
sysctl -a | grep -E 'net.core|net.ipv4.tcp|fs.file-max'

# 检查网卡配置
ethtool -k eth1 | grep -E 'rx-|tx-|offload'

# 检查环形缓冲区
ethtool -g eth1

# 或使用健康检查
sudo ./scripts/setup-env.sh --health-check --interface eth1
```

## 集成测试

### 配置流程

#### 步骤 1：配置服务器环境

```bash
# 配置镜像端口
sudo ./scripts/setup-env.sh --mode prod --interface eth1
```

#### 步骤 2：配置流量采集分析系统

根据流量采集分析系统的配置要求，指定监听接口：

```bash
# 示例：启动流量采集分析系统监听 eth1
sudo XXX --interface eth1
```

#### 步骤 3：验证流量采集

```bash
# 方法 1：使用 tcpdump 验证
sudo tcpdump -i eth1 -c 100 -n

# 方法 2：检查流量采集分析系统日志
sudo tail -f xxx.log

# 方法 3：使用健康检查
sudo ./scripts/setup-env.sh --health-check --interface eth1
```

### 常见集成问题

#### 问题 1：流量采集分析系统未收到流量

**排查步骤**：

```bash
# 1. 检查接口状态
ip link show eth1
# 确保状态为 UP，且有 PROMISC 标志

# 2. 验证交换机镜像配置
sudo tcpdump -i eth1 -c 10
# 如果看不到数据包，检查交换机配置

# 3. 检查流量采集分析系统进程
ps aux | grep XXX

# 4. 查看流量采集分析系统日志
sudo journalctl -u XXX -f
```

#### 问题 2：丢包严重

**可能原因**：
- 系统资源不足
- 内核参数未优化
- 网卡缓冲区过小

**解决方法**：

```bash
# 1. 检查系统资源
top
free -h
df -h

# 2. 确认已执行系统优化
sudo ./scripts/setup-env.sh --mode prod --interface eth1

# 3. 检查网卡统计
ethtool -S eth1 | grep -E 'drop|error'
```

#### 问题 3：性能不足

**优化建议**：

```bash
# 1. 使用多队列网卡
ethtool -l eth1

# 2. 绑定流量采集分析系统进程到 CPU
taskset -c 0-3 XXX --interface eth1

# 3. 启用 RSS/RPS
echo f > /sys/class/net/eth1/queues/rx-0/rps_cpus

# 4. 考虑使用 DPDK（如果流量采集分析系统支持）
```

## 监控与维护

### 健康检查

定期运行健康检查以确保系统正常运行：

```bash
# 手动健康检查
sudo ./scripts/setup-env.sh --health-check --interface eth1
```

**检查项目**：
- 网卡状态（UP/DOWN）
- 混杂模式是否启用
- 流量统计（5 秒采样）
- 丢包统计
- 系统资源（CPU、内存、磁盘）
- 内核参数配置

### 定期监控

#### 创建监控脚本

```bash
# 创建监控脚本
sudo tee /usr/local/bin/check-mirror-port.sh > /dev/null <<'EOF'
#!/bin/bash
INTERFACE="eth1"
LOG_FILE="/var/log/traffic-replayer/health-check.log"

mkdir -p $(dirname "$LOG_FILE")
echo "[$(date)] 开始健康检查" >> "$LOG_FILE"

# 检查接口状态
if ! ip link show "$INTERFACE" | grep -q "state UP"; then
    echo "[$(date)] 警告: 接口 $INTERFACE 未启动" >> "$LOG_FILE"
fi

# 检查混杂模式
if ! ip link show "$INTERFACE" | grep -q "PROMISC"; then
    echo "[$(date)] 警告: 接口 $INTERFACE 混杂模式未启用" >> "$LOG_FILE"
fi

# 检查丢包
RX_DROPPED=$(cat /sys/class/net/"$INTERFACE"/statistics/rx_dropped)
if [ $RX_DROPPED -gt 1000 ]; then
    echo "[$(date)] 警告: 接口 $INTERFACE 丢包数: $RX_DROPPED" >> "$LOG_FILE"
fi

echo "[$(date)] 健康检查完成" >> "$LOG_FILE"
EOF

sudo chmod +x /usr/local/bin/check-mirror-port.sh
```

#### 配置定时任务

```bash
# 添加 cron 任务，每小时执行一次
sudo crontab -e

# 添加以下行
0 * * * * /usr/local/bin/check-mirror-port.sh
```

### 日志管理

```bash
# 查看健康检查日志
sudo tail -f /var/log/traffic-replayer/health-check.log

# 配置日志轮转
sudo tee /etc/logrotate.d/traffic-replayer > /dev/null <<'EOF'
/var/log/traffic-replayer/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 0644 root root
}
EOF
```

### 性能监控

#### 网卡性能监控

```bash
# 实时监控网卡流量
watch -n 1 'ip -s link show eth1'

# 使用 iftop（需要安装）
sudo iftop -i eth1

# 使用 nload（需要安装）
sudo nload eth1
```

#### 系统性能监控

```bash
# CPU 使用率
top -bn1 | head -20

# 内存使用
free -h

# 磁盘 IO
iostat -x 1 5

# 网络统计
netstat -s | grep -E 'packet|error|drop'
```

## 故障排查

### 问题 1：接口配置失败

**错误信息**：
```
[ERROR] 网络接口 eth1 不存在
```

**解决方法**：
```bash
# 1. 列出所有接口
ip link show

# 2. 确认接口名称是否正确
# 3. 检查网线是否连接
# 4. 检查驱动是否加载
lsmod | grep -E 'e1000|igb|ixgbe'
```

### 问题 2：权限不足

**错误信息**：
```
[ERROR] 此脚本需要 root 权限，请使用 sudo 运行
```

**解决方法**：
```bash
sudo ./scripts/setup-env.sh --mode prod --interface eth1
```

### 问题 3：混杂模式未启用

**错误信息**：
```
[ERROR] 混杂模式未正确启用
```

**解决方法**：
```bash
# 手动启用混杂模式
sudo ip link set eth1 promisc on

# 验证
ip link show eth1 | grep PROMISC

# 如果仍然失败，可能是驱动或硬件限制
# 检查网卡是否支持混杂模式
ethtool eth1
```

### 问题 4：系统参数设置失败

**错误信息**：
```
[WARN] 设置 net.core.rmem_max 失败
```

**可能原因**：
- 参数名称错误或不存在
- 内核版本不支持该参数
- SELinux 或 AppArmor 限制

**解决方法**：
```bash
# 1. 检查参数是否存在
sysctl -a | grep net.core.rmem_max

# 2. 临时禁用 SELinux（测试用）
sudo setenforce 0

# 3. 手动设置参数
sudo sysctl -w net.core.rmem_max=134217728

# 4. 如果某些参数不支持，可以跳过系统优化
sudo ./scripts/setup-env.sh --mode prod --interface eth1 --skip-system-tuning
```

### 问题 5：接口已配置 IP 地址

**警告信息**：
```
[WARN] 警告: 接口 eth1 已配置 IP 地址，这可能不是镜像端口
```

**说明**：
镜像端口通常不应该配置 IP 地址。如果看到此警告：

```bash
# 1. 确认这是否是镜像端口
ip addr show eth1

# 2. 如果确认是镜像端口但误配置了 IP，删除 IP
sudo ip addr del <IP 地址>/24 dev eth1

# 3. 如果不是镜像端口，使用正确的接口名
sudo ./scripts/setup-env.sh --mode prod --interface eth2
```

### 问题 6：网卡驱动不支持某些功能

**警告信息**：
```
[DEBUG] 禁用 lro 失败（可能不支持）
```

**说明**：
某些网卡或虚拟网卡不支持部分卸载功能，这是正常的。脚本会尝试禁用所有功能，失败的会被记录但不影响整体配置。

### 问题 7：无法创建备份

**错误信息**：
```
[WARN] 未安装 jq，备份功能受限
```

**解决方法**：
```bash
# 安装 jq
# Ubuntu/Debian
sudo apt-get install -y jq

# CentOS/RHEL
sudo yum install -y jq

# 重新运行配置
sudo ./scripts/setup-env.sh --mode prod --interface eth1
```

### 问题 8：恢复配置失败

**错误信息**：
```
[ERROR] 备份文件不存在
```

**解决方法**：
```bash
# 1. 列出所有可用备份
sudo ./scripts/setup-env.sh --list-backups

# 2. 使用正确的备份文件路径
sudo ./scripts/setup-env.sh --restore /var/lib/traffic-replayer/backups/config_backup_20260128_143022.json

# 3. 如果没有备份，重新配置
sudo ./scripts/setup-env.sh --mode prod --interface eth1
```

### 问题 9：健康检查发现问题

**示例输出**：
```
[WARN] 发现 3 个问题，请检查上述警告信息
```

**处理步骤**：
```bash
# 1. 查看详细输出，识别具体问题
sudo ./scripts/setup-env.sh --health-check --interface eth1

# 2. 根据警告信息逐个解决
# 例如：链路状态 DOWN
sudo ip link set eth1 up

# 例如：混杂模式未启用
sudo ip link set eth1 promisc on

# 例如：丢包严重
# 检查系统资源和网卡配置
ethtool -S eth1 | grep drop

# 3. 重新运行健康检查验证
sudo ./scripts/setup-env.sh --health-check --interface eth1
```

### 问题 10：预览模式看不到具体操作

**解决方法**：
```bash
# 使用 --debug 参数查看详细信息
sudo ./scripts/setup-env.sh --mode prod --interface eth1 --dry-run --debug
```

## 附录

### A. 完整部署示例

#### 场景 1：单接口部署

```bash
# 步骤 1：确认交换机已配置端口镜像
# (在交换机上配置)

# 步骤 2：验证流量
sudo tcpdump -i eth1 -c 10

# 步骤 3：配置服务器
sudo ./scripts/setup-env.sh --mode prod --interface eth1

# 步骤 4：验证配置
sudo ./scripts/setup-env.sh --health-check --interface eth1

# 步骤 5：启动流量采集分析系统
sudo XXX --interface eth1

# 步骤 6：验证流量采集分析系统工作正常
sudo tail -f xxx.log
```

#### 场景 3：测试环境部署

```bash
# 步骤 1：配置测试环境
sudo ./scripts/setup-env.sh --mode test

# 步骤 2：运行测试
sudo ./scripts/remote-test.sh

# 步骤 3：清理环境
sudo ./scripts/setup-env.sh --cleanup
```

### B. 配置检查清单

部署前检查：
- [ ] 交换机端口镜像已配置
- [ ] 服务器硬件满足要求
- [ ] 操作系统版本符合要求
- [ ] 必需软件包已安装
- [ ] 确认镜像端口名称
- [ ] 网线已正确连接

部署后验证：
- [ ] 网卡状态为 UP
- [ ] 混杂模式已启用
- [ ] 能够捕获镜像流量
- [ ] 系统参数已优化
- [ ] 配置已持久化
- [ ] 备份已创建
- [ ] Deeptrace 正常工作
- [ ] 健康检查通过

### C. 性能调优建议

#### 高流量场景（>1Gbps）

```bash
# 1. 使用多队列网卡
# 检查网卡队列数
ethtool -l eth1

# 2. 启用 IRQ 亲和性
# 绑定网卡中断到特定 CPU
echo 1 > /proc/irq/<IRQ>/smp_affinity

# 3. 增加网卡缓冲区
sudo ethtool -G eth1 rx 4096 tx 4096

# 4. 禁用节能功能
sudo ethtool -C eth1 rx-usecs 0

# 5. 增加系统缓冲区
sudo sysctl -w net.core.rmem_max=268435456
sudo sysctl -w net.core.netdev_max_backlog=500000
```

#### 超高流量场景（>10Gbps）

考虑使用：
- DPDK（Data Plane Development Kit）
- AF_XDP（高性能数据包处理）
- 专用硬件加速
- 多服务器负载均衡

### D. 安全建议

```bash
# 1. 限制配置脚本执行权限
sudo chmod 750 ./scripts/setup-env.sh
sudo chown root:root ./scripts/setup-env.sh

# 2. 保护备份文件
sudo chmod 700 /var/lib/traffic-replayer/backups
sudo chown root:root /var/lib/traffic-replayer/backups

# 3. 限制日志文件访��
sudo chmod 640 /var/log/traffic-replayer/*.log

# 4. 使用防火墙保护监控服务器
# 只允许必要的管理端口
sudo ufw allow 22/tcp
sudo ufw enable

# 5. 定期更新系统
sudo apt-get update && sudo apt-get upgrade
```

### E. 常用命令速查

```bash
# 配置生产环境
sudo ./scripts/setup-env.sh --mode prod --interface eth1

# 健康检查
sudo ./scripts/setup-env.sh --health-check --interface eth1

# 列出备份
sudo ./scripts/setup-env.sh --list-backups

# 恢复配置
sudo ./scripts/setup-env.sh --restore

# 查看网卡状态
ip link show eth1
ip -s link show eth1

# 查看内核参数
sysctl -a | grep net.core

# 查看网卡配置
ethtool eth1
ethtool -k eth1
ethtool -g eth1
ethtool -S eth1

# 监控流量
sudo tcpdump -i eth1 -n
sudo iftop -i eth1

# 查看丢包统计
netstat -s | grep -E 'packet|drop|error'
cat /sys/class/net/eth1/statistics/rx_dropped
```

### F. 参考资料

- [Linux 网络性能优化指南](https://www.kernel.org/doc/Documentation/networking/scaling.txt)
- [ethtool 使用手册](https://www.kernel.org/pub/software/network/ethtool/)
- [sysctl 参数说明](https://www.kernel.org/doc/Documentation/sysctl/)
- 交换机端口镜像配置：参考交换机厂商文档