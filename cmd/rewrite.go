package main

import (
	"log"

	"github.com/gyyyy/traffic-replayer/replayer/interceptor"
	"github.com/spf13/cobra"
)

// rewriteFlags 数据包重写参数
type rewriteFlags struct {
	SrcMAC string // 重写源 MAC 地址
	DstMAC string // 重写目标 MAC 地址
	SrcIP  string // 重写源 IP 地址
	DstIP  string // 重写目标 IP 地址
	CIDR   string // 重写 IP 地址 CIDR 网段
}

// addRewriteFlags 为命令注册数据包重写参数
func addRewriteFlags(cmd *cobra.Command, f *rewriteFlags) {
	cmd.Flags().StringVar(&f.SrcMAC, "src-mac", "", "重写源 MAC 地址 (例如: aa:bb:cc:dd:ee:ff)")
	cmd.Flags().StringVar(&f.DstMAC, "dst-mac", "", "重写目标 MAC 地址 (例如: aa:bb:cc:dd:ee:ff)")
	cmd.Flags().StringVar(&f.SrcIP, "src-ip", "", "重写源 IP 地址 (例如: 192.168.1.100 或 192.168.1.100:8080)")
	cmd.Flags().StringVar(&f.DstIP, "dst-ip", "", "重写目标 IP 地址 (例如: 192.168.1.200 或 192.168.1.200:80)")
	cmd.Flags().StringVar(&f.CIDR, "cidr", "", "重写 IP 地址 CIDR 网段 (仅支持 IPv4，例如: 192.168.1.0/24)")
}

// buildInterceptorChain 根据重写参数构建拦截器链
func buildInterceptorChain(f *rewriteFlags) interceptor.Interceptor {
	var interceptors []interceptor.Interceptor
	if f.CIDR != "" {
		// CIDR 模式：使用地址池映射器，优先级高于单独的 MAC/IP 重写
		mapper, err := interceptor.NewAddressMapper(f.CIDR)
		if err != nil {
			log.Fatalf("创建地址映射器失败: %v", err)
		}
		interceptors = append(interceptors, mapper.Rewrite)
	} else {
		// 单独重写模式：MAC 重写 → IP 重写，按顺序叠加
		if f.SrcMAC != "" || f.DstMAC != "" {
			macRewriter, err := interceptor.NewMACRewriter(f.SrcMAC, f.DstMAC)
			if err != nil {
				log.Fatalf("创建 MAC 重写器失败: %v", err)
			}
			interceptors = append(interceptors, macRewriter.Rewrite)
		}
		if f.SrcIP != "" || f.DstIP != "" {
			ipRewriter, err := interceptor.NewIPRewriter(f.SrcIP, f.DstIP)
			if err != nil {
				log.Fatalf("创建 IP 重写器失败: %v", err)
			}
			interceptors = append(interceptors, ipRewriter.Rewrite)
		}
	}
	if len(interceptors) == 0 {
		return nil
	}
	return interceptor.Chain(interceptors...)
}
