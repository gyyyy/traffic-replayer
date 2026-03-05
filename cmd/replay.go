package main

import (
	"fmt"
	"log"

	"github.com/gyyyy/traffic-replayer/replayer"
	"github.com/spf13/cobra"
)

// 时间格式
const timeLayout = "2006-01-02 15:04:05"

var (
	// replay 命令参数
	replayFile    string       // PCAP 文件路径
	replayIface   string       // 网络接口
	replaySpeed   float64      // 回放速度倍率
	replayRewrite rewriteFlags // 数据包重写参数
	replayStats   bool         // 显示 PCAP 文件统计信息
	replayVerbose bool         // 启用详细输出
)

// runReplay replay 命令执行函数
func runReplay(cmd *cobra.Command, args []string) {
	// 验证参数
	if replayIface == "" && !replayStats {
		log.Fatal("参数错误：必须指定 --iface 参数（除非使用 --stats 查看 PCAP 文件统计信息）")
	}
	if replayVerbose {
		log.Printf("正在加载 PCAP 文件: %s", replayFile)
	}
	// 创建重放器并加载数据包
	r := replayer.New()
	rdStats, err := r.LoadAll(replayFile, false)
	if err != nil {
		log.Fatalf("加载数据包失败: %v", err)
	}
	if replayStats {
		// 显示 PCAP 文件统计信息
		fmt.Println()
		fmt.Println("================ PCAP 文件统计信息 ================")
		fmt.Printf("  链路类型:              %s\n", rdStats.LinkType)
		fmt.Printf("  数据包数量:            %d\n", rdStats.Count)
		fmt.Printf("  总字节数:              %d\n", rdStats.TotalBytes)
		fmt.Println()
		return
	}
	if replayVerbose {
		log.Printf("已加载 %d 个数据包，链路类型: %s", rdStats.Count, rdStats.LinkType)
	}
	// 构建拦截器链（无重写参数时为 nil）
	chain := buildInterceptorChain(&replayRewrite)
	if replayVerbose {
		log.Println("开始重放数据包")
	}
	// 重放数据包
	rpStats, err := r.Replay(replayIface, replaySpeed, chain)
	if err != nil {
		log.Fatalf("重放数据包失败: %v", err)
	}
	if replayVerbose {
		log.Println("数据包重放完成")
		// 显示重放统计信息
		fmt.Println()
		fmt.Println("================ 重放统计信息 ================")
		fmt.Printf("  重放数据包数量:        %d\n", rpStats.PacketsSent)
		fmt.Printf("  重放总字节数:          %d\n", rpStats.BytesSent)
		fmt.Printf("  重放失败数据包数量:     %d\n", rpStats.PacketsFailed)
		fmt.Printf("  重放开始时间:          %s\n", rpStats.StartTime.Format(timeLayout))
		fmt.Printf("  重放结束时间:          %s\n", rpStats.EndTime.Format(timeLayout))
		fmt.Printf("  重放持续时间:          %s\n", rpStats.EndTime.Sub(rpStats.StartTime))
		fmt.Println()
	}
}

// NewReplayCommand 创建 replay 子命令
func NewReplayCommand() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "replay",
		Short: "重放模式 - 从 PCAP 文件重放网络流量",
		Long: `重放模式：从 PCAP 文件读取流量并在指定网络接口上重放。

支持速度控制、地址重写等功能。

示例:
  ./traffic-replayer replay --file capture.pcap --iface en0
  ./traffic-replayer replay --file capture.pcap --iface en0 --speed 2.0
  ./traffic-replayer replay --file capture.pcap --iface en0 --src-ip 192.168.1.100 --dst-ip 192.168.1.200`,
		Run: runReplay,
	}
	// 必需参数
	cmd.Flags().StringVarP(&replayFile, "file", "f", "", "PCAP 文件路径 (必需)")
	cmd.MarkFlagRequired("file")
	// 重放参数
	cmd.Flags().StringVarP(&replayIface, "iface", "i", "", "重放数据包的网络接口 (必需，但在使用 --stats 查看时可省略)")
	cmd.Flags().Float64VarP(&replaySpeed, "speed", "s", 1.0, "回放速度倍率 (原始速度=1.0)")
	// 拦截器参数
	addRewriteFlags(cmd, &replayRewrite)
	// 其他参数
	cmd.Flags().BoolVar(&replayStats, "stats", false, "显示 PCAP 文件统计信息")
	cmd.Flags().BoolVar(&replayStats, "info", false, "显示 PCAP 文件统计信息（别名）")
	cmd.Flags().BoolVarP(&replayVerbose, "verbose", "v", false, "启用详细输出")
	return cmd
}
