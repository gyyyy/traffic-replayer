package main

import (
	"fmt"
	"log"
	"time"

	"github.com/gyyyy/traffic-replayer/replayer"
	"github.com/gyyyy/traffic-replayer/replayer/pref"
	"github.com/spf13/cobra"
)

var (
	// perf 命令参数
	perfFile        string       // PCAP 文件路径
	perfIface       string       // 网络接口
	perfRewrite     rewriteFlags // 数据包重写参数（与 replay 共用 rewriteFlags）
	perfDuration    string       // 性能测试持续时间
	perfLoopCount   int          // 性能测试循环次数
	perfConcurrency int          // 性能测试并发数
	perfPPS         int64        // 性能测试包速率限制
	perfBPS         int64        // 性能测试带宽限制
	perfIgnoreTS    bool         // 性能测试忽略时间戳
	perfStatsInt    string       // 性能测试统计报告间隔
	perfVerbose     bool         // 启用详细输出
)

// runPerf perf 命令执行函数
func runPerf(cmd *cobra.Command, args []string) {
	if perfVerbose {
		log.Printf("正在加载 PCAP 文件: %s", perfFile)
	}
	// 创建重放器并加载数据包
	r := replayer.New()
	rdStats, err := r.LoadAll(perfFile, false)
	if err != nil {
		log.Fatalf("加载数据包失败: %v", err)
	}
	if perfVerbose {
		log.Printf("已加载 %d 个数据包，链路类型: %s", rdStats.Count, rdStats.LinkType)
	}
	// 构建拦截器链（无重写参数时为 nil）
	chain := buildInterceptorChain(&perfRewrite)
	// 解析性能测试配置
	config := &pref.Config{
		LoopCount:       perfLoopCount,
		Concurrency:     perfConcurrency,
		PPS:             perfPPS,
		BPS:             perfBPS,
		IgnoreTimestamp: perfIgnoreTS,
	}
	// 解析持续时间
	if perfDuration != "" {
		duration, err := time.ParseDuration(perfDuration)
		if err != nil {
			log.Fatalf("解析持续时间失败: %v", err)
		}
		config.Duration = duration
	}
	// 解析统计间隔
	if perfStatsInt != "" {
		interval, err := time.ParseDuration(perfStatsInt)
		if err != nil {
			log.Fatalf("解析统计间隔失败: %v", err)
		}
		config.StatsInterval = interval
	}
	if perfVerbose {
		// 显示测试配置
		fmt.Println()
		fmt.Println("================ 性能测试配置 ================")
		if config.Duration > 0 {
			fmt.Printf("  测试持续时间:          %v\n", config.Duration)
		} else {
			fmt.Printf("  测试持续时间:          无限制\n")
		}
		if config.LoopCount > 0 {
			fmt.Printf("  循环次数:              %d\n", config.LoopCount)
		} else {
			fmt.Printf("  循环次数:              无限制\n")
		}
		fmt.Printf("  并发数:                %d\n", config.Concurrency)
		if config.PPS > 0 {
			fmt.Printf("  包速率限制:            %d packets/sec\n", config.PPS)
		} else {
			fmt.Printf("  包速率限制:            无限制\n")
		}
		if config.BPS > 0 {
			fmt.Printf("  带宽限制:              %d bytes/sec (%.2f Mbps)\n", config.BPS, float64(config.BPS*8)/(1000*1000))
		} else {
			fmt.Printf("  带宽限制:              无限制\n")
		}
		fmt.Printf("  忽略时间戳:            %v\n", config.IgnoreTimestamp)
		fmt.Printf("  统计报告间隔:          %v\n", config.StatsInterval)
		fmt.Println()
		log.Println("开始性能测试...")
	}
	// 运行性能测试
	stats, err := r.PerformanceTest(perfIface, config, chain)
	if err != nil {
		log.Fatalf("性能测试失败: %v", err)
	}
	if perfVerbose {
		log.Println("性能测试完成")
		// 显示最终统计信息
		fmt.Println()
		fmt.Println("================ 最终性能统计 ================")
		stats.Update()
		fmt.Println(stats.String())
		fmt.Println()
	}
}

// NewPerfCommand 创建 perf 子命令
func NewPerfCommand() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "perf",
		Short: "性能测试模式 - 测试网口或流量采集系统的性能",
		Long: `性能测试模式：对目标网口或流量采集分析系统进行性能测试。

支持循环重放、并发控制、速率限制、实时统计等功能。

示例:
  ./traffic-replayer perf --file capture.pcap --iface en0 --duration 30s
  ./traffic-replayer perf --file capture.pcap --iface en0 --duration 1m --concurrency 10
  ./traffic-replayer perf --file capture.pcap --iface en0 --loops 1000 --concurrency 5`,
		Run: runPerf,
	}
	// 必需参数
	cmd.Flags().StringVarP(&perfFile, "file", "f", "", "PCAP 文件路径 (必需)")
	cmd.MarkFlagRequired("file")
	cmd.Flags().StringVarP(&perfIface, "iface", "i", "", "重放数据包的网络接口 (必需)")
	cmd.MarkFlagRequired("iface")
	// 性能测试参数
	cmd.Flags().StringVarP(&perfDuration, "duration", "d", "", "测试持续时间 (例如: 30s, 5m, 1h，默认无限制)")
	cmd.Flags().IntVarP(&perfLoopCount, "loops", "l", 0, "循环次数 (0=无限制，默认 0)")
	cmd.Flags().IntVarP(&perfConcurrency, "concurrency", "c", 1, "并发数 (默认 1)")
	cmd.Flags().Int64Var(&perfPPS, "pps", 0, "包速率限制 (packets/sec，0=无限制)")
	cmd.Flags().Int64Var(&perfBPS, "bps", 0, "带宽限制 (bytes/sec，0=无限制)")
	cmd.Flags().BoolVar(&perfIgnoreTS, "ignore-timestamp", true, "忽略时间戳，以最快速度发送")
	cmd.Flags().StringVar(&perfStatsInt, "stats-interval", "5s", "统计报告间隔 (例如: 1s, 5s, 10s)")
	// 拦截器参数
	addRewriteFlags(cmd, &perfRewrite)
	// 其他参数
	cmd.Flags().BoolVarP(&perfVerbose, "verbose", "v", false, "启用详细输出")
	return cmd
}
