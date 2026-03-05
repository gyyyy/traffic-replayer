package replayer

import (
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"time"

	"github.com/gyyyy/traffic-replayer/replayer/interceptor"
	"github.com/gyyyy/traffic-replayer/replayer/pref"
)

// Replayer 读取包重放器
type Replayer struct {
	packets map[string][]*Packet // 已加载的数据包，按文件分组
	index   []string             // 文件加载顺序索引
}

// Load 加载数据包并返回统计信息
func (r *Replayer) Load(path string) (*PacketsStats, error) {
	absPath, err := filepath.Abs(path)
	if err != nil {
		return nil, err
	}
	path = absPath
	// 检查数据包文件是否已加载
	if v, exists := r.packets[path]; exists {
		return restats(v), nil
	}
	// 打开读取器
	reader, err := NewReader(path)
	if err != nil {
		return nil, err
	}
	defer reader.Close()
	// 读取数据包
	packets, stats, err := reader.ReadPackets()
	if err != nil {
		return nil, err
	}
	if len(packets) == 0 {
		return nil, fmt.Errorf("没有读取到数据包")
	}
	if stats == nil || stats.TotalBytes == 0 {
		return nil, fmt.Errorf("读取到的数据包为空")
	}
	// 添加数据包到重放器
	r.packets[path] = packets
	r.index = append(r.index, path)
	// 返回统计信息
	return stats, nil
}

// LoadAll 加载目录下所有数据包文件，根据参数决定失败时是否停止
func (r *Replayer) LoadAll(dir string, stopOnError bool) (*PacketsStats, error) {
	// 检查目录是否存在及有效
	info, err := os.Stat(dir)
	if err != nil {
		return nil, err
	}
	if !info.IsDir() {
		return r.Load(dir)
	}
	// 遍历目录加载所有文件
	var totolStats *PacketsStats
	if err = filepath.Walk(dir, func(path string, info fs.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if info.IsDir() {
			return nil
		}
		stats, err := r.Load(path)
		if err != nil && stopOnError {
			return err
		}
		if totolStats == nil {
			totolStats = stats
		} else if stats != nil {
			if totolStats.LinkType != "Composite" && stats.LinkType != totolStats.LinkType {
				totolStats.LinkType = "Composite"
			}
			totolStats.Count += stats.Count
			totolStats.TotalBytes += stats.TotalBytes
		}
		return nil
	}); err != nil {
		return nil, err
	}
	return totolStats, nil
}

// Replay 重放数据包
func (r *Replayer) Replay(iface string, multiplier float64, interceptor interceptor.Interceptor) (*InjectStats, error) {
	if len(r.packets) == 0 {
		return nil, fmt.Errorf("没有数据包可重放")
	}
	if multiplier <= 0 {
		multiplier = 1.0
	}
	// 创建注入器
	injector, err := NewInjector(iface)
	if err != nil {
		return nil, err
	}
	defer injector.Close()
	if interceptor != nil {
		// 设置拦截器
		injector.SetInterceptor(interceptor)
	}
	var (
		totolStats *InjectStats
		timer      *time.Timer
	)
	// 按顺序重放每个文件的数据包
	for i, path := range r.index {
		if i > 0 {
			// 文件间默认延迟 200 毫秒
			if timer == nil {
				timer = time.NewTimer(200 * time.Millisecond)
			} else {
				timer.Reset(200 * time.Millisecond)
			}
			<-timer.C
		}
		packets, exists := r.packets[path]
		if !exists || len(packets) == 0 {
			continue
		}
		// 重放数据包
		if stats := injector.Inject(packets, multiplier); totolStats == nil {
			totolStats = stats
		} else {
			totolStats.PacketsSent += stats.PacketsSent
			totolStats.BytesSent += stats.BytesSent
			totolStats.PacketsFailed += stats.PacketsFailed
			if stats.StartTime.Before(totolStats.StartTime) {
				totolStats.StartTime = stats.StartTime
			}
			if stats.EndTime.After(totolStats.EndTime) {
				totolStats.EndTime = stats.EndTime
			}
			stats.Duration += stats.Duration
		}
	}
	if timer != nil {
		timer.Stop()
	}
	return totolStats, nil
}

// FastReplay 快速重放数据包，使用默认参数
func (r *Replayer) FastReplay(iface string) (*InjectStats, error) {
	return r.Replay(iface, 0, nil)
}

// PerformanceTest 性能测试
func (r *Replayer) PerformanceTest(iface string, config *pref.Config, interceptor interceptor.Interceptor) (*pref.Stats, error) {
	if len(r.packets) == 0 {
		return nil, fmt.Errorf("没有数据包可测试")
	}
	// 创建注入器
	injector, err := NewInjector(iface)
	if err != nil {
		return nil, err
	}
	defer injector.Close()
	if interceptor != nil {
		// 设置拦截器
		injector.SetInterceptor(interceptor)
	}
	// 合并所有数据包
	var allPackets []*pref.Packet
	for _, path := range r.index {
		if packets, exists := r.packets[path]; exists {
			for _, p := range packets {
				allPackets = append(allPackets, &pref.Packet{
					Data:      p.Data,
					Timestamp: p.Timestamp,
				})
			}
		}
	}
	if len(allPackets) == 0 {
		return nil, fmt.Errorf("没有有效数据包可测试")
	}
	// 创建性能测试
	tester := pref.NewTester(config)
	// 运行测试
	if err := tester.Run(injector, allPackets); err != nil {
		return nil, err
	}
	return tester.Stats(), nil
}

// New 创建一个新的重放器
func New() *Replayer {
	return &Replayer{
		packets: make(map[string][]*Packet),
	}
}
