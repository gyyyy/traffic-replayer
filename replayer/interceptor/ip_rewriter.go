package interceptor

import (
	"fmt"
	"net"
	"strconv"
	"strings"
)

// parseIPPort 解析 IP 或 IP:Port 格式
func parseIPPort(addr string) (net.IP, uint16, error) {
	// 如果不包含冒号，补全冒号以便拆分
	if !strings.Contains(addr, ":") {
		addr = addr + ":"
	}
	// 拆分主机和端口
	host, portStr, err := net.SplitHostPort(addr)
	if err != nil {
		return nil, 0, err
	}
	if host == "" && portStr == "" {
		return nil, 0, fmt.Errorf("无效格式")
	}
	var ip net.IP
	if host != "" {
		// 解析 IP 地址
		if ip = net.ParseIP(host); ip == nil {
			return nil, 0, fmt.Errorf("无效 IP 地址: %s", host)
		}
	}
	var port uint64
	if portStr != "" {
		// 解析端口号
		if port, err = strconv.ParseUint(portStr, 10, 16); err != nil || port == 0 {
			return nil, 0, fmt.Errorf("无效端口: %s", portStr)
		}
	}
	return ip, uint16(port), nil
}

// IPRewriter IP 地址重写器
type IPRewriter struct {
	srcIP   net.IP // 待修改源 IP 地址
	srcPort uint16 // 待修改源端口
	dstIP   net.IP // 待修改目标 IP 地址
	dstPort uint16 // 待修改目标端口
}

// Rewrite 重写 IP 地址和端口
func (r *IPRewriter) Rewrite(packet PacketModifier) PacketModifier {
	packet.SetSrcIPv4(r.srcIP)
	packet.SetSrcIPv6(r.srcIP)
	packet.SetSrcPortTCP(r.srcPort)
	packet.SetSrcPortUDP(r.srcPort)
	packet.SetDstIPv4(r.dstIP)
	packet.SetDstIPv6(r.dstIP)
	packet.SetDstPortTCP(r.dstPort)
	packet.SetDstPortUDP(r.dstPort)
	return packet
}

// NewIPRewriter 创建 IP 地址重写器
func NewIPRewriter(srcIP, dstIP string) (*IPRewriter, error) {
	rewriter := &IPRewriter{}
	if srcIP = strings.TrimSpace(srcIP); srcIP != "" {
		ip, port, err := parseIPPort(srcIP)
		if err != nil {
			return nil, fmt.Errorf("无效源 IP 地址或端口: %w", err)
		}
		rewriter.srcIP = ip
		rewriter.srcPort = port
	}
	if dstIP = strings.TrimSpace(dstIP); dstIP != "" {
		ip, port, err := parseIPPort(dstIP)
		if err != nil {
			return nil, fmt.Errorf("无效目的 IP 地址或端口: %w", err)
		}
		rewriter.dstIP = ip
		rewriter.dstPort = port
	}
	if rewriter.srcIP == nil && rewriter.dstIP == nil && rewriter.srcPort == 0 && rewriter.dstPort == 0 {
		return nil, fmt.Errorf("无任何有效的 IP 地址或端口")
	}
	return rewriter, nil
}
