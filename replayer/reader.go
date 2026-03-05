package replayer

import (
	"fmt"
	"time"

	"github.com/google/gopacket"
	"github.com/google/gopacket/pcap"
)

// PacketsStats 数据包统计信息
type PacketsStats struct {
	LinkType   string // 链路类型
	Count      int    // 数据包数量
	TotalBytes int64  // 总字节数
}

// restats 重新计算数据包统计信息
func restats(packets []*Packet) *PacketsStats {
	var stats = &PacketsStats{
		LinkType: "Ethernet",
		Count:    len(packets),
	}
	for _, packet := range packets {
		stats.TotalBytes += packet.Length
	}
	return stats
}

// Packet 数据包
type Packet struct {
	Data      []byte    // 数据包内容
	Length    int64     // 数据包长度
	Timestamp time.Time // 数据包时间戳
}

// Reader PCAP 文件读取器
type Reader struct {
	handle *pcap.Handle           // PCAP 句柄
	source *gopacket.PacketSource // 数据包源
}

// ReadPackets 从 PCAP 文件读取所有数据包
func (r *Reader) ReadPackets() ([]*Packet, *PacketsStats, error) {
	var (
		packets []*Packet
		stats   = &PacketsStats{
			LinkType: r.handle.LinkType().String(),
		}
	)
	// 迭代读取数据包
	for packet := range r.source.Packets() {
		if packet == nil {
			break
		}
		var (
			n         = int64(packet.Metadata().Length)
			timestamp = packet.Metadata().Timestamp
			data      = packet.Data()
		)
		packets = append(packets, &Packet{
			Data:      data,
			Length:    n,
			Timestamp: timestamp,
		})
		stats.Count++
		stats.TotalBytes += int64(n)
	}
	return packets, stats, nil
}

// Close 关闭 PCAP 读取器
func (r *Reader) Close() {
	if r.handle != nil {
		r.handle.Close()
	}
}

// NewReader 创建新的 PCAP 读取器
func NewReader(path string) (*Reader, error) {
	// 打开 PCAP 文件
	handle, err := pcap.OpenOffline(path)
	if err != nil {
		return nil, fmt.Errorf("打开 PCAP 文件失败: %w", err)
	}
	// 创建数据包源
	source := gopacket.NewPacketSource(handle, handle.LinkType())
	return &Reader{
		handle: handle,
		source: source,
	}, nil
}
