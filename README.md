# Traffic Replayer

Traffic Replayer 是一个网络流量回放工具，可从 PCAP 文件中读取并回放网络流量。

该工具支持流量速度调整、地址重写、流量生成、性能测试等功能，主要适用于网络测试、性能分析和流量采集分析系统的模拟联调验证（例如无镜像流量测试条件的环境）。

## 主要特性

- **流量回放**：支持原速或指定倍速回放 PCAP 文件
- **地址重写**：支持将流量的源/目标地址重写到指定 CIDR 网段，或是指定 MAC、IP 及端口
- **流量生成**：可生成完整的 HTTP 会话流量（TCP 握手、HTTP 请求/响应、TCP 挥手）、ICMP Ping、ARP 等测试流量
- **性能测试**：支持高频循环重放、并发控制、速率限制，用于测试网口和流量采集分析系统的性能
- **灵活部署**：支持本地 Docker 测试和远程服务器部署
- **生产就绪**：包含完整的系统优化和监控方案

## 命令结构

工具采用子命令模式，支持以下四种模式：

- `replay` - 重放模式：从 PCAP 文件重放网络流量
- `mock` - 模拟流量模式：生成并发送测试流量（HTTP、ICMP、ARP 等）
- `perf` - 性能测试模式：测试网口或流量采集系统的性能
- `web` - Web 模式：提供 Web 操作界面实现简化模拟流量测试

## 快速开始

### 1. 流量重放模式 (replay)

从 PCAP 文件重放网络流量：

```bash
# 基本用法
sudo ./traffic-replayer replay --file capture.pcap --iface en0

# 查看 PCAP 文件统计信息
./traffic-replayer replay --file capture.pcap --stats

# 2 倍速回放
sudo ./traffic-replayer replay --file capture.pcap --iface en0 --speed 2.0

# 重写 IP 地址
sudo ./traffic-replayer replay --file capture.pcap --iface en0 \
  --src-ip 192.168.1.100 --dst-ip 192.168.1.200

# 重写到指定 CIDR 网段（随机地址映射）
sudo ./traffic-replayer replay --file capture.pcap --iface en0 \
  --cidr 192.168.1.0/24

# 启用详细日志
sudo ./traffic-replayer replay --file capture.pcap --iface en0 --verbose
```

### 2. 模拟流量模式 (mock)

生成并发送测试流量（从网络层开始构建完整会话）：

```bash
# 生成完整的 HTTP 会话流量（TCP 握手 + HTTP 请求/响应 + TCP 挥手）
sudo ./traffic-replayer mock --iface en0 \
  --src-ip 192.168.1.100 --dst-ip 192.168.1.200

# 指定 MAC 地址
sudo ./traffic-replayer mock --iface en0 \
  --src-ip 192.168.1.100 --dst-ip 192.168.1.200 \
  --src-mac 00:11:22:33:44:55 --dst-mac 00:aa:bb:cc:dd:ee

# 自定义 HTTP 请求 URI（支持*占位符随机生成）
sudo ./traffic-replayer mock --iface en0 \
  --src-ip 192.168.1.100 --dst-ip 192.168.1.200 \
  --uri "/admin?id=*&t=*"

# 生成其他类型测试流量，支持 http/ping/arp/all（默认 http） 
sudo ./traffic-replayer mock --iface en0 \
  --src-ip 192.168.1.100 --dst-ip 192.168.1.200 --type ping

# 重复发送 10 次
sudo ./traffic-replayer mock --iface en0 \
  --src-ip 192.168.1.100 --dst-ip 192.168.1.200 --count 10
```

### 3. 性能测试模式 (perf)

对目标网口或流量采集系统进行性能测试：

```bash
# 基础性能测试（持续 30 秒）
sudo ./traffic-replayer perf --file capture.pcap --iface en0 --duration 30s

# 高并发压力测试（10 并发，持续 1 分钟）
sudo ./traffic-replayer perf --file capture.pcap --iface en0 \
  --duration 1m --concurrency 10

# 速率限制测试（10000 PPS）
sudo ./traffic-replayer perf --file capture.pcap --iface en0 \
  --duration 1m --pps 10000

# 循环重放 100 次，每 2 秒显示统计信息
sudo ./traffic-replayer perf --file capture.pcap --iface en0 \
  --loops 100 --concurrency 5 --stats-interval 2s

# 忽略时间戳，以最高速度发送
sudo ./traffic-replayer perf --file capture.pcap --iface en0 \
  --duration 30s --ignore-timestamp
```

### 4. Web 模式 (web)

启动本地 HTTP 服务，提供 Web 界面进行模拟流量测试和日志实时监控：

```bash
# 启动 Web 控制台（默认监听 :18080）
sudo ./traffic-replayer web

# 指定监听地址和端口
sudo ./traffic-replayer web --addr :9090
sudo ./traffic-replayer web --addr 0.0.0.0:18080
```

启动后访问 `http://localhost:18080`，可通过界面完成：

- **模拟流量发送**：填写网卡、流量类型（ARP / ICMP / HTTP / All）、源和目的 IP、自定义 URI，以及发送次数，点击发送后实时展示每个数据包说明和统计结果
- **日志实时监控**：输入任意日志文件路径（如流量采集分析系统的输出日志），以 SSE 方式实时追尾新增内容（以只读方式打开文件，不影响写入方），并支持向上翻页查看历史记录

## 编译

### 使用 Makefile

```bash
# 编译
make build

# 编译并运行测试
make test

# 清理
make clean
```

### 手动编译

```bash
# 编译
go build -o bin/traffic-replayer ./cmd
```

## 工作原理

### 核心机制

工具基于 [gopacket](https://github.com/google/gopacket) 库，通过 libpcap 在链路层直接读写原始数据包：

1. **读取**：使用 `pcap.OpenOffline` 打开 PCAP/PCAPNG 文件，按原始字节序读取每个数据帧（含以太网帧头），不经过内核协议栈解析
2. **时序控制**：根据相邻数据包的时间戳差值计算延迟，配合速率倍数 `delay / multiplier` 还原原始发包节奏；最小间隔 500µs，最大 5s，防止异常时间戳导致长时间阻塞
3. **注入**：使用 `pcap.OpenLive` 以混杂模式打开目标网卡，调用 `WritePacketData` 在链路层直接注入原始帧，绕过内核 TCP/IP 协议栈
4. **地址重写**：在注入前通过拦截器链（Interceptor Chain）就地修改帧内容，支持改写 MAC、IPv4/IPv6 地址、TCP/UDP 端口，以及按 CIDR 网段做随机地址映射；校验和由各层重写器同步更新

### 本地测试

Docker 容器内自带一对以太网接口（`eth0` + 容器网桥），利用 Docker 网络的 **veth 对** 原理，`traffic-replayer` 向容器内网卡注入数据帧，帧经过内核虚拟网桥转发后可被同容器内的 `tcpdump` 等工具捕获，全程无需物理网卡。测试完成后统计发送帧数与捕获帧数之差来判定测试是否通过。

```
PCAP 文件 ─ 读取 ─> traffic-replayer ─ WritePacketData ─> 容器网卡
                                                      ↓ 内核转发
                                                tcpdump 捕获验证
```

### 远程测试

`setup-env.sh --mode test` 在 Linux 宿主机上通过 `ip link add veth0 type veth peer name veth1` 创建一对虚拟以太网接口（**veth 对**）。veth 对是内核提供的全双工虚拟网线，写入一端的帧会立即从另一端读出，无需经过物理介质：

```
                              内核直连
traffic-replayer ─> veth0 ══════════════> veth1 ─> tcpdump
               (注入端，混杂模式)       (捕获端，混杂模式)
```

两个接口均启用**混杂模式**（`ip link set vethX promisc on`），使网卡接受所有帧而不过滤非本机 MAC，从而能捕获回放的任意源/目的地址的流量。

### 生产环境（混杂模式 + 端口镜像）

交换机的 **SPAN（端口镜像）** 将业务端口的流量副本转发到监控端口，监控服务器的物理网卡（如 `eth1`）接收镜像流量。`setup-env.sh --mode prod` 为该网卡开启混杂模式并调优内核参数（ring buffer、中断亲和性、NUMA 绑定等），使流量采集分析系统能在不影响业务的情况下零拷贝接收全量报文。

```
核心交换机 ─ SPAN 镜像 ─> eth1（混杂模式）─> 流量采集分析系统
                              ↑
                      setup-env.sh 配置
```

### 更多文档

- **[本地测试使用手册](docs/01_LOCAL_TESTING.md)** - 使用 Docker 进行本地测试的详细文档
- **[远程测试使用手册](docs/02_REMOTE_TESTING.md)** - 在 Linux 服务器上进行联调测试的详细文档
- **[生产环境配置手册](docs/03_PRODUCTION_SETUP.md)** - 生产环境部署和系统优化的详细文档

## 贡献指南

欢迎提交 Issue 和 Pull Request！

### 开发流程

1. Fork 本仓库
2. 创建特性分支：`git checkout -b feature/your-feature`
3. 提交更改：`git commit -am 'Add some feature'`
4. 推送分支：`git push origin feature/your-feature`
5. 提交 Pull Request

### 代码规范

- 遵循 Go 语言规范
- 使用 `gofmt` 格式化代码
- 添加必要的注释和文档
- 编写单元测试

## 许可证

MIT License

## 联系方式

如有问题或建议，请提交 Issue。