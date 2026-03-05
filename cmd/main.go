package main

import (
	"log"
	"os"

	"github.com/spf13/cobra"
)

// 版本信息
const version = "v1.0.0"

var (
	// 已知子命令集合，用于默认 replay 模式判断
	knownSubcommands = map[string]bool{
		"replay": true,
		"perf":   true,
		"mock":   true,
		"web":    true,
	}
	// 根命令全局 flag，不属于任何子命令的顶层 flag
	knownRootFlags = map[string]bool{
		"--help":    true,
		"-h":        true,
		"--version": true,
		"-V":        true,
	}
)

// 定义根命令
var rootCmd = &cobra.Command{
	Use:     "traffic-replayer",
	Short:   "TRAFFIC-REPLAYER 流量回放工具",
	Long:    "TRAFFIC-REPLAYER 流量回放工具\n\n支持从 PCAP 文件读取网络流量并在指定网络接口上进行回放。\n支持性能测试和网络流量生成等功能。",
	Version: version,
	CompletionOptions: cobra.CompletionOptions{
		DisableDefaultCmd: true, // 禁用自动生成的 completion 命令
	},
}

func init() {
	// 禁用默认的 help 子命令（仍可使用 --help 标志）
	rootCmd.SetHelpCommand(&cobra.Command{Hidden: true})
	// 添加子命令
	rootCmd.AddCommand(NewReplayCommand())
	rootCmd.AddCommand(NewMockCommand())
	rootCmd.AddCommand(NewPerfCommand())
	rootCmd.AddCommand(NewWebCommand())
	// 版本标志
	rootCmd.Flags().BoolP("version", "V", false, "显示版本信息")
}

func main() {
	// 若未指定子命令且不是全局 flag（--help / --version），
	// 则自动在 args 首部插入 "replay"，让用户可以省略 replay 关键字
	args := os.Args[1:]
	if len(args) > 0 && !knownSubcommands[args[0]] && !knownRootFlags[args[0]] {
		os.Args = append([]string{os.Args[0], "replay"}, args...)
	}
	// 执行根命令
	if err := rootCmd.Execute(); err != nil {
		log.Fatalln(err)
	}
}
