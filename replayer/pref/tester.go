package pref

import (
	"context"
	"fmt"
	"sync"
	"sync/atomic"
	"time"
)

// Sender 数据包发送接口，由调用方实现，解耦包依赖
type Sender interface {
	Send(data []byte) error
}

// Config 性能测试配置
type Config struct {
	Duration        time.Duration // 测试持续时间（0 表示无限制，使用循环次数控制）
	LoopCount       int           // 循环次数（0 表示无限制，使用持续时间控制）
	Concurrency     int           // 并发数
	PPS             int64         // 发包速率限制（0 表示不限制）
	BPS             int64         // 带宽限制（bytes per second，0 表示不限制）
	IgnoreTimestamp bool          // 忽略原始时间戳，以最快速度发送
	StatsInterval   time.Duration // 统计报告间隔
}

// Packet 性能测试数据包
type Packet struct {
	Data      []byte
	Timestamp time.Time
}

// Stats 性能测试统计信息
type Stats struct {
	// 状态
	Running atomic.Bool // 是否正在运行
	// 实时统计（上个周期）
	CurrentPPS atomic.Int64 // 当前每秒包数
	CurrentBPS atomic.Int64 // 当前每秒字节数
	// 累计统计
	TotalPacketsSent   atomic.Int64 // 总发送包数
	TotalBytesSent     atomic.Int64 // 总发送字节数
	TotalPacketsFailed atomic.Int64 // 总失败包数
	// 时间戳
	StartTime atomic.Value // time.Time 测试开始时间
	LastTime  atomic.Value // time.Time 上次统计时间
}

// loadStartTime 获取开始时间
func (s *Stats) loadStartTime() time.Time {
	if t := s.StartTime.Load(); t != nil {
		return t.(time.Time)
	}
	return time.Time{}
}

// loadLastTime 获取上次统计时间
func (s *Stats) loadLastTime() time.Time {
	if t := s.LastTime.Load(); t != nil {
		return t.(time.Time)
	}
	return time.Time{}
}

// Update 更新统计信息
func (s *Stats) Update() {
	if now := time.Now(); now.Sub(s.loadLastTime()).Seconds() > 0 {
		var (
			currPackets = s.TotalPacketsSent.Load()
			currBytes   = s.TotalBytesSent.Load()
		)
		// 计算当前速率（基于上次更新以来的增量）
		if duration := now.Sub(s.loadStartTime()).Seconds(); duration > 0 {
			s.CurrentPPS.Store(int64(float64(currPackets) / duration))
			s.CurrentBPS.Store(int64(float64(currBytes) / duration))
		}
		s.LastTime.Store(now)
	}
}

// String 返回统计信息的字符串表示
func (s *Stats) String() string {
	var (
		duration = time.Since(s.loadStartTime())
		packets  = s.TotalPacketsSent.Load()
		bytes    = s.TotalBytesSent.Load()
		faileds  = s.TotalPacketsFailed.Load()
		pps      = s.CurrentPPS.Load()
		bps      = s.CurrentBPS.Load()
	)
	return fmt.Sprintf(
		"  运行时长:      %v\n"+
			"  总发送包数:     %d\n"+
			"  总发送字节数:   %d (%.2f MB)\n"+
			"  总失败包数:     %d\n"+
			"  平均 PPS:      %d 包/秒\n"+
			"  平均带宽:       %d 字节/秒 (%.2f Mbps)\n"+
			"  成功率:         %.2f%%",
		duration,
		packets,
		bytes, float64(bytes)/(1024*1024),
		faileds,
		pps,
		bps, float64(bps*8)/(1000*1000),
		float64(packets)*100/float64(packets+faileds+1),
	)
}

// newPerformanceStats 创建性能统计对象
func newPerformanceStats() *Stats {
	var (
		now   = time.Now()
		stats = &Stats{}
	)
	stats.StartTime.Store(now)
	stats.LastTime.Store(now)
	stats.Running.Store(true)
	return stats
}

// Tester 性能测试器
type Tester struct {
	wg      sync.WaitGroup
	ctx     context.Context
	cancel  context.CancelFunc
	config  *Config
	limiter *rateLimiter
	stats   *Stats
}

// reportStats 定期报告统计信息
func (t *Tester) reportStats() {
	ticker := time.NewTicker(t.config.StatsInterval)
	defer ticker.Stop()
	for {
		select {
		case <-t.ctx.Done():
			return
		case <-ticker.C:
			t.stats.Update()
			fmt.Println("\n" + t.stats.String())
		}
	}
}

// worker 工作协程
func (t *Tester) worker(sender Sender, packets []*Packet, _ int) {
	defer t.wg.Done()
	var loopCount int
	for {
		// 检查是否应该停止
		select {
		case <-t.ctx.Done():
			return
		default:
		}
		// 检查循环次数限制
		if t.config.LoopCount > 0 && loopCount >= t.config.LoopCount {
			return
		}
		// 发送所有数据包
		for _, packet := range packets {
			// 检查上下文
			select {
			case <-t.ctx.Done():
				return
			default:
			}
			if len(packet.Data) == 0 {
				continue
			}
			// 速率限制
			t.limiter.wait(len(packet.Data))
			// 发送数据包
			if err := sender.Send(packet.Data); err != nil {
				t.stats.TotalPacketsFailed.Add(1)
				continue
			}
			// 更新统计
			t.stats.TotalPacketsSent.Add(1)
			t.stats.TotalBytesSent.Add(int64(len(packet.Data)))
			// 如果不忽略时间戳，则等待
			if !t.config.IgnoreTimestamp && loopCount == 0 {
				// 只在第一轮循环时遵守时间戳
				// TODO: 实现基于时间戳的延迟
			}
		}
		loopCount++
	}
}

// Run 运行性能测试
func (t *Tester) Run(sender Sender, packets []*Packet) error {
	if len(packets) == 0 {
		return fmt.Errorf("没有数据包可测试")
	}
	// 启动统计报告
	if t.config.StatsInterval > 0 {
		go t.reportStats()
	}
	// 启动工作协程
	for i := 0; i < t.config.Concurrency; i++ {
		t.wg.Add(1)
		go t.worker(sender, packets, i)
	}
	// 等待所有工作协程完成
	t.wg.Wait()
	t.stats.Running.Store(false)
	return nil
}

// Stop 停止性能测试
func (t *Tester) Stop() {
	t.cancel()
	t.wg.Wait()
}

// Stats 获取统计信息
func (t *Tester) Stats() *Stats {
	return t.stats
}

// NewTester 创建性能测试器
func NewTester(config *Config) *Tester {
	ctx, cancel := context.WithCancel(context.Background())
	if config.Duration > 0 {
		ctx, cancel = context.WithTimeout(context.Background(), config.Duration)
	}
	return &Tester{
		ctx:     ctx,
		cancel:  cancel,
		config:  config,
		stats:   newPerformanceStats(),
		limiter: newRateLimiter(config.PPS, config.BPS),
	}
}
