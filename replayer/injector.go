package replayer

import (
	"fmt"
	"time"

	"github.com/google/gopacket/pcap"
	"github.com/gyyyy/traffic-replayer/replayer/interceptor"
)

const (
	minDelay = 500 * time.Microsecond // 最小延迟 500 微秒
	maxDelay = 5 * time.Second        // 最大延迟 5 秒
)

// InjectStats 注入统计信息
type InjectStats struct {
	PacketsSent   int64         // 发送的数据包数量
	BytesSent     int64         // 发送的字节数
	PacketsFailed int64         // 发送失败的数据包数量
	StartTime     time.Time     // 开始时间
	EndTime       time.Time     // 结束时间
	Duration      time.Duration // 持续时间
}

// Injector 数据包注入器
type Injector struct {
	iface       string                  // 网络接口名称
	handle      *pcap.Handle            // 数据包注入句柄
	interceptor interceptor.Interceptor // 数据包拦截器
}

// SetInterceptor 设置数据包拦截器
func (i *Injector) SetInterceptor(interceptor interceptor.Interceptor) {
	i.interceptor = interceptor
}

// inject 发送单个数据包
func (i *Injector) inject(data []byte) error {
	// 应用拦截器
	if i.interceptor != nil {
		data = i.interceptor(interceptor.NewPacketModifier(data)).Serialize()
	}
	// 使用 PCAP 句柄发送数据包
	if err := i.handle.WritePacketData(data); err != nil {
		return fmt.Errorf("注入数据包失败: %w", err)
	}
	return nil
}

// Inject 发送数据包并收集统计信息
func (i *Injector) Inject(packets []*Packet, multiplier float64) *InjectStats {
	stats := &InjectStats{
		StartTime: time.Now(),
	}
	defer func() {
		stats.EndTime = time.Now()
		stats.Duration = stats.EndTime.Sub(stats.StartTime)
	}()
	var timer *time.Timer
	// 依次发送每个数据包
	for j, packet := range packets {
		if len(packet.Data) == 0 {
			continue
		}
		if j > 0 {
			// 计算延迟时间
			delay := packet.Timestamp.Sub(packets[j-1].Timestamp)
			if delay <= 0 {
				// 如果时间戳无效（倒退或零值），使用最小延迟
				delay = minDelay
			} else {
				// 应用速率倍数，并限制在最大延迟范围内
				delay = min(time.Duration(float64(delay)/multiplier), maxDelay)
			}
			if timer == nil {
				timer = time.NewTimer(delay)
			} else {
				timer.Reset(delay)
			}
			<-timer.C
		}
		// 注入数据包
		if err := i.inject(packet.Data); err != nil {
			stats.PacketsFailed++
			continue
		}
		stats.PacketsSent++
		stats.BytesSent += int64(len(packet.Data))
	}
	if timer != nil {
		timer.Stop()
	}
	return stats
}

// Send 发送单个数据包，实现 pref.Sender 接口
func (i *Injector) Send(data []byte) error {
	return i.inject(data)
}

// Close 关闭注入器
func (i *Injector) Close() error {
	i.handle.Close()
	return nil
}

// NewInjector 创建新的数据包注入器
func NewInjector(iface string) (*Injector, error) {
	// 打开设备进行数据包注入
	handle, err := pcap.OpenLive(
		iface,
		65535, // snaplen
		true,  // 混杂模式
		pcap.BlockForever,
	)
	if err != nil {
		return nil, fmt.Errorf("打开接口 %s 失败: %w", iface, err)
	}
	return &Injector{
		iface:  iface,
		handle: handle,
	}, nil
}
