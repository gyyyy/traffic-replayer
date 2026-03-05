package interceptor

import (
	"net"

	"github.com/google/gopacket"
	"github.com/google/gopacket/layers"
)

// PacketModifier 数据包修改器
type PacketModifier struct {
	raw    []byte          // 原始数据
	packet gopacket.Packet // 底层数据包
}

// Layer 获取指定类型的层
func (p PacketModifier) Layer(typ gopacket.LayerType) gopacket.Layer {
	return p.packet.Layer(gopacket.LayerType(typ))
}

func (p PacketModifier) Layers() []string {
	var layers []string
	for _, layer := range p.packet.Layers() {
		layers = append(layers, layer.LayerType().String())
	}
	return layers
}

// SetSrcMAC 设置源 MAC 地址
func (p PacketModifier) SetSrcMAC(mac net.HardwareAddr) bool {
	if mac == nil || p.packet == nil {
		return false
	}
	var modified bool
	// 修改 Ethernet 层源 MAC 地址
	if ethLayer := p.packet.Layer(layers.LayerTypeEthernet); ethLayer != nil {
		ethLayer.(*layers.Ethernet).SrcMAC = mac
		modified = true
	}
	// 修改 ARP 层源 MAC 地址
	if arpLayer := p.packet.Layer(layers.LayerTypeARP); arpLayer != nil {
		arpLayer.(*layers.ARP).SourceHwAddress = mac
		modified = true
	}
	return modified
}

// SetDstMAC 设置目标 MAC 地址
func (p PacketModifier) SetDstMAC(mac net.HardwareAddr) bool {
	if mac == nil || p.packet == nil {
		return false
	}
	var modified bool
	// 修改 Ethernet 层目标 MAC 地址
	if ethLayer := p.packet.Layer(layers.LayerTypeEthernet); ethLayer != nil {
		ethLayer.(*layers.Ethernet).DstMAC = mac
		modified = true
	}
	// 修改 ARP 层目标 MAC 地址
	if arpLayer := p.packet.Layer(layers.LayerTypeARP); arpLayer != nil {
		arpLayer.(*layers.ARP).DstHwAddress = mac
		modified = true
	}
	return modified
}

// SetSrcIPv4 设置源 IPv4 地址
func (p PacketModifier) SetSrcIPv4(ip net.IP) bool {
	if ip == nil || p.packet == nil {
		return false
	}
	// 修改 IPv4 层源 IP 地址
	if ipLayer := p.packet.Layer(layers.LayerTypeIPv4); ipLayer != nil {
		layer := ipLayer.(*layers.IPv4)
		layer.SrcIP = ip
		layer.Checksum = 0
		return true
	}
	// 修改 ARP 层源协议地址
	if arpLayer := p.packet.Layer(layers.LayerTypeARP); arpLayer != nil {
		layer := arpLayer.(*layers.ARP)
		copy(layer.SourceProtAddress, ip.To4())
		return true
	}
	return false
}

// SetDstIPv4 设置目标 IPv4 地址
func (p PacketModifier) SetDstIPv4(ip net.IP) bool {
	if ip == nil || p.packet == nil {
		return false
	}
	// 修改 IPv4 层目标 IP 地址
	if ipLayer := p.packet.Layer(layers.LayerTypeIPv4); ipLayer != nil {
		layer := ipLayer.(*layers.IPv4)
		layer.DstIP = ip
		layer.Checksum = 0
		return true
	}
	// 修改 ARP 层目标协议地址
	if arpLayer := p.packet.Layer(layers.LayerTypeARP); arpLayer != nil {
		layer := arpLayer.(*layers.ARP)
		copy(layer.DstProtAddress, ip.To4())
		return true
	}
	return false
}

// SetSrcIPv6 设置源 IPv6 地址
func (p PacketModifier) SetSrcIPv6(ip net.IP) bool {
	if ip == nil || p.packet == nil {
		return false
	}
	// 修改 IPv6 层源 IP 地址
	if ipLayer := p.packet.Layer(layers.LayerTypeIPv6); ipLayer != nil {
		ipLayer.(*layers.IPv6).SrcIP = ip
		return true
	}
	return false
}

// SetDstIPv6 设置目标 IPv6 地址
func (p PacketModifier) SetDstIPv6(ip net.IP) bool {
	if ip == nil || p.packet == nil {
		return false
	}
	// 修改 IPv6 层目标 IP 地址
	if ipLayer := p.packet.Layer(layers.LayerTypeIPv6); ipLayer != nil {
		ipLayer.(*layers.IPv6).DstIP = ip
		return true
	}
	return false
}

// SetSrcPortTCP 设置 TCP 源端口
func (p PacketModifier) SetSrcPortTCP(port uint16) bool {
	if port == 0 || p.packet == nil {
		return false
	}
	// 修改 TCP 层源端口
	if tcpLayer := p.packet.Layer(layers.LayerTypeTCP); tcpLayer != nil {
		tcpLayer.(*layers.TCP).SrcPort = layers.TCPPort(port)
		return true
	}
	return false
}

// SetDstPortTCP 设置 TCP 目标端口
func (p PacketModifier) SetDstPortTCP(port uint16) bool {
	if port == 0 || p.packet == nil {
		return false
	}
	// 修改 TCP 层目标端口
	if tcpLayer := p.packet.Layer(layers.LayerTypeTCP); tcpLayer != nil {
		tcpLayer.(*layers.TCP).DstPort = layers.TCPPort(port)
		return true
	}
	return false
}

// SetSrcPortUDP 设置 UDP 源端口
func (p PacketModifier) SetSrcPortUDP(port uint16) bool {
	if port == 0 || p.packet == nil {
		return false
	}
	// 修改 UDP 层源端口
	if udpLayer := p.packet.Layer(layers.LayerTypeUDP); udpLayer != nil {
		udpLayer.(*layers.UDP).SrcPort = layers.UDPPort(port)
		return true
	}
	return false
}

// SetDstPortUDP 设置 UDP 目标端口
func (p PacketModifier) SetDstPortUDP(port uint16) bool {
	if port == 0 || p.packet == nil {
		return false
	}
	// 修改 UDP 层目标端口
	if udpLayer := p.packet.Layer(layers.LayerTypeUDP); udpLayer != nil {
		udpLayer.(*layers.UDP).DstPort = layers.UDPPort(port)
		return true
	}
	return false
}

// Serialize 序列化修改后的数据包
func (p PacketModifier) Serialize() []byte {
	if p.packet == nil {
		return p.raw
	}
	var (
		buf     = gopacket.NewSerializeBuffer()
		options = gopacket.SerializeOptions{
			ComputeChecksums: true, // 自动计算校验和
			FixLengths:       true, // 自动修正长度字段
		}
		layers []gopacket.SerializableLayer
	)
	// 收集所有层
	for _, layer := range p.packet.Layers() {
		if serialLayer, ok := layer.(gopacket.SerializableLayer); ok {
			layers = append(layers, serialLayer)
		}
	}
	// 序列化所有层
	if err := gopacket.SerializeLayers(buf, options, layers...); err != nil {
		return p.raw
	}
	return buf.Bytes()
}

// NewPacketModifier 创建数据包修改器
func NewPacketModifier(data []byte) PacketModifier {
	return PacketModifier{
		raw:    data,
		packet: gopacket.NewPacket(data, layers.LayerTypeEthernet, gopacket.Default),
	}
}
