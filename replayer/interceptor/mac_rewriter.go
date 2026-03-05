package interceptor

import (
	"fmt"
	"net"
	"strings"
)

// MACRewriter MAC 地址重写器
type MACRewriter struct {
	srcMAC net.HardwareAddr // 待修改源 MAC 地址
	dstMAC net.HardwareAddr // 待修改目标 MAC 地址
}

// Rewrite 重写 MAC 地址
func (r *MACRewriter) Rewrite(packet PacketModifier) PacketModifier {
	packet.SetSrcMAC(r.srcMAC)
	packet.SetDstMAC(r.dstMAC)
	return packet
}

// NewMACRewriter 创建 MAC 地址重写器
func NewMACRewriter(srcMAC, dstMAC string) (*MACRewriter, error) {
	rewriter := &MACRewriter{}
	if srcMAC = strings.TrimSpace(srcMAC); srcMAC != "" {
		mac, err := net.ParseMAC(srcMAC)
		if err != nil {
			return nil, fmt.Errorf("无效源 MAC 地址: %w", err)
		}
		rewriter.srcMAC = mac
	}
	if dstMAC = strings.TrimSpace(dstMAC); dstMAC != "" {
		mac, err := net.ParseMAC(dstMAC)
		if err != nil {
			return nil, fmt.Errorf("无效目的 MAC 地址: %w", err)
		}
		rewriter.dstMAC = mac
	}
	if rewriter.srcMAC == nil && rewriter.dstMAC == nil {
		return nil, fmt.Errorf("无任何有效 MAC 地址")
	}
	return rewriter, nil
}
