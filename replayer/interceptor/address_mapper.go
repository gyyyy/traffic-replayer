package interceptor

import (
	"crypto/rand"
	"encoding/binary"
	"fmt"
	"net"

	"github.com/google/gopacket/layers"
)

// AddressMapper 地址映射器（基于网段的随机映射）
type AddressMapper struct {
	ipNet *net.IPNet        // IP 地址网段
	ipMap map[string]net.IP // IP 地址映射表 (原 IP -> 新 IP)
}

// Map 获取当前的地址映射表
func (m *AddressMapper) Map() map[string]net.IP {
	return m.ipMap
}

// randomIP 生成范围内的随机 IPv4 地址
func (m *AddressMapper) randomIP() net.IP {
	ip := m.ipNet.IP.To4()
	if ip == nil {
		return nil
	}
	// 计算网络掩码的长度
	var (
		ones, bits = m.ipNet.Mask.Size()
		hostBits   = bits - ones
	)
	if hostBits <= 0 {
		return m.ipNet.IP
	}
	// 生成随机主机部分
	var randomHost uint32
	binary.Read(rand.Reader, binary.BigEndian, &randomHost)
	// 限制在主机位范围内
	if hostBits < 32 {
		randomHost = randomHost & ((1 << hostBits) - 1)
	}
	// 避免使用网络地址和广播地址
	if randomHost == 0 {
		randomHost = 1
	}
	maxHost := (1 << hostBits) - 1
	if randomHost >= uint32(maxHost) {
		randomHost = uint32(maxHost) - 1
	}
	// 合并网络部分和主机部分
	result := make(net.IP, 4)
	copy(result, ip)
	ipInt := binary.BigEndian.Uint32(result)
	ipInt = (ipInt & ^((1 << hostBits) - 1)) | randomHost
	binary.BigEndian.PutUint32(result, ipInt)
	return result
}

// isUsedIP 检查 IP 是否已被使用
func (m *AddressMapper) isUsedIP(ip net.IP) bool {
	ipStr := ip.String()
	for _, mappedIP := range m.ipMap {
		if mappedIP.String() == ipStr {
			return true
		}
	}
	return false
}

// findAvailableIP 找到一个可用的 IP 地址
func (m *AddressMapper) findAvailableIP() net.IP {
	// 生成初始随机 IP
	ip := m.randomIP()
	if ip == nil {
		return nil
	}
	// 检查这个 IP 是否已经被使用，没有则直接返回
	if !m.isUsedIP(ip) {
		return ip
	}
	// 计算网络掩码的长度
	var (
		ones, bits = m.ipNet.Mask.Size()
		hostBits   = bits - ones
	)
	if hostBits <= 0 {
		return nil
	}
	// 计算最大主机号
	maxHost := (1 << hostBits) - 1
	// 计算网络部分和主机部分
	var (
		ipInt       = binary.BigEndian.Uint32(ip.To4())
		networkMask = ^uint32((1 << hostBits) - 1)
		networkPart = ipInt & networkMask
		hostPart    = ipInt & ^networkMask
	)
	// 从当前主机号开始，循环递增查找可用 IP
	for range maxHost - 1 {
		hostPart++
		// 循环回绕，跳过网络地址和广播地址
		if hostPart == 0 || hostPart >= uint32(maxHost) {
			hostPart = 1
		}
		var (
			newIPInt = networkPart | hostPart
			newIP    = make(net.IP, 4)
		)
		binary.BigEndian.PutUint32(newIP, newIPInt)
		if !m.isUsedIP(newIP) {
			return newIP
		}
	}
	return nil
}

// mapAddress 映射 IP 地址
func (m *AddressMapper) mapAddress(ip net.IP) net.IP {
	if ip == nil {
		return nil
	}
	key := ip.String()
	// 检查缓存
	if newIP, exists := m.ipMap[key]; exists {
		return newIP
	}
	// 如果原 IP 已经在目标网段内，不需要映射
	if m.ipNet.Contains(ip) {
		// 仍然需要缓存，避免重复检查
		m.ipMap[key] = ip
		return ip
	}
	// 找到一个可用的 IP
	newIP := m.findAvailableIP()
	if newIP == nil {
		// 如果找不到可用 IP，返回原地址
		return ip
	}
	// 缓存映射
	m.ipMap[key] = newIP
	return newIP
}

// Rewrite 重写数据包的 IP 地址
func (m *AddressMapper) Rewrite(packet PacketModifier) PacketModifier {
	if m.ipNet == nil {
		return packet
	}
	// 提取原始源 IP 和目标 IP
	var srcIP, dstIP net.IP
	if layer := packet.Layer(layers.LayerTypeIPv4); layer != nil {
		// 尝试从 IPv4 层获取
		ipLayer := layer.(*layers.IPv4)
		srcIP = ipLayer.SrcIP
		dstIP = ipLayer.DstIP
	} else if layer := packet.Layer(layers.LayerTypeARP); layer != nil {
		// 尝试从 ARP 层获取
		arpLayer := layer.(*layers.ARP)
		// ARP 协议地址是 IPv4 地址
		if len(arpLayer.SourceProtAddress) == 4 {
			srcIP = net.IPv4(arpLayer.SourceProtAddress[0], arpLayer.SourceProtAddress[1], arpLayer.SourceProtAddress[2], arpLayer.SourceProtAddress[3])
		}
		if len(arpLayer.DstProtAddress) == 4 {
			dstIP = net.IPv4(arpLayer.DstProtAddress[0], arpLayer.DstProtAddress[1], arpLayer.DstProtAddress[2], arpLayer.DstProtAddress[3])
		}
	}
	// 映射源地址
	if srcAddr := m.mapAddress(srcIP); srcAddr != nil {
		packet.SetSrcIPv4(srcAddr)
	}
	// 映射目标地址
	if dstAddr := m.mapAddress(dstIP); dstAddr != nil {
		packet.SetDstIPv4(dstAddr)
	}
	return packet
}

// NewAddressMapper 创建地址映射器
func NewAddressMapper(cidr string) (*AddressMapper, error) {
	_, ipNet, err := net.ParseCIDR(cidr)
	if err != nil {
		return nil, fmt.Errorf("无效的 CIDR 格式: %w", err)
	}
	// 只支持 IPv4
	if ipNet.IP.To4() == nil {
		return nil, fmt.Errorf("仅支持 IPv4 地址网段")
	}
	return &AddressMapper{
		ipNet: ipNet,
		ipMap: make(map[string]net.IP),
	}, nil
}
