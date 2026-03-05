package main

import (
	"fmt"
	"log"

	"github.com/gyyyy/traffic-replayer/replayer"
	"github.com/spf13/cobra"
)

var (
	// mock 命令参数
	mockIface   string // 网络接口
	mockSrcIP   string // 源 IP 地址
	mockDstIP   string // 目标 IP 地址
	mockSrcMAC  string // 源 MAC 地址（可选）
	mockDstMAC  string // 目标 MAC 地址（可选）
	mockType    string // 测试类型：http, ping, arp, all
	mockURI     string // 自定义 URI（可选，支持*占位符）
	mockCount   int    // 重复次数
	mockVerbose bool   // 启用详细输出
)

// parseMACAddress 解析 MAC 地址
func parseMACAddress(mac string) ([]byte, error) {
	var b [6]byte
	_, err := fmt.Sscanf(mac, "%02x:%02x:%02x:%02x:%02x:%02x", &b[0], &b[1], &b[2], &b[3], &b[4], &b[5])
	if err != nil {
		return nil, fmt.Errorf("无效的 MAC 地址: %s", mac)
	}
	return b[:], nil
}

// sendARPMock 发送 ARP 测试流量
func sendARPMock(injector *replayer.Injector) error {
	if mockVerbose {
		log.Println("生成 ARP 测试流量...")
	}
	srcMAC, err := parseMACAddress(mockSrcMAC)
	if err != nil {
		return err
	}
	dstMAC, err := parseMACAddress(mockDstMAC)
	if err != nil {
		return err
	}
	// 生成 ARP 数据包
	packets, err := replayer.GenerateARPPackets(mockSrcIP, mockDstIP, srcMAC, dstMAC)
	if err != nil {
		return fmt.Errorf("生成 ARP 数据包失败: %v", err)
	}
	if mockVerbose {
		log.Printf("生成了 %d 个数据包", len(packets))
		fmt.Println("\n数据包详情:")
		fmt.Println("  1. ARP Request (ARP 请求)")
		fmt.Println("  2. ARP Reply (ARP 响应)")
		fmt.Println()
		log.Println("发送数据包...")
	}
	// 发送数据包
	stats := injector.Inject(packets, 1.0)
	if mockVerbose {
		// 显示统计信息
		fmt.Println()
		fmt.Println("================ ARP 模拟测试统计 ================")
		fmt.Printf("  发送包数:     %d\n", stats.PacketsSent)
		fmt.Printf("  发送字节数:   %d\n", stats.BytesSent)
		fmt.Printf("  失败包数:     %d\n", stats.PacketsFailed)
		fmt.Printf("  持续时间:     %s\n", stats.Duration)
		fmt.Println()
	}
	if stats.PacketsFailed > 0 {
		return fmt.Errorf("有 %d 个数据包发送失败", stats.PacketsFailed)
	}
	return nil
}

// sendPingMock 发送 Ping 测试流量
func sendPingMock(injector *replayer.Injector) error {
	if mockVerbose {
		log.Println("生成 ICMP Ping 测试流量...")
	}
	srcMAC, err := parseMACAddress(mockSrcMAC)
	if err != nil {
		return err
	}
	dstMAC, err := parseMACAddress(mockDstMAC)
	if err != nil {
		return err
	}
	// 生成 ICMP 数据包
	packets, err := replayer.GenerateICMPPing(mockSrcIP, mockDstIP, srcMAC, dstMAC)
	if err != nil {
		return fmt.Errorf("生成 ICMP 数据包失败: %v", err)
	}
	if mockVerbose {
		log.Printf("生成了 %d 个数据包", len(packets))
		fmt.Println("\n数据包详情:")
		fmt.Println("  1. ICMP Echo Request (Ping 请求)")
		fmt.Println("  2. ICMP Echo Reply (Ping 响应)")
		fmt.Println()
		log.Println("发送数据包...")
	}
	// 发送数据包
	stats := injector.Inject(packets, 1.0)
	if mockVerbose {
		// 显示统计信息
		fmt.Println()
		fmt.Println("================ Ping 模拟测试统计 ================")
		fmt.Printf("  发送包数:     %d\n", stats.PacketsSent)
		fmt.Printf("  发送字节数:   %d\n", stats.BytesSent)
		fmt.Printf("  失败包数:     %d\n", stats.PacketsFailed)
		fmt.Printf("  持续时间:     %s\n", stats.Duration)
		fmt.Println()
	}
	if stats.PacketsFailed > 0 {
		return fmt.Errorf("有 %d 个数据包发送失败", stats.PacketsFailed)
	}
	return nil
}

// sendHTTPMock 发送 HTTP 测试流量
func sendHTTPMock(injector *replayer.Injector, srcPort uint16) error {
	if mockVerbose {
		log.Println("生成 HTTP 测试流量...")
	}
	// 创建 HTTP 测试生成器
	gen, err := replayer.NewHTTPTestGenerator(mockSrcIP, mockDstIP, mockSrcMAC, mockDstMAC, mockURI, srcPort)
	if err != nil {
		return fmt.Errorf("创建 HTTP 生成器失败: %v", err)
	}
	// 生成数据包
	packets, err := gen.GeneratePackets()
	if err != nil {
		return fmt.Errorf("生成 HTTP 数据包失败: %v", err)
	}
	if mockVerbose {
		log.Printf("生成了 %d 个数据包", len(packets))
		fmt.Println("\n数据包详情:")
		fmt.Println("  1. TCP SYN (三次握手 - 第 1 步)")
		fmt.Println("  2. TCP SYN-ACK (三次握手 - 第 2 步)")
		fmt.Println("  3. TCP ACK (三次握手 - 第 3 步)")
		fmt.Println("  4. HTTP 请求 (PSH+ACK)")
		fmt.Println("  5. HTTP 请求确认 (ACK)")
		fmt.Println("  6. HTTP 响应 (PSH+ACK)")
		fmt.Println("  7. HTTP 响应确认 (ACK)")
		fmt.Println("  8. TCP FIN (四次挥手 - 第 1 步)")
		fmt.Println("  9. TCP ACK (四次挥手 - 第 2 步)")
		fmt.Println("  10. TCP FIN (四次挥手 - 第 3 步)")
		fmt.Println("  11. TCP ACK (四次挥手 - 第 4 步)")
		fmt.Println()
		log.Println("发送数据包...")
	}
	// 发送数据包
	stats := injector.Inject(packets, 1.0)
	if mockVerbose {
		// 显示统计信息
		fmt.Println()
		fmt.Println("================ HTTP 模拟测试统计 ================")
		fmt.Printf("  发送包数:     %d\n", stats.PacketsSent)
		fmt.Printf("  发送字节数:   %d\n", stats.BytesSent)
		fmt.Printf("  失败包数:     %d\n", stats.PacketsFailed)
		fmt.Printf("  持续时间:     %s\n", stats.Duration)
		fmt.Println()
	}
	if stats.PacketsFailed > 0 {
		return fmt.Errorf("有 %d 个数据包发送失败", stats.PacketsFailed)
	}
	return nil
}

// runMock mock 命令执行函数
func runMock(cmd *cobra.Command, args []string) {
	// 若未指定 MAC，提前随机生成，保证同一次运行中所有模式 MAC 一致
	if mockSrcMAC == "" {
		mockSrcMAC = replayer.RandomMAC().String()
	}
	if mockDstMAC == "" {
		mockDstMAC = replayer.RandomMAC().String()
	}
	if mockVerbose {
		fmt.Println()
		fmt.Println("================ 模拟测试配置 ================")
		fmt.Printf("模拟流量模式:          %s\n", mockType)
		fmt.Printf("源 IP:               %s\n", mockSrcIP)
		fmt.Printf("源 MAC:              %s\n", mockSrcMAC)
		fmt.Printf("目标 IP:             %s\n", mockDstIP)
		fmt.Printf("目标 MAC:            %s\n", mockDstMAC)
		fmt.Printf("重复次数:             %d\n", mockCount)
		fmt.Println()
	}
	// 创建注入器
	injector, err := replayer.NewInjector(mockIface)
	if err != nil {
		log.Fatalf("创建注入器失败: %v", err)
	}
	defer injector.Close()
	// 固定 HTTP src port，保证重复多轮时流量特征一致
	httpSrcPort := replayer.RandomPort()
	// 根据模式生成数据包
	for i := 0; i < mockCount; i++ {
		if mockCount > 1 && mockVerbose {
			fmt.Printf("\n---------- 第 %d/%d 次测试 ----------\n", i+1, mockCount)
		}
		switch mockType {
		case "arp":
			if err := sendARPMock(injector); err != nil {
				log.Fatalf("ARP 测试失败: %v", err)
			}
		case "ping":
			if err := sendPingMock(injector); err != nil {
				log.Fatalf("Ping 测试失败: %v", err)
			}
		case "http":
			if err := sendHTTPMock(injector, httpSrcPort); err != nil {
				log.Fatalf("HTTP 测试失败: %v", err)
			}
		case "all":
			if err := sendARPMock(injector); err != nil {
				log.Printf("ARP 测试失败: %v", err)
			}
			if err := sendPingMock(injector); err != nil {
				log.Printf("Ping 测试失败: %v", err)
			}
			if err := sendHTTPMock(injector, httpSrcPort); err != nil {
				log.Printf("HTTP 测试失败: %v", err)
			}
		default:
			log.Fatalf("未知的测试类型: %s (支持: http, ping, arp, all)", mockType)
		}
	}
	if mockVerbose {
		log.Println("模拟测试完成！")
	}
}

// NewMockCommand 创建 mock 子命令
func NewMockCommand() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "mock",
		Short: "模拟流量模式 - 生成并发送模拟测试流量",
		Long: `模拟流量模式：生成完整的网络测试流量并发送到指定接口。

支持生成包括 ARP、ICMP Ping、完整 HTTP 会话（TCP 握手、HTTP 请求/响应、TCP 挥手）等流量。

测试类型：
  http  - 完整的 HTTP 会话（TCP 三次握手 + HTTP 请求/响应 + TCP 四次挥手）
  ping  - ICMP Ping（Echo Request + Echo Reply）
  arp   - ARP解析（ARP Request + ARP Reply）
  all   - 所有测试（ARP + Ping + HTTP）

示例:
  ./traffic-replayer mock --iface en0 --src-ip 192.168.1.100 --dst-ip 192.168.1.200
  ./traffic-replayer mock --iface en0 --src-ip 10.0.0.10 --dst-ip 10.0.0.20 --type http
  ./traffic-replayer mock --iface en0 --src-ip 192.168.1.100 --dst-ip 192.168.1.200 --uri "/api/users?id=*"
  ./traffic-replayer mock --iface en0 --src-ip 192.168.1.100 --dst-ip 192.168.1.200 --type all --count 10`,
		Run: runMock,
	}
	// 必需参数
	cmd.Flags().StringVarP(&mockIface, "iface", "i", "", "发送数据包的网络接口 (必需)")
	cmd.MarkFlagRequired("iface")
	cmd.Flags().StringVar(&mockSrcIP, "src-ip", "", "源 IP 地址 (必需)")
	cmd.MarkFlagRequired("src-ip")
	cmd.Flags().StringVar(&mockDstIP, "dst-ip", "", "目标 IP 地址 (必需)")
	cmd.MarkFlagRequired("dst-ip")
	// 可选参数
	cmd.Flags().StringVar(&mockSrcMAC, "src-mac", "", "源 MAC 地址 (可选，默认随机生成)")
	cmd.Flags().StringVar(&mockDstMAC, "dst-mac", "", "目标 MAC 地址 (可选，默认随机生成)")
	cmd.Flags().StringVarP(&mockType, "type", "t", "http", "测试类型: http, ping, arp, all (默认: http)")
	cmd.Flags().StringVar(&mockURI, "uri", "", "自定义 HTTP 请求 URI (支持*占位符随机生成, 例如: /admin?id=*)")
	cmd.Flags().IntVarP(&mockCount, "count", "c", 1, "重复发送次数 (默认: 1)")
	// 其他参数
	cmd.Flags().BoolVarP(&mockVerbose, "verbose", "v", false, "启用详细输出")
	return cmd
}
